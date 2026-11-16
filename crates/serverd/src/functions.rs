//! The functions SQL on the interface can call, as one page the
//! interface serves: `doc://functions/interface.md`. It lists what the
//! plane registers, read from its own registry at boot (after the
//! shipped system loaded), so the page cannot drift from the
//! registration. A load query and a detector call the engine's own
//! functions; the load skill names the readers.

use std::fmt::Write as _;

use crate::engine::{Actor, ActorKind};
use crate::engine::{Plane, Registered, ServedPage, SessionError};

/// The page, built on the plane's own registry: the kits' macros and
/// every declared function once.
pub async fn pages(plane: &Plane) -> Result<Vec<ServedPage>, SessionError> {
    let actor = Actor {
        kind: ActorKind::Human,
        id: crate::BOOTSTRAP.into(),
    };
    let session = plane.channel(actor, None).await?;
    let served = session.registered_functions().await?;
    Ok(vec![page(
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
    )])
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
