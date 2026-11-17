//! The skills, under the standing invariant: their examples are
//! checked here instead of proofread.
//!
//! Two rules, over every fenced ` ```glossql ` and ` ```sql ` block in
//! the product skills (every `.md` under `skills/<name>/` — the
//! SKILL.md and its references, embedded in the binary and served on
//! the MCP interface) and `.claude/skills/*/SKILL.md`:
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

use crate::examples::{self, Block};

/// Every fenced glossql/sql block in the shipped skills: every `.md` of
/// every skill under the repo's `skills/` (the product skills, their
/// references included — the interface serves both) and under
/// `.claude/skills` (the skills for building the server).
fn blocks() -> Vec<Block> {
    let manifest = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let mut out = Vec::new();
    for root in ["../../.claude/skills", "../../skills"] {
        let root = manifest
            .join(root)
            .canonicalize()
            .expect("the skills ship with the repo");
        let mut skills: Vec<std::path::PathBuf> = std::fs::read_dir(&root)
            .expect("a readable skills directory")
            .filter_map(|e| e.ok())
            .map(|e| e.path())
            .filter(|skill| skill.join("SKILL.md").is_file())
            .collect();
        skills.sort();
        for skill in skills {
            out.extend(examples::under(&skill, &root));
        }
    }
    assert!(!out.is_empty(), "no fenced examples found in the skills");
    out
}

#[tokio::test(flavor = "multi_thread")]
async fn every_skill_example_parses_and_every_read_binds() {
    let report = examples::check(&blocks()).await;
    assert!(
        report.unparsed.is_empty(),
        "skill examples that do not parse:\n{}",
        report.unparsed.join("\n")
    );
    assert!(
        report.broken_bodies.is_empty(),
        "skill function bodies that do not compile:\n{}",
        report.broken_bodies.join("\n")
    );
    assert!(
        report.unbound_reads.is_empty(),
        "skill examples naming something the reads do not serve:\n{}",
        report.unbound_reads.join("\n")
    );
    // A scan that silently checks nothing passes forever: the skills
    // teach function bodies and reads, and these floors say the scan
    // still finds its subject.
    assert!(
        report.bodies_checked >= 2,
        "only {} function bodies were compiled",
        report.bodies_checked
    );
    assert!(
        report.reads_bound >= 12,
        "only {} skill reads were bound",
        report.reads_bound
    );
}

/// The served table is the directory. `include_str!` keeps each
/// embedded body current, but only for the files the table names — a
/// skill added under `skills/` without a row in
/// [`glossdb_serverd::skills::SKILLS`] would sit on disk unserved,
/// and this is what refuses that.
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
    let mut served: Vec<String> = glossdb_serverd::skills::SKILLS
        .iter()
        .map(|s| s.name.to_string())
        .collect();
    served.sort();
    assert_eq!(served, on_disk);
    for skill in &glossdb_serverd::skills::SKILLS {
        assert!(
            !skill.description().is_empty(),
            "{} carries no frontmatter description — the listings serve it",
            skill.name
        );
    }
    // And every reference on disk is served, under the skill's own root.
    let mut on_disk: Vec<String> = Vec::new();
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
                on_disk.push(rel);
            }
        }
    }
    on_disk.sort();
    let mut served: Vec<String> = glossdb_serverd::skills::REFERENCES
        .iter()
        .map(|p| p.path.strip_prefix("skills/").unwrap().to_string())
        .collect();
    served.sort();
    assert_eq!(
        served, on_disk,
        "the served references are the files under skills/"
    );
    for p in glossdb_serverd::skills::REFERENCES {
        assert!(
            p.uri().starts_with("skill://") && p.title() != p.path,
            "{} needs a `# ` title line — the listing serves it as the description",
            p.path
        );
    }
}
