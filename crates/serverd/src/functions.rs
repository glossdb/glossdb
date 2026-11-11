//! The function surface per execution context, as pages the interface
//! serves: `doc://functions/interface.md`, `doc://functions/recipe.md`,
//! `doc://functions/detector.md`. Three contexts register different
//! functions, and nothing on the interface said which — an agent learned
//! the surface by refusal. Each page lists what its context registers,
//! read from that context's own registry at boot (after the shipped
//! system loaded), so a page cannot drift from the registration.

use std::fmt::Write as _;

use crate::engine::{Actor, ActorKind};
use crate::engine::{Plane, Registered, ServedPage, SessionError};

use crate::wire;

/// The three pages, built on the plane's own registries.
pub async fn pages(plane: &Plane) -> Result<Vec<ServedPage>, SessionError> {
    let actor = Actor {
        kind: ActorKind::Human,
        id: crate::BOOTSTRAP.into(),
    };
    let session = plane.channel(actor, None).await?;
    let mut served = session.registered_functions().await?;
    // The functions declared when the interface opened — the kit's, and any
    // a workspace declared before this boot. `functions` says what
    // holds now.
    let declared = session
        .execute("SELECT name FROM functions ORDER BY name")
        .await?;
    if let Ok(rendered) = wire::outcomes_json(&declared)
        && let Some(rows) = rendered
            .get(0)
            .and_then(|o| o.get("rows"))
            .and_then(|r| r.as_array())
    {
        served.extend(
            rows.iter()
                .filter_map(|r| r.get("name")?.as_str())
                .map(|name| Registered {
                    kind: "extract",
                    name: name.to_string(),
                    syntax: Some(format!("SELECT {name}() FROM <subject>")),
                }),
        );
    }
    served.sort();
    Ok(vec![
        page(
            "interface",
            "Functions on the interface",
            "What SQL sent through the interface can call — a statement's SQL, a \
             definition's, an app frame's. The engine's functions, the JSON \
             functions, the try-casts and the shipped aggregates plan here \
             (`scalar`, `aggregate`, `window`, `table`); the reads the planner \
             answers by name are the reads over the catalog (`interface`); a \
             declared function runs as an extraction, `SELECT <name>() FROM \
             <subject>`, and `SELECT name FROM functions` lists what is current \
             now (`extract`, as declared when the interface opened); a \
             definition serves under its name.",
            &served,
        ),
        page(
            "recipe",
            "Functions in a recipe or a preview",
            "What the SQL of `DECLARE RECIPE` and `PREVIEW` can call: the \
             engine's defaults, the try-casts, and the three readers over \
             the source's files. Nothing else — no JSON functions, no \
             shipped aggregates, no declared function.",
            &crate::engine::reader_functions(),
        ),
        page(
            "detector",
            "Functions in a detector",
            "What a test's detector query can call over its `annotations` \
             relation: the engine's defaults, nothing more.",
            &crate::engine::detector_functions(),
        ),
    ])
}

fn page(name: &str, title: &str, intro: &str, list: &[Registered]) -> ServedPage {
    let mut body = format!("# {title}\n\n{intro}\n\n| function | kind | syntax |\n|---|---|---|\n");
    for f in list {
        let syntax = f.syntax.as_deref().unwrap_or("").replace('|', "\\|");
        let _ = writeln!(body, "| `{}` | {} | {} |", f.name, f.kind, syntax);
    }
    ServedPage {
        uri: format!("doc://functions/{name}.md"),
        name: format!("functions/{name}.md"),
        title: title.to_string(),
        description: title.to_string(),
        mime: "text/markdown",
        body,
    }
}
