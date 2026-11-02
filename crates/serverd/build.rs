//! Embeds the teaching trees beside the hand-written skill table in
//! `skills.rs`: every `.md` under `skills/` other than a `SKILL.md`
//! (a skill's references, read on demand), every `.md` under `docs/`
//! (the pages an agent working in this repository reads), and every
//! `.md` under `vendor/` (the engine's own SQL guide at the pin). The
//! door serves them as resources, so a connected agent holds what a
//! checkout holds — and what a build serves is what its suite tested:
//! the first two trees sit under the docs and skills harnesses, the
//! third is held to the lock's DuckDB release.
//!
//! The binary links libduckdb as a shared library. A released binary
//! finds it in the `lib` directory beside its own `bin` — the image's
//! and the tarball's layout — through the run path written here; a dev
//! tree's binary finds it where libduckdb-sys put it, through the
//! search path cargo sets for `cargo run` and `cargo test`.

use std::path::{Path, PathBuf};

/// Every `.md` under `root`, recursively, hidden entries skipped.
fn walk(root: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(root) else {
        return;
    };
    for entry in entries.filter_map(|e| e.ok()) {
        let path = entry.path();
        if path
            .file_name()
            .and_then(|n| n.to_str())
            .is_some_and(|n| n.starts_with('.'))
        {
            continue;
        }
        if path.is_dir() {
            walk(&path, out);
        } else if path.extension().is_some_and(|e| e == "md") {
            out.push(path);
        }
    }
}

fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let origin = if target_os == "macos" {
        "@executable_path"
    } else {
        "$ORIGIN"
    };
    println!("cargo:rustc-link-arg-bins=-Wl,-rpath,{origin}/../lib");
    println!("cargo:rustc-link-arg-bins=-Wl,-rpath,{origin}");
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").expect("cargo sets it"));
    let repo = manifest
        .join("../..")
        .canonicalize()
        .expect("the crate sits two levels under the repo root");
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").expect("cargo sets it"));
    let mut src = String::new();
    for (root, table, references_only) in [
        ("skills", "REFERENCES", true),
        ("docs", "PAGES", false),
        ("vendor", "VENDORED", false),
    ] {
        let dir = repo.join(root);
        println!("cargo:rerun-if-changed={}", dir.display());
        let mut files = Vec::new();
        walk(&dir, &mut files);
        files.sort();
        src.push_str(&format!("pub const {table}: &[Page] = &[\n"));
        for file in files {
            if references_only && file.file_name().is_some_and(|n| n == "SKILL.md") {
                continue;
            }
            let rel = file
                .strip_prefix(&repo)
                .expect("under the repo")
                .to_string_lossy()
                .replace('\\', "/");
            src.push_str(&format!(
                "    Page {{ path: {rel:?}, body: include_str!({:?}) }},\n",
                file.display()
            ));
        }
        src.push_str("];\n");
    }
    std::fs::write(out_dir.join("embedded.rs"), src).expect("OUT_DIR is writable");
}
