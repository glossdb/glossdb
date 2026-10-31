//! The engine on DuckDB. The gloss extension owns the language and the
//! record, DuckLake the lake; this crate is the facade the doors use:
//! a plane that opens the workspace, a channel per actor, statements
//! executed and queries streamed as Arrow. The surface mirrors
//! `glossql-session`'s names, so a door switches engines by one `use`.
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

use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use arrow::array::{RecordBatch, RecordBatchReader};
use arrow::datatypes::SchemaRef;
use arrow::ffi_stream::{ArrowArrayStreamReader, FFI_ArrowArrayStream};
use datafusion::execution::SendableRecordBatchStream;
use datafusion::physical_plan::stream::RecordBatchStreamAdapter;
use duckdb_neo::connection::Connection;
use duckdb_neo::environment::{Environment, StorageLocation};
use duckdb_neo::instance::{AttachBuilder, Instance, InstanceBuilder};
use duckdb_neo::query_result::ResultType;
use duckdb_neo::{Parameters, QueryParameter};
pub use glossql_glossary::{Actor, ActorKind};
use glossql_parser::{GlossqlParser, Statement};

/// The default row cap on a paging read.
pub const DEFAULT_ROW_CAP: usize = 200;

/// The lake's name in the catalog; every store relation reads as
/// `ws.glossql.<relation>`.
pub const LAKE: &str = "ws";

/// The instance's own in-memory database: what the build carries and
/// the record does not, the door's pages.
const PAGES_DB: &str = "memory";

/// The record's own words, declared at every open before any kit:
/// the ruling channel, a recipe's approval, the apps as glosses.
pub const CORE: &str = include_str!("../kits/core.sql");
/// The door's reads that stand on the kits', declared after them.
pub const DOOR: &str = include_str!("../kits/door.sql");

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

/// What landed and what never ran, for a refusal at `index` of `total`.
fn sequence_context(index: usize, total: usize) -> String {
    let landed = match index {
        1 => "nothing landed before it".to_string(),
        2 => "statement 1 landed".to_string(),
        _ => format!("statements 1–{} landed", index - 1),
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

/// A read as the doors drive it.
pub struct QueryStream {
    pub stream: SendableRecordBatchStream,
    /// Rows a paging caller ships before declaring the answer cut;
    /// `usize::MAX` on a read of the record, which must be whole.
    pub cap: usize,
    /// Whether the statement reads the record anywhere.
    pub record: bool,
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

/// The service points. None is served on this engine yet: the worlds
/// are the port's fourth step, and their service calls come with them.
pub const POINTS: [&str; 0] = [];

/// The two budgets the flags name, as the session names them; this
/// engine takes neither yet.
pub const DEFAULT_CUBE_CACHE_MB: u64 = 2048;
pub const DEFAULT_MEMORY_LIMIT_MB: u64 = 4096;

/// The environment variable a point is configured by, `GLOSSQL_<POINT>_<WHAT>`.
pub fn point_variable(point: &str, what: &str) -> String {
    format!(
        "GLOSSQL_{}_{}",
        point.to_ascii_uppercase(),
        what.to_ascii_uppercase()
    )
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

/// A call that does not parse shapes as neither — the engine names the
/// refusal when it runs. A read of the record alone is a review; any
/// glossql statement or a substrate write is a write.
pub fn call_shape(statements: &str) -> CallShape {
    let Ok(parsed) = GlossqlParser::parse_sql(statements) else {
        return CallShape {
            reviews: false,
            writes: false,
            dataset: None,
        };
    };
    let mut reads_record = false;
    let mut writes = false;
    let mut dataset = None;
    for statement in &parsed {
        match statement {
            Statement::Use(u) => dataset = Some(u.dataset.value.clone()),
            Statement::Substrate(df) => {
                if reads_only_record(df) {
                    reads_record = true;
                } else if !matches!(
                    df.as_ref(),
                    datafusion_sql::parser::Statement::Statement(inner)
                        if matches!(inner.as_ref(), datafusion_sql::sqlparser::ast::Statement::Query(_))
                ) {
                    writes = true;
                }
            }
            _ => writes = true,
        }
    }
    CallShape {
        reviews: reads_record && !writes,
        writes,
        dataset,
    }
}

/// The store's relations, as the extension serves them under
/// `ws.glossql`, and the two reads over the record.
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
    "recipes",
    "imports",
    "kits",
    "attest",
];

fn reads_only_record(statement: &datafusion_sql::parser::Statement) -> bool {
    use datafusion_sql::sqlparser::ast::visit_relations;
    let datafusion_sql::parser::Statement::Statement(inner) = statement else {
        return false;
    };
    let mut any = false;
    let mut all = true;
    let _ = visit_relations(inner.as_ref(), |name| {
        any = true;
        let parts: Vec<String> = name
            .0
            .iter()
            .filter_map(|p| p.as_ident().map(|i| i.value.to_lowercase()))
            .collect();
        let record = match parts.as_slice() {
            [one] => RECORD.contains(&one.as_str()),
            [schema, one] => schema == "glossql" && RECORD.contains(&one.as_str()),
            [lake, schema, one] => {
                lake == LAKE && schema == "glossql" && RECORD.contains(&one.as_str())
            }
            _ => false,
        };
        if !record {
            all = false;
        }
        std::ops::ControlFlow::<()>::Continue(())
    });
    any && all
}

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
fn is_read(statement: &str) -> bool {
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
            break;
        }
    }
    let rest = rest.trim_start_matches('(');
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
    /// The gloss extension, as a file to load.
    pub extension: PathBuf,
    /// The kits, in order; each a script `gloss_kit` runs at open.
    pub kits: Vec<PathBuf>,
    /// The lake's catalog: a path to a `.ducklake` file, or a
    /// `ducklake:` URI naming a Postgres catalog.
    pub catalog: String,
    /// The lake's data path.
    pub warehouse: String,
    pub row_cap: usize,
}

impl Config {
    /// The laptop's shape: the workspace directory holds the catalog
    /// and the warehouse; the extension and the kits come from the
    /// sibling checkout unless `GLOSS_EXTENSION` and `GLOSS_KITS` say
    /// otherwise.
    pub fn laptop(workspace: &Path) -> Config {
        let gloss = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../gloss");
        let extension = std::env::var_os("GLOSS_EXTENSION")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                gloss.join(format!(
                    "build/release/repository/v2.0.0/{}/gloss.duckdb_extension",
                    platform()
                ))
            });
        let kits_dir = std::env::var_os("GLOSS_KITS")
            .map(PathBuf::from)
            .unwrap_or_else(|| gloss.join("kits"));
        Config {
            extension,
            kits: vec![
                kits_dir.join("kpi/kit.sql"),
                kits_dir.join("quality/kit.sql"),
                kits_dir.join("metrics/kit.sql"),
            ],
            catalog: workspace.join("catalog.ducklake").display().to_string(),
            warehouse: workspace.join("warehouse").display().to_string(),
            row_cap: DEFAULT_ROW_CAP,
        }
    }
}

impl Config {
    /// A deployment's shape: the catalog a `ducklake:` URI or a
    /// Postgres URI, the warehouse an object-store location; the
    /// extension and the kits where `GLOSS_EXTENSION` and `GLOSS_KITS`
    /// say, or beside the binary.
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
             AND schema_name = 'glossql' AND function_name LIKE 'routes\\_%' ESCAPE '\\' \
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
            &format!("SELECT ctes, arms FROM {LAKE}.glossql.{route}()"),
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
        "ds AS (SELECT dataset FROM {LAKE}.glossql.current_dataset), \
         axes AS MATERIALIZED (SELECT * FROM {LAKE}.glossql.metric_axes()), \
         owed AS MATERIALIZED (SELECT * FROM {LAKE}.glossql.owed), \
         reds AS MATERIALIZED (SELECT subject, witness FROM gloss_attest(current_schema(), NULL) WHERE band = 'red'), \
         bodies AS MATERIALIZED (SELECT aspect AS metric, body::VARCHAR AS body FROM ( \
           SELECT g.aspect, g.body, row_number() OVER (PARTITION BY g.aspect ORDER BY g.seq DESC) AS rn \
           FROM {LAKE}.glossql.glossary g, ds WHERE g.dataset = ds.dataset AND g.subject = ds.dataset) WHERE rn = 1), \
         applicable AS (SELECT count(*) AS n, string_agg(metric, ', ' ORDER BY metric) AS metrics, \
           string_agg(chr(39) || metric || chr(39), ', ' ORDER BY metric) AS metric_list FROM axes WHERE applicable)"
    );
    let kit_ctes = if ctes.is_empty() {
        String::new()
    } else {
        format!(", {}", ctes.join(", "))
    };
    Ok(format!(
        "CREATE OR REPLACE VIEW {LAKE}.glossql.next AS WITH {shared}{kit_ctes}, \
         steps AS ({steps}), \
         first AS (SELECT *, row_number() OVER (PARTITION BY surface ORDER BY step, say, why) AS rn FROM steps) \
         SELECT CASE surface WHEN 'structure' THEN 1 WHEN 'metrics' THEN 2 WHEN 'slices' THEN 3 \
                             WHEN 'bands' THEN 4 WHEN 'checks' THEN 5 WHEN 'app' THEN 6 \
                             WHEN 'plan' THEN 7 ELSE 8 END AS goal, \
                surface, step, state, act, say, why, statement, \"then\" \
         FROM first WHERE rn = 1"
    ))
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

/// The search path after a `USE`: the dataset's schema first, the
/// store's schema behind it, so a statement spells a relation of the
/// record bare, `FROM glossary`, as the doors and the skills do.
fn set_search_path(conn: &Connection) -> Result<(), SessionError> {
    let (_, _, batches) = arrow_batches(conn, "SELECT current_schema()", &[])?;
    let schema = one_cell(&batches).unwrap_or_else(|| "main".to_string());
    run(
        conn,
        &format!("SET search_path = '{LAKE}.{schema},{LAKE}.glossql,{LAKE}.main,{PAGES_DB}.main'"),
    )
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

impl Plane {
    /// Open the workspace: the instance, the extension, the lake, the
    /// grammar, the store, and the kits in order.
    pub async fn open(config: Config) -> Result<Plane, SessionError> {
        let opened = tokio::task::spawn_blocking({
            let config = config.clone();
            move || -> Result<(Environment, Instance), SessionError> {
                let environment = Environment::new()?;
                let instance = InstanceBuilder::new()
                    .option("allow_unsigned_extensions", "true")
                    .build(&environment)?;
                instance.attach(AttachBuilder::new(StorageLocation::InMemory).make_default())?;
                let conn = instance.connect()?;
                run(&conn, &format!("LOAD '{}'", config.extension.display()))?;
                run(&conn, "INSTALL ducklake")?;
                run(&conn, "LOAD ducklake")?;
                let catalog = if config.catalog.starts_with("ducklake:") {
                    config.catalog.clone()
                } else {
                    format!("ducklake:{}", config.catalog)
                };
                run(
                    &conn,
                    &format!(
                        "ATTACH '{catalog}' AS {LAKE} (DATA_PATH '{}/')",
                        config.warehouse.trim_end_matches('/')
                    ),
                )?;
                run(&conn, &format!("USE {LAKE}"))?;
                run(&conn, "SET active_grammar_extensions = ['gloss']")?;
                run(&conn, "PRAGMA gloss")?;
                for statement in split_statements(CORE) {
                    run(&conn, &statement)?;
                }
                for kit in &config.kits {
                    run(&conn, &format!("FROM gloss_kit('{}')", kit.display()))
                        .map_err(|e| SessionError::Engine(format!("kit {}: {e}", kit.display())))?;
                }
                for statement in split_statements(DOOR) {
                    run(&conn, &statement)?;
                }
                run(&conn, &next_view(&conn)?)?;
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

    /// The pages the door serves, held here and published as rows of
    /// `pages()`: a table in the instance's own in-memory database,
    /// never the lake, since a page is the build's and not the record's.
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
        run(
            &conn,
            &format!(
                "CREATE OR REPLACE MACRO {PAGES_DB}.main.pages() AS TABLE \
                 SELECT uri, title, body FROM {PAGES_DB}.main.door_pages"
            ),
        )
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
        let conn = tokio::task::spawn_blocking({
            let dataset = dataset.clone();
            move || -> Result<Connection, SessionError> {
                let conn = instance.connect()?;
                run(&conn, &format!("USE {LAKE}"))?;
                run(&conn, "SET active_grammar_extensions = ['gloss']")?;
                run(
                    &conn,
                    &format!("SET VARIABLE gloss_actor = '{}'", kind.replace('\'', "''")),
                )?;
                run(
                    &conn,
                    &format!("SET VARIABLE gloss_actor_id = '{}'", id.replace('\'', "''")),
                )?;
                if let Some(dataset) = &dataset {
                    run(&conn, &format!("USE {LAKE}.{}", quote_name(dataset))).map_err(|_| {
                        SessionError::UnknownName {
                            name: dataset.clone(),
                            detail: format!("no dataset `{dataset}` in the workspace"),
                        }
                    })?;
                }
                set_search_path(&conn)?;
                Ok(conn)
            }
        })
        .await
        .map_err(|e| SessionError::Engine(e.to_string()))??;
        Ok(Arc::new(Session {
            conn: Arc::new(Mutex::new(conn)),
            actor,
            dataset,
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
                &format!("SELECT name FROM {LAKE}.glossql.datasets ORDER BY name"),
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
            "WITH g AS (SELECT * FROM {LAKE}.glossql.glossary),
             humans AS (SELECT count(*) AS n, max(written_at)::VARCHAR AS latest FROM g WHERE actor_kind = 'human'),
             latest AS (SELECT * FROM (SELECT *, row_number() OVER (PARTITION BY dataset, subject, aspect, actor_kind ORDER BY seq DESC) AS rn FROM g) WHERE rn = 1),
             approvals AS (
               SELECT dataset, json_extract_string(body, '$.table') AS tbl, written_at FROM latest
               WHERE actor_kind = 'human' AND aspect = 'recipe_change' AND json_extract_string(body, '$.table') IS NOT NULL),
             pending AS (
               SELECT count(*) AS n FROM approvals a
               WHERE NOT EXISTS (SELECT 1 FROM {LAKE}.glossql.imports i
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
        tokio::task::spawn_blocking(move || -> Result<Vec<Outcome>, SessionError> {
            let conn = conn
                .lock()
                .map_err(|e| SessionError::Engine(e.to_string()))?;
            let pieces: Vec<String> = split_statements(&text);
            let total = pieces.len();
            let mut outcomes = Vec::with_capacity(total);
            for (i, sql) in pieces.iter().enumerate() {
                match execute_one(&conn, sql, cap) {
                    Ok(outcome) => {
                        if sql
                            .trim_start()
                            .get(..3)
                            .is_some_and(|h| h.eq_ignore_ascii_case("use"))
                        {
                            set_search_path(&conn)?;
                        }
                        outcomes.push(outcome);
                    }
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

    /// One read with named parameters, `$name` in the SQL.
    pub async fn query_stream_with_params(
        &self,
        sql: &str,
        params: &[(String, String)],
    ) -> Result<QueryStream, SessionError> {
        self.stream(sql, params, false).await
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
        let stream = RecordBatchStreamAdapter::new(
            schema,
            futures::stream::iter(batches.into_iter().map(Ok)),
        );
        Ok(QueryStream {
            stream: Box::pin(stream),
            cap,
            record,
        })
    }

    /// The docket's re-measure: every function voice of the bound
    /// dataset that landed before the last change runs again over its
    /// subject, and every measurement a metric's fact row wants and
    /// nobody ran runs for the first time. Returns how many ran.
    pub async fn remeasure(&self) -> Result<usize, SessionError> {
        let acts = self
            .batches(
                &format!(
                    "SELECT DISTINCT m.function, m.subject \
                     FROM gloss_glossary(current_schema(), NULL, true) r \
                     JOIN {LAKE}.glossql.measurements m ON m.subject = r.subject AND m.aspect = r.aspect \
                     WHERE r.actor = 'function' AND NOT r.current \
                     UNION \
                     SELECT split_part(w, ' over ', 1), split_part(w, ' over ', 2) \
                     FROM (SELECT unnest(wanted) AS w FROM {LAKE}.glossql.metric_axes()) \
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
            self.execute(&format!("SELECT {function}() FROM {subject}"))
                .await?;
            ran += 1;
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
                &format!("SELECT name FROM {LAKE}.glossql.functions ORDER BY name"),
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
            "SELECT kind FROM {LAKE}.glossql.aspects WHERE name = '{quoted}' ORDER BY seq DESC LIMIT 1"
        ),
        &[],
    )?;
    if one_cell(&kind).as_deref() != Some("QUERY") {
        return Ok(None);
    }
    let (_, _, row) = arrow_batches(
        conn,
        &format!("SELECT * FROM {LAKE}.glossql.metric_axes() WHERE metric = '{quoted}'"),
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
        assert!(reads_record("SELECT * FROM GLOSSARY(orders)"));
        assert!(!reads_record("SELECT * FROM fin.orders"));
    }
}
