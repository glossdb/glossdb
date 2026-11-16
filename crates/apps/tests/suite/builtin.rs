//! The shipped app holds together: what its pages name is what the
//! binary ships. A page that names a frame or a spec the binary does
//! not hold renders an empty tile; a frame or a spec no page names is
//! shipped and never read.

use std::collections::BTreeSet;

use glossdb_apps::BUILTINS;

/// The shell and the macros every built-in page is rendered through.
const TEMPLATES: [&str; 3] = [
    include_str!("../../templates/shell.html"),
    include_str!("../../templates/modules/tiles.html"),
    include_str!("../../templates/modules/object.html"),
];

/// Every `<folder>/<name>` the markup names, by name.
fn named(markup: &str, folder: &str) -> BTreeSet<String> {
    markup
        .split(folder)
        .skip(1)
        .map(|rest| {
            rest.chars()
                .take_while(|c| c.is_ascii_alphanumeric() || *c == '_')
                .collect::<String>()
        })
        .filter(|name| !name.is_empty())
        .collect()
}

#[test]
fn the_pages_of_a_builtin_name_the_frames_and_specs_it_ships() {
    for app in BUILTINS {
        let shipped = |folder: &str, extension: &str| -> BTreeSet<String> {
            app.files
                .iter()
                .filter_map(|(path, _)| path.strip_prefix(folder)?.strip_suffix(extension))
                .map(str::to_string)
                .collect()
        };
        let mut markup: String = TEMPLATES.concat();
        for (path, body) in app.files {
            if path.ends_with(".html") {
                markup.push_str(body);
            }
        }
        assert_eq!(
            named(&markup, "frames/"),
            shipped("frames/", ".sql"),
            "`{}`: the frames its pages name, and the frames it ships",
            app.name
        );
        assert_eq!(
            named(&markup, "specs/"),
            shipped("specs/", ".vl.json"),
            "`{}`: the specs its pages name, and the specs it ships",
            app.name
        );
    }
}
