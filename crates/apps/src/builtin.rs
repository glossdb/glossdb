//! The app shipped in the binary. It serves at its plain name; a
//! workspace authors its own apps as glosses (`glossed.rs`), under
//! their own names — a glossed part under a built-in's name is refused
//! rather than shadowing it. Forking the built-in happens where its
//! source is, in this repository.
//!
//! One ships: the console — the questions a human is asked, //! views, how well the data is held, the dataset's words, the
//! column lineage; then every table and read as a file, and a pane for
//! a read of one's own (one app, not a model app beside a metrics app:
//! they were two sides of one workspace, and keeping them apart meant
//! deriving the same counts twice). It is the dataset's own page:
//! `/<dataset>/app` opens it. Built-ins move in lockstep with the
//! binary instead of going stale in a workspace copy.

#[derive(Debug)]
pub struct BuiltinApp {
    pub name: &'static str,
    /// Paths relative to the app root (`app.toml`, `index.html`,
    /// `frames/<name>.sql`), content verbatim.
    pub files: &'static [(&'static str, &'static str)],
}

/// The app `/<dataset>/app` opens: the dataset's own page.
pub const DATASET_PAGE: &str = "console";

macro_rules! console {
    ($path:literal) => {
        ($path, include_str!(concat!("../builtin/console/", $path)))
    };
}

macro_rules! frame {
    ($name:literal) => {
        (
            concat!("frames/", $name),
            include_str!(concat!("../builtin/console/frames/", $name)),
        )
    };
}

pub const BUILTINS: &[BuiltinApp] = &[BuiltinApp {
    name: DATASET_PAGE,
    files: &[
        console!("app.toml"),
        console!("index.html"),
        console!("review.html"),
        console!("history.html"),
        console!("views.html"),
        console!("quality.html"),
        console!("lineage.html"),
        console!("glossary.html"),
        console!("export.html"),
        console!("query.html"),
        frame!("aspect_head.sql"),
        frame!("aspect_values.sql"),
        frame!("assumptions.sql"),
        frame!("axes.sql"),
        frame!("test.sql"),
        frame!("test_results.sql"),
        frame!("tests.sql"),
        frame!("view_tests.sql"),
        frame!("column_head.sql"),
        frame!("column_values.sql"),
        frame!("columns.sql"),
        frame!("conventions.sql"),
        frame!("dims.sql"),
        frame!("drivers.sql"),
        frame!("fact.sql"),
        frame!("facts.sql"),
        frame!("findings.sql"),
        frame!("functions.sql"),
        frame!("front.sql"),
        frame!("joins.sql"),
        frame!("loads.sql"),
        frame!("latest.sql"),
        frame!("lineage_edges.sql"),
        frame!("lineage_nodes.sql"),
        frame!("history.sql"),
        frame!("measured.sql"),
        frame!("next_rows.sql"),
        frame!("view.sql"),
        frame!("view_head.sql"),
        frame!("view_history.sql"),
        frame!("view_uses.sql"),
        frame!("obj_history.sql"),
        frame!("obj_measurements.sql"),
        frame!("obj_tests.sql"),
        frame!("obj_used.sql"),
        frame!("open.sql"),
        frame!("measures.sql"),
        frame!("reads.sql"),
        frame!("relations.sql"),
        frame!("settled.sql"),
        frame!("slices.sql"),
        frame!("source_head.sql"),
        frame!("source_loads.sql"),
        frame!("source_recipes.sql"),
        frame!("table_columns.sql"),
        frame!("table_head.sql"),
        frame!("table_identities.sql"),
        frame!("table_loads.sql"),
        frame!("tables.sql"),
        frame!("terms.sql"),
        frame!("test_history.sql"),
        frame!("tree.sql"),
        frame!("trend.sql"),
        frame!("unmeasured.sql"),
        frame!("view_fields.sql"),
        frame!("view_tables.sql"),
        frame!("views.sql"),
        frame!("vocabulary.sql"),
        console!("specs/series.vl.json"),
    ],
}];

pub fn builtin(name: &str) -> Option<&'static BuiltinApp> {
    BUILTINS.iter().find(|b| b.name == name)
}
