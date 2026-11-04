//! A human's ruling landed as a gloss: the standing ruling body on the
//! subject, the entry for the key replaced, the body re-glossed under
//! human standing. The statement is the language's; this module only
//! shapes the body.

use crate::{Session, SessionError, rows_as_text};

/// One ruling as the app door takes it.
pub struct Ruling<'a> {
    pub subject: &'a str,
    pub aspect: &'a str,
    pub dimension: &'a str,
    pub key: &'a str,
    pub assumption: &'a str,
    /// `confirmed`, `corrected`, or `unclear`.
    pub stance: &'a str,
    pub note: Option<String>,
}

fn ident_path(text: &str, max_segments: usize) -> bool {
    let segments: Vec<&str> = text.split('.').collect();
    !segments.is_empty()
        && segments.len() <= max_segments
        && segments.iter().all(|s| {
            !s.is_empty()
                && s.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
                && !s.starts_with(|c: char| c.is_ascii_digit())
        })
}

/// Land `ruling` on the human's channel.
pub async fn land(human: &Session, ruling: Ruling<'_>) -> Result<String, SessionError> {
    let Ruling {
        subject,
        aspect,
        dimension,
        key,
        assumption,
        stance,
        note,
    } = ruling;
    if !ident_path(subject, 3) {
        return Err(SessionError::shape(
            subject,
            format!("`{subject}` is not a path subject (identifier segments, dots between)"),
        ));
    }
    if !ident_path(aspect, 1) {
        return Err(SessionError::BadAspectName(aspect.to_string()));
    }
    let dataset = human.dataset().ok_or(SessionError::NoDataset)?;
    let qualified = if subject.starts_with(&format!("{dataset}.")) || subject == dataset {
        subject.to_string()
    } else {
        format!("{dataset}.{subject}")
    };
    let standing = human
        .batches(
            &format!(
                "SELECT body::VARCHAR FROM {}.main.glossary \
                 WHERE dataset = '{dataset}' AND subject = '{qualified}' AND aspect = 'ruling' AND actor_kind = 'human' \
                 ORDER BY seq DESC LIMIT 1",
                crate::LAKE
            ),
            &[],
        )
        .await?;
    let mut body = rows_as_text(&standing)
        .first()
        .and_then(|r| r.first().cloned().flatten())
        .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
        .unwrap_or_else(|| serde_json::json!({ "rulings": [] }));
    let Some(rulings) = body.get_mut("rulings").and_then(|r| r.as_array_mut()) else {
        return Err(SessionError::RulingSlotNotRulings);
    };
    rulings.retain(|r| !(r["aspect"] == aspect && r["key"] == key));
    let mut entry = serde_json::json!({
        "aspect": aspect,
        "dimension": dimension,
        "key": key,
        "assumption": assumption,
        "stance": stance,
    });
    if let Some(note) = note {
        entry["note"] = serde_json::json!(note);
    }
    rulings.push(entry);
    let body = body.to_string();
    if body.contains("$$") {
        return Err(SessionError::DollarQuotedBody);
    }
    human
        .execute(&format!("GLOSS ruling ON {subject} AS $${body}$$"))
        .await
        .map(|_| {
            if stance == "unclear" {
                format!(
                    "ruled (unclear) on `{key}` — the question missed: \
                     reformulate the assumption in `{aspect}` under a new \
                     key and re-record; the clearer wording derives its \
                     own question"
                )
            } else {
                format!(
                    "ruled ({stance}) on `{key}` — the fold-in is yours: \
                     re-record `{aspect}` carrying that key, citing the ruling"
                )
            }
        })
}
