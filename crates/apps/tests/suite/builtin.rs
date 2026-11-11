//! The shipped app rides the standing invariant: every built-in frame
//! parses against the pinned substrate, so read-surface drift breaks
//! the build, not the browser.

use glossdb_apps::BUILTINS;

#[test]
fn every_builtin_carries_manifest_and_index() {
    for app in BUILTINS {
        for required in ["app.toml", "index.html"] {
            assert!(
                app.files.iter().any(|(p, _)| *p == required),
                "builtin `{}` is missing {required}",
                app.name
            );
        }
    }
}
