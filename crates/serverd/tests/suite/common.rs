//! The suite's one harness. A test issuer: a key minted when the test
//! starts, a gate that holds its public half, and tokens signed with the
//! private half — the server only ever verifies, and this is the one
//! place in the tree that signs. A scratch workspace behind the
//! interfaces, and one helper per way a test speaks to them.

#![allow(dead_code)]

use std::sync::Arc;

use axum::Router;
use axum::body::{Body, to_bytes};
use axum::http::{Request, Response, StatusCode, header};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use ed25519_dalek::SigningKey;
use ed25519_dalek::pkcs8::EncodePrivateKey;
use glossdb_serverd::{Access, Endpoints, Gate, InterfaceConfig, Login, Plane, router};
use jsonwebtoken::jwk::JwkSet;
use jsonwebtoken::{Algorithm, EncodingKey, Header};
use serde_json::{Value, json};
use tower::ServiceExt;

pub const ISSUER: &str = "https://issuer.test";
pub const RESOURCE: &str = "http://127.0.0.1:8080";
/// The application registered at the test issuer for this server, and
/// its secret.
pub const CLIENT_ID: &str = "glossql-app";
pub const CLIENT_SECRET: &str = "glossql-app-secret";
/// Where the test issuer would send a browser to sign in. Never
/// reached: a test that goes there reads the redirect and stops.
pub const AUTHORIZE: &str = "https://issuer.test/oauth2/auth";
const TOKEN: &str = "https://issuer.test/oauth2/token";
const KID: &str = "test-key";

/// One fixed seed: the key is the same in every test, which is what
/// lets a token minted in one helper be verified by a gate built in
/// another. It never leaves the test binary.
fn signing_key() -> SigningKey {
    SigningKey::from_bytes(&[7u8; 32])
}

/// The public half, as the issuer would publish it.
pub fn jwks() -> JwkSet {
    let public = signing_key().verifying_key().to_bytes();
    serde_json::from_value(json!({
        "keys": [{
            "kty": "OKP",
            "crv": "Ed25519",
            "kid": KID,
            "use": "sig",
            "x": URL_SAFE_NO_PAD.encode(public),
        }]
    }))
    .unwrap()
}

pub fn gate() -> Arc<Gate> {
    gate_with(TOKEN)
}

/// A gate whose issuer exchanges codes at `token_url` — a test that
/// holds the token endpoint in names where.
pub fn gate_with(token_url: &str) -> Arc<Gate> {
    Arc::new(Gate::with_keys(
        ISSUER,
        RESOURCE,
        CLIENT_ID,
        jwks(),
        Endpoints {
            authorization: AUTHORIZE.into(),
            token: token_url.into(),
        },
    ))
}

/// The interfaces' whole arrangement: the login carries the gate.
pub fn login() -> Arc<Login> {
    Arc::new(Login::new(gate(), CLIENT_SECRET).unwrap())
}

pub fn login_with(token_url: &str) -> Arc<Login> {
    Arc::new(Login::new(gate_with(token_url), CLIENT_SECRET).unwrap())
}

/// A token for `sub`, valid for this issuer and this resource.
pub fn token(sub: &str) -> String {
    token_for(sub, ISSUER, RESOURCE, far_future())
}

pub fn token_for(sub: &str, iss: &str, aud: &str, exp: u64) -> String {
    sign(
        KID,
        &json!({ "iss": iss, "aud": aud, "sub": sub, "exp": exp, "iat": 1 }),
    )
}

/// What an issuer that ignores RFC 8707 mints: `aud` empty, naming
/// only the application the token was issued to. Bound to no resource,
/// so bound to nothing here.
pub fn token_from_app(sub: &str, azp: &str) -> String {
    sign(
        KID,
        &json!({ "iss": ISSUER, "aud": [], "azp": azp, "sub": sub, "exp": far_future(), "iat": 1 }),
    )
}

/// Any claims at all, signed by the test issuer.
pub fn token_with(claims: Value) -> String {
    sign(KID, &claims)
}

/// A valid token whose header names a key the issuer does not publish —
/// what a token signed before a rotation looks like afterwards.
pub fn token_under_kid(sub: &str, kid: &str) -> String {
    sign(
        kid,
        &json!({ "iss": ISSUER, "aud": RESOURCE, "sub": sub, "exp": far_future(), "iat": 1 }),
    )
}

/// `token` with its payload swapped for one naming `sub`: the signature
/// no longer covers what the token says.
pub fn forged(token: &str, sub: &str) -> String {
    let mut parts: Vec<&str> = token.split('.').collect();
    let payload = json!({
        "iss": ISSUER, "aud": RESOURCE, "sub": sub, "exp": far_future(), "iat": 1
    })
    .to_string();
    let encoded = URL_SAFE_NO_PAD.encode(payload);
    parts[1] = &encoded;
    parts.join(".")
}

fn sign(kid: &str, claims: &Value) -> String {
    let der = signing_key().to_pkcs8_der().unwrap();
    let key = EncodingKey::from_ed_der(der.as_bytes());
    let mut header = Header::new(Algorithm::EdDSA);
    header.kid = Some(kid.into());
    jsonwebtoken::encode(&header, claims, &key).unwrap()
}

pub fn bearer(sub: &str) -> String {
    format!("Bearer {}", token(sub))
}

pub fn far_future() -> u64 {
    9_999_999_999
}

/// The person the harness speaks as: the bootstrap actor.
pub fn human() -> glossdb_serverd::engine::Actor {
    glossdb_serverd::engine::Actor {
        kind: glossdb_serverd::engine::ActorKind::Human,
        id: glossdb_serverd::BOOTSTRAP.into(),
    }
}

/// A scratch workspace: the extension and its kits from beside this
/// checkout, the lake in a directory of its own.
pub async fn scratch_plane() -> (tempfile::TempDir, glossdb_serverd::Plane) {
    scratch_plane_capped(glossdb_serverd::DEFAULT_ROW_CAP).await
}

/// The same workspace, a data read cut at `row_cap` rows.
pub async fn scratch_plane_capped(row_cap: usize) -> (tempfile::TempDir, glossdb_serverd::Plane) {
    let dir = tempfile::tempdir().unwrap();
    let mut config = glossdb_serverd::engine::testing::golden(dir.path())
        .await
        .unwrap();
    config.root = vec![glossdb_serverd::BOOTSTRAP.into()];
    config.row_cap = row_cap;
    let plane = glossdb_serverd::Plane::open(config).await.unwrap();
    (dir, plane)
}

/// The 2026-07-28 revision moved the handshake into every request: this
/// `_meta` is what a sessionless client stamps.
pub fn meta() -> Value {
    json!({
        "io.modelcontextprotocol/protocolVersion": "2026-07-28",
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "suite", "version": "0"}
    })
}

/// One stateless JSON-RPC POST to the agent interface at `path` — the
/// workspace's (`/mcp`) or a dataset's (`/<dataset>/mcp`) — under the
/// `Host` a client would send, as the agent `dev-agent`.
pub async fn mcp_on(app: Router, path: &str, host: &str, payload: Value) -> Response<Body> {
    let method = payload["method"].as_str().unwrap().to_string();
    let mut request = Request::post(path)
        // oneshot skips what every real client sends; the transport's
        // rebinding guard (allowed_hosts) rightly insists on it.
        .header(header::HOST, host)
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT, "application/json, text/event-stream")
        .header(header::AUTHORIZATION, bearer("dev-agent"))
        .header("mcp-protocol-version", "2026-07-28")
        .header("mcp-method", method);
    // SEP-2243: a call names its subject in the header too — from
    // `name` for tools and prompts, from `uri` for resources.
    if let Some(name) = payload["params"]["name"]
        .as_str()
        .or_else(|| payload["params"]["uri"].as_str())
    {
        request = request.header("mcp-name", name.to_string());
    }
    app.oneshot(request.body(Body::from(payload.to_string())).unwrap())
        .await
        .unwrap()
}

/// The body, after insisting on 200 — a refused request panics with what
/// the transport said, not a bare status.
pub async fn expect_ok(response: Response<Body>) -> Value {
    let status = response.status();
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let text = String::from_utf8_lossy(&bytes);
    assert_eq!(status, StatusCode::OK, "{text}");
    serde_json::from_str(&text).unwrap()
}

/// A served workspace: the interfaces, the plane behind them, and the
/// directory the lake lives in (dropped with the test).
pub type Served = (Router, Arc<Plane>, tempfile::TempDir);

/// The interfaces over a scratch workspace with the served pages, a data
/// read cut at `row_cap` rows.
pub async fn served(row_cap: usize, interfaces: InterfaceConfig, access: Access) -> Served {
    let (dir, plane) = scratch_plane_capped(row_cap).await;
    let plane = Arc::new(
        plane.with_pages(
            glossdb_serverd::skills::served_pages()
                .expect("the language's documents beside the extension's kits"),
        ),
    );
    (router(Arc::clone(&plane), interfaces, access), plane, dir)
}

/// The gated interfaces over an empty workspace.
pub async fn app() -> Served {
    served(
        glossdb_serverd::DEFAULT_ROW_CAP,
        InterfaceConfig::default(),
        Access::Gated(login()),
    )
    .await
}

/// The gated interfaces over a workspace that holds `dataset`, declared
/// through the workspace's agent interface.
pub async fn app_on(dataset: &str) -> Served {
    let served = app().await;
    say(
        &served.0,
        "/mcp",
        &format!("DECLARE DATASET {dataset} SET (purpose: 'the suite');"),
    )
    .await;
    served
}

/// The gated interfaces over a new workspace that holds `dataset`, the
/// engine opened with every kit but `kits/<kit>/kit.sql` for each kit
/// named.
pub async fn app_on_without(dataset: &str, kits: &[&str]) -> Served {
    let dir = tempfile::tempdir().unwrap();
    let mut config = glossdb_serverd::engine::Config::laptop(dir.path());
    let before = config.kits.len();
    config.kits.retain(|path| {
        !kits
            .iter()
            .any(|kit| path.ends_with(std::path::Path::new(kit).join("kit.sql")))
    });
    assert_eq!(
        config.kits.len(),
        before - kits.len(),
        "a kit of {kits:?} is not among the kits"
    );
    app_on_config(dataset, config, dir).await
}

/// The gated interfaces over a new workspace that holds `dataset`, the
/// engine opened with the model service at `url`.
pub async fn app_on_service(dataset: &str, url: &str) -> Served {
    let dir = tempfile::tempdir().unwrap();
    let mut config = glossdb_serverd::engine::Config::laptop(dir.path());
    config.service = Some(glossdb_serverd::engine::Service {
        url: url.to_string(),
        token: None,
        audience: None,
    });
    app_on_config(dataset, config, dir).await
}

async fn app_on_config(
    dataset: &str,
    mut config: glossdb_serverd::engine::Config,
    dir: tempfile::TempDir,
) -> Served {
    config.root = vec![glossdb_serverd::BOOTSTRAP.into()];
    let plane = Arc::new(
        Plane::open(config).await.unwrap().with_pages(
            glossdb_serverd::skills::served_pages()
                .expect("the language's documents beside the extension's kits"),
        ),
    );
    let app = router(
        Arc::clone(&plane),
        InterfaceConfig::default(),
        Access::Gated(login()),
    );
    say(
        &app,
        "/mcp",
        &format!("DECLARE DATASET {dataset} SET (purpose: 'the suite');"),
    )
    .await;
    (app, plane, dir)
}

/// A `tools/call` of the one tool, stamped with `meta_value`; `answer`
/// is a review form's answer under its key, sent back with the call.
pub fn call_with(meta_value: Value, statements: &str, answer: Option<(&str, Value)>) -> Value {
    let mut params = json!({
        "_meta": meta_value,
        "name": "glossql",
        "arguments": {"statements": statements}
    });
    if let Some((key, answer)) = answer {
        params["inputResponses"] = json!({ key: answer });
        params["requestState"] = json!("review:v1");
    }
    json!({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": params})
}

/// The sessionless stamp with the elicitation capability advertised.
pub fn meta_elicit() -> Value {
    let mut stamp = meta();
    stamp["io.modelcontextprotocol/clientCapabilities"] = json!({"elicitation": {}});
    stamp
}

/// A JSON-RPC request other than a tool call, on the agent interface at `path`.
pub async fn rpc(app: &Router, path: &str, method: &str, params: Value) -> Value {
    let mut params = params;
    params["_meta"] = meta();
    let payload = json!({"jsonrpc": "2.0", "id": 1, "method": method, "params": params});
    expect_ok(mcp_on(app.clone(), path, "127.0.0.1", payload).await).await
}

/// The JSON-RPC body of one tool call on the agent interface at `path`.
pub async fn tool(app: &Router, path: &str, statements: &str) -> Value {
    let payload = call_with(meta(), statements, None);
    expect_ok(mcp_on(app.clone(), path, "127.0.0.1", payload).await).await
}

/// One tool call on the workspace's agent interface from a client that
/// takes review forms, with the answer to one form if given.
pub async fn elicit(app: &Router, statements: &str, answer: Option<(&str, Value)>) -> Value {
    let payload = call_with(meta_elicit(), statements, answer);
    expect_ok(mcp_on(app.clone(), "/mcp", "127.0.0.1", payload).await).await
}

/// The outcomes of a tool call, one per statement.
pub fn outcomes(body: &Value) -> Value {
    let text = body["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_else(|| panic!("{body}"));
    serde_json::from_str(text).unwrap_or_else(|e| panic!("{e}: {text}"))
}

/// The lines that close a tool call's result: the second content block.
pub fn window(body: &Value) -> String {
    body["result"]["content"][1]["text"]
        .as_str()
        .unwrap_or_else(|| panic!("{body}"))
        .to_string()
}

/// Statements on the agent interface at `path`: their outcomes, and a
/// panic on a refusal.
pub async fn say(app: &Router, path: &str, statements: &str) -> Value {
    let body = tool(app, path, statements).await;
    assert_ne!(
        body["result"]["isError"],
        json!(true),
        "`{statements}`: {body}"
    );
    outcomes(&body)
}

/// The rows of the last read among `statements` on the agent interface at `path`.
pub async fn rows(app: &Router, path: &str, statements: &str) -> Vec<Value> {
    let outcomes = say(app, path, statements).await;
    let last = outcomes.as_array().and_then(|o| o.last()).cloned();
    last.and_then(|o| o["rows"].as_array().cloned())
        .unwrap_or_default()
}

/// A tool call that must be refused: its body.
pub async fn refused(app: &Router, path: &str, statements: &str) -> Value {
    let body = tool(app, path, statements).await;
    assert_eq!(
        body["result"]["isError"],
        json!(true),
        "`{statements}` was not refused: {body}"
    );
    body
}

/// A POST of `sql` to the query interface at `path`, with `authorization`
/// as the header if given.
pub async fn post_query(
    app: &Router,
    path: &str,
    authorization: Option<String>,
    sql: &str,
) -> Response<Body> {
    let mut request = Request::post(path);
    if let Some(authorization) = authorization {
        request = request.header(header::AUTHORIZATION, authorization);
    }
    app.clone()
        .oneshot(request.body(Body::from(sql.to_string())).unwrap())
        .await
        .unwrap()
}

/// `sql` on `fin`'s query interface as the person `dev-human`: the
/// status and the JSON body.
pub async fn query(app: &Router, sql: &str) -> (StatusCode, Value) {
    let response = post_query(app, "/fin/query", Some(bearer("dev-human")), sql).await;
    let status = response.status();
    (status, body_json(response).await)
}

/// A GET as the person `dev-human`.
pub async fn get(app: &Router, uri: &str) -> Response<Body> {
    app.clone()
        .oneshot(
            Request::get(uri)
                .header(header::AUTHORIZATION, bearer("dev-human"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap()
}

pub async fn body_json(response: Response<Body>) -> Value {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    serde_json::from_slice(&bytes).unwrap_or_else(|e| panic!("{e}: {bytes:?}"))
}

pub async fn body_text(response: Response<Body>) -> String {
    let bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    String::from_utf8(bytes.to_vec()).unwrap()
}
