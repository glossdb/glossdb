//! The app shipped in the binary. It serves at its plain name; a
//! workspace authors its own apps as glosses (`glossed.rs`), under
//! their own names — a glossed part under a built-in's name is refused
//! rather than shadowing it. Forking the built-in happens where its
//! source is, in this repository.
//!
//! One ships: the docket — the questions a human is asked, the metric
//! surfaces, how well the data is held, the dataset's words, the
//! column lineage; then every table and read as a file, and a pane for
//! a read of one's own (one app, not a model app beside a metrics app:
//! they were two faces of one workspace, and keeping them apart meant
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
pub const DATASET_PAGE: &str = "docket";

macro_rules! docket {
    ($path:literal) => {
        ($path, include_str!(concat!("../builtin/docket/", $path)))
    };
}

macro_rules! frame {
    ($name:literal) => {
        (
            concat!("frames/", $name),
            include_str!(concat!("../builtin/docket/frames/", $name)),
        )
    };
}

pub const BUILTINS: &[BuiltinApp] = &[BuiltinApp {
    name: DATASET_PAGE,
    files: &[
        docket!("app.toml"),
        docket!("index.html"),
        docket!("metrics.html"),
        docket!("quality.html"),
        docket!("lineage.html"),
        docket!("glossary.html"),
        docket!("export.html"),
        docket!("query.html"),
        frame!("aspect_head.sql"),
        frame!("aspect_values.sql"),
        frame!("assumptions.sql"),
        frame!("axes.sql"),
        frame!("breaches.sql"),
        frame!("check.sql"),
        frame!("check_points.sql"),
        frame!("check_rates.sql"),
        frame!("check_slots.sql"),
        frame!("check_verdicts.sql"),
        frame!("checks.sql"),
        frame!("column_head.sql"),
        frame!("column_slots.sql"),
        frame!("columns.sql"),
        frame!("conventions.sql"),
        frame!("corridor.sql"),
        frame!("dims.sql"),
        frame!("drivers.sql"),
        frame!("fact.sql"),
        frame!("facts.sql"),
        frame!("findings.sql"),
        frame!("front.sql"),
        frame!("joins.sql"),
        frame!("latest.sql"),
        frame!("lineage_edges.sql"),
        frame!("landing.sql"),
        frame!("lineage_nodes.sql"),
        frame!("measured.sql"),
        frame!("metric.sql"),
        frame!("movers.sql"),
        frame!("open.sql"),
        frame!("owed.sql"),
        frame!("plan.sql"),
        frame!("pulse.sql"),
        frame!("reads.sql"),
        frame!("relations.sql"),
        frame!("remeasure.sql"),
        frame!("settled.sql"),
        frame!("slices.sql"),
        frame!("table_columns.sql"),
        frame!("table_head.sql"),
        frame!("table_identities.sql"),
        frame!("table_landing.sql"),
        frame!("tables.sql"),
        frame!("terms.sql"),
        frame!("trend.sql"),
        frame!("unmeasured.sql"),
        frame!("unsaid.sql"),
        frame!("view_fields.sql"),
        frame!("view_tables.sql"),
        frame!("views.sql"),
        frame!("vocabulary.sql"),
        docket!("specs/corridor.vl.json"),
        docket!("specs/series.vl.json"),
    ],
}];

pub fn builtin(name: &str) -> Option<&'static BuiltinApp> {
    BUILTINS.iter().find(|b| b.name == name)
}
