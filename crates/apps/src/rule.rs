//! The console's one write: a human review decision on a claim that holds open.
//!
//! The gate is the derivation itself. A posted review decision is accepted only
//! if `open_questions` still carries that exact `(subject, aspect,
//! key)` — so the page cannot rule something already decided, already
//! folded in, or never disclosed, and a stale tab is refused rather
//! than believed. The prose the review decision records comes from that read,
//! not from the form: what the human agreed with is what the workspace
//! says, never what a browser posted.
//!
//! Nothing else about the page changes. It still holds no other write,
//! and the review decision is stored exactly where the round's would — the human's
//! own value, on the human's own channel, witnessed by this server.
//!
//! Who that human is comes from the token the request carries; that
//! the caller is human comes from the interface, which stamps the kind on
//! every request it admits.
//!
//! The response is an event, not a navigation (not a 303 back to
//! the Referer — PRG bent out of shape, since
//! the reader never leaves the page and the console is client-rendered
//! anyway). Success is 204 with `HX-Trigger: glossql:written`; the
//! store hears the event, drops its frame caches, and every connected
//! component refetches in place. The stale-tab 409 carries the same
//! trigger, so a tab that decided a dead question re-derives to the
//! current state instead of asking for a reload.

use crate::engine::Caller;
use crate::engine::rulings::{self, Ruling};
use axum::Extension;
use axum::Form;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::Deserialize;

use crate::AppDoor;
use crate::app::AppDef;

#[derive(Deserialize)]
pub struct Answer {
    subject: String,
    aspect: String,
    key: String,
    /// `confirmed`, `corrected`, or `unclear` — the stances the round
    /// serves. `unclear` refuses the question rather than the claim:
    /// the agent owes a reformulation, not an applied decision. Admission is the
    /// one gate: the review decision aspect's schema holds the enum, so an
    /// unknown stance answers with the store's own refusal.
    stance: String,
    /// The human's own words, empty allowed — the MCP interface writes the
    /// same act the same way.
    #[serde(default)]
    note: String,
}

/// The write announced: htmx dispatches this on the posting form and it
/// bubbles — the store clears on it, components refetch on it.
pub(crate) const WRITTEN: [(&str, &str); 1] = [("HX-Trigger", "glossql:written")];

pub async fn rule(
    State(door): State<AppDoor>,
    Path((dataset, app)): Path<(String, String)>,
    Extension(Caller(actor)): Extension<Caller>,
    Form(answer): Form<Answer>,
) -> Response {
    let stance = answer.stance.as_str();
    if let Some(missing) = crate::missing(&door, &dataset).await {
        return plain(StatusCode::NOT_FOUND, missing);
    }
    let glossed = crate::glossed::parts(&door, &dataset, false).await.parts;
    match AppDef::load(&app, &glossed) {
        Ok(Some(_)) => {}
        Ok(None) => return plain(StatusCode::NOT_FOUND, format!("no app `{app}`")),
        Err(e) => return plain(StatusCode::INTERNAL_SERVER_ERROR, e),
    };
    let human = match door.plane.channel(actor, Some(&dataset)).await {
        Ok(session) => session,
        Err(e) => return plain(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };

    // The question must still stand, and its own words are what the
    // review decision records.
    let standing = match crate::frames::one_open_question(
        &human,
        &answer.subject,
        &answer.aspect,
        &answer.key,
    )
    .await
    {
        Ok(Some(standing)) => standing,
        Ok(None) => {
            // The trigger rides the refusal too: the stale tab's panels
            // re-derive to the current state on their own.
            return (
                StatusCode::CONFLICT,
                WRITTEN,
                "that question is no longer open — the page has been refreshed".to_string(),
            )
                .into_response();
        }
        Err(e) => return plain(StatusCode::INTERNAL_SERVER_ERROR, e),
    };

    let note = (!answer.note.trim().is_empty()).then(|| answer.note.trim().to_string());
    match rulings::land(
        &human,
        Ruling {
            subject: &answer.subject,
            aspect: &answer.aspect,
            dimension: &standing.dimension,
            key: &answer.key,
            assumption: &standing.assumption,
            stance,
            note,
        },
    )
    .await
    {
        Ok(_) => (StatusCode::NO_CONTENT, WRITTEN).into_response(),
        Err(e) => plain(StatusCode::UNPROCESSABLE_ENTITY, e.to_string()),
    }
}

pub(crate) fn plain(status: StatusCode, message: String) -> Response {
    (status, message).into_response()
}
