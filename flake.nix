{
  description = "fts-auth — the FastTrackStudio identity server";

  inputs = {
    # The fleet's pins, the same revision architect v0.13.1's flake takes:
    # nixpkgs, and `lib.toolchainFor` for the fleet's rustc (1.99.1).
    # architect v0.13 needs it: its Dioxus components do not build on the
    # 1.97 a plain nixpkgs had.
    devenv-fleet.url = "github:FastTrackStudios/devenv-fleet/c4ddec850ad97b5da74c746bff39a988f02b13a4";
    nixpkgs.follows = "devenv-fleet/nixpkgs";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      devenv-fleet,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ devenv-fleet.overlays.default ];
        };
        toolchain = devenv-fleet.lib.toolchainFor pkgs;
        rustPlatform = pkgs.makeRustPlatform {
          cargo = toolchain;
          rustc = toolchain;
        };

        # CI passes the tag/rev through the environment rather than as flake
        # args, so the workflow stays a plain `nix build --impure .#image`.
        # A bare `nix build .#image` gets the defaults.
        env =
          name: default:
          let
            v = builtins.getEnv name;
          in
          if v == "" then default else v;

        fts-auth = rustPlatform.buildRustPackage {
          pname = "fts-auth";
          version = "0.1.0";
          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
            # Git dependencies need their hash pinned here. Update whenever
            # a pinned tag or rev moves — the build fails loudly with the
            # expected value, so the fix is to paste what it prints.
            #
            # One entry per git *source*, not per crate, keyed by the
            # alphabetically first crate that source provides. Dioxus is 30
            # crates from a single rev, and `const-serialize` happens to
            # sort first — which is why the key names a crate nothing here
            # depends on directly.
            outputHashes = {
              "architect-0.1.0" = "sha256-2CA4VCcoGVOn8nfUEyg6LqzfnCV01M6zgfs6BaEEX+8=";
              # vendor v0.4.1 under two URLs (Cargo.toml's facet-core note).
              "phon-0.2.0-rc.7" = "sha256-/OA9kGYoZZkUB6278O3e3qOmhHu96Cyg5Ud07HMWUA8=";
              "facet-core-0.50.0-rc.7" = "sha256-/OA9kGYoZZkUB6278O3e3qOmhHu96Cyg5Ud07HMWUA8=";
              "phon-jit-0.2.0-rc.7" = "sha256-5a0PwCfBdJjV06rv2Nn5x8VnX7mx5/oPl0IiDne/OUI=";
              "vox-phon-0.10.0-rc.7" = "sha256-aYDaHTS2NHVK1sp/yZwbzM2WNUsIzmtOwJdvUE46iUk=";
              # Dioxus and the FTS forks of its components, as before.
              "const-serialize-0.8.0-alpha.3" = "sha256-ZWqLFm5apsJu24ishMsilTkndLrlRmb0JQRyVXSBt50=";
              "dioxus-attributes-0.1.0" = "sha256-ps01vX4NHu9LG3sDRqld9U6dNC3YKpUldfojFCEpKzs=";
              "dioxus-sdk-time-0.7.0" = "sha256-ruoicXlLe/XyT0lRpWG9wPyc0fEYUYvdT21/agEPUgA=";
              "lucide-dioxus-3.63.0" = "sha256-wr8/XSAdSO+Ea5MPXk02lgvapAySaW4nZWBR0NPwgRM=";
              # Since v0.11 architect's workspace-hack (the fleet feature
              # union) puts the desktop stack in the lock: Blitz and its
              # stylo and taffy, vendor v0.7.1 and v0.1.0, the editor. Fetched
              # to vendor the lock, never compiled (`no_workspace_hack` below).
              "accesskit_xplat-0.2.1" = "sha256-YQ/UxwfZrOgSTReACYdJxNnnU0+eT+qH2WKY2SVNYgg=";
              "anyrender_vello-0.15.0" = "sha256-2ePRT+w0Ov9TPt1geN4GCRi9MAWkpo1Ji1HSjsjnqGQ=";
              "dioxus-native-dom-0.8.0-alpha.3" = "sha256-CtITYjtbsxbcxyonYLmhq2wwNIbBD/YhUVRzLVxGFa4=";
              "editor-ext-0.1.0" = "sha256-U0yOcIHGWtvWiC591YzTD7RpJYYaJUy3GxVEP9Nj1h8=";
              "selectors-0.41.0" = "sha256-lbhr0hkTHF9DHQRVWjrd5t8ZpKP6zCmK3OQ81KJVDUI=";
              "styx-format-5.0.0-rc.5" = "sha256-MJsMiM1GMSEez2JzmHWEbE6jdt4lseDnxW+I5xpMG80=";
              "taffy-0.15.0" = "sha256-HkJSyqxG5cFc39ercnTSqRZo723kxm844BlTp6Jxyk8=";
            };
          };

          nativeBuildInputs = [
            pkgs.pkg-config
            pkgs.removeReferencesTo
          ];
          buildInputs = [ pkgs.openssl ];

          # The round-trip tests bind sockets and the postgres ones want a
          # server; neither belongs in a sandboxed image build.
          doCheck = false;

          # architect's workspace-hack (the fleet feature union) is in the
          # lock but not in the binary: off, as architect's own server
          # builds have it (its flake.nix, `architect-node`).
          RUSTFLAGS = "--cfg no_workspace_hack";

          # std's panic locations name the toolchain's rust-src, which would
          # keep the whole toolchain (about 2 GB) in the runtime closure.
          postFixup = ''
            remove-references-to -t ${toolchain} $out/bin/fts-auth
          '';
          disallowedReferences = [ toolchain ];

          meta.mainProgram = "fts-auth";
        };
      in
      {
        packages = {
          inherit fts-auth;
          default = fts-auth;
          image = import ./nix/image.nix {
            inherit pkgs fts-auth;
            tag = env "FTS_TAG" "latest";
            rev = env "FTS_REV" "dev";
          };
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.cargo
            pkgs.rustc
            pkgs.pkg-config
            pkgs.openssl
            pkgs.skopeo
            pkgs.postgresql
          ];
        };

        formatter = pkgs.nixfmt-rfc-style;
      }
    );
}
