//! The lockstep rule as a check: every arrow crate is one version in
//! the lock. The engine's Arrow C stream is read by the arrow the
//! workspace manifest names; a bare `cargo update` that splits the
//! tree does not compile at that stream, but only on the target that
//! builds it.

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

fn crates_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .canonicalize()
        .expect("the crates directory")
}

#[test]
fn one_arrow_in_the_lock() {
    let lock = std::fs::read_to_string(crates_dir().join("../Cargo.lock")).expect("Cargo.lock");
    let mut versions: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    let mut name = None;
    for line in lock.lines() {
        if let Some(n) = line.strip_prefix("name = ") {
            name = Some(n.trim_matches('"'));
        } else if let Some(v) = line.strip_prefix("version = ")
            && let Some(n) = name.take()
            && n.starts_with("arrow")
        {
            versions.entry(n).or_default().push(v.trim_matches('"'));
        }
    }
    assert!(!versions.is_empty(), "the lock names arrow");
    let split: Vec<String> = versions
        .iter()
        .filter(|(_, v)| v.len() > 1)
        .map(|(n, v)| format!("{n}: {}", v.join(", ")))
        .collect();
    assert!(
        split.is_empty(),
        "the arrow tree split: {}",
        split.join("; ")
    );
}
