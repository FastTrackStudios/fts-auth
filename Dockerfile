# Build
FROM docker.io/library/rust:1.90-bookworm AS build
WORKDIR /build
RUN apt-get update \
 && apt-get install -y --no-install-recommends pkg-config libssl-dev \
 && rm -rf /var/lib/apt/lists/*
COPY Cargo.toml Cargo.lock ./
COPY src ./src
RUN cargo build --release --locked

# Runtime — distroless-ish: no shell, no package manager, nothing an
# attacker who lands RCE in the auth server can pivot with.
FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=build /build/target/release/fts-auth /usr/local/bin/fts-auth
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/fts-auth"]
