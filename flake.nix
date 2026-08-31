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
            # architect is a git dependency, so Nix needs its hash. Update
            # this whenever the pinned architect tag moves — the build fails
            # loudly with the expected value, so the fix is to paste what it
            # prints.
            outputHashes = {
              "architect-0.1.0" = "sha256-pAjc8JbLIJqlqDKOZR3yyvBNFp9h9cF6RtLXmfRQlY4=";
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
