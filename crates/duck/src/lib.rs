//! The engine. The glossql extension owns the language and the record,
//! DuckLake the lake; this crate is the facade the doors use: a plane
//! that opens the workspace, a channel per actor, statements executed
//! and queries streamed as Arrow.
//!
//! Every DuckDB call is synchronous C, so each runs on the blocking pool
//! and hands its rows back as batches; a channel is one connection, the
//! actor set on it as the session variables the extension reads.

// An unwrap outside a test is a panic waiting for the row that has it;
// tests are exempt (clippy.toml).
#![warn(clippy::unwrap_used)]
// A narrowing cast is a value the type did not promise.
#![warn(
    clippy::cast_possible_wrap,
    clippy::cast_sign_loss,
    clippy::cast_possible_truncation
)]

pub mod rulings;
pub mod sqllogic;

use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{Arc, Mutex};

use arrow::array::{RecordBatch, RecordBatchReader};
use arrow::datatypes::SchemaRef;
use arrow::ffi_stream::{ArrowArrayStreamReader, FFI_ArrowArrayStream};
use duckdb_neo::connection::Connection;
use duckdb_neo::environment::{Environment, StorageLocation};
use duckdb_neo::instance::{AttachBuilder, Instance, InstanceBuilder};
use duckdb_neo::query_result::ResultType;
use duckdb_neo::{Parameters, QueryParameter};
use futures::Stream;
/// Who a connection speaks as (SPEC.md §1). Every write the engine
/// lands is stamped with it; there is no BY clause anywhere. The doors
/// read it off the gate and hand it to the engine with the call.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActorKind {
    Agent,
    Human,
}

impl ActorKind {
    pub fn as_str(self) -> &'static str {
        match self {
            ActorKind::Agent => "agent",
            ActorKind::Human => "human",
        }
    }
}

impl std::fmt::Display for ActorKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// The connection's actor: the kind the door it came through says, the
/// id the token says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Actor {
    pub kind: ActorKind,
    pub id: String,
}

/// The default row cap on a paging read.
pub const DEFAULT_ROW_CAP: usize = 200;

/// The lake's name in the catalog; every store relation reads as
/// `ws.main.<relation>`, bare from any dataset in use, since the
/// lake's `main` schema is on every search path.
pub const LAKE: &str = "ws";

/// The instance's own in-memory database: what the build carries and
/// the record does not, the door's pages.
const PAGES_DB: &str = "memory";

// -- the refusal -------------------------------------------------------

#[derive(Debug, thiserror::Error)]
pub enum SessionError {
    #[error("no dataset in use — USE one first")]
    NoDataset,
    #[error("not a subject: {detail}")]
    UnknownName { name: String, detail: String },
    #[error("not a subject: {detail}")]
    NotServed { door: String, detail: String },
    #[error("function runtime: {0}")]
    Service(String),
    #[error("not a subject: {detail}")]
    BadShape { subject: String, detail: String },
    #[error("not an aspect name: `{0}`")]
    BadAspectName(String),
    #[error("the standing ruling slot is not a ruling body")]
    RulingSlotNotRulings,
    #[error("a body carrying `$$` cannot ride the dollar-quoted statement")]
    DollarQuotedBody,
    #[error("streaming takes exactly one query — everything else answers through execute")]
    NotOneRead,
    #[error("statement {index} of {total} refused: {source} — {context}")]
    Sequence {
        index: usize,
        total: usize,
        context: String,
        source: Box<SessionError>,
        landed: Vec<Outcome>,
    },
    #[error("{0}")]
    Engine(String),
    #[error("`{statement}` is closed at this door: {why}. A root actor runs it.")]
    Closed {
        statement: String,
        why: &'static str,
    },
}

impl SessionError {
    pub(crate) fn shape(subject: impl Into<String>, detail: impl Into<String>) -> Self {
        SessionError::BadShape {
            subject: subject.into(),
            detail: detail.into(),
        }
    }

    /// The engine's refusal, classed where its text says what it is: a
    /// name the catalog does not hold reads as an unknown name.
    fn engine(e: impl std::fmt::Display) -> Self {
        let text = e.to_string();
        let lower = text.to_lowercase();
        if lower.contains("does not exist") || lower.contains("not found") {
            return SessionError::UnknownName {
                name: String::new(),
                detail: text,
            };
        }
        SessionError::Engine(text)
    }
}

impl From<duckdb_neo::Error> for SessionError {
    fn from(e: duckdb_neo::Error) -> Self {
        SessionError::engine(e)
    }
}

impl From<arrow::error::ArrowError> for SessionError {
    fn from(e: arrow::error::ArrowError) -> Self {
        SessionError::Engine(e.to_string())
    }
}

/// What ran and what never ran, for a refusal at `index` of `total`.
fn sequence_context(index: usize, total: usize) -> String {
    let landed = match index {
        1 => "nothing ran before it".to_string(),
        2 => "statement 1 ran".to_string(),
        _ => format!("statements 1–{} ran", index - 1),
    };
    let tail = if index == total {
        String::new()
    } else if index + 1 == total {
        format!("; statement {total} not run")
    } else {
        format!("; statements {}–{} not run", index + 1, total)
    };
    format!("{landed}{tail}")
}

// -- the outcome -------------------------------------------------------

/// What one statement produced.
#[derive(Debug)]
pub enum Outcome {
    Done(String),
    Rows {
        batches: Vec<RecordBatch>,
        truncated: bool,
    },
    Affected(u64),
}

/// A read's batches as the doors drive them: one item per batch, the
/// engine's refusal as an item's error.
pub type BatchStream = Pin<Box<dyn Stream<Item = Result<RecordBatch, SessionError>> + Send>>;

/// A read as the doors drive it.
pub struct QueryStream {
    pub schema: SchemaRef,
    pub stream: BatchStream,
    /// Rows a paging caller ships before declaring the answer cut;
    /// `usize::MAX` on a read of the record, which must be whole.
    pub cap: usize,
    /// Whether the statement reads the record anywhere.
    pub record: bool,
}

/// A file the engine writes a read into, for the app door's downloads:
/// the engine's own CSV and parquet writers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CopyFormat {
    Csv,
    Parquet,
}

impl CopyFormat {
    fn clause(self) -> &'static str {
        match self {
            CopyFormat::Csv => "FORMAT CSV, HEADER",
            CopyFormat::Parquet => "FORMAT PARQUET",
        }
    }

    pub fn extension(self) -> &'static str {
        match self {
            CopyFormat::Csv => "csv",
            CopyFormat::Parquet => "parquet",
        }
    }
}

/// A page the door serves as a resource.
#[derive(Debug, Clone)]
pub struct DoorPage {
    pub uri: String,
    pub name: String,
    pub title: String,
    pub description: String,
    pub mime: &'static str,
    pub body: String,
}

/// One function a listing page names.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct Registered {
    pub kind: &'static str,
    pub name: String,
    pub syntax: Option<String>,
}

/// The doors by name: on this engine a door is a kit's table macro, so
/// the list is read from the catalog ([`Session::registered_functions`])
/// and this constant stays empty for the callers that still name it.
pub const DOORS: &[(&str, &str)] = &[];

/// The request's standing as the gate stamps it: the actor the door
/// verified, carried into the handlers.
#[derive(Debug, Clone)]
pub struct Caller(pub Actor);

/// The model service, named once for the instance: `GLOSSDB_SERVICE_URL`
/// its base, the route each call's own; `GLOSSDB_SERVICE_TOKEN` a key
/// sent as-is, or `GLOSSDB_SERVICE_AUDIENCE` the audience an ID token is
/// minted for by the platform this process runs on — the host mints and
/// refreshes it through `Plane::token_sink`. Unnamed, every service call
/// refuses by name.
pub const SERVICE_URL: &str = "GLOSSDB_SERVICE_URL";
pub const SERVICE_TOKEN: &str = "GLOSSDB_SERVICE_TOKEN";
pub const SERVICE_AUDIENCE: &str = "GLOSSDB_SERVICE_AUDIENCE";

/// The model service as the environment names it.
#[derive(Clone, Debug, Default)]
pub struct Service {
    pub url: String,
    pub token: Option<String>,
    pub audience: Option<String>,
}

/// How the engine reaches a warehouse in an object store: a key pair —
/// S3's, or the HMAC pair a Google service account holds — or a bearer
/// the host mints for the account this process runs as, refreshed
/// through `Plane::warehouse_sink`. The secret is scoped to the
/// warehouse's location. A warehouse under a directory needs none.
#[derive(Clone)]
pub enum WarehouseCredential {
    Keys {
        key_id: String,
        secret: String,
        /// S3's region; GCS has none.
        region: Option<String>,
    },
    Bearer(String),
}

/// The secret and the bearer stay out of every log.
impl std::fmt::Debug for WarehouseCredential {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WarehouseCredential::Keys { key_id, region, .. } => f
                .debug_struct("Keys")
                .field("key_id", key_id)
                .field("region", region)
                .finish_non_exhaustive(),
            WarehouseCredential::Bearer(_) => f.write_str("Bearer(..)"),
        }
    }
}

/// The secret type httpfs keeps for a warehouse location's scheme;
/// none for a path under a directory.
pub fn store_kind(warehouse: &str) -> Option<&'static str> {
    let scheme = warehouse.split("://").next()?;
    if scheme == warehouse {
        return None;
    }
    match scheme {
        "s3" => Some("s3"),
        "gs" | "gcs" => Some("gcs"),
        "r2" => Some("r2"),
        _ => None,
    }
}

/// The statement that holds the warehouse's credential in the engine's
/// secret manager, replacing the one before it.
fn secret_sql(kind: &str, credential: &WarehouseCredential, scope: &str) -> String {
    let quoted = |text: &str| text.replace('\'', "''");
    let fields = match credential {
        WarehouseCredential::Keys {
            key_id,
            secret,
            region,
        } => {
            let mut fields = format!("KEY_ID '{}', SECRET '{}'", quoted(key_id), quoted(secret));
            if let Some(region) = region {
                fields.push_str(&format!(", REGION '{}'", quoted(region)));
            }
            fields
        }
        WarehouseCredential::Bearer(token) => format!("BEARER_TOKEN '{}'", quoted(token)),
    };
    format!(
        "CREATE OR REPLACE SECRET warehouse (TYPE {kind}, {fields}, SCOPE '{}')",
        quoted(scope)
    )
}

/// Sets the bearer every service call sends, for the host that mints it.
#[derive(Clone)]
pub struct TokenSink {
    instance: Arc<Instance>,
}

/// Replaces the warehouse's bearer, for the host that mints it anew.
#[derive(Clone)]
pub struct WarehouseSink {
    instance: Arc<Instance>,
    kind: &'static str,
    scope: String,
}

impl WarehouseSink {
    pub fn set(&self, token: &str) -> Result<(), SessionError> {
        let conn = self.instance.connect()?;
        run(
            &conn,
            &secret_sql(
                self.kind,
                &WarehouseCredential::Bearer(token.to_string()),
                &self.scope,
            ),
        )
    }
}

impl TokenSink {
    pub fn set(&self, token: &str) -> Result<(), SessionError> {
        let conn = self.instance.connect()?;
        run(
            &conn,
            &format!(
                "SET GLOBAL glossql_service_token = '{}'",
                token.replace('\'', "''")
            ),
        )
    }
}

/// What a recipe or a probe can call: the engine's readers over the
/// source's files, as DuckDB names them.
pub fn reader_functions() -> Vec<Registered> {
    ["read_csv", "read_parquet", "read_json"]
        .iter()
        .map(|name| Registered {
            kind: "table",
            name: (*name).to_string(),
            syntax: Some(format!("{name}('<path under the source>')")),
        })
        .collect()
}

/// What a detector's query can call over its `slots` relation: the
/// engine's own functions, nothing more.
pub fn detector_functions() -> Vec<Registered> {
    Vec::new()
}

/// The brief's counts: what the record holds of the human's hand.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct BriefCounts {
    pub human_writings: i64,
    pub latest_human_at: Option<String>,
    pub approvals_pending: i64,
    pub rulings_owed: i64,
}

/// The shape of a call, read off the statements before they run.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CallShape {
    pub reviews: bool,
    pub writes: bool,
    pub dataset: Option<String>,
}

/// The shape, from the statements' text: `USE` names the dataset, the
/// last one standing; a statement that is not a read, and an
/// extraction, write; a call of reads alone that names a record
/// relation is a review. Syntactic, as the doors need it before the
/// engine runs anything: a statement that is none of these is refused
/// by the engine, by name, when it runs.
pub fn call_shape(statements: &str) -> CallShape {
    let mut reads_the_record = false;
    let mut writes = false;
    let mut dataset = None;
    for piece in split_statements(statements) {
        if let Some(name) = use_target(&piece) {
            dataset = Some(name);
        } else if is_read(&piece) && !is_extraction(&piece) {
            reads_the_record |= reads_record(&piece);
        } else {
            writes = true;
        }
    }
    CallShape {
        reviews: reads_the_record && !writes,
        writes,
        dataset,
    }
}

/// `USE <dataset>`: the name, an unquoted one folded to lowercase as
/// the engine folds it, a quoted one as spelled.
fn use_target(statement: &str) -> Option<String> {
    let mut words = statement.trim().trim_end_matches(';').split_whitespace();
    if !words.next()?.eq_ignore_ascii_case("use") {
        return None;
    }
    let name = words.next()?.trim_end_matches(';');
    Some(
        match name.strip_prefix('"').and_then(|n| n.strip_suffix('"')) {
            Some(quoted) => quoted.to_string(),
            None => name.to_ascii_lowercase(),
        },
    )
}

/// The store's relations, as the extension serves them in the
/// lake's `main` schema, and the reads over the record.
const RECORD: &[&str] = &[
    "glossary",
    // the door's derived reads, which say what the record holds
    "open_questions",
    "ruling_entries",
    "agent_assumptions",
    "owed",
    "metric_surfaces",
    "metric_axes",
    "metric_sources",
    "workspace_next",
    "app_parts",
    "app_releases",
    "next",
    "imports",
    "recipes",
    "aspects",
    "witnesses",
    "functions",
    "measurements",
    "relationships",
    "datasets",
    "sources",
    "kits",
    "attest",
];

/// Whether a read touches the record anywhere: the store's relations by
/// name, bare or under the store's schema, or the two reads over it.
/// Syntactic, as the frame class needs: the words of the text, with
/// the quoting and punctuation taken off.
pub fn reads_record(sql: &str) -> bool {
    let lower = sql.to_lowercase();
    lower
        .split(|c: char| !(c.is_ascii_alphanumeric() || c == '_' || c == '.'))
        .filter(|w| !w.is_empty())
        .any(|word| {
            let name = word.rsplit('.').next().unwrap_or(word);
            name == "glossary" || name == "attest" || RECORD.contains(&name)
        })
}

/// Whether one statement answers rows: a query by its first word, the
/// comments before it skipped. Everything else is a statement of the
/// language or of SQL, run for its effect.
/// A statement's text after its leading comments.
fn after_comments(statement: &str) -> &str {
    let mut rest = statement.trim_start();
    loop {
        if let Some(after) = rest.strip_prefix("--") {
            rest = after
                .split_once('\n')
                .map(|(_, r)| r)
                .unwrap_or("")
                .trim_start();
        } else if let Some(after) = rest.strip_prefix("/*") {
            rest = after
                .split_once("*/")
                .map(|(_, r)| r)
                .unwrap_or("")
                .trim_start();
        } else {
            return rest;
        }
    }
}

/// A statement's words, uppercased: the keywords and the names, in
/// order; a leading parenthesis reads as a `SELECT`.
fn words(statement: &str) -> Vec<String> {
    let rest = after_comments(statement);
    let mut out: Vec<String> = Vec::new();
    if rest.starts_with('(') {
        out.push("SELECT".to_string());
    }
    out.extend(
        rest.split(|c: char| !c.is_ascii_alphanumeric() && c != '_')
            .filter(|w| !w.is_empty())
            .map(str::to_ascii_uppercase),
    );
    out
}

/// What a door opens: the workspace, never the engine. A standard
/// actor lands tables, writes rows, copies files in and out, drops what
/// it made, declares and glosses, reads. The engine's own knobs are
/// closed, and the refusal names which: its settings and the session's
/// variables (`SET`, `RESET`, a `PRAGMA` switch), where the actor and
/// the workspace ride; what it attaches (`ATTACH`, `DETACH`); its
/// extensions (`INSTALL`, `LOAD`); the lake's maintenance (`CALL`,
/// `IMPORT DATABASE`, `EXPORT DATABASE`). A pragma call, with
/// parentheses, is a read and passes. A root actor ([`Config::root`])
/// has the knobs.
fn admitted(sql: &str) -> Result<(), SessionError> {
    let words = words(sql);
    let first = words.first().map(String::as_str).unwrap_or("");
    let second = words.get(1).map(String::as_str).unwrap_or("");
    let (statement, why) = match (first, second) {
        ("PRAGMA", _) if sql.contains('(') => return Ok(()),
        ("SET" | "RESET" | "PRAGMA", _) => (
            first.to_string(),
            "the engine's settings and the session's variables are the door's, and the actor and the workspace ride them",
        ),
        ("ATTACH" | "DETACH", _) => (
            first.to_string(),
            "what the engine attaches is the deployment's: the lake at open, a relational source by root",
        ),
        ("INSTALL" | "LOAD" | "FORCE", _) => (first.to_string(), "the extensions are the build's"),
        ("CALL", _) => (first.to_string(), "the lake's maintenance is root's"),
        ("IMPORT" | "EXPORT", "DATABASE") => (
            format!("{first} DATABASE"),
            "the lake is the workspace, whole",
        ),
        _ => return Ok(()),
    };
    Err(SessionError::Closed { statement, why })
}

fn is_read(statement: &str) -> bool {
    let rest = after_comments(statement).trim_start_matches('(');
    let word: String = rest
        .chars()
        .take_while(|c| c.is_ascii_alphabetic())
        .collect::<String>()
        .to_ascii_lowercase();
    matches!(
        word.as_str(),
        "select"
            | "with"
            | "from"
            | "values"
            | "table"
            | "describe"
            | "show"
            | "summarize"
            | "pivot"
            | "unpivot"
    )
}

// -- the plane ---------------------------------------------------------

/// Where the engine finds its pieces.
#[derive(Debug, Clone)]
pub struct Config {
    /// The glossql extension, as a file to load.
    pub extension: PathBuf,
    /// The kits, in order; each a script `glossql_kit` runs at open.
    pub kits: Vec<PathBuf>,
    /// Where DuckDB's own extensions — ducklake, httpfs, postgres —
    /// are installed; none, DuckDB's default under the home directory,
    /// installed from its repository at first open.
    pub extension_dir: Option<PathBuf>,
    /// The lake's catalog: a path to a `.ducklake` file, or a
    /// `ducklake:` URI naming a Postgres catalog.
    pub catalog: String,
    /// The lake's data path.
    pub warehouse: String,
    /// How the engine reaches the warehouse when it is in an object
    /// store; none for a directory.
    pub warehouse_credential: Option<WarehouseCredential>,
    pub row_cap: usize,
    /// The model service, where the environment names one.
    pub service: Option<Service>,
    /// The engine's memory ceiling and the disk it may spill onto, in
    /// megabytes; unset, the engine's own defaults.
    pub memory_limit_mb: Option<u64>,
    pub spill_limit_mb: Option<u64>,
    /// The actors that have the engine's own knobs at the doors:
    /// `SET`, `ATTACH`, `INSTALL`, `LOAD`, `CALL`. Everyone else has
    /// the workspace ([`admitted`]). Actor ids; none by default.
    pub root: Vec<String>,
}

/// The engine's spill files, and the files the export door writes:
/// under the system's temporary directory, never beside the process.
fn spill_dir() -> PathBuf {
    std::env::temp_dir().join("glossdb")
}

/// The extension's pieces beside a released binary: `<bin>/../share/glossdb`,
/// the image's and the tarball's layout.
fn share() -> Option<PathBuf> {
    let exe = std::env::current_exe().ok()?;
    Some(exe.parent()?.parent()?.join("share/glossdb"))
}

/// The engine's pieces and where they are.
struct Pieces {
    extension: PathBuf,
    /// The extension's kits: the language's examples, kpi and quality.
    /// The language's documents, SPEC.md and grammar.ebnf, sit beside
    /// this directory, as they do in the extension's repository.
    glossql_kits: PathBuf,
    /// This repository's kits, `kits/`: metrics and futures.
    kits: PathBuf,
    extension_dir: Option<PathBuf>,
}

/// Where the extension, the kits and the lake extensions are: what
/// `GLOSSQL_EXTENSION`, `GLOSSQL_KITS`, `GLOSSDB_KITS` and
/// `GLOSSQL_EXTENSION_DIR` name; else the share directory beside the
/// binary where it holds them, whose one `kits` directory carries both
/// roots' kits; else the dev tree: the sibling checkout's build and
/// its kits, and `kits/` at this workspace's root.
fn pieces() -> Pieces {
    let gloss = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../gloss");
    let share = share();
    let beside = |name: &str| share.as_ref().map(|s| s.join(name)).filter(|p| p.exists());
    let extension = std::env::var_os("GLOSSQL_EXTENSION")
        .map(PathBuf::from)
        .or_else(|| beside("glossql.duckdb_extension"))
        .unwrap_or_else(|| {
            gloss.join(format!(
                "build/release/repository/v2.0.0/{}/glossql.duckdb_extension",
                platform()
            ))
        });
    let glossql_kits = std::env::var_os("GLOSSQL_KITS")
        .map(PathBuf::from)
        .or_else(|| beside("kits"))
        .unwrap_or_else(|| gloss.join("kits"));
    let kits = std::env::var_os("GLOSSDB_KITS")
        .map(PathBuf::from)
        .or_else(|| beside("kits"))
        .unwrap_or_else(|| Path::new(env!("CARGO_MANIFEST_DIR")).join("../../kits"));
    let extension_dir = std::env::var_os("GLOSSQL_EXTENSION_DIR")
        .map(PathBuf::from)
        .or_else(|| beside("extensions"));
    Pieces {
        extension,
        glossql_kits,
        kits,
        extension_dir,
    }
}

/// One of the language's documents, `SPEC.md` or `grammar.ebnf`:
/// what the door serves as `doc://SPEC.md` and `doc://grammar.ebnf`.
/// Read from beside the extension's kits, where its repository, the
/// share and the CI cache all keep them. A missing document is the
/// caller's error to raise: the door serves nothing it cannot read.
pub fn language_document(name: &str) -> std::io::Result<String> {
    let kits = pieces().glossql_kits;
    let path = kits.parent().unwrap_or(&kits).join(name);
    std::fs::read_to_string(&path)
        .map_err(|e| std::io::Error::new(e.kind(), format!("{}: {e}", path.display())))
}

impl Config {
    /// The laptop's shape: the workspace directory holds the lake's
    /// catalog and its files.
    pub fn laptop(workspace: &Path) -> Config {
        let pieces = pieces();
        Config {
            extension: pieces.extension,
            kits: vec![
                pieces.kits.join("core/kit.sql"),
                pieces.glossql_kits.join("kpi/kit.sql"),
                pieces.glossql_kits.join("quality/kit.sql"),
                pieces.kits.join("metrics/kit.sql"),
                pieces.kits.join("futures/kit.sql"),
                pieces.kits.join("door/kit.sql"),
            ],
            extension_dir: pieces.extension_dir,
            catalog: workspace.join("catalog.ducklake").display().to_string(),
            warehouse: workspace.join("warehouse").display().to_string(),
            warehouse_credential: None,
            row_cap: DEFAULT_ROW_CAP,
            service: None,
            memory_limit_mb: None,
            spill_limit_mb: None,
            root: Vec::new(),
        }
    }

    /// A deployment's shape: the catalog a `ducklake:` URI or a
    /// Postgres URI, the lake's files an object-store location.
    pub fn deployment(catalog: &str, warehouse: &str) -> Config {
        let mut config = Config::laptop(Path::new("."));
        config.catalog = if catalog.starts_with("ducklake:") {
            catalog.to_string()
        } else {
            format!("ducklake:postgres:{catalog}")
        };
        config.warehouse = warehouse.to_string();
        config
    }
}

/// DuckDB's name for this build's platform.
fn platform() -> &'static str {
    match (std::env::consts::OS, std::env::consts::ARCH) {
        ("macos", "aarch64") => "osx_arm64",
        ("macos", _) => "osx_amd64",
        ("linux", "aarch64") => "linux_arm64",
        ("linux", _) => "linux_amd64",
        ("windows", _) => "windows_amd64",
        _ => "unknown",
    }
}

/// The workspace, open: one DuckDB instance with the extension and the
/// lake, and what every channel shares.
pub struct Plane {
    _environment: Environment,
    instance: Arc<Instance>,
    config: Config,
    pages: Arc<[DoorPage]>,
}

impl std::fmt::Debug for Plane {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Plane")
            .field("catalog", &self.config.catalog)
            .field("row_cap", &self.config.row_cap)
            .finish()
    }
}

/// Run one statement for its effect on a connection.
/// The `next` read, written at open from every `routes_<kit>()` macro
/// the kits and the door declare: each serves its goals' CTEs and arms
/// as SQL text over the reads this query takes once — `ds`, `axes`,
/// `owed`, `reds`, `bodies`, `applicable` — so one `next` reads the
/// record once per relation, and the lowest step decides each goal, in
/// the goals' order.
fn next_view(conn: &Connection) -> Result<String, SessionError> {
    let (_, _, batches) = arrow_batches(
        conn,
        &format!(
            "SELECT function_name FROM duckdb_functions() WHERE database_name = '{LAKE}' \
             AND schema_name = 'main' AND function_name LIKE 'routes\\_%' ESCAPE '\\' \
             AND function_type = 'table_macro' ORDER BY function_name"
        ),
        &[],
    )?;
    let routes: Vec<String> = rows_as_text(&batches)
        .into_iter()
        .filter_map(|row| row.into_iter().next().flatten())
        .collect();
    let mut ctes = Vec::new();
    let mut arms = Vec::new();
    for route in &routes {
        let (_, _, batches) = arrow_batches(
            conn,
            &format!("SELECT ctes, arms FROM {LAKE}.main.{route}()"),
            &[],
        )?;
        for row in rows_as_text(&batches) {
            if let Some(Some(c)) = row.first()
                && !c.trim().is_empty()
            {
                ctes.push(c.trim().trim_end_matches(',').to_string());
            }
            if let Some(Some(a)) = row.get(1)
                && !a.trim().is_empty()
            {
                arms.push(a.trim().to_string());
            }
        }
    }
    let steps = if arms.is_empty() {
        "SELECT NULL::VARCHAR AS surface, NULL::INTEGER AS step, NULL::VARCHAR AS state, \
         NULL::VARCHAR AS act, NULL::VARCHAR AS say, NULL::VARCHAR AS why, \
         NULL::VARCHAR AS statement, NULL::VARCHAR AS \"then\" WHERE false"
            .to_string()
    } else {
        arms.join("\nUNION ALL\n")
    };
    let shared = format!(
        "ds AS (SELECT dataset FROM {LAKE}.main.current_dataset), \
         axes AS MATERIALIZED (SELECT * FROM {LAKE}.main.metric_axes()), \
         owed AS MATERIALIZED (SELECT * FROM {LAKE}.main.owed), \
         reds AS MATERIALIZED (SELECT subject, witness FROM glossql_attest(current_schema(), NULL) WHERE band = 'red'), \
         bodies AS MATERIALIZED (SELECT aspect AS metric, body::VARCHAR AS body FROM ( \
           SELECT g.aspect, g.body, row_number() OVER (PARTITION BY g.aspect ORDER BY g.seq DESC) AS rn \
           FROM {LAKE}.main.glossary g, ds WHERE g.dataset = ds.dataset AND g.subject = ds.dataset) WHERE rn = 1), \
         applicable AS (SELECT count(*) AS n, string_agg(metric, ', ' ORDER BY metric) AS metrics, \
           string_agg(chr(39) || metric || chr(39), ', ' ORDER BY metric) AS metric_list FROM axes WHERE applicable)"
    );
    let kit_ctes = if ctes.is_empty() {
        String::new()
    } else {
        format!(", {}", ctes.join(", "))
    };
    Ok(format!(
        "CREATE OR REPLACE VIEW {LAKE}.main.next AS WITH {shared}{kit_ctes}, \
         steps AS ({steps}), \
         first AS (SELECT *, row_number() OVER (PARTITION BY surface ORDER BY step, say, why) AS rn FROM steps) \
         SELECT CASE surface WHEN 'structure' THEN 1 WHEN 'metrics' THEN 2 WHEN 'slices' THEN 3 \
                             WHEN 'bands' THEN 4 WHEN 'checks' THEN 5 WHEN 'app' THEN 6 \
                             WHEN 'plan' THEN 7 ELSE 8 END AS goal, \
                surface, step, state, act, say, why, statement, \"then\" \
         FROM first WHERE rn = 1"
    ))
}

/// The `next` view, written when its text is new. The hash of the
/// composed text rides the view as its comment, which a replace
/// clears; a view whose comment is the hash stands, and the open
/// skips the bind of the whole text. A kit that changed changes the
/// text through its routes.
fn write_next(conn: &Connection) -> Result<(), SessionError> {
    let view = next_view(conn)?;
    let (_, _, hashed) = arrow_batches(
        conn,
        &format!("SELECT md5('{}')", view.replace('\'', "''")),
        &[],
    )?;
    let hash = one_cell(&hashed).unwrap_or_default();
    let (_, _, standing) = arrow_batches(
        conn,
        &format!(
            "SELECT comment FROM duckdb_views() WHERE database_name = '{LAKE}' \
             AND schema_name = 'main' AND view_name = 'next'"
        ),
        &[],
    )?;
    if one_cell(&standing).as_deref() == Some(hash.as_str()) {
        return Ok(());
    }
    run(conn, &view)?;
    run(
        conn,
        &format!("COMMENT ON VIEW {LAKE}.main.next IS '{hash}'"),
    )?;
    Ok(())
}

fn run(conn: &Connection, sql: &str) -> Result<(), SessionError> {
    conn.query(sql, Parameters::None)
        .map_err(|e| {
            SessionError::Engine(format!("{e}\n  in: {}", sql.lines().next().unwrap_or("")))
        })?
        .drain()?;
    Ok(())
}

/// A query's result through the Arrow C stream the engine exports: its
/// kind and its batches. One execution: a DuckDB result runs when it is
/// read, so a statement that answers nothing is read to its end too.
fn arrow_batches(
    conn: &Connection,
    sql: &str,
    params: &[(String, String)],
) -> Result<(ResultType, SchemaRef, Vec<RecordBatch>), SessionError> {
    // Only the parameters the text names: the doors bind every URL
    // parameter, and the engine refuses one the statement never spells.
    let named: Vec<(&str, &dyn QueryParameter)> = params
        .iter()
        .filter(|(k, _)| names_parameter(sql, k))
        .map(|(k, v)| (k.as_str(), v as &dyn QueryParameter))
        .collect();
    let parameters = if named.is_empty() {
        Parameters::None
    } else {
        Parameters::Named(&named)
    };
    let result = conn
        .arrow_query(sql, parameters, None)
        .map_err(SessionError::engine)?;
    let kind = result.result_type()?;
    let stream = result.to_arrow_stream()?;
    // SAFETY: both structs are the Arrow C stream interface, `repr(C)`
    // with the same five fields in order. The reader releases the
    // stream when dropped, before `_collections` and before the
    // connection is used again.
    let (raw, _collections) = unsafe { stream.into_raw() };
    let ffi: FFI_ArrowArrayStream = unsafe { std::mem::transmute(raw) };
    let reader = ArrowArrayStreamReader::try_new(ffi)?;
    let schema = reader.schema();
    let batches = reader
        .collect::<Result<Vec<_>, _>>()
        .map_err(SessionError::engine)?;
    Ok((kind, schema, batches))
}

/// Whether `sql` spells `$name` as a whole word.
fn names_parameter(sql: &str, name: &str) -> bool {
    sql.match_indices(&format!("${name}")).any(|(at, hit)| {
        !sql[at + hit.len()..]
            .chars()
            .next()
            .is_some_and(|c| c.is_ascii_alphanumeric() || c == '_')
    })
}

/// An extraction, `SELECT <function>() FROM <subject>`: the language's
/// form, which the grammar takes whole and a paging subquery would hide.
fn is_extraction(sql: &str) -> bool {
    let tokens: Vec<&str> = sql
        .trim()
        .trim_end_matches(';')
        .split_whitespace()
        .collect();
    let [select, call, from, subject] = tokens.as_slice() else {
        return false;
    };
    let function = call.strip_suffix("()").unwrap_or("");
    select.eq_ignore_ascii_case("select")
        && from.eq_ignore_ascii_case("from")
        && !function.is_empty()
        && function
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_')
        && subject
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.')
}

/// The glossql heads: a statement of the language answers one line.
fn is_glossql_head(sql: &str) -> bool {
    let head = sql
        .split_whitespace()
        .next()
        .unwrap_or("")
        .to_ascii_uppercase();
    matches!(head.as_str(), "DECLARE" | "GLOSS" | "IMPORT" | "USE")
}

/// One cell of a one-row, one-column batch, as text.
fn one_cell(batches: &[RecordBatch]) -> Option<String> {
    let batch = batches.iter().find(|b| b.num_rows() > 0)?;
    if batch.num_columns() != 1 || batch.num_rows() != 1 {
        return None;
    }
    let column = batch.column(0);
    let options = arrow::util::display::FormatOptions::default();
    let formatter =
        arrow::util::display::ArrayFormatter::try_new(column.as_ref(), &options).ok()?;
    Some(formatter.value(0).to_string())
}

/// Cut `batches` at `cap` rows; says whether it cut.
fn cut(batches: Vec<RecordBatch>, cap: usize) -> (Vec<RecordBatch>, bool) {
    let mut kept = Vec::new();
    let mut shipped = 0usize;
    let mut truncated = false;
    for batch in batches {
        if shipped >= cap {
            if batch.num_rows() > 0 {
                truncated = true;
            }
            continue;
        }
        let room = cap - shipped;
        if batch.num_rows() > room {
            kept.push(batch.slice(0, room));
            shipped += room;
            truncated = true;
        } else {
            shipped += batch.num_rows();
            kept.push(batch);
        }
    }
    (kept, truncated)
}

/// The instance before the lake: the options, the spill directory
/// and the limits, the extension and the lake's own, with the
/// connection they were set on. The workspace opens on it; the kits'
/// suites attach their own lake to it.
fn engine_instance(config: &Config) -> Result<(Environment, Instance, Connection), SessionError> {
    let environment = Environment::new()?;
    let mut builder = InstanceBuilder::new().option("allow_unsigned_extensions", "true");
    if let Some(dir) = &config.extension_dir {
        builder = builder.option("extension_directory", dir.display().to_string());
    }
    let instance = builder.build(&environment)?;
    instance.attach(AttachBuilder::new(StorageLocation::InMemory).make_default())?;
    let conn = instance.connect()?;
    // The engine's spill files under the system's temporary
    // directory, never beside the process: an in-memory
    // instance would spill into the working directory.
    run(
        &conn,
        &format!(
            "SET temp_directory = '{}'",
            spill_dir().display().to_string().replace('\'', "''")
        ),
    )?;
    if let Some(mb) = config.memory_limit_mb {
        run(&conn, &format!("SET memory_limit = '{mb}MB'"))?;
    }
    if let Some(mb) = config.spill_limit_mb {
        run(&conn, &format!("SET max_temp_directory_size = '{mb}MB'"))?;
    }
    run(&conn, &format!("LOAD '{}'", config.extension.display()))?;
    run(&conn, "INSTALL ducklake")?;
    run(&conn, "LOAD ducklake")?;
    Ok((environment, instance, conn))
}

impl Plane {
    /// Open the workspace: the instance, the extension, the lake, the
    /// grammar, the store, the kits in order and the `next` view. A kit
    /// whose text the lake recorded stands and runs nothing; the view is
    /// written when its text is new. An existing workspace opens in the
    /// time of the attach.
    pub async fn open(config: Config) -> Result<Plane, SessionError> {
        let opened = tokio::task::spawn_blocking({
            let config = config.clone();
            move || -> Result<(Environment, Instance), SessionError> {
                let (environment, instance, conn) = engine_instance(&config)?;
                // httpfs for the POST a service call makes and for a
                // warehouse in an object store; the warehouse's credential
                // held before the lake is attached, since the record's own
                // files are in the warehouse too.
                let store = store_kind(&config.warehouse);
                if config.service.is_some() || store.is_some() {
                    run(&conn, "INSTALL httpfs")?;
                    run(&conn, "LOAD httpfs")?;
                }
                if let (Some(kind), Some(credential)) = (store, &config.warehouse_credential) {
                    run(&conn, &secret_sql(kind, credential, &config.warehouse))?;
                }
                // The service named once for the instance; unnamed, a
                // call refuses by name before any HTTP client is asked.
                if let Some(service) = &config.service {
                    run(
                        &conn,
                        &format!(
                            "SET GLOBAL glossql_service_url = '{}'",
                            service.url.replace('\'', "''")
                        ),
                    )?;
                    run(
                        &conn,
                        &format!(
                            "SET GLOBAL glossql_service_token = '{}'",
                            service
                                .token
                                .as_deref()
                                .unwrap_or_default()
                                .replace('\'', "''")
                        ),
                    )?;
                }
                let catalog = if config.catalog.starts_with("ducklake:") {
                    config.catalog.clone()
                } else {
                    format!("ducklake:{}", config.catalog)
                };
                // The catalog remembers the warehouse it was created
                // with, as an absolute path; the override makes the
                // configured one stand, so a workspace directory that
                // was moved or copied opens where it now is.
                run(
                    &conn,
                    &format!(
                        "ATTACH '{catalog}' AS {LAKE} (DATA_PATH '{}/', OVERRIDE_DATA_PATH true)",
                        config.warehouse.trim_end_matches('/')
                    ),
                )?;
                run(&conn, &format!("USE {LAKE}"))?;
                run(&conn, "SET active_grammar_extensions = ['glossql']")?;
                run(&conn, "PRAGMA glossql")?;
                // the door's pages: a table of the instance's own in-memory
                // database, empty until a door publishes them
                run(
                    &conn,
                    &format!(
                        "CREATE TABLE IF NOT EXISTS {PAGES_DB}.main.door_pages \
                         (uri VARCHAR, title VARCHAR, body VARCHAR)"
                    ),
                )?;
                for kit in &config.kits {
                    run(&conn, &format!("FROM glossql_kit('{}')", kit.display()))
                        .map_err(|e| SessionError::Engine(format!("kit {}: {e}", kit.display())))?;
                }
                write_next(&conn)?;
                Ok((environment, instance))
            }
        })
        .await
        .map_err(|e| SessionError::Engine(e.to_string()))??;
        let (environment, instance) = opened;
        Ok(Plane {
            _environment: environment,
            instance: Arc::new(instance),
            config,
            pages: Arc::from(Vec::new()),
        })
    }

    /// The model service as named at open, for the host's log and its minting.
    pub fn service(&self) -> Option<&Service> {
        self.config.service.as_ref()
    }

    /// Where the host sets the service's bearer when it mints one.
    pub fn token_sink(&self) -> TokenSink {
        TokenSink {
            instance: self.instance.clone(),
        }
    }

    /// Where the host replaces the warehouse's bearer when it mints one
    /// anew; none while the warehouse is under a directory.
    pub fn warehouse_sink(&self) -> Option<WarehouseSink> {
        store_kind(&self.config.warehouse).map(|kind| WarehouseSink {
            instance: self.instance.clone(),
            kind,
            scope: self.config.warehouse.clone(),
        })
    }

    /// The pages the door serves, held here and published as rows of
    /// `pages()`, a temp macro of every channel over a table in the
    /// instance's own in-memory database, never the lake, since a page
    /// is the build's and not the record's.
    pub fn with_pages(mut self, pages: Arc<[DoorPage]>) -> Self {
        if let Err(e) = self.publish_pages(&pages) {
            tracing::warn!(error = %e, "the door pages are not rows of pages()");
        }
        self.pages = pages;
        self
    }

    fn publish_pages(&self, pages: &[DoorPage]) -> Result<(), SessionError> {
        let conn = self.instance.connect()?;
        run(
            &conn,
            &format!(
                "CREATE OR REPLACE TABLE {PAGES_DB}.main.door_pages (uri VARCHAR, title VARCHAR, body VARCHAR)"
            ),
        )?;
        for page in pages {
            arrow_batches(
                &conn,
                &format!("INSERT INTO {PAGES_DB}.main.door_pages VALUES ($uri, $title, $body)"),
                &[
                    ("uri".to_string(), page.uri.clone()),
                    ("title".to_string(), page.title.clone()),
                    ("body".to_string(), page.body.clone()),
                ],
            )?;
        }
        Ok(())
    }

    pub fn pages(&self) -> Arc<[DoorPage]> {
        Arc::clone(&self.pages)
    }

    pub fn with_row_cap(mut self, cap: usize) -> Self {
        self.config.row_cap = cap;
        self
    }

    pub fn row_cap(&self) -> usize {
        self.config.row_cap
    }

    /// A channel: one connection, the grammar on, the actor set, the
    /// dataset in use where one is named.
    pub async fn channel(
        &self,
        actor: Actor,
        dataset: Option<&str>,
    ) -> Result<Arc<Session>, SessionError> {
        let instance = Arc::clone(&self.instance);
        let dataset = dataset.map(str::to_string);
        let kind = actor.kind.to_string();
        let id = actor.id.clone();
        let root = self.config.root.contains(&actor.id);
        let conn = tokio::task::spawn_blocking({
            let dataset = dataset.clone();
            move || -> Result<Connection, SessionError> {
                let conn = instance.connect()?;
                run(&conn, &format!("USE {LAKE}"))?;
                run(&conn, "SET active_grammar_extensions = ['glossql']")?;
                run(
                    &conn,
                    &format!(
                        "SET VARIABLE glossql_actor = '{}'",
                        kind.replace('\'', "''")
                    ),
                )?;
                run(
                    &conn,
                    &format!(
                        "SET VARIABLE glossql_actor_id = '{}'",
                        id.replace('\'', "''")
                    ),
                )?;
                if let Some(dataset) = &dataset {
                    run(&conn, &format!("USE {LAKE}.{}", quote_name(dataset))).map_err(|_| {
                        SessionError::UnknownName {
                            name: dataset.clone(),
                            detail: format!("no dataset `{dataset}` in the workspace"),
                        }
                    })?;
                }
                // `pages()` for this connection: `temp.main` is first on every
                // search path, whatever dataset the session puts in use
                run(
                    &conn,
                    &format!(
                        "CREATE OR REPLACE TEMP MACRO pages() AS TABLE \
                         SELECT uri, title, body FROM {PAGES_DB}.main.door_pages"
                    ),
                )?;
                Ok(conn)
            }
        })
        .await
        .map_err(|e| SessionError::Engine(e.to_string()))??;
        Ok(Arc::new(Session {
            conn: Arc::new(Mutex::new(conn)),
            actor,
            dataset,
            root,
            row_cap: self.config.row_cap,
        }))
    }

    /// One call: a channel, the statements, the outcomes.
    pub async fn execute(
        &self,
        actor: Actor,
        dataset: Option<&str>,
        sql: &str,
    ) -> Result<Vec<Outcome>, SessionError> {
        let session = self.channel(actor, dataset).await?;
        session.execute(sql).await
    }

    /// The datasets the record holds.
    pub async fn datasets(&self) -> Result<Vec<String>, SessionError> {
        let session = self.channel(bootstrap_actor(), None).await?;
        let batches = session
            .batches(
                &format!("SELECT name FROM {LAKE}.main.datasets ORDER BY name"),
                &[],
            )
            .await?;
        Ok(column_strings(&batches, 0))
    }

    pub async fn dataset_exists(&self, name: &str) -> Result<bool, SessionError> {
        Ok(self.datasets().await?.iter().any(|d| d == name))
    }

    /// The brief's counts over the record.
    pub async fn brief_counts(&self) -> Result<BriefCounts, SessionError> {
        let session = self.channel(bootstrap_actor(), None).await?;
        let sql = format!(
            "WITH g AS (SELECT * FROM {LAKE}.main.glossary),
             humans AS (SELECT count(*) AS n, max(written_at)::VARCHAR AS latest FROM g WHERE actor_kind = 'human'),
             latest AS (SELECT * FROM (SELECT *, row_number() OVER (PARTITION BY dataset, subject, aspect, actor_kind ORDER BY seq DESC) AS rn FROM g) WHERE rn = 1),
             approvals AS (
               SELECT dataset, json_extract_string(body, '$.table') AS tbl, written_at FROM latest
               WHERE actor_kind = 'human' AND aspect = 'recipe_change' AND json_extract_string(body, '$.table') IS NOT NULL),
             pending AS (
               SELECT count(*) AS n FROM approvals a
               WHERE NOT EXISTS (SELECT 1 FROM {LAKE}.main.imports i
                                 WHERE i.dataset = a.dataset AND i.table_name = a.tbl AND i.imported_at >= a.written_at)),
             rulings AS (
               SELECT r.dataset, r.subject, json_extract_string(jr, '$.key') AS key, json_extract_string(jr, '$.aspect') AS aspect
               FROM latest r, unnest(coalesce(json_extract(r.body, '$.rulings')::JSON[], [])) t(jr)
               WHERE r.actor_kind = 'human' AND r.aspect = 'ruling'),
             owed AS (
               SELECT count(*) AS n FROM rulings ru
               WHERE EXISTS (SELECT 1 FROM latest a, unnest(coalesce(json_extract(a.body, '$.assumptions')::JSON[], [])) t(ja)
                             WHERE a.actor_kind = 'agent' AND a.dataset = ru.dataset AND a.subject = ru.subject AND a.aspect = ru.aspect
                               AND json_extract_string(ja, '$.key') = ru.key
                               AND coalesce(json_extract(ja, '$.confidence')::DOUBLE, 0) < 1.0))
             SELECT humans.n::BIGINT, humans.latest, pending.n::BIGINT, owed.n::BIGINT FROM humans, pending, owed"
        );
        let batches = session.batches(&sql, &[]).await?;
        let rows = rows_as_text(&batches);
        let row = rows
            .first()
            .ok_or_else(|| SessionError::Engine("the brief read no row".into()))?;
        let int = |i: usize| {
            row.get(i)
                .and_then(|c| c.as_deref())
                .and_then(|c| c.parse::<i64>().ok())
                .unwrap_or(0)
        };
        Ok(BriefCounts {
            human_writings: int(0),
            latest_human_at: row.get(1).cloned().flatten(),
            approvals_pending: int(2),
            rulings_owed: int(3),
        })
    }
}

/// The server's own hand on the unbound channel.
fn bootstrap_actor() -> Actor {
    Actor {
        kind: ActorKind::Human,
        id: "glossql:bootstrap".into(),
    }
}

/// An identifier quoted for the catalog.
fn quote_name(name: &str) -> String {
    format!("\"{}\"", name.replace('"', "\"\""))
}

fn column_strings(batches: &[RecordBatch], column: usize) -> Vec<String> {
    rows_as_text(batches)
        .into_iter()
        .filter_map(|r| r.get(column).cloned().flatten())
        .collect()
}

/// Every cell as text, NULL as `None`.
pub fn rows_as_text(batches: &[RecordBatch]) -> Vec<Vec<Option<String>>> {
    let options = arrow::util::display::FormatOptions::default();
    let mut out = Vec::new();
    for batch in batches {
        let formatters: Vec<_> = batch
            .columns()
            .iter()
            .filter_map(|c| {
                arrow::util::display::ArrayFormatter::try_new(c.as_ref(), &options).ok()
            })
            .collect();
        if formatters.len() != batch.num_columns() {
            continue;
        }
        for i in 0..batch.num_rows() {
            out.push(
                formatters
                    .iter()
                    .enumerate()
                    .map(|(c, f)| {
                        if batch.column(c).is_null(i) {
                            None
                        } else {
                            Some(f.value(i).to_string())
                        }
                    })
                    .collect(),
            );
        }
    }
    out
}

// -- the session -------------------------------------------------------

/// One channel: a connection with its actor and its dataset.
pub struct Session {
    conn: Arc<Mutex<Connection>>,
    actor: Actor,
    dataset: Option<String>,
    row_cap: usize,
    /// Whether the actor is one of [`Config::root`]: the engine's knobs
    /// are theirs; else [`admitted`] judges each statement first.
    root: bool,
}

impl std::fmt::Debug for Session {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Session")
            .field("actor", &self.actor)
            .field("dataset", &self.dataset)
            .finish()
    }
}

impl Session {
    pub fn actor(&self) -> &Actor {
        &self.actor
    }

    pub fn dataset(&self) -> Option<&str> {
        self.dataset.as_deref()
    }

    /// A query's batches, on the blocking pool.
    pub async fn batches(
        &self,
        sql: &str,
        params: &[(String, String)],
    ) -> Result<Vec<RecordBatch>, SessionError> {
        self.batches_with_schema(sql, params).await.map(|(_, b)| b)
    }

    /// One read's shape and rows: the shape stands when no row does.
    pub async fn batches_with_schema(
        &self,
        sql: &str,
        params: &[(String, String)],
    ) -> Result<(SchemaRef, Vec<RecordBatch>), SessionError> {
        let conn = Arc::clone(&self.conn);
        let sql = sql.to_string();
        let params = params.to_vec();
        tokio::task::spawn_blocking(move || {
            let conn = conn
                .lock()
                .map_err(|e| SessionError::Engine(e.to_string()))?;
            arrow_batches(&conn, &sql, &params).map(|(_, schema, batches)| (schema, batches))
        })
        .await
        .map_err(|e| SessionError::Engine(e.to_string()))?
    }

    /// The statements, in order, each an outcome; a refusal names its
    /// place and carries what landed before it.
    pub async fn execute(&self, text: &str) -> Result<Vec<Outcome>, SessionError> {
        let conn = Arc::clone(&self.conn);
        let text = text.to_string();
        let cap = self.row_cap;
        let root = self.root;
        tokio::task::spawn_blocking(move || -> Result<Vec<Outcome>, SessionError> {
            let conn = conn
                .lock()
                .map_err(|e| SessionError::Engine(e.to_string()))?;
            let pieces: Vec<String> = split_statements(&text);
            let total = pieces.len();
            let mut outcomes = Vec::with_capacity(total);
            for (i, piece) in pieces.iter().enumerate() {
                let ran = if root {
                    execute_one(&conn, piece, cap)
                } else {
                    admitted(piece).and_then(|()| execute_one(&conn, piece, cap))
                };
                match ran {
                    Ok(outcome) => outcomes.push(outcome),
                    Err(e) if total == 1 => return Err(e),
                    Err(e) => {
                        return Err(SessionError::Sequence {
                            index: i + 1,
                            total,
                            context: sequence_context(i + 1, total),
                            source: Box::new(e),
                            landed: outcomes,
                        });
                    }
                }
            }
            Ok(outcomes)
        })
        .await
        .map_err(|e| SessionError::Engine(e.to_string()))?
    }

    /// One read, whole: the record's relations are never cut.
    pub async fn query_stream(&self, sql: &str) -> Result<QueryStream, SessionError> {
        self.stream(sql, &[], false).await
    }

    /// One read under the row cap: one row past it, so the cut can be
    /// told from a whole answer.
    pub async fn query_page(&self, sql: &str) -> Result<QueryStream, SessionError> {
        self.stream(sql, &[], true).await
    }

    /// The gate a standard actor's text passes before it runs
    /// ([`admitted`]); a root actor's passes untouched.
    fn admit(&self, sql: &str) -> Result<(), SessionError> {
        if self.root { Ok(()) } else { admitted(sql) }
    }

    /// One read with named parameters, `$name` in the SQL.
    pub async fn query_stream_with_params(
        &self,
        sql: &str,
        params: &[(String, String)],
    ) -> Result<QueryStream, SessionError> {
        self.stream(sql, params, false).await
    }

    /// The statements the engine's parser finds in `text`, the
    /// language's grammar on: how many, or the first refusal. Nothing
    /// is bound or run.
    pub async fn parse(&self, text: &str) -> Result<usize, SessionError> {
        let conn = Arc::clone(&self.conn);
        let text = text.to_string();
        tokio::task::spawn_blocking(move || -> Result<usize, SessionError> {
            let conn = conn
                .lock()
                .map_err(|e| SessionError::Engine(e.to_string()))?;
            let mut count = 0;
            for statement in conn
                .parse(&text)
                .map_err(|e| SessionError::Engine(e.to_string()))?
            {
                statement.map_err(|e| SessionError::Engine(e.to_string()))?;
                count += 1;
            }
            Ok(count)
        })
        .await
        .map_err(|e| SessionError::Engine(e.to_string()))?
    }

    /// One read written to a file by the engine's own writer, under
    /// the spill directory. The caller streams the file out and
    /// removes it; a read the engine refuses is its refusal, and no
    /// file.
    pub async fn copy_to(&self, sql: &str, format: CopyFormat) -> Result<PathBuf, SessionError> {
        let pieces = split_statements(sql);
        if pieces.len() != 1 || !is_read(&pieces[0]) {
            return Err(SessionError::NotOneRead);
        }
        self.admit(&pieces[0])?;
        let dir = spill_dir();
        std::fs::create_dir_all(&dir).map_err(|e| SessionError::Engine(e.to_string()))?;
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let path = dir.join(format!(
            "export-{}-{nanos}.{}",
            std::process::id(),
            format.extension()
        ));
        let text = format!(
            "COPY ({}) TO '{}' ({})",
            pieces[0].trim().trim_end_matches(';'),
            path.display().to_string().replace('\'', "''"),
            format.clause()
        );
        let conn = Arc::clone(&self.conn);
        tokio::task::spawn_blocking(move || -> Result<(), SessionError> {
            let conn = conn
                .lock()
                .map_err(|e| SessionError::Engine(e.to_string()))?;
            run(&conn, &text)
        })
        .await
        .map_err(|e| SessionError::Engine(e.to_string()))??;
        Ok(path)
    }

    async fn stream(
        &self,
        sql: &str,
        params: &[(String, String)],
        paged: bool,
    ) -> Result<QueryStream, SessionError> {
        let pieces = split_statements(sql);
        if pieces.len() != 1 || !is_read(&pieces[0]) {
            return Err(SessionError::NotOneRead);
        }
        let one = pieces[0].clone();
        self.admit(&one)?;
        let record = reads_record(&one);
        // an extraction is the language's, not a SELECT to page: it runs
        // as written, and lands one row per function
        let cap = if paged && !record && !is_extraction(&one) {
            self.row_cap
        } else {
            usize::MAX
        };
        let text = if cap == usize::MAX {
            one
        } else {
            format!("SELECT * FROM ({one}) LIMIT {}", cap + 1)
        };
        let (schema, batches) = self.batches_with_schema(&text, params).await?;
        let stream: BatchStream = Box::pin(futures::stream::iter(batches.into_iter().map(Ok)));
        Ok(QueryStream {
            schema,
            stream,
            cap,
            record,
        })
    }

    /// The console's re-measure: every function voice of the bound
    /// dataset that landed before the last change runs again over its
    /// subject; every measurement a metric's fact row wants and nobody
    /// ran, and every witnessed measurement on the dataset nobody ran
    /// (the walk), runs for the first time, in the functions' name order,
    /// which runs the forecast before the plan judgement that reads it.
    /// Returns how many ran. A
    /// function that refuses — the walk with no service named — is
    /// logged and stays owed, where the banner and the goal's next act
    /// carry its refusal by name; the others run.
    pub async fn remeasure(&self) -> Result<usize, SessionError> {
        let acts = self
            .batches(
                &format!(
                    "SELECT DISTINCT m.function, m.subject \
                     FROM glossql_glossary(current_schema(), NULL, true) r \
                     JOIN {LAKE}.main.measurements m ON m.subject = r.subject AND m.aspect = r.aspect \
                     WHERE r.actor = 'function' AND NOT r.current \
                     UNION \
                     SELECT split_part(w, ' over ', 1), split_part(w, ' over ', 2) \
                     FROM (SELECT unnest(wanted) AS w FROM {LAKE}.main.metric_axes()) \
                     UNION \
                     SELECT o.subject, split_part(o.what, ' over ', 2) \
                     FROM {LAKE}.main.owed o \
                     WHERE o.kind = 'never measured' AND split_part(o.what, ' over ', 2) = current_schema() \
                     ORDER BY 1, 2"
                ),
                &[],
            )
            .await?;
        let mut ran = 0;
        for row in rows_as_text(&acts) {
            let (Some(Some(function)), Some(Some(subject))) = (row.first(), row.get(1)) else {
                continue;
            };
            match self
                .execute(&format!("SELECT {function}() FROM {subject}"))
                .await
            {
                Ok(_) => ran += 1,
                Err(e) => tracing::warn!(function, subject, "re-measure: {e}"),
            }
        }
        Ok(ran)
    }

    /// What SQL on this channel can call beyond the engine's own: the
    /// kits' macros as doors, the declared functions as extractions.
    pub async fn registered_functions(&self) -> Result<Vec<Registered>, SessionError> {
        let macros = self
            .batches(
                "SELECT DISTINCT function_name FROM duckdb_functions() \
                 WHERE NOT internal AND function_type IN ('table_macro', 'macro') ORDER BY 1",
                &[],
            )
            .await?;
        let mut out: Vec<Registered> = column_strings(&macros, 0)
            .into_iter()
            .map(|name| Registered {
                kind: "door",
                syntax: Some(format!("{name}(...)")),
                name,
            })
            .collect();
        let declared = self
            .batches(
                &format!("SELECT name FROM {LAKE}.main.functions ORDER BY name"),
                &[],
            )
            .await?;
        out.extend(
            column_strings(&declared, 0)
                .into_iter()
                .map(|name| Registered {
                    kind: "extract",
                    syntax: Some(format!("SELECT {name}() FROM <subject>")),
                    name,
                }),
        );
        out.sort();
        Ok(out)
    }
}

/// One statement, run once: a glossql statement answers one line, a
/// write its count, a read its rows under the cap.
fn execute_one(conn: &Connection, sql: &str, cap: usize) -> Result<Outcome, SessionError> {
    let cap = if reads_record(sql) { usize::MAX } else { cap };
    let (kind, _, batches) = arrow_batches(conn, sql, &[])?;
    match kind {
        ResultType::ChangedRows => {
            let n = one_cell(&batches)
                .and_then(|c| c.parse::<u64>().ok())
                .unwrap_or(0);
            Ok(Outcome::Affected(n))
        }
        ResultType::Nothing => Ok(Outcome::Done(String::new())),
        _ => {
            if is_glossql_head(sql)
                && let Some(text) = one_cell(&batches)
            {
                if let Some(row) = grounding_row(conn, &text)? {
                    return Ok(Outcome::Rows {
                        batches: row,
                        truncated: false,
                    });
                }
                return Ok(Outcome::Done(text));
            }
            let (batches, truncated) = cut(batches, cap);
            Ok(Outcome::Rows { batches, truncated })
        }
    }
}

/// A grounding's write answers with the metric's fact row: what the
/// view's columns say and what they owe, at the pin the write moved
/// to, in place of the outcome's one line. Any other gloss keeps its
/// line; a metric with no row (the kit not loaded) keeps it too.
fn grounding_row(
    conn: &Connection,
    outcome: &str,
) -> Result<Option<Vec<RecordBatch>>, SessionError> {
    let Some(rest) = outcome.strip_prefix("glossed ") else {
        return Ok(None);
    };
    let Some(aspect) = rest.split(" on ").next().filter(|a| !a.is_empty()) else {
        return Ok(None);
    };
    let quoted = aspect.replace('\'', "''");
    let (_, _, kind) = arrow_batches(
        conn,
        &format!(
            "SELECT kind FROM {LAKE}.main.aspects WHERE name = '{quoted}' ORDER BY seq DESC LIMIT 1"
        ),
        &[],
    )?;
    if one_cell(&kind).as_deref() != Some("QUERY") {
        return Ok(None);
    }
    let (_, _, row) = arrow_batches(
        conn,
        &format!("SELECT * FROM {LAKE}.main.metric_axes() WHERE metric = '{quoted}'"),
        &[],
    )?;
    let rows: usize = row.iter().map(|b| b.num_rows()).sum();
    Ok((rows > 0).then_some(row))
}

/// Statements split on `;` outside quotes, dollar quotes (`$$` and
/// tagged, `$tag$`) and comments.
fn split_statements(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    let mut in_single = false;
    let mut in_double = false;
    // the tag of the dollar quote open, `""` for `$$`
    let mut dollar: Option<String> = None;
    let mut in_line_comment = false;
    // a dollar quote opening or closing at `i`: its tag, and its length
    let delimiter = |i: usize| -> Option<(String, usize)> {
        if chars.get(i) != Some(&'$') {
            return None;
        }
        let mut j = i + 1;
        while j < chars.len() && (chars[j].is_ascii_alphanumeric() || chars[j] == '_') {
            j += 1;
        }
        (chars.get(j) == Some(&'$')).then(|| (chars[i + 1..j].iter().collect(), j + 1 - i))
    };
    while i < chars.len() {
        let c = chars[i];
        if in_line_comment {
            current.push(c);
            if c == '\n' {
                in_line_comment = false;
            }
            i += 1;
            continue;
        }
        let in_dollar = dollar.is_some();
        if !in_single && !in_double && !in_dollar && c == '-' && chars.get(i + 1) == Some(&'-') {
            in_line_comment = true;
            current.push(c);
            i += 1;
            continue;
        }
        if !in_single && !in_double && c == '$' {
            match (&dollar, delimiter(i)) {
                (None, Some((tag, len))) => {
                    current.extend(chars[i..i + len].iter());
                    dollar = Some(tag);
                    i += len;
                    continue;
                }
                (Some(open), Some((tag, len))) if *open == tag => {
                    current.extend(chars[i..i + len].iter());
                    dollar = None;
                    i += len;
                    continue;
                }
                _ => {}
            }
        }
        if !in_double && !in_dollar && c == '\'' {
            in_single = !in_single;
        } else if !in_single && !in_dollar && c == '"' {
            in_double = !in_double;
        } else if !in_single && !in_double && !in_dollar && c == ';' {
            if !current.trim().is_empty() {
                out.push(current.trim().to_string());
            }
            current.clear();
            i += 1;
            continue;
        }
        current.push(c);
        i += 1;
    }
    if !current.trim().is_empty() {
        out.push(current.trim().to_string());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn statements_split_outside_quotes_and_dollar_bodies() {
        let pieces = split_statements(
            "USE fin; GLOSS meaning ON orders.amount AS $${\"value\": \"a; b\"}$$; SELECT ';' AS c",
        );
        assert_eq!(pieces.len(), 3);
        assert!(pieces[1].contains("a; b"));
    }

    #[test]
    fn a_record_read_reviews_and_a_gloss_writes() {
        assert_eq!(
            call_shape("SELECT * FROM glossary"),
            CallShape {
                reviews: true,
                writes: false,
                dataset: None
            }
        );
        assert!(call_shape("USE fin; GLOSS meaning ON orders.amount AS $${}$$").writes);
        assert_eq!(
            call_shape("USE fin; SELECT * FROM owed").dataset.as_deref(),
            Some("fin")
        );
        assert!(call_shape("SELECT column_profile() FROM ops").writes);
        let setup = r#"
        DECLARE DATASET fin SET (purpose: 'brief delivery');
        USE fin;
        DECLARE ASPECT dso WITH $${"title": "DSO", "x-kind": "metric"}$$ AS QUERY;
        GLOSS dso ON fin AS $${"sql": "SELECT 1 AS v",
          "assumptions": [{"dimension": "definition", "key": "per-line", "assumption": "per line", "basis": "judgment", "confidence": 0.7}]}$$;
    "#;
        let shape = call_shape(setup);
        assert!(shape.writes && !shape.reviews, "{shape:?}");
        assert_eq!(shape.dataset.as_deref(), Some("fin"));
        assert!(reads_record("SELECT * FROM GLOSSARY(orders)"));
        assert!(!reads_record("SELECT * FROM fin.orders"));
    }

    /// A warehouse in an object store is known by its scheme, and its
    /// credential is one scoped secret, a key pair or a bearer.
    #[test]
    fn the_warehouse_credential_is_one_scoped_secret() {
        assert_eq!(store_kind("gs://lake/warehouse"), Some("gcs"));
        assert_eq!(store_kind("s3://lake/warehouse/"), Some("s3"));
        assert_eq!(store_kind("/var/lib/glossql/warehouse"), None);
        assert_eq!(store_kind("abfss://lake@acct.dfs.core.windows.net/w"), None);
        let keys = WarehouseCredential::Keys {
            key_id: "GOOG1E".into(),
            secret: "s'cret".into(),
            region: None,
        };
        assert_eq!(
            secret_sql("gcs", &keys, "gs://lake/warehouse"),
            "CREATE OR REPLACE SECRET warehouse (TYPE gcs, KEY_ID 'GOOG1E', SECRET 's''cret', \
             SCOPE 'gs://lake/warehouse')"
        );
        let keys = WarehouseCredential::Keys {
            key_id: "AKIA".into(),
            secret: "x".into(),
            region: Some("eu-west-1".into()),
        };
        assert_eq!(
            secret_sql("s3", &keys, "s3://lake/warehouse"),
            "CREATE OR REPLACE SECRET warehouse (TYPE s3, KEY_ID 'AKIA', SECRET 'x', \
             REGION 'eu-west-1', SCOPE 's3://lake/warehouse')"
        );
        assert_eq!(
            secret_sql(
                "gcs",
                &WarehouseCredential::Bearer("t".into()),
                "gs://lake/w"
            ),
            "CREATE OR REPLACE SECRET warehouse (TYPE gcs, BEARER_TOKEN 't', SCOPE 'gs://lake/w')"
        );
    }

    /// The sink replaces the warehouse's secret on the instance, where
    /// httpfs is loaded; a directory warehouse has no sink.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_warehouse_sink_replaces_the_secret() {
        let dir = tempfile::tempdir().expect("a directory");
        let mut config = Config::laptop(dir.path());
        config.service = Some(Service {
            url: "http://127.0.0.1:1".into(),
            token: Some("k".into()),
            audience: None,
        });
        let plane = Plane::open(config).await.expect("opens");
        assert!(plane.warehouse_sink().is_none());
        let sink = WarehouseSink {
            instance: plane.instance.clone(),
            kind: "gcs",
            scope: "gs://lake/warehouse".into(),
        };
        sink.set("t1").expect("set");
        sink.set("t2").expect("replaced");
        let channel = plane
            .channel(
                Actor {
                    kind: ActorKind::Agent,
                    id: "t".into(),
                },
                None,
            )
            .await
            .expect("a channel");
        let rows = rows_as_text(
            &channel
                .batches(
                    "SELECT name, type, scope::VARCHAR FROM duckdb_secrets() ORDER BY name",
                    &[],
                )
                .await
                .expect("reads"),
        );
        assert_eq!(
            rows,
            vec![vec![
                Some("warehouse".to_string()),
                Some("gcs".to_string()),
                Some("['gs://lake/warehouse']".to_string())
            ]]
        );
    }

    /// The service is named once for the instance: the settings every
    /// service call reads, httpfs loaded for the POST, and the bearer
    /// the host mints set through the sink.
    #[tokio::test(flavor = "multi_thread")]
    async fn the_service_is_named_once_for_the_instance() {
        let dir = tempfile::tempdir().expect("a directory");
        let mut config = Config::laptop(dir.path());
        config.service = Some(Service {
            url: "http://127.0.0.1:1".into(),
            token: Some("k1".into()),
            audience: None,
        });
        let plane = Plane::open(config).await.expect("opens");
        let channel = plane
            .channel(
                Actor {
                    kind: ActorKind::Agent,
                    id: "t".into(),
                },
                None,
            )
            .await
            .expect("a channel");
        let read = "SELECT current_setting('glossql_service_url'), current_setting('glossql_service_token'), \
                    (SELECT loaded FROM duckdb_extensions() WHERE extension_name = 'httpfs')";
        let rows = rows_as_text(&channel.batches(read, &[]).await.expect("reads"));
        assert_eq!(
            rows[0],
            vec![
                Some("http://127.0.0.1:1".to_string()),
                Some("k1".to_string()),
                Some("true".to_string())
            ]
        );
        plane.token_sink().set("k2").expect("set");
        let rows = rows_as_text(&channel.batches(read, &[]).await.expect("reads"));
        assert_eq!(rows[0][1].as_deref(), Some("k2"));
        let unnamed = Plane::open(Config::laptop(
            tempfile::tempdir().expect("a directory").path(),
        ))
        .await
        .expect("opens");
        let channel = unnamed
            .channel(
                Actor {
                    kind: ActorKind::Agent,
                    id: "t".into(),
                },
                None,
            )
            .await
            .expect("a channel");
        let rows = rows_as_text(
            &channel
                .batches("SELECT current_setting('glossql_service_url')", &[])
                .await
                .expect("reads"),
        );
        assert_eq!(rows[0][0].as_deref(), Some(""));
    }
}

/// For the suites: a workspace copied from a golden one, so a test
/// opens in the time of the attach instead of paying the kits. The
/// golden copy is built once per content, keyed by the extension
/// artifact and the kits' texts, under the system's temporary
/// directory. A build that loses the race to another process yields to
/// the one that landed: the rename is atomic, so a copy sees a whole
/// workspace or none.
pub mod testing {
    use super::{Config, Plane, SessionError};
    use std::hash::{Hash, Hasher};
    use std::path::{Path, PathBuf};

    /// The laptop config for `into`, holding a copy of the golden
    /// workspace: every kit's row stands, so the open is the attach. A
    /// directory that holds a workspace already is left as it is.
    pub async fn golden(into: &Path) -> Result<Config, SessionError> {
        let config = Config::laptop(into);
        if into.join("catalog.ducklake").exists() {
            return Ok(config);
        }
        let golden = golden_dir(&config).await?;
        copy_dir(&golden, into)
            .map_err(|e| SessionError::Engine(format!("the golden copy: {e}")))?;
        Ok(config)
    }

    async fn golden_dir(config: &Config) -> Result<PathBuf, SessionError> {
        let io = |e: std::io::Error| SessionError::Engine(format!("the golden workspace: {e}"));
        let root = std::env::temp_dir().join("glossdb-golden");
        std::fs::create_dir_all(&root).map_err(io)?;
        let dir = root.join(key(config).map_err(io)?);
        if dir.is_dir() {
            return Ok(dir);
        }
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0);
        let scratch = root.join(format!("build-{}-{nanos}", std::process::id()));
        std::fs::create_dir_all(&scratch).map_err(io)?;
        let built = Plane::open(Config::laptop(&scratch)).await?;
        drop(built);
        match std::fs::rename(&scratch, &dir) {
            Ok(()) => {}
            Err(_) if dir.is_dir() => {
                let _ = std::fs::remove_dir_all(&scratch);
            }
            Err(e) => return Err(io(e)),
        }
        Ok(dir)
    }

    /// What the golden workspace is made of: the extension artifact (by
    /// size and time, a rebuild being a new one), the kits' texts and
    /// this crate's version.
    fn key(config: &Config) -> std::io::Result<String> {
        let mut h = std::hash::DefaultHasher::new();
        env!("CARGO_PKG_VERSION").hash(&mut h);
        let artifact = std::fs::metadata(&config.extension)?;
        artifact.len().hash(&mut h);
        artifact.modified()?.hash(&mut h);
        for kit in &config.kits {
            std::fs::read(kit)?.hash(&mut h);
        }
        Ok(format!("{:016x}", h.finish()))
    }

    fn copy_dir(from: &Path, to: &Path) -> std::io::Result<()> {
        std::fs::create_dir_all(to)?;
        for entry in std::fs::read_dir(from)? {
            let entry = entry?;
            let target = to.join(entry.file_name());
            if entry.file_type()?.is_dir() {
                copy_dir(&entry.path(), &target)?;
            } else {
                std::fs::copy(entry.path(), &target)?;
            }
        }
        Ok(())
    }
}
