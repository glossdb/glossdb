//! The console's second write, a compute act: re-run every measurement
//! that holds from before the last change.
//!
//! Every write moves the data version, and a function's value loaded at an earlier
//! data version is served and marked (SPEC.md §7): the numbers are current (a
//! metric's view reads the data as it holds); the judged axes and the
//! check results stand on those values until they run again. The banner counts them
//! (the raw read's `current`), and this writes the next rows — the same
//! extractions an agent would run, nothing authored: the functions
//! speak.
//!
//! The response is the write event, as the review decision's is — and it names
//! itself: 204 with `HX-Trigger: glossql:remeasured, glossql:written`.
//! A review decision cannot change a data frame, so the store keeps data frames
//! across one; a re-measure can (the axes), so on `glossql:remeasured`
//! the store drops them too, and every tile refetches in place.

use crate::engine::Caller;
use axum::Extension;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};

use crate::AppInterface;
use crate::app::AppDef;
use crate::decide::plain;

/// Both events, the re-measure's own first: the store evicts on each
/// in capture phase before any tile's own listener refetches.
const REMEASURED: [(&str, &str); 1] = [("HX-Trigger", "glossql:remeasured, glossql:written")];

pub async fn remeasure(
    State(interface): State<AppInterface>,
    Path((dataset, app)): Path<(String, String)>,
    Extension(Caller(actor)): Extension<Caller>,
) -> Response {
    if let Some(missing) = crate::missing(&interface, &dataset).await {
        return plain(StatusCode::NOT_FOUND, missing);
    }
    let glossed = crate::glossed::parts(&interface, &dataset, false)
        .await
        .parts;
    match AppDef::load(&app, &glossed) {
        Ok(Some(_)) => {}
        Ok(None) => return plain(StatusCode::NOT_FOUND, format!("no app `{app}`")),
        Err(e) => return plain(StatusCode::INTERNAL_SERVER_ERROR, e),
    };
    let human = match interface.plane.channel(actor, Some(&dataset)).await {
        Ok(session) => session,
        Err(e) => return plain(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };
    match human.remeasure().await {
        Ok(_) => (StatusCode::NO_CONTENT, REMEASURED).into_response(),
        Err(e) => plain(StatusCode::UNPROCESSABLE_ENTITY, e.to_string()),
    }
}
