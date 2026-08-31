# fts-auth

The FastTrackStudio identity server — **one account across Task,
Session, Signal, Keyflow and Ignition**, served at
`auth.fasttrackstudio.app`.

This repo is the *deployment*, not the server. The server is
[`apps/auth-server`](https://github.com/FastTrackStudios/architect/tree/main/apps/auth-server)
in the public `architect` repo, built on `architect-auth`. Everything
here is FastTrackStudio-specific: the issuer, the registered clients,
the cluster manifests. Improvements to the auth engine belong upstream.

## Why it exists

`architect-auth` is a complete auth engine, but it shipped as a library
with no way to run it — so every app embedded its own copy and its own
user store. Task went further and gave each *org* a separate
`auth.sqlite`. One account could not span two apps because there was no
single place an account lived. This server is that place.

## Surfaces

| Path | Purpose |
|------|---------|
| `/vox` | vox RPC over WebSocket — the native path for the Rust apps |
| `/.well-known/openid-configuration` | OIDC discovery |
| `/oauth2/authorize`, `/oauth2/token`, `/oauth2/userinfo` | OIDC provider |
| `/auth/jwt/jwks` | key set (empty — see Caveats) |
| `/auth/sign-up/email`, `/auth/sign-in/email`, `/auth/session`, `/auth/refresh`, `/auth/sign-out` | session JSON |
| `/healthz`, `/readyz` | probes |

## Configuration

All environment. Required:

| Variable | Notes |
|----------|-------|
| `AUTH_SECRET` / `AUTH_SECRET_FILE` | Session signing key, **≥32 bytes**. The server refuses to start below that. |
| `AUTH_DATABASE_URL` / `AUTH_DATABASE_URL_FILE` | `postgres://…` |

Optional, with defaults:

| Variable | Default | Notes |
|----------|---------|-------|
| `AUTH_BIND_ADDR` | `0.0.0.0:8080` | |
| `AUTH_BASE_URL` | `http://localhost:8080` | Must be the externally visible origin. |
| `AUTH_OIDC_ISSUER` | `AUTH_BASE_URL` | Stable identity; outlives a hostname change. |
| `AUTH_SESSION_TTL_SECONDS` | `2592000` (30d) | |
| `AUTH_REQUIRE_EMAIL_VERIFICATION` | `false` | Turn on once SMTP exists. |
| `AUTH_PASSKEY_RP_ID` | unset | Registrable domain, e.g. `fasttrackstudio.app`. |
| `AUTH_CORS_ORIGINS` | none | Comma-separated. Empty allows no cross-origin calls. |
| `AUTH_OIDC_CLIENTS` | `[]` | JSON array; see the Deployment manifest. |
| `AUTH_OIDC_DYNAMIC_REGISTRATION` | `false` | Keep off on a public issuer. |
| `AUTH_RUN_MIGRATIONS` | `true` | Idempotent; safe on every pod start. |

The `_FILE` variants are preferred in the cluster: a mounted file does
not show up in `kubectl describe pod` or a crash dump.

## Deploying

Argo CD syncs `deploy/chart/fts-auth`. The `Application` itself is
declared in the cluster repo (`~/.starcommand`,
`modules/services/fts-auth`), which also owns the CNPG database and the
secrets — so this repo holds the code, the chart and the image build, and
the cluster holds what actually runs.

The image is built by `.github/workflows/deploy.yml` on the self-hosted
`nix-host` runner: `nix build .#image` (dockerTools, no Docker daemon)
streamed through skopeo to `registry.starcommand.live:30050/fts-auth`.
The in-cluster registry is LAN-only, so a GitHub-hosted runner cannot
reach it. `argocd-image-updater` then rolls the Deployment by digest.

Historical note, in case the first sync misbehaves:

1. **Database.** CNPG `Database` + owner role for `fts_auth` on
   `pg-main` — declared in the cluster's `databases` service.

2. **Secrets.** `fts-auth-pg` and `fts-auth-secrets`, from nix-secrets
   via `just gen-secrets`. Never committed here. Rotating the signing
   key invalidates every live session across every app — that is the
   revoke-all lever, by design.

3. **Ingress target.** The external-dns annotation comes from
   `constants.tunnelTarget` in the cluster module, so the hostname
   resolves through the Cloudflare tunnel.

4. **Repo credential.** This repo is private, so Argo CD needs a
   read-only deploy key registered as a repository secret before it can
   read the chart.

5. **Architect hash.** `flake.nix` pins the hash of the `architect` git
   dependency. When the pinned tag moves, the build fails loudly with
   the expected value — paste what it prints.

## Caveats

**JWKS is empty, by design.** The engine signs JWTs with `HS256`
(symmetric, hardcoded in `auth/src/flows.rs`). A JWKS publishes *public*
keys; the "public" half of an HS256 key is the signing secret itself, so
publishing it would let any reader mint tokens for any account. Relying
parties verify through `/oauth2/userinfo` instead. Offline id_token
verification by a genuine third party needs RS256/ES256 support
upstream.

**The HTTP surface is a subset.** `architect-auth` describes ~150
routes; this server mounts the OIDC provider and the core session API.
Admin, orgs, teams, passkeys, 2FA and API keys remain reachable over vox
and through `ArchitectAuth` directly. Mounting them generically is
blocked on those command structs deriving no serde.

## Local development

```sh
podman run -d --rm --name fts-auth-pg \
  -e POSTGRES_PASSWORD=dev -e POSTGRES_DB=fts_auth \
  -p 5432:5432 docker.io/library/postgres:16-alpine

AUTH_SECRET=$(openssl rand -base64 48) \
AUTH_DATABASE_URL=postgres://postgres:dev@localhost:5432/fts_auth \
AUTH_BASE_URL=http://localhost:8080 \
  cargo run
```
