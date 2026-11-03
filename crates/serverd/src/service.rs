//! Bearers a platform mints for the service account this process runs
//! as (Cloud Run, GKE, Compute Engine): the model service's ID token for
//! its audience, and the warehouse's access token where a Google bucket
//! is named without a key pair. Each is minted from the metadata
//! server, set on the engine, and minted anew before it expires. A key
//! needs none of this: the engine carries it as named at open.

use std::time::Duration;

use base64::Engine;
use glossql_serverd::engine::SessionError;

/// Google's metadata server, which mints tokens for the attached
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

/// What the metadata server mints: an ID token for an audience, or the
/// account's own access token.
#[derive(Clone)]
pub enum Mint {
    Identity { audience: String },
    Access,
}

impl Mint {
    fn what(&self) -> &'static str {
        match self {
            Mint::Identity { .. } => "the service's bearer",
            Mint::Access => "the warehouse's bearer",
        }
    }
}

/// A bearer now, with how long it is good for: the first one, held
/// before the engine opens on it.
pub async fn first(mint: &Mint) -> Result<(String, Duration), String> {
    mint_token(&reqwest::Client::new(), mint).await
}

/// Keeps a bearer fresh: minted now, unless `held` says one already is
/// and for how long; set on the engine through `set`; minted anew
/// before it expires. A server that does not mint is logged, and tried
/// again: the service answers 401 meanwhile, with its own text, and
/// the warehouse's reads refuse.
pub async fn keep_minting(
    set: impl Fn(&str) -> Result<(), SessionError> + Send + Sync + 'static,
    mint: Mint,
    held: Option<Duration>,
) {
    let client = reqwest::Client::new();
    let mut due = match held {
        Some(ttl) => next(ttl),
        None => match mint_token(&client, &mint).await {
            Ok((token, ttl)) => put(&set, &mint, &token, ttl),
            Err(e) => {
                tracing::warn!(error = %e, what = mint.what(), "not minted yet");
                RETRY
            }
        },
    };
    tokio::spawn(async move {
        loop {
            tokio::time::sleep(due).await;
            due = match mint_token(&client, &mint).await {
                Ok((token, ttl)) => put(&set, &mint, &token, ttl),
                Err(e) => {
                    tracing::warn!(error = %e, what = mint.what(), "not minted anew");
                    RETRY
                }
            };
        }
    });
}

/// Sets the token and says when the next one is due.
fn put(
    set: &impl Fn(&str) -> Result<(), SessionError>,
    mint: &Mint,
    token: &str,
    ttl: Duration,
) -> Duration {
    if let Err(e) = set(token) {
        tracing::warn!(error = %e, what = mint.what(), "the minted bearer did not reach the engine");
        return RETRY;
    }
    tracing::info!(what = mint.what(), valid_for = ?ttl, "minted");
    next(ttl)
}

/// When a token good for `ttl` is minted anew.
fn next(ttl: Duration) -> Duration {
    ttl.saturating_sub(MARGIN).max(Duration::from_secs(1))
}

/// The token from the metadata server, with how long it is good for.
async fn mint_token(client: &reqwest::Client, mint: &Mint) -> Result<(String, Duration), String> {
    let account = format!("{METADATA}/computeMetadata/v1/instance/service-accounts/default");
    let request = match mint {
        Mint::Identity { audience } => client
            .get(format!("{account}/identity"))
            .query(&[("audience", audience.as_str()), ("format", "full")]),
        Mint::Access => client.get(format!("{account}/token")),
    };
    let response = request
        .header("Metadata-Flavor", "Google")
        .timeout(CONNECT_TIMEOUT)
        .send()
        .await
        .map_err(|e| format!("the metadata server did not mint {}: {e}", mint.what()))?;
    if !response.status().is_success() {
        return Err(format!(
            "the metadata server refused to mint {} ({}) — is a service account attached?",
            mint.what(),
            response.status()
        ));
    }
    let body = response
        .text()
        .await
        .map_err(|e| format!("the metadata server's token did not arrive whole: {e}"))?;
    match mint {
        Mint::Identity { .. } => {
            let token = body.trim().to_string();
            let ttl = expires_in(&token).unwrap_or(ASSUMED);
            Ok((token, ttl))
        }
        Mint::Access => access_token(&body),
    }
}

/// The access token and its life from the metadata server's answer:
/// `{"access_token": …, "expires_in": seconds, "token_type": "Bearer"}`.
fn access_token(body: &str) -> Result<(String, Duration), String> {
    let answer: serde_json::Value = serde_json::from_str(body)
        .map_err(|e| format!("the metadata server's answer is not JSON: {e}"))?;
    let token = answer
        .get("access_token")
        .and_then(|v| v.as_str())
        .filter(|t| !t.is_empty())
        .ok_or("the metadata server's answer holds no access_token")?
        .to_string();
    let ttl = answer
        .get("expires_in")
        .and_then(|v| v.as_u64())
        .map(Duration::from_secs)
        .unwrap_or(ASSUMED);
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
        let payload =
            base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(format!(r#"{{"exp": {exp}}}"#));
        let ttl = expires_in(&format!("h.{payload}.s")).expect("an exp claim");
        assert!(ttl > Duration::from_secs(590) && ttl <= Duration::from_secs(600));
        assert_eq!(expires_in("not.a.jwt"), None);
    }

    /// The access token comes in the metadata server's JSON with its
    /// life in seconds; an answer without one is a refusal.
    #[test]
    fn an_access_token_is_read_with_its_life() {
        let (token, ttl) = access_token(
            r#"{"access_token": "ya29.x", "expires_in": 3599, "token_type": "Bearer"}"#,
        )
        .expect("a token");
        assert_eq!(token, "ya29.x");
        assert_eq!(ttl, Duration::from_secs(3599));
        let (_, ttl) = access_token(r#"{"access_token": "t"}"#).expect("a token");
        assert_eq!(ttl, ASSUMED);
        assert!(access_token(r#"{"token_type": "Bearer"}"#).is_err());
        assert!(access_token("not json").is_err());
    }
}
