//! The MCP shim: one interface, one tool. `glossql` takes statements and
//! returns outcomes — the interface tells, skills teach. Everything an agent
//! must *learn* (grammar, function authoring, flows) ships as skills,
//! served from this same interface as resources and prompts ([`crate::skills`]);
//! everything live (declared functions, the glossary, the tables) is
//! read through the language itself, where it is always current.

use std::sync::Arc;

use rmcp::model::{
    CallToolRequestParams, CallToolResponse, CallToolResult, ContentBlock, GetPromptRequestParams,
    GetPromptResponse, GetPromptResult, Implementation, InitializeRequestParams, InitializeResult,
    ListPromptsResult, ListResourcesResult, ListToolsResult, PaginatedRequestParams, Prompt,
    PromptMessage, ProtocolVersion, ReadResourceRequestParams, ReadResourceResponse,
    ReadResourceResult, Resource, ResourceContents, Role, ServerCapabilities, ServerConfig, Tool,
};
use rmcp::model::{ListResourceTemplatesResult, ResourceTemplate};
use rmcp::service::{RequestContext, RoleServer};
use rmcp::{ErrorData as McpError, ServerHandler};

use crate::engine::Caller;
use crate::engine::{Actor, ActorKind};

use crate::engine::{Plane, Session, SessionError};

use crate::window;
use crate::wire;

type SummaryCounts = crate::engine::SummaryCounts;

/// The summary's counts, as each engine serves them.
async fn summary_counts(plane: &Plane) -> Result<SummaryCounts, String> {
    plane.summary_counts().await.map_err(|e| e.to_string())
}

const INSTRUCTIONS: &str = "glossdb is the data harness for people and agents. Here you \
build this workspace's data intelligence layer in the lake, beside the data: what the data \
means, how its sources map, whether it can be trusted, and who decides. There are four kinds \
of work. Integrate: declare a source, load its tables with load queries, define views. \
Describe: annotate the dataset, its tables, columns, relationships and views. Test: the \
built-in tests run after each write, and a rule of your own is a view. Review: state each \
judgment call as an assumption with a key and a confidence; a person confirms or corrects it, \
and their decision outranks your annotation. The kinds are not stages: work in the order the \
task asks for. \
Everything you keep is a view: a named SQL query on the dataset with its reason, defined in \
one statement, `GLOSS <name> ON <dataset> AS $${\"kind\": \"<kind>\", \"sql\": \"<query>\", \
\"meaning\": \"<why it is kept>\", \"tags\": [\"<word>\"]}$$`. The kind says what it is for. \
No kind: a query worth reading again, the evidence behind a decision (a profile, a \
comparison, a mapping, a unit); it asks for nothing more. `table`, `value`, `metric`: what \
the dataset serves; `next` asks for their descriptions, and the built-in tests run on them. \
`rule`: a query whose rows break a rule; it must return none, a test runs on it after every \
write, and only a person accepts a count of rows. Keep each query that decided something \
and tag it: `find('<term>')` searches views by name, meaning, tags and the columns they \
read, so the next agent and the reviewer find it. A function (`DECLARE FUNCTION`) is a \
kit's machinery: one stored result per asset, computed again when what it read changed. \
Write one only for a measure that many assets need. \
One tool, `glossql`, runs glossql statements and SQL. Start with the entry skill: `SELECT \
body FROM pages() WHERE uri = 'skill://glossql/SKILL.md'`. Every page this server serves is \
a row of `pages()`; the language is `doc://SPEC.md` and `doc://grammar.ebnf`. Read the \
catalog as `main.<relation>` (`main.next`, `main.glossary`, `main.results`): a table of the \
same name in a dataset would hide it. \
Every result ends with `status:`: whether the last statement ran or was refused. A call on \
a dataset (`USE <dataset>;` or the dataset's own endpoint) adds `next:`, the count of what \
must and what should be done on the dataset per kind of work, and `first:`, the first of them. \
A call that changed what waits in the workspace adds `summary:`. \
`SELECT level, kind, asset, state, open, statement FROM main.next` lists every open row with \
the statement that opens the work; `<...>` marks what you fill in. Each row has a level. Must: \
served data is wrong or cannot be served. Should: the layer is incomplete for what is served. \
Could: what sits beside it, read on request with `WHERE level = 'could'`. Work on a dataset is \
complete when no must is open; the should rows make the layer complete. Rows that wait for a \
person are counted apart and do not hold you back. The list is context: what the person asked \
for decides what you work on. Read live state through the tool instead of assuming it.";

/// What the summary is decided on: the store's counts plus the open
/// question count. Movement is a comparison of these FACTS — never of
/// rendered lines (string equality on non-keys is forbidden; a
/// rendered string is display, not identity).
#[derive(Clone, PartialEq, Eq)]
pub struct SummaryFacts {
    counts: SummaryCounts,
    questions: usize,
    datasets: usize,
}

/// The `_meta` key a tool result carries its moved summary under.
pub const SUMMARY_META: &str = "glossdb/summary";

/// The `_meta` key a refused call carries its refusal's code under,
/// as `{"code": …}`, where the refusal has one.
pub const REFUSAL_META: &str = "glossdb/refusal";

/// A refused call: the reason the agent reads, and the refusal's code
/// where it has one (`SessionError::code`).
struct Refusal {
    reason: String,
    code: Option<String>,
}

impl Refusal {
    fn of(e: &SessionError) -> Refusal {
        Refusal {
            reason: e.to_string(),
            code: e.code().map(str::to_string),
        }
    }
}

impl From<String> for Refusal {
    fn from(reason: String) -> Refusal {
        Refusal { reason, code: None }
    }
}

/// The summary a call moved: the line, as the `summary:` block carries
/// it, and the counts it renders, as the result's `_meta` carries them.
struct SummaryMoved {
    line: String,
    facts: SummaryFacts,
}

impl SummaryMoved {
    /// The counts as the result's `_meta` field, beside the line: what
    /// a client or a test reads without parsing the text.
    fn meta(&self) -> rmcp::model::MetaObject {
        let mut meta = rmcp::model::MetaObject::new();
        meta.0.insert(
            SUMMARY_META.to_string(),
            serde_json::json!({
                "line": self.line,
                "datasets": self.facts.datasets,
                "assumptions_waiting": self.facts.questions,
                "decisions_to_apply": self.facts.counts.decisions_open,
                "load_changes_to_declare": self.facts.counts.approvals_pending,
                "annotations_by_a_person": self.facts.counts.human_writings,
            }),
        );
        meta
    }
}

/// The summary's shared state, one per interface process: the composed line
/// (served in the initialize instructions and on the tool result that
/// moved it), the opening (how to begin here — served at initialize
/// only, since it is the same on every call and a tool result that
/// repeats it reads as an order), and the facts they render. One
/// shared baseline — the call that moved the facts carries the new
/// line back. A second agent on the same workspace hears nothing until
/// its own call moves something; that is a known gap, kept open rather
/// than paid for with per-actor state no run has needed.
#[derive(Default)]
pub struct Summary {
    line: std::sync::RwLock<String>,
    opening: std::sync::RwLock<String>,
    facts: std::sync::RwLock<Option<SummaryFacts>>,
}

impl Summary {
    pub fn line(&self) -> String {
        self.line.read().map(|l| l.clone()).unwrap_or_default()
    }

    fn opening(&self) -> String {
        self.opening.read().map(|l| l.clone()).unwrap_or_default()
    }
}

#[derive(Clone)]
pub struct GlossqlMcp {
    plane: Arc<Plane>,
    /// The summary: one composed line over live counts, appended to
    /// the instructions every initialize/discover serves — and, since
    /// a client fetches those once per connection, ALSO appended as a
    /// content block to any tool result whose call moved the facts.
    /// Shared across the per-session handler instances; refreshed after
    /// every tool call.
    summary: Arc<Summary>,
}

impl GlossqlMcp {
    pub fn new(plane: Arc<Plane>, summary: Arc<Summary>) -> Self {
        GlossqlMcp { plane, summary }
    }

    /// Recompose the summary from the store and the question derivation.
    /// Cheap (four bounded reads), awaited at the end of every tool
    /// call and once at boot.
    pub async fn refresh_summary(plane: &Plane, summary: &Summary) {
        let (facts, line, opening) = Self::compose_summary(plane).await;
        if let Ok(mut held) = summary.facts.write() {
            *held = facts;
        }
        if let Ok(mut held) = summary.line.write() {
            *held = line;
        }
        if let Ok(mut held) = summary.opening.write() {
            *held = opening;
        }
    }

    /// What the handshake serves: the standing instructions, the
    /// summary's line, and how to begin on this interface. The workspace
    /// interface's opening is composed with the summary; a bound interface's
    /// caller already holds on its dataset, so the opening is the
    /// summary on it.
    fn instructions(&self, bound: Option<&str>) -> String {
        let opening = match bound {
            Some(dataset) => format!(
                "Every call on this interface opens on `{dataset}`. Begin with `SELECT level, \
                 kind, asset, state, open, statement FROM main.next WHERE level <> 'could'`."
            ),
            None => self.summary.opening(),
        };
        format!("{INSTRUCTIONS}\n\n{} {opening}", self.summary.line())
    }

    /// The facts, their rendering, and the opening, in one read pass.
    async fn compose_summary(plane: &Plane) -> (Option<SummaryFacts>, String, String) {
        let questions = open_question_count(plane).await.unwrap_or(0);
        let datasets = plane.datasets().await.map(|d| d.len()).unwrap_or(0);
        // How to begin, decided by whether anything holds to read: a
        // workspace before its first dataset has no summary to sweep —
        // `next`, `GLOSSARY(d)` and `TESTS(d)` all need one — and
        // the modeling skill's load page is where it starts.
        let opening = if datasets == 0 {
            "No dataset exists yet. Declare a dataset, `DECLARE DATASET <name> SET (purpose: \
             '<what it is for>')`, then read `USE <name>; SELECT * FROM main.next`."
        } else {
            "Begin with `SELECT name FROM datasets`, then `USE <dataset>; SELECT level, kind, \
             asset, state, open, statement FROM main.next WHERE level <> 'could'`."
        }
        .to_string();
        match summary_counts(plane).await {
            Ok(counts) => {
                // Debt first, presence last: what owes an act is what
                // the reader acts on, and a count of human writings is
                // the catalog's size, not a task. The required acts are
                // the kinds of `next` row the whole workspace can count;
                // the questions are `open_questions`'s rows.
                let mut open = Vec::new();
                if counts.decisions_open > 0 {
                    open.push(format!(
                        "{} review decision{} wait{} to be applied: `next` lists each as a `review` \
                         row with the definition to record again",
                        counts.decisions_open,
                        if counts.decisions_open == 1 { "" } else { "s" },
                        if counts.decisions_open == 1 { "s" } else { "" },
                    ));
                }
                if counts.approvals_pending > 0 {
                    open.push(format!(
                        "{} approved load-query change{} wait{} to be declared",
                        counts.approvals_pending,
                        if counts.approvals_pending == 1 {
                            ""
                        } else {
                            "s"
                        },
                        if counts.approvals_pending == 1 {
                            "s"
                        } else {
                            ""
                        },
                    ));
                }
                if questions > 0 {
                    open.push(format!(
                        "{} assumption{} wait{} for a person's decision. The person sees each as \
                         an open question in the console; where they are not there, ask them \
                         in chat. The work goes on meanwhile",
                        questions,
                        if questions == 1 { "" } else { "s" },
                        if questions == 1 { "s" } else { "" },
                    ));
                }
                let mut line = if open.is_empty() {
                    "Live now: no review decision to apply, no assumption waits for a person"
                        .to_string()
                } else {
                    format!("Live now: {}", open.join("; "))
                };
                line.push_str(&format!(
                    ". Annotations by a person: {}{}.",
                    counts.human_writings,
                    match &counts.latest_human_at {
                        Some(at) => format!(", latest {at}"),
                        None => String::new(),
                    },
                ));
                (
                    Some(SummaryFacts {
                        counts,
                        questions,
                        datasets,
                    }),
                    line,
                    opening,
                )
            }
            // No facts on a failed read: the interface says so in the line
            // and tells the next caller again rather than recording a
            // silence as "nothing moved".
            Err(e) => (
                None,
                format!("Live now: the summary could not be read ({e})."),
                opening,
            ),
        }
    }

    /// The one tool, described for the interface it is listed on: how a
    /// call opens is the one thing the two agent interfaces say differently.
    fn tool(&self, bound: Option<&str>) -> Tool {
        let opens = match bound {
            Some(dataset) => format!(
                "Every call opens on `{dataset}`: its tables and columns resolve without a \
                 prefix, another dataset's with the dataset's name in front."
            ),
            None => "A call opens on no dataset: begin a call that names a dataset's tables, \
                     columns or views with `USE <dataset>;`. It holds for that call."
                .to_string(),
        };
        let serde_json::Value::Object(schema) = serde_json::json!({
            "type": "object",
            "properties": {
                "statements": {
                    "type": "string",
                    "description": "glossql statements, `;`-separated"
                }
            },
            "required": ["statements"]
        }) else {
            unreachable!("literal object")
        };
        Tool::new(
            "glossql",
            format!(
                "Run glossql statements and SQL on the workspace: load sources, annotate, define \
                 and keep views, read data and the catalog. One outcome per statement, \
                 `;`-separated. \
                 {opens} \
                 Outcomes: a read is `{{columns, rows, row_count, truncated}}`, rows capped at \
                 {} (`GLOSSARY()`, `TESTS()` and the catalog tables are not capped; a null \
                 field is left out of its row); a write is `{{done}}` or `{{affected}}`; the \
                 definition of a table, a single value or a metric (`GLOSS <view> ON <dataset>`) \
                 answers with the view's row of `view_summary()`. A refused statement is an error that names what was wrong \
                 and its place in the call; the statements before it stay stored \
                 (`{{completed}}`). Every result ends with `status:` (the last statement); a call \
                 on a dataset adds `next:` (what must and what should be done on it, per kind of \
                 work) and `first:` (the first of them); \
                 `SELECT level, kind, asset, state, open, statement FROM main.next` gives each row's \
                 statement; work on a dataset is complete when no must is open. Start with `SELECT body FROM pages() WHERE uri = \
                 'skill://glossql/SKILL.md'`.",
                self.plane.row_cap()
            ),
            schema,
        )
    }
}

/// One read, rows as JSON, run through the session exactly as frames
/// do.
async fn read_rows(session: &Session, sql: &str) -> Result<Vec<serde_json::Value>, String> {
    let query = session.query_stream(sql).await.map_err(|e| e.to_string())?;
    let out = wire::stream_json(query, usize::MAX)
        .await
        .map_err(|e| e.to_string())?;
    Ok(out["rows"].as_array().cloned().unwrap_or_default())
}

/// How many questions the workspace would serve right now, across every
/// dataset — the same span the review itself asks over, since each row
/// carries its own dataset and a review decision is stored where its question came
/// from. No dataset, no count: a workspace before its first load has
/// nothing to ask.
///
/// One count, not one per dataset. `open_questions` derives from the
/// workspace-wide `glossary`, so every channel already answers for the
/// whole workspace; summing across channels multiplied the total by the
/// number of datasets. A channel is opened only because the read needs
/// one, which is why any dataset that admits one will do.
async fn open_question_count(plane: &Plane) -> Option<usize> {
    let actor = Actor {
        kind: ActorKind::Human,
        id: crate::BOOTSTRAP.into(),
    };
    for dataset in plane.datasets().await.ok()? {
        let Ok(session) = plane.channel(actor.clone(), Some(&dataset)).await else {
            continue;
        };
        if let Some(n) = read_rows(&session, "SELECT count(*) AS n FROM open_questions")
            .await
            .ok()
            .and_then(|rows| rows.first().and_then(|r| r["n"].as_u64()))
            .and_then(|n| usize::try_from(n).ok())
        {
            return Some(n);
        }
    }
    None
}

impl ServerHandler for GlossqlMcp {
    fn get_info(&self) -> ServerConfig {
        let mut info = ServerConfig::new(
            ServerCapabilities::builder()
                .enable_tools()
                .enable_resources()
                .enable_prompts()
                .build(),
        );
        info.server_info = Implementation::new("glossdb-serverd", env!("CARGO_PKG_VERSION"));
        info.instructions = Some(self.instructions(None));
        info
    }

    /// The handshake, with the opening said for the interface it came
    /// through: a bound interface's caller has its dataset already, so the
    /// opening names the summary alone.
    async fn initialize(
        &self,
        request: InitializeRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<InitializeResult, McpError> {
        context.peer.set_peer_info(request.clone());
        let mut result = self.negotiate_initialize(&request)?;
        if let Some(dataset) = bound(&context) {
            result.instructions = Some(self.instructions(Some(&dataset)));
        }
        Ok(result)
    }

    /// The revisions the interface serves: the newest, whose handshake rides
    /// every request's `_meta`, and the newest that still has an
    /// `initialize` handshake, which is what the library answers any
    /// `initialize` with — a 2026-07-28 client's as much as an older
    /// one's, since the newest revision has no handshake to echo. The
    /// library negotiates from this list alone, so without the second
    /// entry every `initialize` is refused. The interface serves either
    /// caller statelessly like every other ([`crate::router`]).
    fn supported_protocol_versions(&self) -> std::borrow::Cow<'static, [ProtocolVersion]> {
        std::borrow::Cow::Borrowed(&[
            ProtocolVersion::LATEST_WITH_INITIALIZE,
            ProtocolVersion::LATEST,
        ])
    }

    /// The list is static per process — one tool, built from a constant
    /// schema — so it is cacheable for an hour. `private` because a
    /// workspace's interface is not a shared intermediary's to hand on.
    async fn list_tools(
        &self,
        _request: Option<PaginatedRequestParams>,
        context: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, McpError> {
        Ok(ListToolsResult {
            tools: vec![self.tool(bound(&context).as_deref())],
            ttl_ms: Some(3_600_000),
            cache_scope: Some(rmcp::model::CacheScope::Private),
            ..Default::default()
        })
    }

    /// The teaching resources: the plane's pages, which are constants
    /// of the binary plus the function listings built at boot — static
    /// per process, so cacheable like the tool list.
    async fn list_resources(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListResourcesResult, McpError> {
        let resources = self
            .plane
            .pages()
            .iter()
            .map(|p| {
                Resource::new(p.uri.clone(), p.name.clone())
                    .with_description(p.description.clone())
                    .with_mime_type(p.mime)
                    .with_size(p.body.len() as u64)
            })
            .collect();
        Ok(ListResourcesResult {
            resources,
            ttl_ms: Some(3_600_000),
            cache_scope: Some(rmcp::model::CacheScope::Private),
            ..Default::default()
        })
    }

    /// The one dynamic resource: where the catalog holds toward a goal
    /// on a dataset, as a page with the statement to send.
    async fn list_resource_templates(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListResourceTemplatesResult, McpError> {
        Ok(ListResourceTemplatesResult {
            resource_templates: vec![
                ResourceTemplate::new("next://{dataset}/{kind}", "next")
                    .with_description(
                        "What is open on a dataset for one kind of work (integrate, \
                         describe, test, review): each row with its level (must, should, \
                         could), its asset, its state, what the newest load changed and the \
                         statement that opens the work. `next://{dataset}` serves every \
                         row; the same rows through the tool are `SELECT * FROM main.next WHERE \
                         kind = '<kind>'`.",
                    )
                    .with_mime_type("text/markdown"),
            ],
            ..Default::default()
        })
    }

    async fn read_resource(
        &self,
        request: ReadResourceRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<ReadResourceResponse, McpError> {
        // `next://<dataset>[/<kind of work>]` is computed from the catalog for
        // the caller, never a page of the binary.
        if let Some(rest) = request.uri.strip_prefix("next://") {
            return self.next_resource(rest, &request.uri, &context).await;
        }
        let (mime, body) = self
            .plane
            .pages()
            .iter()
            .find(|p| p.uri == request.uri)
            .map(|p| (p.mime, p.body.clone()))
            .ok_or_else(|| {
                McpError::resource_not_found(format!("no resource at `{}`", request.uri), None)
            })?;
        Ok(ReadResourceResult::new(vec![
            ResourceContents::text(body, request.uri).with_mime_type(mime),
        ])
        .with_ttl_ms(3_600_000)
        .with_cache_scope(rmcp::model::CacheScope::Private)
        .into())
    }

    /// Each skill is also a prompt of the same name — the slash-command
    /// way in for a person, where resources wait on the client to offer
    /// them.
    async fn list_prompts(
        &self,
        _request: Option<PaginatedRequestParams>,
        _context: RequestContext<RoleServer>,
    ) -> Result<ListPromptsResult, McpError> {
        Ok(ListPromptsResult {
            prompts: crate::skills::SKILLS
                .iter()
                .map(|s| Prompt::new(s.name, Some(s.description()), None))
                .collect(),
            ttl_ms: Some(3_600_000),
            cache_scope: Some(rmcp::model::CacheScope::Private),
            ..Default::default()
        })
    }

    async fn get_prompt(
        &self,
        request: GetPromptRequestParams,
        _context: RequestContext<RoleServer>,
    ) -> Result<GetPromptResponse, McpError> {
        let skill = crate::skills::SKILLS
            .iter()
            .find(|s| s.name == request.name)
            .ok_or_else(|| {
                McpError::invalid_params(format!("unknown prompt `{}`", request.name), None)
            })?;
        Ok(
            GetPromptResult::new(vec![PromptMessage::new_text(Role::User, skill.body)])
                .with_description(skill.description())
                .into(),
        )
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<CallToolResponse, McpError> {
        if request.name != "glossql" {
            return Err(McpError::invalid_params(
                format!("unknown tool `{}`", request.name),
                None,
            ));
        }
        let statements = request
            .arguments
            .as_ref()
            .and_then(|arguments| arguments.get("statements"))
            .and_then(|v| v.as_str())
            .ok_or_else(|| McpError::invalid_params("`statements` (string) is required", None))?;

        // Actor rides the transport (SPEC.md §1). The gate verified a
        // token and left the caller in the HTTP extensions, which rmcp
        // forwards to this handler as `http::request::Parts`; this interface
        // is the agent interface, so the gate stamped the agent actor kind. The
        // client's own `clientInfo` name is not used: it is a string the
        // caller picks for itself on each request, so recording it would
        // put an unproven name in the actor column of the catalog.
        let actor = caller(&context)?;
        let id = actor.id.clone();
        // The call opens where the interface says: on the dataset a bound
        // interface's URL names, or unbound at the workspace interface. There is
        // no session to hold a dataset between calls; within one, the
        // statements say where they are, as `USE`, and `execute` moves
        // with them. An unbound call that names none is
        // workspace-scoped, which is what reading `datasets` and
        // writing a source-grain gloss both want.
        let bound = bound(&context);
        let session = self
            .plane
            .channel(actor.clone(), bound.as_deref())
            .await
            .map_err(|e| McpError::internal_error(e.to_string(), None))?;

        let shape = crate::engine::call_shape(statements);
        // The summary as it stood when the call arrived: what the call's
        // own refresh is compared against, whatever else is stored
        // meanwhile — the boot's refresh included.
        let before = self.summary.facts.read().ok().and_then(|f| f.clone());
        let (rendered, completed) = self
            .run_statements(&session, &actor, bound.as_deref(), statements)
            .await;
        // A write moves the counts; a call before the boot's own refresh
        // has loaded composes them too.
        let summary_moved = self
            .summary_moved(shape.writes || before.is_none(), before)
            .await;
        // Where the call left the agent and one act per goal from there,
        // on every call (`window`). It rides the result, never the
        // instructions, so the stable prefix holds.
        let window = self
            .situation_block(
                &actor,
                shape.dataset.as_deref().or(bound.as_deref()),
                &rendered,
                statements,
            )
            .await;
        Ok(call_result(&id, rendered, completed, window, summary_moved).into())
    }
}

impl GlossqlMcp {
    /// The statements, run: a single query streams from the engine;
    /// everything else runs through execute. Either way the session
    /// pages a data read — its plan carries the cap, so what the agent
    /// won't see is never computed — and serves a metadata read
    /// (GLOSSARY(), TESTS(), the store relations) whole: the map must
    /// be whole, and the store bounds it. What a refused sequence had
    /// already loaded rides beside the refusal, in the usual shape —
    /// the writes stood.
    async fn run_statements(
        &self,
        session: &Session,
        actor: &Actor,
        bound: Option<&str>,
        statements: &str,
    ) -> (
        Result<serde_json::Value, Refusal>,
        Option<serde_json::Value>,
    ) {
        let mut completed_json: Option<serde_json::Value> = None;
        let rendered = match session.query_page(statements).await {
            Ok(query) => {
                let cap = query.cap;
                wire::stream_json(query, cap)
                    .await
                    .map(|rows| serde_json::Value::Array(vec![rows]))
                    .map_err(|e| Refusal::of(&e))
            }
            // Statement sequences run at the plane: `USE` moves the
            // statements after it onto another channel for the rest of
            // this call, and never rebinds a session.
            Err(SessionError::NotOneRead) => {
                match self.plane.execute(actor.clone(), bound, statements).await {
                    Ok(outcomes) => wire::outcomes_json(&outcomes).map_err(Refusal::from),
                    Err(e) => {
                        if let SessionError::Sequence { loaded, .. } = &e
                            && !loaded.is_empty()
                        {
                            completed_json = wire::outcomes_json(loaded).ok();
                        }
                        Err(Refusal::of(&e))
                    }
                }
            }
            Err(e) => Err(Refusal::of(&e)),
        };
        (rendered, completed_json)
    }

    /// The summary travels on the call that moved it: initialize
    /// instructions are fetched once per connection, so a long-lived
    /// session would never see the counts change. Two rules hold it
    /// honest: movement is decided on the COUNTS, never on the rendered
    /// line (a rendered string is display, not identity); and the
    /// baseline is the facts as they stood before this call. One shared
    /// baseline, so the mover hears it: a second agent watching the
    /// same workspace does not, and that is the known cost of not
    /// keeping per-actor state the run has never asked for. Scoped to
    /// the cause: only a write can move the counts, so a pure read never
    /// pays the recomposition.
    async fn summary_moved(
        &self,
        moved: bool,
        before: Option<SummaryFacts>,
    ) -> Option<SummaryMoved> {
        if !moved {
            return None;
        }
        Self::refresh_summary(&self.plane, &self.summary).await;
        let after = self.summary.facts.read().ok().and_then(|f| f.clone());
        after
            .filter(|facts| Some(facts) != before.as_ref())
            .map(|facts| SummaryMoved {
                line: self.summary.line(),
                facts,
            })
    }
}

/// The call's result: the rows, the window and the summary where it
/// moved, as a closing `summary:` block and as counts under `_meta`. A
/// failed statement is the agent's business, not the transport's: an
/// error result, never a protocol error — and the summary still
/// travels: the statements before it may have written.
fn call_result(
    id: &str,
    rendered: Result<serde_json::Value, Refusal>,
    completed: Option<serde_json::Value>,
    window: String,
    summary_moved: Option<SummaryMoved>,
) -> CallToolResult {
    let mut meta = summary_moved.as_ref().map(SummaryMoved::meta);
    if let Err(Refusal {
        code: Some(code), ..
    }) = &rendered
    {
        meta.get_or_insert_with(rmcp::model::MetaObject::new)
            .0
            .insert(
                REFUSAL_META.to_string(),
                serde_json::json!({ "code": code }),
            );
    }
    let summary_moved = summary_moved.map(|moved| format!("summary: {}", moved.line));
    let mut result = match rendered {
        Ok(body) => {
            let mut blocks = vec![ContentBlock::text(body.to_string())];
            blocks.push(ContentBlock::text(window));
            if let Some(summary) = summary_moved {
                blocks.push(ContentBlock::text(summary));
            }
            CallToolResult::success(blocks)
        }
        Err(Refusal { reason, .. }) => {
            tracing::warn!(subject = %id, error = %reason, "refused");
            let mut blocks = vec![ContentBlock::text(reason)];
            if let Some(completed) = completed {
                blocks.push(ContentBlock::text(
                    serde_json::json!({ "completed": completed }).to_string(),
                ));
            }
            blocks.push(ContentBlock::text(window));
            if let Some(summary) = summary_moved {
                blocks.push(ContentBlock::text(summary));
            }
            CallToolResult::error(blocks)
        }
    };
    result.meta = meta;
    result
}

impl GlossqlMcp {
    /// The lines every result carries: where the call left the agent
    /// (`status:`), and what is open (`next:`, `first:`) on the dataset
    /// the call's last `USE` named, else the interface's own; none of
    /// the two where the call is on no dataset.
    async fn situation_block(
        &self,
        actor: &Actor,
        dataset: Option<&str>,
        rendered: &Result<serde_json::Value, Refusal>,
        statements: &str,
    ) -> String {
        // The last statement's one row, where it served one — a
        // metric definition's fact row. The wire renders an outcome as
        // `{columns, rows, …}` (`wire::outcomes_json`), so the row
        // sits under `rows`.
        let last_row = rendered
            .as_ref()
            .ok()
            .and_then(|v| v.as_array())
            .and_then(|a| a.last())
            .and_then(|o| o.get("rows"))
            .and_then(|r| r.as_array())
            .filter(|r| r.len() == 1)
            .and_then(|r| r.first())
            .cloned();
        let refusal = rendered.as_ref().err().map(|r| r.reason.as_str());
        let mut lines = vec![window::situation(refusal, last_row.as_ref())];
        if let Some(dataset) = dataset {
            match self.next_rows(actor, dataset, None).await {
                Ok(rows) => lines.push(window::next_line(dataset, &rows)),
                Err(e) => tracing::debug!(error = %e, "next: not served"),
            }
        }
        if rendered.is_ok()
            && let Some(line) = window::series_window(statements)
        {
            lines.push(line.to_string());
        }
        lines.join("\n")
    }

    /// The `next` read on a channel bound to the dataset, as JSON rows.
    async fn next_rows(
        &self,
        actor: &Actor,
        dataset: &str,
        kind: Option<&str>,
    ) -> Result<Vec<serde_json::Value>, String> {
        let session = self
            .plane
            .channel(actor.clone(), Some(dataset))
            .await
            .map_err(|e| e.to_string())?;
        let rows = read_rows(&session, "SELECT * FROM next").await?;
        Ok(rows
            .into_iter()
            .filter(|row| kind.is_none_or(|k| row["kind"].as_str() == Some(k)))
            .collect())
    }

    /// `next://<dataset>[/<kind of work>]` as a page: every open row with its
    /// statement, for the caller the gate stamped.
    async fn next_resource(
        &self,
        rest: &str,
        uri: &str,
        context: &RequestContext<RoleServer>,
    ) -> Result<ReadResourceResponse, McpError> {
        let actor = caller(context)?;
        let (dataset, kind) = match rest.split_once('/') {
            Some((d, s)) => (d, Some(s)),
            None => (rest, None),
        };
        let rows = self
            .next_rows(&actor, dataset, kind)
            .await
            .map_err(|e| McpError::resource_not_found(format!("`{uri}`: {e}"), None))?;
        let body = window::next_page(dataset, &rows);
        Ok(ReadResourceResult::new(vec![
            ResourceContents::text(body, uri).with_mime_type("text/markdown"),
        ])
        .into())
    }
}

/// The caller the gate stamped on the request.
fn caller(context: &RequestContext<RoleServer>) -> Result<Actor, McpError> {
    context
        .extensions
        .get::<axum::http::request::Parts>()
        .and_then(|parts| parts.extensions.get::<Caller>())
        .map(|caller| caller.0.clone())
        .ok_or_else(|| {
            McpError::internal_error("the interface is not behind the gate: no caller", None)
        })
}

/// The dataset a bound agent interface was opened on — `/{dataset}/mcp`,
/// stamped onto the request by [`bind`] the way the gate stamps the
/// caller. The workspace interface (`/mcp`) carries none.
#[derive(Clone)]
pub struct Bound(pub String);

/// The binding the request arrived with, if the interface is a bound one.
fn bound(context: &RequestContext<RoleServer>) -> Option<String> {
    context
        .extensions
        .get::<axum::http::request::Parts>()
        .and_then(|parts| parts.extensions.get::<Bound>())
        .map(|bound| bound.0.clone())
}

/// The bound interface's way in: the URL's first segment names the dataset,
/// and one the workspace does not hold is a 404 that names what it
/// does hold — the same answer the human interfaces give. This interface reads
/// and writes on the dataset; bringing one into being is the
/// workspace interface's.
pub async fn bind(
    axum::extract::State(plane): axum::extract::State<Arc<Plane>>,
    axum::extract::Path(dataset): axum::extract::Path<String>,
    mut request: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    use axum::response::IntoResponse;
    if let Some(missing) = crate::missing_dataset(&plane, &dataset).await {
        return (
            axum::http::StatusCode::NOT_FOUND,
            axum::Json(serde_json::json!({ "error": missing })),
        )
            .into_response();
    }
    request.extensions_mut().insert(Bound(dataset));
    next.run(request).await
}
