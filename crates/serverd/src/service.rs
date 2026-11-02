//! The model service's bearer on a platform that mints ID tokens for
//! the service account this process runs as (Cloud Run, GKE, Compute
//! Engine): minted from the metadata server for the service's audience,
//! set on the engine, and minted anew before it expires. A key needs
//! none of this: the engine carries it as named at open.

use std::time::Duration;

use base64::Engine;
use glossql_serverd::engine::TokenSink;

/// Google's metadata server, which mints an ID token for the attached
/// service account.
const METADATA: &str = "http://metadata.google.internal";

/// How long the metadata server has to answer.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);

/// How long before a token's stated expiry it is minted anew.
const MARGIN: Duration = Duration::from_secs(120);

/// What a minted token is good for when it does not say.
const ASSUMED: Duration = Duration::from_secs(1800);

/// How long to wait before trying again when the server did not mint.
const RETRY: Duration = Duration::from_secs(60);

/// Mints the first token now and keeps the engine's bearer fresh from
/// then on. A server that does not mint is logged, and tried again: the
/// service answers 401 meanwhile, with its own text.
pub async fn keep_minting(sink: TokenSink, audience: String) {
    let client = reqwest::Client::new();
    let mut due = match mint(&client, &audience).await {
        Ok((token, ttl)) => set(&sink, &token, ttl),
        Err(e) => {
            tracing::warn!(error = %e, "the service's bearer is not minted yet");
            RETRY
        }
    };
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(due).await;
            due = match mint(&client, &audience).await {
                Ok((token, ttl)) => set(&sink, &token, ttl),
                Err(e) => {
                    tracing::warn!(error = %e, "the service's bearer was not minted anew");
                    RETRY
                }
            };
        }
    });
}

/// Sets the token and says when the next one is due.
fn set(sink: &TokenSink, token: &str, ttl: Duration) -> Duration {
    if let Err(e) = sink.set(token) {
        tracing::warn!(error = %e, "the minted bearer did not reach the engine");
        return RETRY;
    }
    tracing::info!(valid_for = ?ttl, "the service's bearer is minted");
    ttl.saturating_sub(MARGIN).max(Duration::from_secs(1))
}

/// An ID token for `audience` from the metadata server, with how long
/// it is good for.
async fn mint(client: &reqwest::Client, audience: &str) -> Result<(String, Duration), String> {
    let url = format!("{METADATA}/computeMetadata/v1/instance/service-accounts/default/identity");
    let response = client
        .get(&url)
        .query(&[("audience", audience), ("format", "full")])
        .header("Metadata-Flavor", "Google")
        .timeout(CONNECT_TIMEOUT)
        .send()
        .await
        .map_err(|e| format!("the metadata server did not mint a token for the service: {e}"))?;
    if !response.status().is_success() {
        return Err(format!(
            "the metadata server refused to mint a token for the service ({}) — is a service account attached?",
            response.status()
        ));
    }
    let token = response
        .text()
        .await
        .map_err(|e| format!("the metadata server's token did not arrive whole: {e}"))?
        .trim()
        .to_string();
    let ttl = expires_in(&token).unwrap_or(ASSUMED);
    Ok((token, ttl))
}

/// How long a JWT says it is good for, from its `exp` claim.
fn expires_in(token: &str) -> Option<Duration> {
    let payload = token.split('.').nth(1)?;
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(payload)
        .ok()?;
    let claims: serde_json::Value = serde_json::from_slice(&bytes).ok()?;
    let exp = claims.get("exp")?.as_u64()?;
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .ok()?
        .as_secs();
    Some(Duration::from_secs(exp.saturating_sub(now)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_token_says_how_long_it_is_good_for() {
        let exp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs()
            + 600;
        let payload = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .encode(format!(r#"{{"exp": {exp}}}"#));
        let ttl = expires_in(&format!("h.{payload}.s")).expect("an exp claim");
        assert!(ttl > Duration::from_secs(590) && ttl <= Duration::from_secs(600));
        assert_eq!(expires_in("not.a.jwt"), None);
    }
}
