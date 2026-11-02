//! The skills, under the standing invariant.
//!
//! Run 2's first friction was five skills teaching `SELECT value FROM
//! GLOSSARY(…)` — a column that does not exist and never did. Prose
//! drifts from a moving surface because nothing checks it, so the
//! examples are checked here instead of proofread.
//!
//! Two rules, over every fenced ` ```glossql ` and ` ```sql ` block in
//! the product skills (every `.md` under `skills/<name>/` — the
//! SKILL.md and its references, embedded in the binary and served on
//! the MCP door) and `.claude/skills/*/SKILL.md`:
//!
//!   1. it parses;
//!   2. if it is a single read, it PLANS against a bootstrapped
//!      workspace — with the one exemption that a missing TABLE is
//!      fine, because an example may name a customer's data. A missing
//!      or misspelled COLUMN is not fine: those are ours, and that is
//!      exactly the class of error that shipped.
//!
//! Nothing here executes a write. A block that declares or glosses is
//! held to rule 1 alone.

use crate::common;

struct Block {
    skill: String,
    line: usize,
    sql: String,
}

/// Every fenced glossql/sql block in the shipped skills: the product
/// skills under the repo's `skills/`, and what lives under
/// `.claude/skills` (the substrate skill).
fn blocks() -> Vec<Block> {
    let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut skills = Vec::new();
    for (dir, why) in [
        (
            manifest.join("../../.claude/skills"),
            "the substrate skill ships with the repo",
        ),
        (
            manifest.join("../../skills"),
            "the product skills ship with the repo",
        ),
    ] {
        let dir = dir.canonicalize().expect(why);
        skills.extend(
            std::fs::read_dir(&dir)
                .expect("readable skills directory")
                .filter_map(|e| e.ok())
                .map(|e| e.path()),
        );
    }
    let mut out = Vec::new();
    skills.sort();
    // Every `.md` in the skill's directory, its references included —
    // a fence in a reference is held to the same rules as one on the
    // first page, because the door serves both.
    let mut files: Vec<std::path::PathBuf> = Vec::new();
    for skill in skills {
        if !skill.join("SKILL.md").is_file() {
            continue;
        }
        let mut stack = vec![skill];
        while let Some(dir) = stack.pop() {
            let Ok(entries) = std::fs::read_dir(&dir) else {
                continue;
            };
            for entry in entries.filter_map(|e| e.ok()) {
                let path = entry.path();
                if path.is_dir() {
                    stack.push(path);
                } else if path.extension().is_some_and(|e| e == "md") {
                    files.push(path);
                }
            }
        }
    }
    files.sort();
    for path in files {
        let Ok(text) = std::fs::read_to_string(&path) else {
            continue;
        };
        let name = path
            .iter()
            .rev()
            .take_while(|s| *s != "skills")
            .collect::<Vec<_>>()
            .into_iter()
            .rev()
            .map(|s| s.to_string_lossy())
            .collect::<Vec<_>>()
            .join("/");
        let mut open: Option<(usize, String)> = None;
        for (i, line) in text.lines().enumerate() {
            match &mut open {
                None => {
                    if line.trim() == "```glossql" || line.trim() == "```sql" {
                        open = Some((i + 2, String::new()));
                    }
                }
                Some((start, body)) => {
                    if line.trim() == "```" {
                        out.push(Block {
                            skill: name.clone(),
                            line: *start,
                            sql: std::mem::take(body),
                        });
                        open = None;
                    } else {
                        body.push_str(line);
                        body.push('\n');
                    }
                }
            }
        }
    }
    assert!(!out.is_empty(), "no fenced examples found in the skills");
    out
}

#[tokio::test(flavor = "multi_thread")]
async fn every_skill_example_parses() {
    let mut broken = Vec::new();
    for b in blocks() {
        if let Err(e) = glossql_parser::GlossqlParser::parse_sql(&b.sql) {
            broken.push(format!("{}:{} — {e}", b.skill, b.line));
        }
    }
    assert!(
        broken.is_empty(),
        "skill examples that do not parse:\n{}",
        broken.join("\n")
    );
}

/// Every `DECLARE FUNCTION … AS $$…$$` body in the skills is one SQL
/// query.
///
/// Rule 1 cannot see this: a function's body is opaque text to the
/// glossql parser, so an example whose body the engine would refuse
/// parses perfectly and ships as teaching. A body is SQL — a
/// measurement over data, a detector over `slots` (§6) — so the check
/// is the same shape rule the session applies.
#[tokio::test(flavor = "multi_thread")]
async fn every_skill_function_body_compiles() {
    let mut broken = Vec::new();
    let mut checked = 0usize;
    for b in blocks() {
        // Anchored on DECLARE FUNCTION: PROBE, RECIPE and GLOSS bodies
        // ride the same dollar quoting and are SQL or JSON, so a bare
        // scan for `AS $$` compiles the wrong thing. Within a function
        // statement, `AS $$` opens the body and the next `$$` closes
        // it — bodies cannot contain `$$`, which is what makes this
        // sound.
        for part in b.sql.split("DECLARE FUNCTION").skip(1) {
            let Some(open) = part.find("AS $$") else {
                continue;
            };
            let after = &part[open + 5..];
            let Some(close) = after.find("$$") else {
                continue;
            };
            checked += 1;
            let body = &after[..close];
            let is_sql = match glossql_parser::GlossqlParser::parse_sql(body) {
                Ok(statements) => statements.len() == 1,
                Err(e) => {
                    broken.push(format!("{}:{} — {e}", b.skill, b.line));
                    continue;
                }
            };
            if !is_sql {
                let e = "a function body is one SQL query";
                broken.push(format!("{}:{} — {e}", b.skill, b.line));
            }
        }
    }
    assert!(
        broken.is_empty(),
        "skill function bodies that do not compile:\n{}",
        broken.join("\n")
    );
    assert!(
        checked >= 2,
        "only {checked} function bodies were compiled — the scan has stopped finding its subject"
    );
}

/// The served table is the directory. `include_str!` keeps each
/// embedded body current, but only for the files the table names — a
/// skill added under `skills/` without a row in
/// [`glossql_serverd::skills::SKILLS`] would sit on disk unserved,
/// and this is what refuses that.

/// A missing table is fine: an example may name a customer's data, or a
/// grounding a fresh workspace has none of. A missing column is not.
fn missing_table(error: &str) -> bool {
    error.contains("Table with name") && error.contains("does not exist")
}

/// A frame's read binds its parameters at the call: an example that
/// spells them bound up to the values it was not given.
fn unbound_parameters(error: &str) -> bool {
    error.contains("Values were not provided for the following parameters")
}

/// The examples' reads, bound on a fresh workspace: a read naming a
/// column, a relation or a function the engine and its kits do not
/// serve fails here. One channel for the run, with a dataset in use —
/// the names the examples spell — so a read reaches its columns
/// instead of stopping at the binding.
async fn bind_reads(blocks: &[Block], at: impl Fn(&Block) -> String) -> (usize, Vec<String>) {
    let (_dir, plane) = common::scratch_plane().await;
    let session = plane.channel(common::human(), None).await.unwrap();
    for name in ["ops", "fin", "orders", "erp_export"] {
        session
            .execute(&format!(
                "DECLARE DATASET {name} SET (purpose: 'the docs harness');"
            ))
            .await
            .unwrap();
    }
    session.execute("USE ops;").await.unwrap();
    let mut bound = 0;
    let mut broken = Vec::new();
    for b in blocks {
        let trimmed: String = b
            .sql
            .lines()
            .filter(|l| !l.trim_start().starts_with("--"))
            .collect::<Vec<_>>()
            .join("\n");
        let head = trimmed.trim_start().to_lowercase();
        // Reads only: a write example is held to parsing alone, and a
        // read of the language's own — GLOSSARY(), ATTEST(), a
        // measurement over a subject — binds in the extension, not in
        // a plan.
        if !(head.starts_with("select") || head.starts_with("with ") || head.starts_with("from "))
            || head.contains("glossary(")
            || head.contains("attest(")
            || head.starts_with("select temporal(")
        {
            continue;
        }
        // One statement per block, or we cannot bound it.
        if trimmed.trim_end().trim_end_matches(';').contains(';') {
            continue;
        }
        bound += 1;
        let sql = format!("EXPLAIN {}", trimmed.trim().trim_end_matches(';'));
        if let Err(e) = session.batches(&sql, &[]).await {
            let text = e.to_string();
            if !missing_table(&text) && !unbound_parameters(&text) {
                broken.push(format!("{} — {text}", at(b)));
            }
        }
    }
    (bound, broken)
}

#[tokio::test(flavor = "multi_thread")]
async fn every_skill_read_names_columns_that_exist() {
    let blocks = blocks();
    let (bound, broken) = bind_reads(&blocks, |b| format!("{}:{}", b.skill, b.line)).await;
    assert!(
        broken.is_empty(),
        "skill examples naming something the reads do not serve:\n{}",
        broken.join("\n")
    );
    // A test that silently checks nothing passes forever. The skills
    // teach reads; if this floor is not met, the classification above
    // has started skipping what it should be holding.
    assert!(bound >= 12, "only {bound} skill reads were bound");
}

#[test]
fn the_served_skills_are_the_skills_directory() {
    let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let dir = manifest.join("../../skills").canonicalize().unwrap();
    let mut on_disk: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .filter(|e| e.path().join("SKILL.md").is_file())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    on_disk.sort();
    let mut served: Vec<String> = glossql_serverd::skills::SKILLS
        .iter()
        .map(|s| s.name.to_string())
        .collect();
    served.sort();
    assert_eq!(served, on_disk);
    for skill in &glossql_serverd::skills::SKILLS {
        assert!(
            !skill.description().is_empty(),
            "{} carries no frontmatter description — the listings serve it",
            skill.name
        );
    }
    // And every reference on disk is served, current, under the
    // skill's own root — the build embeds the directory, and this is
    // what proves the embedding is the directory as it stands.
    let mut on_disk: Vec<(String, String)> = Vec::new();
    let mut stack = vec![dir.clone()];
    while let Some(d) = stack.pop() {
        for entry in std::fs::read_dir(&d).unwrap().filter_map(|e| e.ok()) {
            let path = entry.path();
            if path.is_dir() {
                stack.push(path);
            } else if path.extension().is_some_and(|e| e == "md")
                && path.file_name().is_some_and(|n| n != "SKILL.md")
            {
                let rel = path
                    .strip_prefix(&dir)
                    .unwrap()
                    .to_string_lossy()
                    .into_owned();
                on_disk.push((rel, std::fs::read_to_string(&path).unwrap()));
            }
        }
    }
    on_disk.sort();
    let mut served: Vec<(String, String)> = glossql_serverd::skills::REFERENCES
        .iter()
        .map(|p| {
            (
                p.path.strip_prefix("skills/").unwrap().to_string(),
                p.body.to_string(),
            )
        })
        .collect();
    served.sort();
    assert_eq!(
        served.iter().map(|(p, _)| p.as_str()).collect::<Vec<_>>(),
        on_disk.iter().map(|(p, _)| p.as_str()).collect::<Vec<_>>(),
        "the served references are the files under skills/"
    );
    assert_eq!(
        served, on_disk,
        "a served reference is the file as it stands"
    );
    for p in glossql_serverd::skills::REFERENCES {
        assert!(
            p.uri().starts_with("skill://") && p.title() != p.path,
            "{} needs a `# ` title line — the listing serves it as the description",
            p.path
        );
    }
}

/// The first quoted `x.y.z` literal in `s` — how a minified bundle
/// states its own version near the top — read as its major.
fn first_quoted_semver_major(s: &str) -> Option<u32> {
    let mut i = 0;
    while let Some(q) = s[i..].find('"') {
        let start = i + q + 1;
        let end = start + s[start..].find('"')?;
        let lit = &s[start..end];
        let parts: Vec<&str> = lit.split('.').collect();
        if parts.len() == 3
            && parts
                .iter()
                .all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
        {
            return parts[0].parse().ok();
        }
        i = end + 1;
    }
    None
}

/// Every `vega-lite/v<N>` major named in `text`.
fn schema_majors(text: &str) -> Vec<u32> {
    let mut out = Vec::new();
    let mut rest = text;
    while let Some(at) = rest.find("vega-lite/v") {
        rest = &rest[at + "vega-lite/v".len()..];
        let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
        if let Ok(v) = digits.parse() {
            out.push(v);
        }
    }
    out
}

/// The apps skill names the vega-lite major outright, and this pin
/// holds the number to what the door actually serves — the vendored
/// bundle — alongside the built-in docket's own spec. Foreign agents
/// keep writing the `v5` habit into `app_spec` bodies; the skill's
/// hint is the counter, and a bundle bump that forgets the prose
/// fails here instead of teaching an outdated `$schema`.
#[test]
fn the_apps_skill_names_the_vega_lite_major_the_door_serves() {
    let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let bundle = std::fs::read_to_string(manifest.join("../apps/assets/vendor/vega-lite.min.js"))
        .expect("the vendored vega-lite bundle");
    let served = first_quoted_semver_major(&bundle).expect("a version literal in the bundle");

    let skill = glossql_serverd::skills::SKILLS
        .iter()
        .find(|s| s.name == "glossql-apps")
        .expect("the apps skill ships");
    // A skill that names the major must name the served one; a skill
    // that names none is not held to name it — prose is not glued to
    // the suite, only held to the facts it states.
    let mut claimed = schema_majors(skill.body);
    let spec =
        std::fs::read_to_string(manifest.join("../apps/builtin/docket/specs/series.vl.json"))
            .expect("the docket's series spec");
    claimed.extend(schema_majors(&spec));
    assert!(
        claimed.iter().all(|&v| v == served),
        "vega-lite majors out of step: the bundle serves v{served}, prose and specs claim {claimed:?}"
    );
}
