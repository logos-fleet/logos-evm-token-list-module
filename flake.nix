{
  description = "Logos token_list module — Uniswap token-lists fetch/parse/merge + custom list (proxyable, fail-closed).";

  inputs = {
    logos-module-builder.url = "github:logos-co/logos-module-builder";
  };

  outputs = inputs@{ self, logos-module-builder, ... }:
    let
      nixpkgs = logos-module-builder.inputs.nixpkgs;
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];

      # x86_64-windows is a cross PSEUDO-SYSTEM the builder already understands
      # (logos-module-builder lib/common.nix routes it to
      # logos-nix.lib.mkWindowsPkgs, and picks the build platform separately).
      # It is a target, never a host we evaluate nixpkgs natively for, so it
      # only ever belongs in `packages`.
      targets = systems ++ [ "x86_64-windows" ];

      # ONE module, answered for every target at once — mkLogosModule already
      # keys its own outputs by system, so calling it inside the genAttrs
      # evaluated the same module five times over and threw four away.
      module = logos-module-builder.lib.mkLogosModule {
        src = ./.;
        configFile = ./metadata.json;
        flakeInputs = inputs;
      };

      # The mobile pseudo-systems logos-nix keys its cross package sets by. Kept
      # out of `targets` above for the reason the builder keeps them out of its
      # own: a phone gets the Bare image and none of the other outputs.
      #
      # THIS IS WHAT MAKES token_list BUNDLABLE (#148). A phone's Bundled set is
      # resolved out of a catalog whose every entry is a module's own
      # `mobile.<target>.bare`, so a module with no mobile output cannot be in
      # that set however well it builds on a desktop — and the wallet UI's `web`
      # variant then has nothing to ask for a token list, which is why its Token
      # lists tab printed "token_list_module ... has no mobile build".
      #
      # NOTHING HAD TO CHANGE IN THE MODULE to cross, and that is the point of
      # this being a one-line absence rather than a port. Its crate is the SAME
      # stack eth_rpc_module already crosses with: `reqwest` with default
      # features off plus `rustls-tls` (pure-Rust TLS, so no openssl to
      # cross-build), `socks`, `json` and `blocking` — no C dependency and no
      # `nix.external_libraries`, on either phone.
      #
      # `? ${t}` rather than a bare index, so a logos-module-builder pin without
      # the mobile cross sets leaves this flake simply WITHOUT mobile keys
      # instead of failing to evaluate.
      mobileTargets = builtins.filter (t: module.packages ? ${t})
        [ "aarch64-ios" "aarch64-ios-simulator" "aarch64-android" ];
    in
    {
      packages = nixpkgs.lib.genAttrs (targets ++ mobileTargets)
        (target: module.packages.${target});

      # An Android cross derivation's `system` is its BUILD platform, so
      # `packages.aarch64-android` is pinned to the builder's canonical one
      # (x86_64-linux) and a Mac cannot realise it. The same artifact, reached
      # from whichever machine is doing the building:
      #   nix build .#legacyPackages.aarch64-darwin.mobile.aarch64-android.bare
      legacyPackages = module.legacyPackages or { };

      # THE MODULE'S OWN ANSWER ABOUT ITSELF, forwarded so a consumer flake can
      # read it without building anything. logos-basecamp's mobile catalog takes
      # this module's `version` and its `dependencies` from here rather than
      # restating them: a Bundled set resolves a CLOSURE out of the catalog
      # entry, and a hand-copied list in a SIGNED manifest is a claim the core
      # would act on after it had drifted. This module declares none, which is
      # exactly the fact the catalog has to read rather than assume.
      # `configFor` is the per-target resolution of the same document; this
      # module has no `platforms` overlay, so the two agree everywhere.
      inherit (module) config configFor;

      # ── WHY THERE IS NO `web` (wasm) OUTPUT ──────────────────────────────
      #
      # `platform: true` in metadata.json, and the builder's ADR 0009 gate then
      # refuses a `web` variant BY NAME at eval. That is a declaration, not an
      # accident of this flake: this module opens its own sockets — the
      # `reqwest::blocking::Client::builder` at rust-lib/src/proxy.rs, with the
      # `socks` feature and a `proxy_required` that fails CLOSED rather than
      # sending a request in the clear — and a webview gives a page none of
      # that. A `fetch`-based port would not merely be work; it would silently
      # void the fail-closed guarantee, because a page cannot force its own
      # requests through SOCKS5h.
      #
      # So a Downloaded module reaches token metadata by CALLING this one, which
      # is always in the Bundled set — the arrangement the mobile Bare build
      # above is what makes possible.
    };
}
