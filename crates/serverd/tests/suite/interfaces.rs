//! The interfaces against a real plane, driven in-process through the router
//! (tower's oneshot — no sockets): `/query` streams Arrow IPC a reader
//! round-trips; the MCP interface initializes, lists the one tool, executes
//! statements, and answers a failed statement as a tool error, not a
//! protocol error.

use std::collections::HashMap;
use std::sync::Arc;

use axum::Router;
use axum::body::Body;
use axum::http::{Request, Response, StatusCode, header};
use glossdb_serverd::{ARROW_STREAM, Access, INSECURE_DEV_MODE, InterfaceConfig, router};
use serde_json::{Value, json};
use tower::ServiceExt;

use crate::common::{
    self, app, app_on, body_json, body_text, elicit, expect_ok, get, mcp_on, meta, outcomes,
    post_query, query, rows, rpc, say, tool, window,
};

const INT: &str = "Int32";
type IntArray = arrow::array::Int32Array;

/// The gated interfaces under `interfaces` and `login`, a data read cut
/// at `row_cap` rows.
async fn app_with(
    row_cap: usize,
    interfaces: InterfaceConfig,
    login: Arc<glossdb_serverd::Login>,
) -> common::Served {
    common::served(row_cap, interfaces, Access::Gated(login)).await
}

/// One JSON-RPC POST to the workspace's agent interface under `host`.
async fn mcp_at(app: &Router, host: &str, payload: Value) -> Response<Body> {
    mcp_on(app.clone(), "/mcp", host, payload).await
}

fn initialize() -> Value {
    json!({
        "jsonrpc": "2.0", "id": 0, "method": "initialize",
        "params": {
            "protocolVersion": "2026-07-28",
            "capabilities": {},
            "clientInfo": {"name": "interfaces-test", "version": "0"}
        }
    })
}

/// The gated interfaces over a workspace with the dataset `fin`, the
/// kits' own vocabulary, and `statements` run on it: the fixture of the
/// review and the workspace map.
async fn on_fin(statements: &str) -> common::Served {
    let served = app_on("fin").await;
    say(&served.0, "/mcp", &format!("USE fin; {statements}")).await;
    served
}

/// A raw `tools/call` request on `/mcp` with `authorization` if given:
/// for the tests that speak as someone other than `dev-agent`.
fn raw_call(authorization: Option<String>, statements: &str) -> Request<Body> {
    let mut request = Request::post("/mcp")
        .header(header::HOST, "127.0.0.1")
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT, "application/json, text/event-stream")
        .header("mcp-protocol-version", "2026-07-28")
        .header("mcp-method", "tools/call")
        .header("mcp-name", "glossql");
    if let Some(authorization) = authorization {
        request = request.header(header::AUTHORIZATION, authorization);
    }
    request
        .body(Body::from(
            common::call_with(meta(), statements, None).to_string(),
        ))
        .unwrap()
}

#[tokio::test(flavor = "multi_thread")]
async fn a_dataset_the_workspace_does_not_hold_is_a_404() {
    // The URL is the binding, so a name nobody declared is a missing
    // resource. The answer names what the workspace does hold.
    let (app, _, _dir) = app_on("fin").await;
    let response = get(&app, "/nope/app/console/frames/census").await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);

    let response = post_query(
        &app,
        "/nope/query",
        Some(common::bearer("dev-human")),
        "SELECT 1",
    )
    .await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    let body = body_json(response).await;
    assert!(body["error"].as_str().unwrap().contains("fin"), "{body}");
}

/// A refusal answers by its class, with its reason in the body: a name
/// the catalog does not hold is not found, the statement's own fault is
/// unprocessable, and so is a refused statement that is not one read.
#[tokio::test(flavor = "multi_thread")]
async fn the_query_interface_answers_a_refusal_by_its_class() {
    let (app, _, _dir) = app_on("fin").await;
    for (sql, status, named) in [
        ("SELECT * FROM nope", StatusCode::NOT_FOUND, "nope"),
        (
            "SELECT * FROM view_summary('revenue')",
            StatusCode::UNPROCESSABLE_ENTITY,
            "view_summary",
        ),
        ("USE nothing", StatusCode::UNPROCESSABLE_ENTITY, "nothing"),
    ] {
        let (answered, body) = query(&app, sql).await;
        assert_eq!(answered, status, "{sql}: {body}");
        assert!(body["error"].as_str().unwrap().contains(named), "{body}");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn the_query_interface_streams_arrow_ipc() {
    let (app, _, _dir) = app_on("fin").await;
    let response = post_query(
        &app,
        "/fin/query",
        Some(common::bearer("dev-human")),
        "SELECT 1 + 1 AS two",
    )
    .await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.headers()[header::CONTENT_TYPE], ARROW_STREAM);
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let reader =
        arrow_ipc::reader::StreamReader::try_new(std::io::Cursor::new(bytes.to_vec()), None)
            .unwrap();
    let batches: Vec<_> = reader.map(|b| b.unwrap()).collect();
    assert_eq!(batches.len(), 1);
    assert_eq!(batches[0].schema().field(0).name(), "two");
    let column = batches[0]
        .column(0)
        .as_any()
        .downcast_ref::<IntArray>()
        .unwrap();
    assert_eq!(column.value(0), 2);
}

/// A read that plans but fails on its first poll — here a cast the
/// engine only evaluates at execution — is refused, not answered 200
/// with a body that breaks: the status is set on the first batch.
#[tokio::test(flavor = "multi_thread")]
async fn the_query_interface_refuses_a_read_the_engine_cannot_start() {
    let (app, _, _dir) = app_on("fin").await;
    let (status, body) = query(&app, "SELECT CAST('x' AS INT) AS n").await;
    assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY, "{body}");
    assert!(body["error"].as_str().unwrap().contains("'x'"), "{body}");
}

/// The interface's gate: a human at the query interface is a standard actor
/// unless the deployment names them root, so a `SET` that would take
/// another actor kind is closed, and so is an `ATTACH`.
#[tokio::test(flavor = "multi_thread")]
async fn the_query_interface_refuses_engine_settings_to_a_standard_actor() {
    let (app, _, _dir) = app_on("fin").await;
    for (statement, word) in [
        ("SET VARIABLE glossql_actor = 'human'", "SET"),
        ("ATTACH ':memory:' AS other", "ATTACH"),
    ] {
        let (status, body) = query(&app, statement).await;
        assert!(status.is_client_error(), "{statement}");
        let error = body["error"].as_str().unwrap();
        assert!(error.contains(word), "{statement}: {error}");
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn the_query_interface_answers_a_statement_sequence_in_json() {
    let (app, _, _dir) = app_on("fin").await;
    let (status, body) = query(&app, "SELECT 1 AS a; SELECT 2 AS b").await;
    assert_eq!(status, StatusCode::OK);
    let outcomes = body.as_array().unwrap();
    assert_eq!(outcomes.len(), 2);
    assert_eq!(outcomes[0]["rows"][0]["a"], json!(1));
    assert_eq!(outcomes[1]["rows"][0]["b"], json!(2));
}

/// The pages the interface serves as resources are rows of `pages()` too —
/// the read for a client that has the statement tool and nothing else.
#[tokio::test(flavor = "multi_thread")]
async fn the_served_pages_are_rows_of_pages() {
    let (app, _, _dir) = app_on("fin").await;
    let (status, body) = query(
        &app,
        "SELECT body FROM pages() WHERE uri = 'skill://glossql/SKILL.md'; \
         SELECT count(*) AS n FROM pages()",
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body[0]["rows"][0]["body"],
        json!(glossdb_serverd::skills::SKILLS[0].body)
    );
    let served = {
        use glossdb_serverd::skills::{DOC_NAMES, PAGES, REFERENCES, SKILLS, VENDORED};
        SKILLS.len() + DOC_NAMES.len() + REFERENCES.len() + PAGES.len() + VENDORED.len()
    };
    assert_eq!(body[1]["rows"][0]["n"], json!(served));
}

/// The statements both arrangements write a note with: the agent
/// interface declares and annotates, a human interface annotates again,
/// and the glossary then holds one current row per actor kind.
const NOTE_BY_AGENT: &str = "DECLARE DATASET fin SET (purpose: 'who wrote it');\n\
     USE fin;\n\
     DECLARE ASPECT note WITH $${\"type\": \"object\"}$$ AS FACT ON DATASET;\n\
     GLOSS note ON fin AS $${\"value\": \"through the agent interface\"}$$;\n\
     SELECT actor_id, actor_kind FROM glossary WHERE aspect = 'note';";
const NOTE_BY_HUMAN: &str = "GLOSS note ON fin AS $${\"value\": \"through the human interface\"}$$;\n\
     SELECT actor_id, actor_kind FROM glossary WHERE aspect = 'note' ORDER BY actor_kind;";

/// The note's writers, as the agent interface and then a human interface
/// recorded them, each with `authorization` if given.
async fn note_writers(app: &Router, authorization: Option<String>) -> (Value, Vec<Value>) {
    let request = raw_call(authorization.clone(), NOTE_BY_AGENT);
    let body = expect_ok(app.clone().oneshot(request).await.unwrap()).await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");
    let by_agent = outcomes(&body).as_array().unwrap().last().unwrap()["rows"][0].clone();
    let response = post_query(app, "/fin/query", authorization, NOTE_BY_HUMAN).await;
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    let both = body[1]["rows"]
        .as_array()
        .cloned()
        .unwrap_or_else(|| panic!("{body}"));
    (by_agent, both)
}

/// The gate. A bearer token from the issuer names who is speaking; the
/// interface names with which actor kind — never the handshake's
/// `clientInfo` name, which a client picks for itself. Both rows are
/// current: the supersession key's third leg is the kind.
#[tokio::test(flavor = "multi_thread")]
async fn the_token_names_the_actor_and_the_interface_names_its_kind() {
    let (app, _, _dir) = app().await;
    let (by_agent, both) = note_writers(&app, Some(common::bearer("ada"))).await;
    assert_eq!(by_agent["actor_id"], json!("ada"), "{by_agent}");
    assert_eq!(by_agent["actor_kind"], json!("agent"), "{by_agent}");
    let kinds: Vec<&Value> = both.iter().map(|r| &r["actor_kind"]).collect();
    assert_eq!(kinds, [&json!("agent"), &json!("human")], "{both:?}");
    assert!(
        both.iter().all(|r| r["actor_id"] == json!("ada")),
        "{both:?}"
    );
}

/// The explicit open arrangement (`Access::Open`, the
/// GLOSSDB_INSECURE_OPEN switch): no interface asks for a token, and the
/// catalog still names who spoke — the well-known dev actor, with the
/// interface's actor kind. No login and no discovery document are served.
#[tokio::test(flavor = "multi_thread")]
async fn open_access_asks_no_token_and_writes_as_the_dev_actor() {
    let (app, _, _dir) = common::served(
        glossdb_serverd::DEFAULT_ROW_CAP,
        InterfaceConfig::default(),
        Access::Open,
    )
    .await;
    let (by_agent, both) = note_writers(&app, None).await;
    assert_eq!(by_agent["actor_id"], json!(INSECURE_DEV_MODE));
    assert_eq!(by_agent["actor_kind"], json!("agent"));
    let kinds: Vec<&Value> = both.iter().map(|r| &r["actor_kind"]).collect();
    assert_eq!(kinds, [&json!("agent"), &json!("human")], "{both:?}");
    assert!(
        both.iter()
            .all(|r| r["actor_id"] == json!(INSECURE_DEV_MODE)),
        "{both:?}"
    );

    for path in ["/auth/login", "/.well-known/oauth-protected-resource"] {
        let response = app
            .clone()
            .oneshot(Request::get(path).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND, "{path}");
    }
}

/// A request that brings no token, or one this issuer did not mint for
/// this server, is refused with the discovery pointer an OAuth-capable
/// client follows. Each refusal here is one check the gate makes:
/// signature, key, issuer, audience, expiry.
#[tokio::test(flavor = "multi_thread")]
async fn a_missing_or_foreign_token_is_refused_with_the_discovery_pointer() {
    let (app, _, _dir) = app().await;

    let none = post_query(&app, "/fin/query", None, "SELECT 1").await;
    assert_eq!(none.status(), StatusCode::UNAUTHORIZED);
    let challenge = none.headers()[header::WWW_AUTHENTICATE]
        .to_str()
        .unwrap()
        .to_string();
    assert!(
        challenge.contains("oauth-protected-resource"),
        "{challenge}"
    );

    // The agent interface refuses before the protocol ever sees the body.
    let agent_interface = app
        .clone()
        .oneshot(
            Request::post("/mcp")
                .header(header::HOST, "127.0.0.1")
                .header(header::CONTENT_TYPE, "application/json")
                .body(Body::from("{}"))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(agent_interface.status(), StatusCode::UNAUTHORIZED);

    let foreign = [
        ("not a token", "not.a.token".to_string()),
        (
            "another audience",
            common::token_for(
                "ada",
                common::ISSUER,
                "https://elsewhere.example",
                common::far_future(),
            ),
        ),
        (
            "another issuer",
            common::token_for(
                "ada",
                "https://other.issuer.test",
                common::RESOURCE,
                common::far_future(),
            ),
        ),
        (
            "expired",
            common::token_for("ada", common::ISSUER, common::RESOURCE, 1),
        ),
        (
            "a key the issuer does not publish",
            common::token_under_kid("ada", "rotated-away"),
        ),
        (
            "a rewritten subject",
            common::forged(&common::token("ada"), "mallory"),
        ),
    ];
    for (why, token) in foreign {
        let response = post_query(
            &app,
            "/fin/query",
            Some(format!("Bearer {token}")),
            "SELECT 1",
        )
        .await;
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED, "{why}");
    }
}

/// The audience is the whole binding. RFC 8707, which the MCP
/// authorization spec makes a MUST, has the client ask for this
/// server's canonical URI with `resource=` and the issuer stamp it as
/// `aud`. A token that names some other resource is refused, and so is
/// one that names none — whatever application it was minted for, under
/// either name that claim goes by (RFC 9068 spells it `client_id`).
#[tokio::test(flavor = "multi_thread")]
async fn only_a_token_that_names_this_server_opens_it() {
    let (app, _, _dir) = app_on("fin").await;
    let status = async |token: String| {
        post_query(
            &app,
            "/fin/query",
            Some(format!("Bearer {token}")),
            "SELECT 1 AS one",
        )
        .await
        .status()
    };
    assert_eq!(status(common::token("ada")).await, StatusCode::OK);
    for token in [
        common::token_from_app("ada", common::CLIENT_ID),
        common::token_with(json!({
            "iss": common::ISSUER, "aud": [], "client_id": common::CLIENT_ID,
            "sub": "ada", "exp": common::far_future(), "iat": 1
        })),
        common::token_with(json!({
            "iss": common::ISSUER, "aud": "https://elsewhere.example", "azp": common::CLIENT_ID,
            "sub": "ada", "exp": common::far_future(), "iat": 1
        })),
    ] {
        assert_eq!(status(token).await, StatusCode::UNAUTHORIZED);
    }
}

/// A person in a browser holds no token, so a navigation to an interface is
/// sent to sign in and brought back afterwards; a machine's call gets
/// the 401 it can act on.
#[tokio::test(flavor = "multi_thread")]
async fn a_browser_without_a_token_is_sent_to_sign_in() {
    let (app, _, _dir) = app().await;
    let response = app
        .oneshot(
            Request::get("/fin/app/console?page=2")
                .header(header::ACCEPT, "text/html,application/xhtml+xml")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::SEE_OTHER);
    assert_eq!(
        response.headers()[header::LOCATION],
        "/auth/login?next=%2Ffin%2Fapp%2Fconsole%3Fpage%3D2"
    );
}

/// The whole browser flow against a stand-in issuer: off to sign in
/// with PKCE and the resource named, back with a code, the code
/// exchanged at the token endpoint with the verifier and the
/// application's secret in the body, the token verified by the gate and
/// handed to the browser as the cookie — which then opens a human interface.
#[tokio::test(flavor = "multi_thread")]
async fn a_browser_signs_in_at_the_issuer_and_comes_back_with_a_cookie() {
    // The issuer's token endpoint, stood in for: it records what it was
    // asked and answers with a token the test issuer signed.
    let asked: Arc<std::sync::Mutex<Option<HashMap<String, String>>>> = Arc::default();
    let recorder = Arc::clone(&asked);
    let issuer = Router::new().route(
        "/token",
        axum::routing::post(
            move |axum::Form(form): axum::Form<HashMap<String, String>>| {
                let recorder = Arc::clone(&recorder);
                async move {
                    *recorder.lock().unwrap() = Some(form);
                    axum::Json(json!({
                        "access_token": common::token("ada"),
                        "token_type": "Bearer",
                        "expires_in": 3600
                    }))
                }
            },
        ),
    );
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let token_url = format!("http://{}/token", listener.local_addr().unwrap());
    tokio::spawn(async move { axum::serve(listener, issuer).await.unwrap() });

    let (app, _, _dir) = app_with(
        glossdb_serverd::DEFAULT_ROW_CAP,
        InterfaceConfig::default(),
        common::login_with(&token_url),
    )
    .await;
    say(
        &app,
        "/mcp",
        "DECLARE DATASET fin SET (purpose: 'login test');",
    )
    .await;

    // Off to the issuer, with everything the code flow needs.
    let going = app
        .clone()
        .oneshot(
            Request::get("/auth/login?next=/fin/app/console")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(going.status(), StatusCode::SEE_OTHER);
    let location = going.headers()[header::LOCATION]
        .to_str()
        .unwrap()
        .to_string();
    assert!(location.starts_with(common::AUTHORIZE), "{location}");
    let params: HashMap<String, String> = oauth2::url::Url::parse(&location)
        .unwrap()
        .query_pairs()
        .into_owned()
        .collect();
    assert_eq!(params["response_type"], "code");
    assert_eq!(params["client_id"], common::CLIENT_ID);
    assert_eq!(params["code_challenge_method"], "S256");
    assert_eq!(params["resource"], common::RESOURCE);
    assert_eq!(
        params["redirect_uri"],
        format!("{}/auth/callback", common::RESOURCE)
    );
    let state = params["state"].clone();
    let pending = going.headers()[header::SET_COOKIE]
        .to_str()
        .unwrap()
        .to_string();
    assert!(
        pending.starts_with("glossql_login=")
            && pending.contains("HttpOnly")
            && pending.contains("Path=/auth"),
        "{pending}"
    );
    let pending_cookie = pending.split(';').next().unwrap().to_string();

    // Back with the wrong state: refused.
    let wrong = app
        .clone()
        .oneshot(
            Request::get("/auth/callback?code=abc&state=not-that-one")
                .header(header::COOKIE, &pending_cookie)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(wrong.status(), StatusCode::BAD_REQUEST);

    // Back with the right one: exchanged, verified, handed over.
    let back = app
        .clone()
        .oneshot(
            Request::get(format!("/auth/callback?code=abc&state={state}"))
                .header(header::COOKIE, &pending_cookie)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let status = back.status();
    let headers = back.headers().clone();
    let said = body_text(back).await;
    assert_eq!(status, StatusCode::SEE_OTHER, "{said}");
    assert_eq!(headers[header::LOCATION], "/fin/app/console");
    let cookies: Vec<String> = headers
        .get_all(header::SET_COOKIE)
        .iter()
        .map(|v| v.to_str().unwrap().to_string())
        .collect();
    let token_cookie = cookies
        .iter()
        .find(|c| c.starts_with("glossql_token="))
        .unwrap_or_else(|| panic!("no token cookie in {cookies:?}"));
    assert!(
        token_cookie.contains("HttpOnly")
            && token_cookie.contains("SameSite=Lax")
            && token_cookie.contains("Path=/")
            && token_cookie.contains("Max-Age=3600")
            && !token_cookie.contains("Secure"),
        "{token_cookie}"
    );
    assert!(
        cookies
            .iter()
            .any(|c| c.starts_with("glossql_login=;") && c.contains("Max-Age=0")),
        "the login in progress is cleared: {cookies:?}"
    );
    let exchange = asked
        .lock()
        .unwrap()
        .clone()
        .expect("the token endpoint was asked");
    assert_eq!(exchange["grant_type"], "authorization_code");
    assert_eq!(exchange["code"], "abc");
    assert_eq!(exchange["client_id"], common::CLIENT_ID);
    assert_eq!(exchange["client_secret"], common::CLIENT_SECRET);
    assert_eq!(
        exchange["redirect_uri"],
        format!("{}/auth/callback", common::RESOURCE)
    );
    assert_eq!(exchange["resource"], common::RESOURCE);
    assert!(exchange.contains_key("code_verifier"), "{exchange:?}");

    // The cookie opens a human interface.
    let cookie = token_cookie.split(';').next().unwrap().to_string();
    // And no agent interface: a browser's session never speaks as an agent.
    let as_agent = app
        .clone()
        .oneshot(
            Request::post("/mcp")
                .header(header::HOST, "127.0.0.1")
                .header(header::CONTENT_TYPE, "application/json")
                .header(header::ACCEPT, "application/json, text/event-stream")
                .header(header::COOKIE, &cookie)
                .body(Body::from(
                    json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}})
                        .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(as_agent.status(), StatusCode::UNAUTHORIZED);
    let console = app
        .clone()
        .oneshot(
            Request::get("/fin/app/console")
                .header(header::COOKIE, &cookie)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(console.status(), StatusCode::OK);

    // And logout takes it away — on a POST, the person's own act; a
    // GET, which any page could send with the cookie riding along, is
    // not a way out.
    let link = app
        .clone()
        .oneshot(Request::get("/auth/logout").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(link.status(), StatusCode::METHOD_NOT_ALLOWED);
    let out = app
        .oneshot(Request::post("/auth/logout").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(out.status(), StatusCode::SEE_OTHER);
    assert!(
        out.headers()[header::SET_COOKIE]
            .to_str()
            .unwrap()
            .starts_with("glossql_token=;")
    );
}

/// Where a sign-in comes back to is a path on this server and nothing
/// else: a `next` that a browser would read as another host — a
/// scheme-relative URL, a backslash after the slash, an absolute URL
/// elsewhere — or that carries a control character is stored on `/`.
#[tokio::test(flavor = "multi_thread")]
async fn the_login_brings_a_person_back_to_this_server_alone() {
    use base64::Engine as _;
    let (app, _, _dir) = app().await;
    // `next` as the browser sends it (the request line is encoded) and
    // the path the pending cookie keeps.
    let cases = [
        (
            "%2Ffin%2Fapp%2Fconsole%3Fpage%3D2",
            "/fin/app/console?page=2",
        ),
        ("http%3A%2F%2F127.0.0.1%3A8080%2Ffin", "/fin"),
        ("", "/"),
        ("%2F%5Cevil.example", "/"),
        ("%2F%255Cevil.example", "/"),
        ("%2F%2Fevil.example", "/"),
        ("https%3A%2F%2Fevil.example%2Fx", "/"),
        ("https%3A%2F%2F127.0.0.1%3A8080%2Ffin", "/"),
        ("%2Ffin%0D%0ASet-Cookie%3Ax", "/"),
        ("%2Ffin%250D%250A", "/"),
    ];
    for (sent, kept) in cases {
        let going = app
            .clone()
            .oneshot(
                Request::get(format!("/auth/login?next={sent}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(going.status(), StatusCode::SEE_OTHER, "{sent}");
        let pending = going.headers()[header::SET_COOKIE]
            .to_str()
            .unwrap()
            .split(';')
            .next()
            .unwrap()
            .trim_start_matches("glossql_login=")
            .to_string();
        let pending: serde_json::Value = serde_json::from_slice(
            &base64::engine::general_purpose::URL_SAFE_NO_PAD
                .decode(pending)
                .unwrap(),
        )
        .unwrap();
        assert_eq!(pending["next"], kept, "{sent}");
    }
}

/// The discovery document sits outside the gate — it is where a client
/// learns how to authenticate, and a document that answered 401 would
/// point the client at itself. So do the app's own assets, which hold
/// no data.
#[tokio::test(flavor = "multi_thread")]
async fn the_discovery_document_and_the_assets_answer_without_a_token() {
    let (app, _, _dir) = app().await;
    let response = app
        .clone()
        .oneshot(
            Request::get("/.well-known/oauth-protected-resource")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let body = body_json(response).await;
    assert_eq!(body["resource"], json!(common::RESOURCE), "{body}");
    assert_eq!(
        body["authorization_servers"],
        json!([common::ISSUER]),
        "{body}"
    );
    // RFC 9728 §3.1: a client given `…/mcp` asks under that path first.
    let under_path = app
        .clone()
        .oneshot(
            Request::get("/.well-known/oauth-protected-resource/mcp")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(under_path.status(), StatusCode::OK);
    assert_eq!(body_json(under_path).await, body);

    let asset = app
        .oneshot(
            Request::get("/assets/gl-rows.js")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(asset.status(), StatusCode::OK);
}

/// The probe answers outside the gate in both arrangements: it is the
/// one path a platform asks every few seconds, and a probe that had to
/// authenticate would be a platform holding a token.
#[tokio::test(flavor = "multi_thread")]
async fn the_probe_answers_without_a_token_in_both_arrangements() {
    let (gated, plane, _dir) = app().await;
    let open = router(plane, InterfaceConfig::default(), Access::Open);
    for app in [gated, open] {
        let response = app
            .oneshot(Request::get("/healthz").body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(body_text(response).await, "ok");
    }
}

/// The agent interface's `Host` guard: the transport's loopback default
/// refuses a public hostname — the DNS-rebinding guard of a laptop
/// server — and a config that names the host, the deployment's own
/// URL, answers it.
#[tokio::test(flavor = "multi_thread")]
async fn the_agent_interface_answers_the_hosts_its_config_names() {
    let public = "glossql-trial.example.azurecontainerapps.io";
    let (app, _, _dir) = app().await;
    let refused = mcp_at(&app, public, initialize()).await;
    assert_eq!(refused.status(), StatusCode::FORBIDDEN);

    let mut named = InterfaceConfig::default();
    named.allowed_hosts.push(public.to_string());
    let (app, _, _dir) = app_with(glossdb_serverd::DEFAULT_ROW_CAP, named, common::login()).await;
    let body = expect_ok(mcp_at(&app, public, initialize()).await).await;
    assert_eq!(body["result"]["serverInfo"]["name"], "glossdb-serverd");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_mcp_interface_initializes_and_lists_the_one_tool() {
    let (app, _, _dir) = app().await;
    let body = expect_ok(mcp_at(&app, "127.0.0.1", initialize()).await).await;
    assert_eq!(body["result"]["serverInfo"]["name"], "glossdb-serverd");

    let body = rpc(&app, "/mcp", "tools/list", json!({})).await;
    let tools = body["result"]["tools"].as_array().unwrap();
    assert_eq!(tools.len(), 1);
    assert_eq!(tools[0]["name"], "glossql");
    // The revision's tools/list contract as shipping clients validate
    // it: the SEP-2322 discriminator and the list-caching fields the
    // interface injects.
    assert_eq!(body["result"]["resultType"], "complete", "{body}");
    assert!(body["result"]["ttlMs"].is_number(), "{body}");
    assert_eq!(body["result"]["cacheScope"], "private", "{body}");
}

/// The tolerant floor: an initialize declaring an older revision is
/// negotiated down to the library's floor rather than refused, and a
/// request that stamps no version marker at all — no header, no
/// `_meta` — is served at the server's own revision, which is what the
/// spec has a server assume for an absent header.
#[tokio::test(flavor = "multi_thread")]
async fn the_mcp_interface_serves_older_and_unstamped_clients() {
    let (app, _, _dir) = app().await;

    // The floor moves with rmcp: when this breaks on an upgrade, the new
    // value is the new floor.
    let older = Request::post("/mcp")
        .header(header::HOST, "127.0.0.1")
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT, "application/json, text/event-stream")
        .header(header::AUTHORIZATION, common::bearer("dev-agent"))
        .header("mcp-protocol-version", "2025-06-18")
        .body(Body::from(
            json!({
                "jsonrpc": "2.0", "id": 0, "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "older-client", "version": "0"}
                }
            })
            .to_string(),
        ))
        .unwrap();
    let body = expect_ok(app.clone().oneshot(older).await.unwrap()).await;
    assert_eq!(body["result"]["protocolVersion"], "2025-11-25", "{body}");

    let bare = Request::post("/mcp")
        .header(header::HOST, "127.0.0.1")
        .header(header::CONTENT_TYPE, "application/json")
        .header(header::ACCEPT, "application/json, text/event-stream")
        .header(header::AUTHORIZATION, common::bearer("dev-agent"))
        .body(Body::from(
            json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}).to_string(),
        ))
        .unwrap();
    let body = expect_ok(app.oneshot(bare).await.unwrap()).await;
    let tools = body["result"]["tools"].as_array().unwrap();
    assert_eq!(tools[0]["name"], "glossql", "{body}");
}

/// The teaching surface: every skill is a resource and a prompt, the
/// normative artifacts are resources, and what is read back is what
/// the build embedded.
#[tokio::test(flavor = "multi_thread")]
async fn the_mcp_interface_serves_the_skills_as_resources_and_prompts() {
    let (app, _, _dir) = app().await;
    let body = expect_ok(mcp_at(&app, "127.0.0.1", initialize()).await).await;
    assert!(
        body["result"]["capabilities"]["resources"].is_object(),
        "{body}"
    );
    assert!(
        body["result"]["capabilities"]["prompts"].is_object(),
        "{body}"
    );

    let body = rpc(&app, "/mcp", "resources/list", json!({})).await;
    let uris: Vec<&str> = body["result"]["resources"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["uri"].as_str().unwrap())
        .collect();
    for uri in [
        "skill://glossql/SKILL.md",
        "skill://glossql-modeling/SKILL.md",
        "skill://glossql-functions/SKILL.md",
        "skill://glossql-apps/SKILL.md",
        "skill://glossql-modeling/references/define.md",
        "doc://SPEC.md",
        "doc://grammar.ebnf",
        "doc://docs/reference/reads.md",
    ] {
        assert!(uris.contains(&uri), "{uri} missing from {uris:?}");
    }
    // A tree page reads back as the file, under the skill's own root.
    let read = async |uri: &str| {
        rpc(&app, "/mcp", "resources/read", json!({"uri": uri})).await["result"]["contents"][0]
            .clone()
    };
    let reads = glossdb_serverd::skills::PAGES
        .iter()
        .find(|p| p.path == "docs/reference/reads.md")
        .expect("the reads reference is embedded");
    assert_eq!(
        read("doc://docs/reference/reads.md").await["text"],
        json!(reads.body)
    );
    let skill = read("skill://glossql/SKILL.md").await;
    assert_eq!(
        skill["text"],
        json!(glossdb_serverd::skills::SKILLS[0].body)
    );
    assert_eq!(skill["mimeType"], "text/markdown", "{skill}");

    let body = rpc(&app, "/mcp", "prompts/list", json!({})).await;
    let prompts = body["result"]["prompts"].as_array().unwrap();
    assert_eq!(
        prompts.len(),
        glossdb_serverd::skills::SKILLS.len(),
        "{body}"
    );
    assert!(
        prompts
            .iter()
            .all(|p| !p["description"].as_str().unwrap_or_default().is_empty()),
        "{body}"
    );

    let body = rpc(&app, "/mcp", "prompts/get", json!({"name": "glossql"})).await;
    assert_eq!(
        body["result"]["messages"][0]["content"]["text"],
        glossdb_serverd::skills::SKILLS[0].body,
        "{body}"
    );

    // A URI this interface does not hold is refused, never served as an
    // empty page: in band, HTTP 200 with the JSON-RPC error, which the
    // 2026-07-28 revision spells as invalid params.
    let body = rpc(
        &app,
        "/mcp",
        "resources/read",
        json!({"uri": "doc://README.md"}),
    )
    .await;
    assert_eq!(body["error"]["code"], -32602, "{body}");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_mcp_interface_executes_and_reports_refusals_as_tool_errors() {
    let (app, _, _dir) = app().await;
    let answer = json!([{"name": "answer", "type": INT}]);

    let body = tool(&app, "/mcp", "SELECT 41 + 1 AS answer").await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");
    // A call's result is complete and carries none of the list's
    // caching fields.
    assert_eq!(body["result"]["resultType"], "complete", "{body}");
    assert!(body["result"].get("ttlMs").is_none(), "{body}");
    let said = outcomes(&body);
    assert_eq!(said[0]["rows"][0]["answer"], json!(42));
    assert_eq!(said[0]["row_count"], json!(1));
    assert_eq!(said[0]["truncated"], json!(false));
    assert_eq!(said[0]["columns"], answer, "{said}");
    // Every read carries its shape as (name, type), an empty one too —
    // alone and as one statement of several, the path a PREVIEW takes.
    let said = say(&app, "/mcp", "SELECT 41 + 1 AS answer LIMIT 0").await;
    assert_eq!(said[0]["row_count"], json!(0), "{said}");
    assert_eq!(said[0]["columns"], answer, "{said}");
    let said = say(
        &app,
        "/mcp",
        "SELECT 1 AS a; SELECT 41 + 1 AS answer LIMIT 0",
    )
    .await;
    assert_eq!(said[1]["row_count"], json!(0), "{said}");
    assert_eq!(said[1]["columns"], answer, "{said}");

    // A failed statement comes back as a tool error the agent can read,
    // never a protocol error.
    let body = common::refused(&app, "/mcp", "USE nothing").await;
    let text = body["result"]["content"][0]["text"].as_str().unwrap();
    assert!(text.contains("nothing"), "{text}");

    // A refusal mid-sequence is a tool error too, and what ran rides
    // beside it in the usual shape.
    let body = common::refused(&app, "/mcp", "SELECT 1 AS a; USE nothing; SELECT 2 AS b").await;
    let completed: Value = serde_json::from_str(&window(&body)).unwrap();
    assert_eq!(
        completed["completed"],
        json!([{
            "columns": [{"name": "a", "type": INT}],
            "rows": [{"a": 1}],
            "row_count": 1,
            "truncated": false
        }]),
        "{completed}"
    );
}

/// The bound agent interface: `/{dataset}/mcp` opens every call on the
/// dataset its URL names, so a call needs no `USE` to read the dataset's
/// relations and gets the dataset's `next` line on every result. The
/// workspace interface keeps opening unbound, and a dataset the
/// workspace does not hold is the same 404 the human interfaces answer.
#[tokio::test(flavor = "multi_thread")]
async fn the_dataset_mcp_interface_runs_every_call_on_its_dataset() {
    let (app, _, _dir) = app_on("fin").await;
    let read = "SELECT dataset FROM current_dataset";

    let bound = tool(&app, "/fin/mcp", read).await;
    assert_eq!(
        outcomes(&bound)[0]["rows"][0]["dataset"],
        json!("fin"),
        "{bound}"
    );
    assert!(window(&bound).contains("next://fin/"), "{bound}");

    // `USE` inside a call still moves the statements after it.
    common::refused(&app, "/fin/mcp", "USE nothing; SELECT 1").await;

    // The workspace interface opens unbound: the relation serves no row and
    // the result links to no dataset's `next` page.
    let unbound = tool(&app, "/mcp", read).await;
    assert_eq!(outcomes(&unbound)[0]["row_count"], json!(0), "{unbound}");
    assert!(!window(&unbound).contains("next://"), "{unbound}");

    // The bound interface names its dataset on the one tool and in the
    // handshake's instructions.
    let listed = rpc(&app, "/fin/mcp", "tools/list", json!({})).await;
    let description = listed["result"]["tools"][0]["description"]
        .as_str()
        .unwrap();
    assert!(description.contains("`fin`"), "{description}");
    let opened = expect_ok(mcp_on(app.clone(), "/fin/mcp", "127.0.0.1", initialize()).await).await;
    let instructions = opened["result"]["instructions"].as_str().unwrap();
    assert!(instructions.contains("`fin`"), "{instructions}");

    let response = mcp_on(
        app,
        "/nope/mcp",
        "127.0.0.1",
        common::call_with(meta(), read, None),
    )
    .await;
    assert_eq!(response.status(), StatusCode::NOT_FOUND);
    let body = body_json(response).await;
    assert!(body["error"].as_str().unwrap().contains("fin"), "{body}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_key_decided_on_one_view_is_offered_on_the_next_and_may_be_decided_differently() {
    // One key on three views is asked once per view. The form of the
    // second view offers the first decision back, with the person's
    // words, as a box of its own; ticking it stores the same stance
    // and words on that view. The third view is confirmed as stated:
    // the same key holds two different decisions.
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
        DECLARE ASPECT dio WITH $${"title": "DIO", "x-kind": "metric"}$$ AS VIEW;
        DECLARE ASPECT dpo WITH $${"title": "DPO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dpo ON fin AS $${"sql": "SELECT 3 AS v",
          "assumptions": [{"dimension": "convention", "key": "days-in-period",
            "assumption": "calendar days", "basis": "judgment", "confidence": 0.9}]}$$;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [{"dimension": "convention", "key": "days-in-period",
            "assumption": "days are the month's own calendar days, 28 to 31",
            "basis": "judgment", "confidence": 0.8}]}$$;
        GLOSS dio ON fin AS $${"sql": "SELECT 2 AS v",
          "assumptions": [{"dimension": "convention", "key": "days-in-period",
            "assumption": "days are the month's own calendar days",
            "basis": "judgment", "confidence": 0.8}]}$$;
    "#,
    )
    .await;

    let open = async || rows(&app, "/mcp", "SELECT aspect, key FROM open_questions;").await;

    // One key, disclosed on three views: three rows stand open.
    assert_eq!(open().await.len(), 3);

    let review = "SELECT subject, aspect FROM glossary LIMIT 5";

    // dio asks first (aspect order) and the human corrects it. With
    // nothing yet decided on this key, there is no box to repeat one.
    let body = elicit(&app, review, None).await;
    let first = &body["result"]["inputRequests"]["loose:fin:dio:days-in-period"];
    assert!(first.is_object(), "{body}");
    let boxes = &first["params"]["requestedSchema"]["properties"];
    assert!(
        boxes.get("3_same_as").is_none(),
        "nothing to repeat yet: {boxes}"
    );

    let corrected = json!({"action": "accept",
        "content": {"5_correction": "use a fixed 30-day month"}});
    let body = elicit(
        &app,
        review,
        Some(("loose:fin:dio:days-in-period", corrected)),
    )
    .await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");

    // dso asks next. The same key is decided on dio, so the form
    // offers that decision back: a box of its own that names the view
    // and carries the person's words.
    let body = elicit(&app, review, None).await;
    let second = &body["result"]["inputRequests"]["loose:fin:dso:days-in-period"];
    assert!(second.is_object(), "{body}");
    let repeat = &second["params"]["requestedSchema"]["properties"]["3_same_as"];
    assert_eq!(repeat["type"], json!("boolean"), "{second}");
    let offered = repeat["description"].as_str().unwrap_or_default();
    assert!(offered.contains("dio"), "{second}");
    assert!(offered.contains("use a fixed 30-day month"), "{second}");

    // Ticking it replays the stance AND the human's own words.
    let same = json!({"action": "accept",
        "content": {"3_same_as": true}});
    let body = elicit(&app, review, Some(("loose:fin:dso:days-in-period", same))).await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");

    // dpo asks last and is confirmed as stated: the same key, decided
    // differently on another view.
    let confirmed = json!({"action": "accept", "content": {"1_correct": true}});
    let body = elicit(
        &app,
        review,
        Some(("loose:fin:dpo:days-in-period", confirmed)),
    )
    .await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");

    // Nothing is open now, and each view carries its own entry.
    assert!(open().await.is_empty());
    let body = tool(
        &app,
        "/mcp",
        "SELECT aspect, stance, note, assumption FROM review_decisions ORDER BY aspect;",
    )
    .await;
    let outcomes = outcomes(&body);
    let rows = outcomes[0]["rows"].as_array().unwrap();
    let decided: Vec<(&str, &str)> = rows
        .iter()
        .map(|r| {
            (
                r["aspect"].as_str().unwrap_or_default(),
                r["stance"].as_str().unwrap_or_default(),
            )
        })
        .collect();
    assert_eq!(
        decided,
        [
            ("dio", "corrected"),
            ("dpo", "confirmed"),
            ("dso", "corrected")
        ],
        "{rows:?}"
    );
    assert!(
        rows[2]["note"].as_str().unwrap().contains("fixed 30-day"),
        "the repeat carries the person's own words: {rows:?}"
    );
    assert!(
        rows[2]["assumption"].as_str().unwrap().contains("28 to 31"),
        "each view keeps its own wording: {rows:?}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_confirmed_assumption_is_stored_as_the_persons_decision_and_applied_by_the_next_definition()
 {
    // A judged assumption below full confidence becomes a
    // confirm/correct form; "holds as stated" stores a review decision entry —
    // the judgment alone, never a copy of the agent's body (a
    // frozen copy would outrank every later correction).
    // The review decision holds the question closed and stands as not
    // yet applied until the agent records the definition again.
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [
            {"dimension": "definition", "key": "per-line", "assumption": "per line", "basis": "judgment", "confidence": 0.7},
            {"dimension": "grain", "key": "grain-preserving", "assumption": "grain-preserving", "basis": "measured", "confidence": 1.0}
          ]}$$;
    "#,
    )
    .await;
    let applied = async || {
        let read = "SELECT key, stance, folded_in FROM review_decisions;";
        Value::Array(rows(&app, "/mcp", read).await)
    };

    let body = elicit(&app, "SELECT subject, aspect FROM glossary LIMIT 5", None).await;
    assert_eq!(
        body["result"]["resultType"],
        json!("input_required"),
        "{body}"
    );
    let ask = &body["result"]["inputRequests"]["loose:fin:dso:per-line"];
    assert_eq!(ask["method"], json!("elicitation/create"), "{body}");
    // The claim rides the description of the box that confirms it: a
    // message is clipped at three lines and a title is truncated to
    // share its line with the value, while a description renders whole.
    assert!(
        ask["params"]["requestedSchema"]["properties"]["1_correct"]["description"]
            .as_str()
            .is_some_and(|d| d.contains("per line")),
        "{body}"
    );

    let answer = json!({"action": "accept", "content": {"1_correct": true}});
    let body = elicit(
        &app,
        "SELECT subject, aspect FROM glossary LIMIT 5",
        Some(("loose:fin:dso:per-line", answer)),
    )
    .await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");

    // The human value is the review decision record alone — the judgment, never
    // the agent's metric definition; the dso aspect stays agent-authored.
    let body = tool(
        &app,
        "/mcp",
        "SELECT aspect, body FROM glossary WHERE actor_kind = 'human';",
    )
    .await;
    let outcomes = outcomes(&body);
    assert_eq!(outcomes[0]["row_count"], json!(1), "{outcomes}");
    assert_eq!(
        outcomes[0]["rows"][0]["aspect"],
        json!("review_decision"),
        "{outcomes}"
    );
    let human_body = outcomes[0]["rows"][0]["body"].as_str().unwrap();
    assert!(human_body.contains("per line"), "{human_body}");
    assert!(human_body.contains("confirmed"), "{human_body}");
    assert!(
        !human_body.contains("sql"),
        "the decision stored a copy of the definition: {human_body}"
    );

    // The review decision holds the question closed on the next review…
    let body = elicit(&app, "SELECT subject, aspect FROM glossary LIMIT 5", None).await;
    assert_eq!(body["result"]["resultType"], json!("complete"), "{body}");
    assert_eq!(
        applied().await,
        json!([{"key": "per-line", "stance": "confirmed", "folded_in": false}])
    );

    // …and the agent writes the metric definition again at full
    // confidence, citing the decision: the decision is applied.
    let fold_in = r#"USE fin; GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
        "assumptions": [
          {"dimension": "definition", "key": "per-line", "assumption": "per line", "basis": "decided-by-person", "confidence": 1.0},
          {"dimension": "grain", "key": "grain-preserving", "assumption": "grain-preserving", "basis": "measured", "confidence": 1.0}
        ]}$$;"#;
    say(&app, "/mcp", fold_in).await;
    assert_eq!(
        applied().await,
        json!([{"key": "per-line", "stance": "confirmed", "folded_in": true}])
    );
}

/// An assumption that names an alternative offers it as an answer of
/// its own. A person who takes it has corrected the assumption: the
/// decision is stored under the assumption's key as the person's, with
/// the alternative as what is right instead, and the agent is asked to
/// apply it to the view's definition.
#[tokio::test(flavor = "multi_thread")]
async fn an_alternative_taken_is_stored_as_the_persons_correction_and_handed_to_the_agent() {
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [{"dimension": "definition", "key": "per-line", "assumption": "per line",
            "basis": "judgment", "alternative": "per order", "confidence": 0.7}]}$$;
    "#,
    )
    .await;

    let review = "SELECT subject, aspect FROM glossary LIMIT 5";
    let body = elicit(&app, review, None).await;
    assert_eq!(
        body["result"]["resultType"],
        json!("input_required"),
        "{body}"
    );
    let fields = &body["result"]["inputRequests"]["loose:fin:dso:per-line"]["params"]["requestedSchema"]
        ["properties"];
    assert!(
        fields["2_rather"].is_object(),
        "the alternative is a field of the form: {body}"
    );

    let answer = json!({"action": "accept", "content": {"2_rather": true}});
    let body = elicit(&app, review, Some(("loose:fin:dso:per-line", answer))).await;
    assert_ne!(body["result"]["isError"], json!(true), "{body}");
    assert_eq!(body["result"]["resultType"], json!("complete"), "{body}");

    // The decision: the person's, a correction under the assumption's
    // key, whose note is the alternative the agent had named; the one
    // annotation a person wrote is that decision.
    let stored = "USE fin; \
        SELECT aspect, key, stance, note, folded_in FROM review_decisions; \
        SELECT aspect, actor_kind FROM glossary WHERE actor_kind = 'human'; \
        SELECT step, asset, state, who, for_view FROM next WHERE step = 'review';";
    let body = tool(&app, "/mcp", stored).await;
    let outcomes = outcomes(&body);
    assert_eq!(
        outcomes[1]["rows"],
        json!([{"aspect": "dso", "key": "per-line", "stance": "corrected",
                "note": "per order", "folded_in": false}]),
        "{outcomes}"
    );
    assert_eq!(
        outcomes[2]["rows"],
        json!([{"aspect": "review_decision", "actor_kind": "human"}]),
        "{outcomes}"
    );
    // What the agent is asked to do: apply the decision to the view.
    assert_eq!(
        outcomes[3]["rows"],
        json!([{"step": "review", "asset": "fin.dso", "state": "decided",
                "who": "agent", "for_view": "dso"}]),
        "{outcomes}"
    );

    // The question is closed: the next review asks nothing.
    let body = elicit(&app, review, None).await;
    assert_eq!(body["result"]["resultType"], json!("complete"), "{body}");

    // Without an alternative the form has no such field.
    let plain = r#"USE fin; DECLARE ASPECT dpo WITH $${"title": "DPO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dpo ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [{"dimension": "definition", "key": "goods-only", "assumption": "goods only",
            "basis": "judgment", "confidence": 0.7}]}$$;"#;
    say(&app, "/mcp", plain).await;
    let body = elicit(&app, review, None).await;
    let fields = &body["result"]["inputRequests"]["loose:fin:dpo:goods-only"]["params"]["requestedSchema"]
        ["properties"];
    assert!(fields["1_correct"].is_object(), "{body}");
    assert!(fields["2_rather"].is_null(), "{body}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_declined_cancelled_or_empty_form_records_nothing_and_is_asked_again() {
    // The dialog has two outcomes. Accepting with something said is
    // the save; Decline, Esc, and a form confirmed empty are all the
    // same defer — nothing recorded, the claim still derives, and the
    // next review asks it again. Nobody may opt out of being asked:
    // the question is what the numbers rest on, and the way to make it
    // stop is to answer it, `unclear` included.
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [{"dimension": "definition", "key": "per-line", "assumption": "per line", "basis": "judgment", "confidence": 0.7}]}$$;
    "#,
    )
    .await;

    let review = "SELECT subject, aspect FROM glossary LIMIT 5";
    for way_out in [
        json!({"action": "decline"}),
        json!({"action": "cancel"}),
        json!({"action": "accept", "content": {}}),
    ] {
        let body = elicit(&app, review, None).await;
        assert_eq!(
            body["result"]["resultType"],
            json!("input_required"),
            "still open before {way_out}: {body}"
        );
        let body = elicit(
            &app,
            review,
            Some(("loose:fin:dso:per-line", way_out.clone())),
        )
        .await;
        assert_ne!(body["result"]["isError"], json!(true), "{way_out}: {body}");
    }

    // No write in between, and it is asked again every time — a defer
    // buys no quiet, because the claim is still what the numbers rest
    // on.
    let body = elicit(&app, review, None).await;
    assert_eq!(
        body["result"]["resultType"],
        json!("input_required"),
        "a deferred question stands open: {body}"
    );

    // And nothing was recorded by any of the three.
    let body = tool(&app, "/mcp", "SELECT count(*) AS n FROM review_decisions;").await;
    assert_eq!(
        outcomes(&body)[0]["rows"][0]["n"],
        json!(0),
        "a defer records nothing: {body}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_review_form_is_sent_only_on_a_call_that_reads_the_glossary() {
    // Cadence: forms ride
    // only calls that read the catalog. A load call and a plain data
    // read run uninterrupted even while a question holds open; the
    // review-shaped call carries the form.
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [{"dimension": "definition", "key": "per-line", "assumption": "per line", "basis": "judgment", "confidence": 0.7}]}$$;
    "#,
    )
    .await;

    // A writing call: the question holds, the load runs through.
    let body = elicit(
        &app,
        r#"DECLARE ASPECT note WITH $${"title": "note"}$$ AS FACT;"#,
        None,
    )
    .await;
    assert_ne!(
        body["result"]["resultType"],
        json!("input_required"),
        "{body}"
    );
    assert_ne!(body["result"]["isError"], json!(true), "{body}");

    // A plain data read: judging work, not a review — no form either.
    let body = elicit(&app, "SELECT 1 AS ok", None).await;
    assert_ne!(
        body["result"]["resultType"],
        json!("input_required"),
        "{body}"
    );

    // The review-shaped call carries the form.
    let body = elicit(&app, "SELECT subject, aspect FROM glossary LIMIT 5", None).await;
    assert_eq!(
        body["result"]["resultType"],
        json!("input_required"),
        "{body}"
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_data_read_is_cut_at_the_row_cap_and_a_catalog_read_is_whole() {
    let (app, _, _dir) = app_with(3, InterfaceConfig::default(), common::login()).await;
    let alone = say(
        &app,
        "/mcp",
        "SELECT * FROM (VALUES (1), (2), (3), (4), (5)) AS t(v)",
    )
    .await;
    assert_eq!(alone[0]["rows"].as_array().unwrap().len(), 3);
    assert_eq!(alone[0]["row_count"], json!(3));
    assert_eq!(alone[0]["truncated"], json!(true));

    // A data read inside a sequence is cut at the same row and says so:
    // the session that collected it carried the cap in the read's plan.
    let outcomes = say(
        &app,
        "/mcp",
        "SELECT 1 AS one; \
         SELECT * FROM (VALUES (1), (2), (3), (4), (5)) AS t(v) ORDER BY v DESC",
    )
    .await;
    assert_eq!(outcomes[0]["truncated"], json!(false), "{outcomes}");
    assert_eq!(
        outcomes[1]["rows"],
        json!([{"v": 5}, {"v": 4}, {"v": 3}]),
        "{outcomes}"
    );
    assert_eq!(outcomes[1]["row_count"], json!(3));
    assert_eq!(outcomes[1]["truncated"], json!(true));

    // The catalog is served whole: five annotations pass the cap of
    // three, read alone, behind a `USE`, and through `GLOSSARY()`.
    let setup = r#"
        DECLARE DATASET fin SET (purpose: 'cap test');
        USE fin;
        DECLARE ASPECT unit WITH $${"type": "object"}$$ AS FACT;
        GLOSS unit ON t.a AS $${"value": "EUR"}$$;
        GLOSS unit ON t.b AS $${"value": "EUR"}$$;
        GLOSS unit ON t.c AS $${"value": "EUR"}$$;
        GLOSS unit ON t.d AS $${"value": "EUR"}$$;
        GLOSS unit ON t.e AS $${"value": "EUR"}$$;
    "#;
    say(&app, "/mcp", setup).await;
    for (read, at) in [
        ("SELECT subject FROM glossary;", 0),
        ("USE fin; SELECT subject FROM glossary;", 1),
        ("SELECT subject FROM GLOSSARY(fin, all => true);", 0),
    ] {
        let outcomes = say(&app, "/mcp", read).await;
        assert_eq!(
            outcomes[at]["truncated"],
            json!(false),
            "{read}: {outcomes}"
        );
        assert!(
            outcomes[at]["row_count"].as_u64().unwrap() >= 5,
            "{read}: {outcomes}"
        );
    }
}

#[tokio::test(flavor = "multi_thread")]
async fn a_second_review_decision_keeps_the_first() {
    // Deciding a second assumption must not revert the
    // first. Review decisions accumulate as entries in the human's
    // one review decision value — each append carries the earlier entries along,
    // and no review decision ever touches the agent's body.
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [
            {"dimension": "convention", "key": "flat-30-day-month", "assumption": "a flat 30-day month", "basis": "judgment", "confidence": 0.6},
            {"dimension": "definition", "key": "total-revenue-denominator", "assumption": "total revenue in the denominator", "basis": "judgment", "confidence": 0.7}
          ]}$$;
    "#,
    )
    .await;

    // Decide the first (lowest confidence asks first), then the second.
    for key in [
        "loose:fin:dso:flat-30-day-month",
        "loose:fin:dso:total-revenue-denominator",
    ] {
        let answer = json!({"action": "accept", "content": {"1_correct": true}});
        let body = elicit(&app, "SELECT 1 AS ok", Some((key, answer))).await;
        assert_ne!(body["result"]["isError"], json!(true), "{key}: {body}");
    }

    // Both review decisions stand — the first did not revert — and
    // the agent's definition is as it was written.
    let body = tool(
        &app,
        "/mcp",
        "SELECT key, stance FROM review_decisions ORDER BY key;
                 SELECT body FROM glossary WHERE actor_kind = 'agent' AND aspect = 'dso';",
    )
    .await;
    let outcomes = outcomes(&body);
    assert_eq!(
        outcomes[0]["rows"],
        json!([
            {"key": "flat-30-day-month", "stance": "confirmed"},
            {"key": "total-revenue-denominator", "stance": "confirmed"}
        ]),
        "{outcomes}"
    );
    let agent_body = outcomes[1]["rows"][0]["body"].as_str().unwrap();
    let agent_body: Value = serde_json::from_str(agent_body).expect(agent_body);
    let confidences: Vec<&Value> = agent_body["assumptions"]
        .as_array()
        .unwrap()
        .iter()
        .map(|a| &a["confidence"])
        .collect();
    assert_eq!(confidences, [&json!(0.6), &json!(0.7)], "{agent_body}");

    // And the review is quiet — nothing re-derives.
    let body = elicit(&app, "SELECT subject, aspect FROM glossary LIMIT 5", None).await;
    assert_eq!(body["result"]["resultType"], json!("complete"), "{body}");
}

#[tokio::test(flavor = "multi_thread")]
async fn a_review_asks_one_views_open_assumptions_and_none_a_measurement_settles() {
    // `open_questions` is what the review asks from: the judged
    // assumptions below full confidence, without those on a dimension
    // a measurement settles (`grain`). One call asks the assumptions
    // of one view, the least confident first.
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
        DECLARE ASPECT dpo WITH $${"title": "DPO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [{"dimension": "definition", "key": "per-line", "assumption": "per line", "basis": "judgment", "confidence": 0.5}]}$$;
        GLOSS dpo ON fin AS $${"sql": "SELECT 2 AS v",
          "assumptions": [{"dimension": "definition", "key": "goods-only", "assumption": "goods suppliers only", "basis": "judgment", "confidence": 0.4},
                          {"dimension": "grain", "key": "monthly", "assumption": "month grain", "basis": "judgment", "confidence": 0.3}]}$$;
    "#,
    )
    .await;

    // Two rows are open; dpo's `grain` assumption is not among them.
    let body = tool(
        &app,
        "/mcp",
        "SELECT aspect, key FROM open_questions ORDER BY aspect;",
    )
    .await;
    assert_eq!(
        outcomes(&body)[0]["rows"],
        json!([
            {"aspect": "dpo", "key": "goods-only"},
            {"aspect": "dso", "key": "per-line"}
        ]),
        "{body}"
    );

    let body = elicit(&app, "SELECT subject, aspect FROM glossary LIMIT 5;", None).await;
    // The least confident open assumption picks the view, and only
    // that view's assumptions are asked.
    let asked = body["result"]["inputRequests"].as_object().unwrap();
    assert_eq!(asked.len(), 1, "one metric definition per call: {body}");
    assert!(asked["loose:fin:dpo:goods-only"].is_object(), "{body}");
}

#[tokio::test(flavor = "multi_thread")]
async fn an_agent_authors_an_app_over_the_tool() {
    // An app is glosses, one per part. As a directory
    // read from disk only, the one thing an agent
    // connected over MCP could not build was the surface a human looks
    // at — it has statements, not a filesystem. Nothing new carries it:
    // the parts travel as glosses, supersession versions each one, and
    // actor kind records whose hand shaped it.
    let (app, _, _dir) = on_fin(
        r#"
        GLOSS app ON cash AS $${"title": "Monday cash", "dataset": "fin"}$$;
        GLOSS app_page ON cash.index AS $${"html": "{% extends \"shell.html\" %}{% block main %}<h1>What stands open</h1>{% endblock %}"}$$;
        GLOSS app_frame ON cash.open AS $${"sql": "SELECT count(*) AS waiting FROM open_questions"}$$;
    "#,
    )
    .await;

    // The page the agent wrote is served by the app interface.
    let response = get(&app, "/fin/app/cash").await;
    assert_eq!(response.status(), StatusCode::OK);
    let html = body_text(response).await;
    assert!(html.contains("What stands open"), "{html}");
    assert!(
        html.contains("Monday cash"),
        "the manifest names it: {html}"
    );

    // And its frame runs, over a shipped read, as Arrow IPC.
    let response = get(&app, "/fin/app/cash/frames/open").await;
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.headers()[header::CONTENT_TYPE], ARROW_STREAM);

    // A re-gloss supersedes that one part; the rest of the app stands.
    let edit = r#"USE fin;
        GLOSS app_page ON cash.index AS $${"html": "{% extends \"shell.html\" %}{% block main %}<h1>Open work</h1>{% endblock %}"}$$;"#;
    say(&app, "/mcp", edit).await;
    let response = get(&app, "/fin/app/cash").await;
    let html = body_text(response).await;
    assert!(html.contains("Open work"), "{html}");
    assert!(!html.contains("What stands open"), "superseded: {html}");
}

#[tokio::test(flavor = "multi_thread")]
async fn workspace_status_counts_what_exists_is_open_and_waits_per_area() {
    // What this workspace can be extended through, how much of each
    // holds, and what is open on it.
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [{"dimension": "definition", "key": "per-line", "assumption": "per line", "basis": "judgment", "confidence": 0.5}]}$$;
        DECLARE ASPECT price_hike WITH $${"title": "Price +15%", "x-kind": "scenario"}$$ AS FACT ON DATASET;
        DECLARE ASPECT late_pairs WITH $${"title": "Late pairs", "x-kind": "sample"}$$ AS VIEW;
        DECLARE ASPECT ar_tie WITH $${"type": "object"}$$ AS FACT ON DATASET;
        DECLARE TEST ar_tie_test ON ar_tie BY (AGENT, HUMAN);
    "#,
    )
    .await;

    let rows = rows(
        &app,
        "/mcp",
        "SELECT area, existing, open, waiting FROM workspace_status ORDER BY area;",
    )
    .await;
    let areas: Vec<&str> = rows.iter().filter_map(|r| r["area"].as_str()).collect();
    for expected in [
        "apps",
        "properties",
        "annotations",
        "functions",
        "views",
        "plans",
        "relationships",
        "review",
        "scenarios",
        "sources",
        "tables",
        "tests",
    ] {
        assert!(areas.contains(&expected), "{expected} missing: {rows:?}");
    }
    let row = |name: &str| {
        rows.iter()
            .find(|r| r["area"] == json!(name))
            .unwrap_or_else(|| panic!("no {name} row"))
            .clone()
    };
    // One metric declared and defined, one assumption on it waiting for
    // a person. The question waits on the review row; it leaves no
    // metric and no claim open, so "nothing open" stays reachable
    // without a person. The sample frame is a VIEW aspect too and does
    // not count as a view.
    assert_eq!(row("views")["existing"], json!(1), "{rows:?}");
    assert_eq!(row("views")["open"], json!(0), "{rows:?}");
    assert_eq!(row("annotations")["open"], json!(0), "{rows:?}");
    assert_eq!(row("review")["waiting"], json!(1), "{rows:?}");
    assert_eq!(row("views")["waiting"], json!(0), "{rows:?}");
    // The scenarios and the sample frames. The sample interface is a planner interface, not a row
    // in `functions`, so this map is the only place an agent meets them
    // at all. Each is declared here and never glossed — vocabulary
    // current with no body, which is exactly what `open` means.
    assert_eq!(row("scenarios")["existing"], json!(1), "{rows:?}");
    assert_eq!(row("scenarios")["open"], json!(1), "{rows:?}");
    // Nothing decided yet, so no decision waits to be applied.
    assert_eq!(row("review")["existing"], json!(0), "{rows:?}");
    assert_eq!(row("review")["open"], json!(0), "{rows:?}");
    // A validation is open while its property is in use and has no
    // value: the agent's own `ar_tie` is one of them, and it stops
    // being open the moment somebody annotates.
    let open_before = row("tests")["open"].as_i64().unwrap();
    assert!(open_before >= 1, "{rows:?}");
    let annotate = r#"USE fin;
        GLOSS ar_tie ON fin AS $${"outcome": "the subledger ties to its control account", "tolerance": 0.01}$$;"#;
    say(&app, "/mcp", annotate).await;
    let after = say(
        &app,
        "/mcp",
        "SELECT open FROM workspace_status WHERE area = 'tests';",
    )
    .await;
    assert_eq!(
        after[0]["rows"][0]["open"],
        json!(open_before - 1),
        "{after}"
    );
}

/// A filter on `workspace_status` binds: it keeps the rows it names,
/// and their counts are the counts the unfiltered read gives.
#[tokio::test(flavor = "multi_thread")]
async fn a_filter_on_workspace_status_keeps_its_rows_and_their_counts() {
    let (app, _, _dir) = on_fin(
        r#"
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS VIEW;
    "#,
    )
    .await;

    let whole_rows = rows(
        &app,
        "/mcp",
        "SELECT area, existing FROM workspace_status ORDER BY area;",
    )
    .await;
    let existing = |rows: &[Value], name: &str| -> i64 {
        rows.iter()
            .find(|r| r["area"] == json!(name))
            .and_then(|r| r["existing"].as_i64())
            .unwrap_or(-1)
    };
    let properties_whole = existing(&whole_rows, "properties");
    assert!(
        properties_whole > 0,
        "the kits declare properties: {whole_rows:?}"
    );

    // The same question, filtered.
    let one_rows = rows(
        &app,
        "/mcp",
        "SELECT area, existing FROM workspace_status WHERE area = 'properties';",
    )
    .await;
    assert_eq!(
        one_rows.len(),
        1,
        "the filter must bind — got every area back: {one_rows:?}"
    );
    assert_eq!(
        existing(&one_rows, "properties"),
        properties_whole,
        "filtered and unfiltered disagree on the same count"
    );

    // And a filter that keeps several rows keeps exactly those.
    let some_rows = rows(
        &app,
        "/mcp",
        "SELECT area, existing FROM workspace_status \
         WHERE area IN ('tables', 'sources') ORDER BY area;",
    )
    .await;
    let areas: Vec<&str> = some_rows
        .iter()
        .filter_map(|r| r["area"].as_str())
        .collect();
    assert_eq!(areas, vec!["sources", "tables"], "{some_rows:?}");
}

/// A workspace before its first dataset has no dataset-bound read to
/// open with, so the instructions name `workspace_status`, the read
/// that needs none.
#[tokio::test(flavor = "multi_thread")]
async fn the_instructions_of_an_empty_workspace_name_workspace_status() {
    let (app, _, _dir) = app().await;
    // A call refreshes the summary; the opening rides initialize.
    tool(&app, "/mcp", "SELECT * FROM datasets;").await;
    let body = expect_ok(mcp_at(&app, "127.0.0.1", initialize()).await).await;
    let instructions = body["result"]["instructions"].as_str().unwrap();
    assert!(instructions.contains("workspace_status"), "{instructions}");
}

/// A preview measurement calls the model service. Where none is named
/// the query interface answers 503 and the agent interface a refusal,
/// both with one reason: it names the setting an operator sets, the
/// server's, and carries none of the engine's error-class prefixes.
#[tokio::test(flavor = "multi_thread")]
async fn a_preview_measurement_without_its_service_is_unavailable_on_both_interfaces() {
    let (app, _, _dir) = app_on("fin").await;
    // A metric with nine whole months: the expected ranges have a
    // request to send, and the call is where the refusal comes from.
    let setup = r#"CREATE TABLE fin.ledger AS SELECT DATE '2024-01-01' + INTERVAL (i) DAY AS booked,
                     (i % 7 + 1)::DOUBLE AS amount FROM range(300) r(i);
                   DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
                   GLOSS spend ON fin AS $${"sql": "SELECT booked AS period, amount AS value FROM fin.ledger", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}}$$;"#;
    say(&app, "/fin/mcp", setup).await;

    let measure = "SELECT metric_ranges() FROM fin";
    let (status, answered) = query(&app, measure).await;
    assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
    let reason = answered["error"].as_str().unwrap().to_string();
    assert!(
        reason.contains(glossdb_serverd::engine::SERVICE_URL),
        "{reason}"
    );
    assert!(!reason.contains("Error:"), "{reason}");

    let body = tool(&app, "/fin/mcp", measure).await;
    assert_eq!(body["result"]["isError"], json!(true), "{body}");
    assert_eq!(
        body["result"]["content"][0]["text"],
        json!(reason),
        "{body}"
    );
}

/// The functions page lists what SQL on the interface can call, each
/// function once per kind; a page with nothing to list is not served.
#[tokio::test(flavor = "multi_thread")]
async fn the_functions_page_lists_each_function_once() {
    let (_, plane, _dir) = app().await;
    let pages = glossdb_serverd::functions::pages(&plane).await.unwrap();
    let uris: Vec<&str> = pages.iter().map(|p| p.uri.as_str()).collect();
    assert_eq!(uris, ["doc://functions/interface.md"]);
    let rows: Vec<&str> = pages[0]
        .body
        .lines()
        .filter(|line| line.starts_with("| `"))
        .collect();
    let distinct: std::collections::BTreeSet<&str> = rows.iter().copied().collect();
    assert!(rows.len() > 1, "{}", pages[0].body);
    assert_eq!(rows.len(), distinct.len(), "a function is listed twice");
    // a declared function is on it, as an extraction
    assert!(
        rows.iter()
            .any(|row| row.starts_with("| `metric_ranges` | extract |")),
        "{}",
        pages[0].body
    );
}

/// A call that moves the summary's counts carries them in the result's
/// `_meta`, beside the closing `summary:` block with the same line; a
/// call that moves nothing carries neither.
#[tokio::test(flavor = "multi_thread")]
async fn a_call_that_moves_the_summary_carries_its_counts() {
    let (app, _, _dir) = app().await;
    // The first call composes the summary this interface compares with.
    tool(&app, "/mcp", "SELECT * FROM datasets;").await;
    let moved = tool(
        &app,
        "/mcp",
        "DECLARE DATASET fin SET (purpose: 'the summary');",
    )
    .await;
    let summary = &moved["result"]["_meta"][glossdb_serverd::SUMMARY_META];
    assert_eq!(summary["datasets"], json!(1), "{moved}");
    assert_eq!(summary["assumptions_waiting"], json!(0), "{moved}");
    let line = summary["line"].as_str().unwrap();
    let blocks = moved["result"]["content"].as_array().unwrap();
    assert_eq!(
        blocks.last().unwrap()["text"],
        json!(format!("summary: {line}")),
        "{moved}"
    );

    let read = tool(&app, "/mcp", "SELECT * FROM datasets;").await;
    assert!(
        read["result"]["_meta"]
            .get(glossdb_serverd::SUMMARY_META)
            .is_none(),
        "{read}"
    );
    assert_eq!(
        read["result"]["content"].as_array().unwrap().len(),
        blocks.len() - 1,
        "{read}"
    );
}

/// A refusal raised inside a function body reaches both interfaces
/// with its reason once: the code the kit raised it under is a field
/// of its own, and the reason begins at the refusal, without the
/// engine's error-class wrappers before it.
#[tokio::test(flavor = "multi_thread")]
async fn a_refusal_from_a_function_body_carries_its_code_and_its_reason_once() {
    let (app, _, _dir) = app_on("fin").await;
    let setup = r#"CREATE TABLE fin.ledger AS SELECT DATE '2024-01-01' + INTERVAL (i) DAY AS booked,
                     (i % 7 + 1)::DOUBLE AS amount FROM range(300) r(i);
                   DECLARE ASPECT spend WITH $${"title": "Spend"}$$ AS VIEW;
                   GLOSS spend ON fin AS $${"sql": "SELECT booked AS period, amount AS value FROM fin.ledger", "time": "period", "measure": {"column": "value", "additivity": "additive", "unit": "EUR"}}$$;"#;
    say(&app, "/fin/mcp", setup).await;

    // A measurement the extension runs, and a read whose macro refuses.
    for (statement, code) in [
        ("SELECT metric_plan() FROM fin.spend", "not_a_plan"),
        (
            "SELECT * FROM metric_series(world := 'dream')",
            "unknown_world",
        ),
    ] {
        let (status, answered) = query(&app, statement).await;
        assert_eq!(status, StatusCode::UNPROCESSABLE_ENTITY);
        assert_eq!(answered["code"], json!(code), "{answered}");
        let reason = answered["error"].as_str().unwrap().to_string();
        let after_prefix = reason.strip_prefix("glossql: ").unwrap_or(&reason);
        assert!(
            after_prefix.starts_with(&format!("{code}: ")),
            "the reason begins at the refusal: {reason}"
        );

        let body = tool(&app, "/fin/mcp", statement).await;
        assert_eq!(body["result"]["isError"], json!(true), "{body}");
        assert_eq!(
            body["result"]["_meta"][glossdb_serverd::REFUSAL_META]["code"],
            json!(code),
            "{body}"
        );
        assert_eq!(
            body["result"]["content"][0]["text"],
            json!(reason),
            "{body}"
        );
    }
}
