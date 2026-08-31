//! `fts-auth` — the FastTrackStudio identity server.
//!
//! One account across Task, Session, Signal, Keyflow and Ignition.
//!
//! Almost nothing lives here on purpose. The server itself is
//! `auth-server` in the public `architect` repo; this crate is the
//! *deployment*: it holds the configuration that is specific to
//! FastTrackStudio and nothing that would be useful to anyone else.
//! Keeping it that way means improvements to the server benefit every
//! consumer, and the private repo stays reviewable in one sitting.
//!
//! Everything is supplied through the environment — see
//! `deploy/manifests.yaml` for what the cluster sets, and the README
//! for the full list.

use auth_server::{ServerConfig, server};

#[tokio::main]
async fn main() -> eyre::Result<()> {
    architect::host::init_tracing("info,auth_server=debug,fts_auth=debug");
    architect::host::install_panic_logger();

    let config = ServerConfig::from_env()?;

    // Fail loudly rather than quietly issuing tokens no one can trust.
    // A misconfigured issuer is not a cosmetic problem: it is the value
    // relying parties pin, so serving the placeholder in production
    // would bake a wrong `iss` into every token minted before someone
    // noticed.
    if config.base_url.starts_with("http://localhost") {
        tracing::warn!(
            "AUTH_BASE_URL is still the localhost default — OIDC discovery will \
             advertise unreachable endpoints"
        );
    }
    if config.oidc_clients.is_empty() {
        tracing::warn!(
            "no OIDC clients configured (AUTH_OIDC_CLIENTS) — only the vox and \
             session-JSON surfaces will be usable"
        );
    }

    tracing::info!(
        issuer = %config.issuer(),
        clients = config.oidc_clients.len(),
        "fts-auth starting"
    );

    let built = server::build(&config).await?;
    server::serve(built).await
}
