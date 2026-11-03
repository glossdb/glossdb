//! Downloads: a landed table or a served metric's relation as a file.
//! `GET /<dataset>/app/export/<name>.csv` or `.parquet`, where `<name>`
//! is a table or a metric of the dataset — a metric's grounding is a
//! view under its name. The engine writes the file with its own CSV or
//! parquet writer, under its spill directory; the door streams it out
//! and removes it when the stream ends, drained or not. Parquet keeps
//! the engine's types; CSV is text. What a file cannot answer — a read
//! of the caller's own, a filter — the Arrow door does.
//!
//! The name is an identifier and nothing else: the plan is
//! `SELECT * FROM "<name>"`, so a name the dataset does not hold is
//! the engine's refusal, with its text, not a guess of ours.

use std::path::PathBuf;

use axum::body::{Body, Bytes};
use axum::extract::{Path, State};
use axum::http::{StatusCode, header};
use axum::response::{IntoResponse, Response};
use glossql_glossary::{Actor, ActorKind};
use tokio::io::AsyncReadExt;

use crate::AppDoor;
use crate::engine::CopyFormat;

pub async fn export(
    State(door): State<AppDoor>,
    Path((dataset, file)): Path<(String, String)>,
) -> Response {
    if let Some(missing) = crate::missing(&door, &dataset).await {
        return plain(StatusCode::NOT_FOUND, missing);
    }
    let Some((name, ext)) = file.rsplit_once('.') else {
        return plain(
            StatusCode::NOT_FOUND,
            format!("`{file}` names no format — `<name>.csv` or `<name>.parquet`"),
        );
    };
    let format = match ext {
        "csv" => CopyFormat::Csv,
        "parquet" => CopyFormat::Parquet,
        other => {
            return plain(
                StatusCode::NOT_FOUND,
                format!("no format `{other}` — csv or parquet"),
            );
        }
    };
    let Some(sql) = relation_sql(name) else {
        return plain(
            StatusCode::NOT_FOUND,
            format!("`{name}` is not a table's or a metric's name"),
        );
    };
    let actor = Actor {
        kind: ActorKind::Human,
        id: "app:export".into(),
    };
    let session = match door.plane.channel(actor, Some(&dataset)).await {
        Ok(session) => session,
        Err(e) => return plain(StatusCode::UNPROCESSABLE_ENTITY, e.to_string()),
    };
    // The engine writes the whole file before a byte is on the wire, so
    // a relation it refuses is a refusal with its text, not a 200 and
    // an empty file.
    let path = match session.copy_to(&sql, format).await {
        Ok(path) => path,
        Err(e) => return plain(StatusCode::UNPROCESSABLE_ENTITY, e.to_string()),
    };
    let written = Written(path);
    let file = match tokio::fs::File::open(&written.0).await {
        Ok(file) => file,
        Err(e) => return plain(StatusCode::INTERNAL_SERVER_ERROR, e.to_string()),
    };
    (
        [
            (header::CONTENT_TYPE, mime(format).to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"{name}.{ext}\""),
            ),
            (header::CACHE_CONTROL, "no-store".to_string()),
        ],
        Body::from_stream(chunks(file, written)),
    )
        .into_response()
}

/// The plan for a name: a table quoted as spelled, or a grounding's
/// relation. Identifiers only — nothing else reaches the planner.
fn relation_sql(name: &str) -> Option<String> {
    let ident = |s: &str| {
        !s.is_empty()
            && !s.starts_with(|c: char| c.is_ascii_digit())
            && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
    };
    if let Some(aspect) = name.strip_prefix("read.") {
        let relation = aspect.to_string();
        return ident(aspect).then(|| format!("SELECT * FROM {relation}"));
    }
    ident(name).then(|| format!("SELECT * FROM \"{name}\""))
}

fn mime(format: CopyFormat) -> &'static str {
    match format {
        CopyFormat::Csv => "text/csv; charset=utf-8",
        CopyFormat::Parquet => "application/vnd.apache.parquet",
    }
}

/// The file the engine wrote, removed when the stream that reads it
/// is dropped — at its end, or when the client hangs up.
struct Written(PathBuf);

impl Drop for Written {
    fn drop(&mut self) {
        if let Err(e) = std::fs::remove_file(&self.0) {
            tracing::warn!(path = %self.0.display(), error = %e, "an export file was not removed");
        }
    }
}

/// The file as a chunked body, 64 KiB a chunk; the guard rides the
/// stream so the file outlives every chunk and nothing else.
fn chunks(
    file: tokio::fs::File,
    written: Written,
) -> impl futures::Stream<Item = Result<Bytes, std::io::Error>> {
    futures::stream::unfold((file, written), |(mut file, written)| async move {
        let mut buf = vec![0u8; 1 << 16];
        match file.read(&mut buf).await {
            Ok(0) => None,
            Ok(n) => {
                buf.truncate(n);
                Some((Ok(Bytes::from(buf)), (file, written)))
            }
            Err(e) => Some((Err(e), (file, written))),
        }
    })
}

/// A download that cannot start answers as text: the link was opened
/// in a tab, and the reason is what the tab should show.
fn plain(status: StatusCode, text: String) -> Response {
    (status, [(header::CONTENT_TYPE, "text/plain")], text).into_response()
}
