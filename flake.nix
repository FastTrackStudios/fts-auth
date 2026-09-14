{
  description = "fts-auth — the FastTrackStudio identity server";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        # CI passes the tag/rev through the environment rather than as flake
        # args, so the workflow stays a plain `nix build --impure .#image`.
        # A bare `nix build .#image` gets the defaults.
        env =
          name: default:
          let
            v = builtins.getEnv name;
          in
          if v == "" then default else v;

        fts-auth = pkgs.rustPlatform.buildRustPackage {
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
              "architect-0.1.0" = "sha256-IBxL61ap+88p+1c+o35RZsrB8+1NuapQzihsxYA50I8=";
              "const-serialize-0.8.0-alpha.0" = "sha256-oHqJMK+0yxoQ9N6eKD6TeWATtlsFXmdw/MX/PIs6UyM=";
              # v0.8.3 brings auth-ui, which is a Dioxus application, so
              # three more git sources arrive with it. Same rule: one
              # entry per source, keyed by the alphabetically first crate
              # that source provides — which is why none of these names
              # is a crate this repo depends on directly.
              "dioxus-attributes-0.1.0" = "sha256-nGZMMY/xDO9zPmFf4TBPiUSYKzCwlSyEEcjJFoGxpkc=";
              "dioxus-sdk-time-0.7.0" = "sha256-p8o2hmdB2LJYyFci3meqEClpqDhW9Kb2bs8JCXOJw4M=";
              "lucide-dioxus-2.26.0" = "sha256-jDss/I2w9trqzXuQx+8RXhIgV0F6PfdbwWwnnDz1leM=";
            };
          };

          nativeBuildInputs = [ pkgs.pkg-config ];
          buildInputs = [ pkgs.openssl ];

          # The round-trip tests bind sockets and the postgres ones want a
          # server; neither belongs in a sandboxed image build.
          doCheck = false;

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
