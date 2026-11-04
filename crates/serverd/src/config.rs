//! What a run is told, read once before anything opens: the flags, and
//! the environment — `.env` beside a workspace, or the variables a
//! platform injects. A sizing flag has a variable named after it
//! (`--memory-limit` is `GLOSSDB_MEMORY_LIMIT`), the flag winning, so a
//! deployment sizes a box without replacing the image's command. The
//! arrangements that carry a secret are variables only, since a flag
//! sits in a process list. Every reading goes through `get`, so it is
//! testable without touching the process environment. The telemetry's
//! variables are the export SDK's own and are read where it is
//! installed ([`glossdb_serverd::telemetry`]).

use std::path::PathBuf;

use glossdb_serverd::engine::{WarehouseCredential, store_kind};
use glossdb_serverd::{DEFAULT_ROW_CAP, DoorConfig};

const USAGE_TEXT: &str = "usage: glossql [--workspace <dir>] [--addr <ip:port>] \
[--row-cap <n>] [--memory-limit <megabytes>] [--spill-limit <megabytes>] \
| glossdb --version | glossql --help\n\
--workspace is the laptop's shape: the directory holding the lake's catalog \
and its files. GLOSSDB_CATALOG_SQL names the catalog on a Postgres server \
(postgres://…), GLOSSDB_WAREHOUSE the lake's files in an object store \
(s3://…, gs://…); a deployment names them and runs without a directory. \
The engine reaches the store with GLOSSDB_WAREHOUSE_KEY_ID and \
GLOSSDB_WAREHOUSE_SECRET (GLOSSDB_WAREHOUSE_REGION for S3), or, a gs:// \
bucket named without them, as the account the platform runs it as.\n\
every other flag has a variable named after it, the flag winning: \
GLOSSDB_ADDR, GLOSSDB_ROW_CAP, GLOSSDB_MEMORY_LIMIT, GLOSSDB_SPILL_LIMIT, GLOSSDB_ROOT.\n\
{service}\
the authorization arrangement is read from .env or the environment: \
GLOSSDB_ISSUER, GLOSSDB_CLIENT_ID, GLOSSDB_CLIENT_SECRET, [GLOSSDB_AUDIENCE] \
— or GLOSSDB_INSECURE_OPEN=true serves the doors without authentication, \
every caller recorded as insecure_dev_mode (the name is the warning) \
(see .env.example)";

const SERVICE_USAGE: &str = "the model service — the walk, the forecast, the what-if — is \
named once: GLOSSDB_SERVICE_URL, with its bearer in GLOSSDB_SERVICE_TOKEN or \
minted by the platform for GLOSSDB_SERVICE_AUDIENCE; unnamed, its reads \
refuse by name and everything else serves.\n";

/// The usage, with the service's line as this build names it.
pub fn usage() -> String {
    USAGE_TEXT.replace("{service}", SERVICE_USAGE)
}

/// The command line as typed. `workspace` decides whether `.env` is
/// read, so the flags are parsed before the environment is.
#[derive(Debug, Default)]
pub struct Flags {
    /// The laptop's shape, and only that: the directory holding the
    /// catalog and the warehouse. A deployment names both in the
    /// environment and has no directory.
    pub workspace: Option<PathBuf>,
    addr: Option<String>,
    row_cap: Option<usize>,
    memory_limit_mb: Option<u64>,
    spill_limit_mb: Option<u64>,
}

pub fn parse(mut argv: impl Iterator<Item = String>) -> Result<Flags, String> {
    argv.next();
    let mut flags = Flags::default();
    while let Some(flag) = argv.next() {
        let mut value = || argv.next().ok_or(format!("{flag} needs a value"));
        match flag.as_str() {
            "--workspace" => flags.workspace = Some(PathBuf::from(value()?)),
            "--addr" => flags.addr = Some(value()?),
            "--row-cap" => flags.row_cap = Some(number(&flag, &value()?)?),
            "--memory-limit" => flags.memory_limit_mb = Some(number(&flag, &value()?)?),
            "--spill-limit" => flags.spill_limit_mb = Some(number(&flag, &value()?)?),
            other => return Err(format!("unknown flag {other}")),
        }
    }
    Ok(flags)
}

/// A flag's or a variable's number; the refusal names which one.
fn number<T: std::str::FromStr<Err: std::fmt::Display>>(
    name: &str,
    value: &str,
) -> Result<T, String> {
    value.trim().parse().map_err(|e| format!("{name}: {e}"))
}

/// The run's whole configuration. Nothing past [`Config::read`] reads a
/// flag or a variable.
pub struct Config {
    pub addr: String,
    pub doors: DoorConfig,
    /// Rows a data read ships before a door declares `truncated`.
    pub row_cap: usize,
    /// The engine's memory ceiling, in megabytes; unset, the engine's
    /// own default, most of the box's memory.
    pub memory_limit_mb: Option<u64>,
    /// The disk the engine may spill onto, in megabytes — the box's
    /// disk, a number of its own; unset, the engine's own default.
    pub spill_limit_mb: Option<u64>,
    /// This server's own URI — `GLOSSDB_AUDIENCE`, the API identifier a
    /// token must name (RFC 8707 §2) and the host the world reaches
    /// the doors at — defaulting to the bind address. Read under both
    /// arrangements: the open switch verifies nobody, and the door
    /// still has to know its name.
    pub audience: String,
    /// The authorization arrangement; none under the open switch.
    pub auth: Option<Auth>,
    /// The model service, named once, where the environment names it.
    pub service: Option<glossdb_serverd::engine::Service>,
    pub catalog: Catalog,
    /// `GLOSSDB_ROOT`: the actor ids that run every statement at the
    /// doors; everyone else runs the language, the reads and `DELETE
    /// FROM glossary`. Comma-separated; nobody by default.
    pub root: Vec<String>,
}

/// The authorization arrangement: one issuer and one registered
/// application, verified against the run's audience. It comes from the
/// environment as one thing — `.env` beside the server or the variables
/// set outright.
#[derive(Debug)]
pub struct Auth {
    /// The authorization server's issuer URL, from which its keys are
    /// discovered.
    pub issuer: String,
    /// The application registered at the issuer for this server, and
    /// its secret, which only the browser login uses.
    pub client_id: String,
    pub client_secret: String,
}

/// The lake: its catalog on the Postgres server the environment names,
/// or the workspace directory's own catalog file; its files in the
/// object store the environment names, or under the directory. A
/// laptop names a directory and it holds both; a deployment names both
/// in the environment and has no directory at all. The catalog URI
/// carries its credentials; the warehouse's come beside it, a key
/// pair, or are the platform's own.
#[derive(Debug, Clone)]
pub struct Catalog {
    pub catalog: String,
    pub warehouse: String,
    /// The key pair the environment names for a warehouse in an object
    /// store; none, and a Google bucket is reached as the account the
    /// platform runs this process as.
    pub credential: Option<WarehouseCredential>,
    /// The directory, on a laptop; a deployment has none.
    pub workspace: Option<PathBuf>,
}

impl Config {
    pub fn read(flags: Flags, get: impl Fn(&str) -> Option<String>) -> Result<Config, String> {
        let var = |name: &str| get(name).filter(|v| !v.trim().is_empty());
        let sized = |name: &str| var(name).map(|v| number::<u64>(name, &v)).transpose();

        let addr = flags
            .addr
            .or_else(|| var("GLOSSDB_ADDR"))
            .unwrap_or_else(|| "127.0.0.1:8080".to_string());
        let audience = var("GLOSSDB_AUDIENCE").unwrap_or_else(|| format!("http://{addr}"));
        let doors = DoorConfig {
            allowed_hosts: allowed_hosts(&audience),
            own_uri: audience.clone(),
        };
        let row_cap = match flags.row_cap {
            Some(n) => n,
            None => var("GLOSSDB_ROW_CAP")
                .map(|v| number("GLOSSDB_ROW_CAP", &v))
                .transpose()?
                .unwrap_or(DEFAULT_ROW_CAP),
        };
        // The open switch is read where the arrangement would be: a run
        // is one or the other, and a misconfigured arrangement still
        // refuses rather than falling open.
        let auth = if open(&get) {
            None
        } else {
            Some(Auth::from(&var)?)
        };
        Ok(Config {
            memory_limit_mb: match flags.memory_limit_mb {
                Some(mb) => Some(mb),
                None => sized("GLOSSDB_MEMORY_LIMIT")?,
            },
            spill_limit_mb: match flags.spill_limit_mb {
                Some(mb) => Some(mb),
                None => sized("GLOSSDB_SPILL_LIMIT")?,
            },
            service: var(glossdb_serverd::engine::SERVICE_URL).map(|url| {
                glossdb_serverd::engine::Service {
                    url,
                    token: var(glossdb_serverd::engine::SERVICE_TOKEN),
                    audience: var(glossdb_serverd::engine::SERVICE_AUDIENCE),
                }
            }),
            catalog: Catalog::from(&var, flags.workspace.as_deref())?,
            root: var("GLOSSDB_ROOT")
                .map(|ids| {
                    ids.split(',')
                        .map(str::trim)
                        .filter(|id| !id.is_empty())
                        .map(str::to_string)
                        .collect()
                })
                .unwrap_or_default(),
            addr,
            doors,
            row_cap,
            audience,
            auth,
        })
    }
}

impl Auth {
    fn from(var: &impl Fn(&str) -> Option<String>) -> Result<Auth, String> {
        let required = |name: &str| {
            var(name).ok_or_else(|| {
                format!(
                    "{name} is not set — the authorization arrangement lives in .env \
                     (see .env.example); GLOSSDB_INSECURE_OPEN=true serves open instead, \
                     every caller insecure_dev_mode"
                )
            })
        };
        Ok(Auth {
            issuer: required("GLOSSDB_ISSUER")?,
            client_id: required("GLOSSDB_CLIENT_ID")?,
            client_secret: required("GLOSSDB_CLIENT_SECRET")?,
        })
    }
}

/// The explicit way to serve without the arrangement:
/// `GLOSSDB_INSECURE_OPEN=true` opens every door, every caller
/// recorded as [`glossdb_serverd::INSECURE_DEV_MODE`]. Only the literal
/// `true` counts — the switch is a statement, never a fallback:
/// anything else leaves the gate required, and the refusal names the
/// switch.
fn open(get: &impl Fn(&str) -> Option<String>) -> bool {
    get("GLOSSDB_INSECURE_OPEN").is_some_and(|v| v.trim() == "true")
}

/// Whose `Host` header the agent door answers: loopback — the
/// transport's DNS-rebinding guard, for a server on a laptop where a
/// browser could be steered at 127.0.0.1 — and the audience's host,
/// the name the world reaches this server by. A deployment names its
/// URL; one that does not answers its bind address alone, and the
/// transport says so to every real request.
fn allowed_hosts(audience: &str) -> Vec<String> {
    let mut hosts = DoorConfig::default().allowed_hosts;
    if let Some(host) = audience
        .parse::<axum::http::Uri>()
        .ok()
        .and_then(|uri| uri.host().map(str::to_string))
        && !hosts.contains(&host)
    {
        hosts.push(host);
    }
    hosts
}

impl Catalog {
    /// The catalog: on the Postgres server `GLOSSDB_CATALOG_SQL` names,
    /// or the workspace directory's own file; the lake's files at the
    /// location `GLOSSDB_WAREHOUSE` names in an object store, or under
    /// the workspace directory. Without a directory the environment has
    /// to name both.
    fn from(
        var: &impl Fn(&str) -> Option<String>,
        workspace: Option<&std::path::Path>,
    ) -> Result<Catalog, String> {
        let catalog = match (var("GLOSSDB_CATALOG_SQL"), workspace) {
            (Some(uri), _) => uri.trim().to_string(),
            (None, Some(dir)) => dir.join("catalog.ducklake").display().to_string(),
            (None, None) => return Err(NO_WORKSPACE.into()),
        };
        let warehouse = match (var("GLOSSDB_WAREHOUSE"), workspace) {
            (Some(location), _) => location.trim().to_string(),
            (None, Some(dir)) => dir.join("warehouse").display().to_string(),
            (None, None) => return Err(NO_WORKSPACE.into()),
        };
        let credential = match (
            var("GLOSSDB_WAREHOUSE_KEY_ID"),
            var("GLOSSDB_WAREHOUSE_SECRET"),
        ) {
            (Some(key_id), Some(secret)) => Some(WarehouseCredential::Keys {
                key_id,
                secret,
                region: var("GLOSSDB_WAREHOUSE_REGION"),
            }),
            (None, None) => None,
            (Some(_), None) => {
                return Err(HALF_A_PAIR.replace("{missing}", "GLOSSDB_WAREHOUSE_SECRET"));
            }
            (None, Some(_)) => {
                return Err(HALF_A_PAIR.replace("{missing}", "GLOSSDB_WAREHOUSE_KEY_ID"));
            }
        };
        if credential.is_some() && store_kind(&warehouse).is_none() {
            return Err(format!(
                "GLOSSDB_WAREHOUSE_KEY_ID names a key pair while the warehouse is a directory \
                 ({warehouse}): a key pair goes with GLOSSDB_WAREHOUSE in an object store"
            ));
        }
        Ok(Catalog {
            catalog,
            warehouse,
            credential,
            workspace: workspace.map(std::path::Path::to_path_buf),
        })
    }
}

/// What a run is told when the environment names one half of the key
/// pair.
const HALF_A_PAIR: &str = "{missing} is not set — the warehouse's key pair is \
GLOSSDB_WAREHOUSE_KEY_ID and GLOSSDB_WAREHOUSE_SECRET together";

/// What a run without a workspace directory is told when the
/// environment does not name the state either.
const NO_WORKSPACE: &str = "--workspace is required while the catalog or the warehouse lives \
in it: name both GLOSSDB_CATALOG_SQL and GLOSSDB_WAREHOUSE, or the directory";

#[cfg(test)]
mod tests {
    use super::{Config, allowed_hosts, parse};

    fn flags(flags: &[&str]) -> super::Flags {
        parse(
            std::iter::once("glossdb")
                .chain(flags.iter().copied())
                .map(str::to_string),
        )
        .expect("the flags parse")
    }

    fn env(vars: &'static [(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        move |name: &str| {
            vars.iter()
                .find(|(k, _)| *k == name)
                .map(|(_, v)| v.to_string())
        }
    }

    /// A readable run: a workspace and the open switch, plus `vars`.
    fn read(typed: &[&str], vars: &'static [(&str, &str)]) -> Result<Config, String> {
        let base = env(&[("GLOSSDB_INSECURE_OPEN", "true")]);
        let more = env(vars);
        let mut all = vec!["--workspace", "/tmp/w"];
        all.extend(typed);
        Config::read(flags(&all), move |name| more(name).or_else(|| base(name)))
    }

    /// A configuration holds auth material, so it carries no `Debug` to
    /// unwrap through; a refusal is read off the error alone.
    fn refusal(read: Result<Config, String>) -> String {
        read.err().expect("a refusal, not a configuration")
    }

    /// The audience's host joins the transport's loopback list; a bind
    /// address as the audience adds the bind address and nothing else.
    #[test]
    fn the_agent_door_answers_loopback_and_its_own_name() {
        let named = allowed_hosts("https://glossql-trial.example.azurecontainerapps.io");
        assert!(named.contains(&"glossql-trial.example.azurecontainerapps.io".to_string()));
        assert!(named.contains(&"127.0.0.1".to_string()) && named.len() == 4);
        let bound = allowed_hosts("http://0.0.0.0:8080");
        assert!(bound.contains(&"0.0.0.0".to_string()) && bound.len() == 4);
        assert_eq!(allowed_hosts("http://127.0.0.1:8080").len(), 3);

        let named = read(
            &["--addr", "0.0.0.0:8080"],
            &[("GLOSSDB_AUDIENCE", "https://glossql.example")],
        )
        .expect("readable");
        assert_eq!(named.audience, "https://glossql.example");
        assert!(
            named
                .doors
                .allowed_hosts
                .contains(&"glossql.example".to_string())
        );
        let unnamed = read(&[], &[]).expect("readable");
        assert_eq!(
            unnamed.audience, "http://127.0.0.1:8080",
            "the audience defaults to the address"
        );
    }

    /// Without an issuer and a registered application there is nothing
    /// to verify against, and the server does not start. The refusal
    /// names the variable and where it lives, since the flags say
    /// nothing about it.
    #[test]
    fn the_arrangement_needs_an_issuer_and_an_application() {
        let gated = |vars: &'static [(&str, &str)]| {
            Config::read(flags(&["--workspace", "/tmp/w"]), env(vars))
        };
        let none = refusal(gated(&[]));
        assert!(
            none.contains("GLOSSDB_ISSUER") && none.contains(".env"),
            "{none}"
        );

        let issuer_only = refusal(gated(&[("GLOSSDB_ISSUER", "https://issuer.test")]));
        assert!(issuer_only.contains("GLOSSDB_CLIENT_ID"), "{issuer_only}");

        let no_secret = refusal(gated(&[
            ("GLOSSDB_ISSUER", "https://issuer.test"),
            ("GLOSSDB_CLIENT_ID", "app-1"),
        ]));
        assert!(no_secret.contains("GLOSSDB_CLIENT_SECRET"), "{no_secret}");

        let whole = gated(&[
            ("GLOSSDB_ISSUER", "https://issuer.test"),
            ("GLOSSDB_CLIENT_ID", "app-1"),
            ("GLOSSDB_CLIENT_SECRET", "s3cret"),
            ("GLOSSDB_AUDIENCE", "https://glossql.example"),
        ])
        .expect("readable");
        assert_eq!(whole.audience, "https://glossql.example");
        assert!(
            whole
                .auth
                .is_some_and(|a| a.issuer == "https://issuer.test")
        );
    }

    /// The open switch is a statement, not a fallback: only the
    /// literal `true` opens, anything else keeps the gate required.
    #[test]
    fn only_the_literal_true_opens_the_doors() {
        let env = |v: Option<&'static str>| move |_: &str| v.map(str::to_string);
        assert!(super::open(&env(Some("true"))));
        assert!(super::open(&env(Some(" true "))), "whitespace is trimmed");
        assert!(!super::open(&env(None)));
        assert!(!super::open(&env(Some("1"))));
        assert!(!super::open(&env(Some("TRUE"))));
        assert!(!super::open(&env(Some("false"))));
    }

    /// A warehouse in an object store takes its key pair whole, with
    /// S3's region beside it; half a pair refuses by the missing name,
    /// and a pair for a directory warehouse refuses too.
    #[test]
    fn the_warehouse_key_pair_is_whole_or_absent() {
        let keyed = read(
            &[],
            &[
                ("GLOSSDB_WAREHOUSE", "s3://lake/warehouse"),
                ("GLOSSDB_WAREHOUSE_KEY_ID", "AKIA"),
                ("GLOSSDB_WAREHOUSE_SECRET", "s3cret"),
                ("GLOSSDB_WAREHOUSE_REGION", "eu-west-1"),
            ],
        )
        .expect("readable");
        assert!(matches!(
            keyed.catalog.credential,
            Some(super::WarehouseCredential::Keys { ref key_id, ref region, .. })
                if key_id == "AKIA" && region.as_deref() == Some("eu-west-1")
        ));
        let bare = read(&[], &[("GLOSSDB_WAREHOUSE", "gs://lake/warehouse")]).expect("readable");
        assert!(bare.catalog.credential.is_none());
        let half = refusal(read(
            &[],
            &[
                ("GLOSSDB_WAREHOUSE", "gs://lake/warehouse"),
                ("GLOSSDB_WAREHOUSE_KEY_ID", "GOOG1E"),
            ],
        ));
        assert!(half.contains("GLOSSDB_WAREHOUSE_SECRET"), "{half}");
        let misplaced = refusal(read(
            &[],
            &[
                ("GLOSSDB_WAREHOUSE_KEY_ID", "GOOG1E"),
                ("GLOSSDB_WAREHOUSE_SECRET", "s"),
            ],
        ));
        assert!(misplaced.contains("directory"), "{misplaced}");
    }

    /// The two budgets are the engine's own until named, and naming
    /// one leaves the other to the engine.
    #[test]
    fn the_budgets_are_the_engines_own_until_named() {
        let default = read(&[], &[]).expect("readable");
        assert_eq!(default.memory_limit_mb, None);
        assert_eq!(default.spill_limit_mb, None);
        let set = read(&["--memory-limit", "512"], &[]).expect("readable");
        assert_eq!(set.memory_limit_mb, Some(512));
        assert_eq!(
            set.spill_limit_mb, None,
            "naming one budget must not move the other"
        );
    }

    /// A sizing flag's variable is the flag's name; the flag wins over
    /// it, and a number that does not parse refuses by the name it was
    /// given under.
    #[test]
    fn a_flag_has_a_variable_and_wins_over_it() {
        let named = read(
            &[],
            &[
                ("GLOSSDB_ADDR", "0.0.0.0:8080"),
                ("GLOSSDB_ROW_CAP", "50"),
                ("GLOSSDB_MEMORY_LIMIT", "512"),
                ("GLOSSDB_SPILL_LIMIT", "1024"),
            ],
        )
        .expect("readable");
        assert_eq!(named.addr, "0.0.0.0:8080");
        assert_eq!(named.audience, "http://0.0.0.0:8080");
        assert_eq!(named.row_cap, 50);
        assert_eq!(
            (named.memory_limit_mb, named.spill_limit_mb),
            (Some(512), Some(1024))
        );

        let typed = read(
            &["--memory-limit", "256", "--addr", "127.0.0.1:9000"],
            &[
                ("GLOSSDB_MEMORY_LIMIT", "512"),
                ("GLOSSDB_ADDR", "0.0.0.0:8080"),
            ],
        )
        .expect("readable");
        assert_eq!(typed.memory_limit_mb, Some(256));
        assert_eq!(typed.addr, "127.0.0.1:9000");

        let bad = refusal(read(&[], &[("GLOSSDB_MEMORY_LIMIT", "4g")]));
        assert!(bad.contains("GLOSSDB_MEMORY_LIMIT"), "{bad}");
    }

    /// The shape of the run: a workspace directory holds the lake, a
    /// deployment names its catalog and its files and has no directory.
    #[test]
    fn the_shape_is_the_directory_or_the_named_lake() {
        let laptop = read(&[], &[]).expect("readable");
        assert_eq!(
            laptop.catalog.workspace.as_deref(),
            Some(std::path::Path::new("/tmp/w"))
        );
        assert!(laptop.catalog.catalog.ends_with("/tmp/w/catalog.ducklake"));
        assert!(laptop.catalog.warehouse.ends_with("/tmp/w/warehouse"));

        let deployment = Config::read(flags(&[]), |name| {
            match name {
                "GLOSSDB_INSECURE_OPEN" => Some("true"),
                "GLOSSDB_CATALOG_SQL" => Some("postgres://catalog.internal/glossql"),
                "GLOSSDB_WAREHOUSE" => Some("s3://warehouse/glossql"),
                _ => None,
            }
            .map(str::to_string)
        })
        .expect("readable");
        assert_eq!(deployment.catalog.workspace, None);
        assert_eq!(
            deployment.catalog.catalog,
            "postgres://catalog.internal/glossql"
        );
        assert_eq!(deployment.catalog.warehouse, "s3://warehouse/glossql");
    }

    /// The model service is named once, with its bearer a key or the
    /// audience the platform mints a token for; unnamed, it is not there.
    #[test]
    fn the_service_is_named_once() {
        let none =
            read(&[], &[("GLOSSDB_FORECAST_URL", "http://127.0.0.1:8100")]).expect("readable");
        assert!(
            none.service.is_none(),
            "a point's variable names no service"
        );
        let key = read(
            &[],
            &[
                ("GLOSSDB_SERVICE_URL", "http://127.0.0.1:8100"),
                ("GLOSSDB_SERVICE_TOKEN", "k1"),
            ],
        )
        .expect("readable");
        let service = key.service.expect("named");
        assert_eq!(service.url, "http://127.0.0.1:8100");
        assert_eq!(service.token.as_deref(), Some("k1"));
        assert_eq!(service.audience, None);
        let minted = read(
            &[],
            &[
                ("GLOSSDB_SERVICE_URL", "https://thesi.example"),
                ("GLOSSDB_SERVICE_AUDIENCE", "https://thesi.example"),
            ],
        )
        .expect("readable");
        assert_eq!(
            minted.service.expect("named").audience.as_deref(),
            Some("https://thesi.example")
        );
        assert!(super::usage().contains("GLOSSDB_SERVICE_URL"));
    }
}
