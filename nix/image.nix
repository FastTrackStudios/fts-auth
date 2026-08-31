# OCI image for fts-auth, built WITHOUT a container daemon.
#
# Why not a Dockerfile: the `nix-host` CI runner executes as the
# `github-runner` user, which has no docker on PATH and is not in the
# `docker` group — reaching a daemon would mean granting CI
# effectively-root access to the workstation. Nix builds the image as a
# plain derivation and skopeo pushes it straight to the in-cluster
# registry, so neither is needed. Same shape as fasttrackstudio.app's
# `fts-www` and the monorepo's `fts-site`.

{
  pkgs,
  fts-auth,
  name ? "fts-auth",
  tag ? "latest",
  # Commit this image was built from; surfaced in the startup log.
  rev ? "dev",
}:

let
  # Scratch images have no user database. The server runs as a non-root
  # uid, and without an entry for it some libraries fail to resolve the
  # current user at all.
  passwd = pkgs.runCommand "${name}-passwd" { } ''
    mkdir -p $out/etc
    echo 'app:x:1000:1000::/app:/bin/sh' > $out/etc/passwd
    echo 'app:x:1000:' > $out/etc/group
    echo 'root:x:0:0::/root:/bin/sh' >> $out/etc/passwd
    echo 'root:x:0:' >> $out/etc/group
  '';
in
pkgs.dockerTools.streamLayeredImage {
  inherit name tag;

  contents = [
    fts-auth
    passwd
    # TLS roots: the server talks to Postgres and may fetch an OAuth
    # provider's metadata. Without these every outbound TLS handshake
    # fails with an opaque certificate error.
    pkgs.cacert
  ];

  config = {
    Entrypoint = [ "${fts-auth}/bin/fts-auth" ];
    User = "app";
    WorkingDir = "/app";
    ExposedPorts."8080/tcp" = { };
    Env = [
      "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
      "FTS_AUTH_REV=${rev}"
    ];
    Labels = {
      "org.opencontainers.image.title" = "fts-auth";
      "org.opencontainers.image.description" = "The FastTrackStudio identity server";
      "org.opencontainers.image.revision" = rev;
      "org.opencontainers.image.source" = "https://github.com/FastTrackStudios/fts-auth";
    };
  };
}
