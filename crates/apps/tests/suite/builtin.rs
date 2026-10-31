//! The shipped app rides the standing invariant: every built-in frame
//! parses against the pinned substrate, so read-surface drift breaks
//! the build, not the browser.

use glossql_apps::BUILTINS;
#[cfg(not(feature = "duck"))]
use glossql_parser::GlossqlParser;

// The DuckDB frames are in the engine's own dialect, which the session
// parser does not read; the door suite executes every one of them.
#[cfg(not(feature = "duck"))]
#[test]
fn every_builtin_frame_parses() {
    for app in BUILTINS {
        for (path, sql) in app.files.iter().filter(|(p, _)| p.ends_with(".sql")) {
            GlossqlParser::parse_sql(sql)
                .unwrap_or_else(|e| panic!("builtin `{}` frame {path}: {e}", app.name));
        }
    }
}

#[test]
fn every_builtin_carries_manifest_and_index() {
    for app in BUILTINS {
        for owed in ["app.toml", "index.html"] {
            assert!(
                app.files.iter().any(|(p, _)| *p == owed),
                "builtin `{}` is missing {owed}",
                app.name
            );
        }
    }
}
