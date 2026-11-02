//! The shipped app rides the standing invariant: every built-in frame
//! parses against the pinned substrate, so read-surface drift breaks
//! the build, not the browser.

use glossql_apps::BUILTINS;

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
