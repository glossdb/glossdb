//! A read as an Arrow IPC stream body — the one encoder behind the
//! Arrow interface and the app interface's frames.
//!
//! Encoded into a chunked body as batches arrive. The channel's
//! capacity is the backpressure: the encoder waits for the client to
//! drain. A caller polls the first batch itself, because that poll
//! runs the plan: a read the engine cannot start is a refusal with its
//! text while the status is still the caller's to set. An error after
//! bytes flowed can only break the stream — the body ends without its
//! terminating chunk, so the IPC reader on the other end sees a
//! truncated stream, which is the truth; the reason is logged here, the
//! one place it can still be read.

use arrow::datatypes::SchemaRef;
use arrow::record_batch::RecordBatch;
use arrow_ipc::writer::StreamWriter;
use axum::body::{Body, Bytes};
use futures::{SinkExt, StreamExt, channel::mpsc};

use crate::engine::{BatchStream, SessionError};

pub const ARROW_STREAM: &str = "application/vnd.apache.arrow.stream";

/// The body of `batches`, `first` being the batch the caller already
/// polled.
pub fn body(
    schema: SchemaRef,
    mut batches: BatchStream,
    first: Option<Result<RecordBatch, SessionError>>,
) -> Body {
    let (mut tx, rx) = mpsc::channel::<Result<Bytes, std::io::Error>>(2);
    tokio::spawn(async move {
        let mut writer = match StreamWriter::try_new(Vec::new(), schema.as_ref()) {
            Ok(writer) => writer,
            Err(e) => {
                let _ = tx.send(Err(std::io::Error::other(e))).await;
                return;
            }
        };
        // The schema message is written at construction — ship it first.
        if ship(&mut writer, &mut tx).await.is_err() {
            return;
        }
        let mut next = first;
        while let Some(batch) = next {
            let written = batch
                .map_err(std::io::Error::other)
                .and_then(|b| writer.write(&b).map_err(std::io::Error::other));
            if let Err(e) = written {
                tracing::warn!(error = %e, "an Arrow stream broke after bytes flowed");
                let _ = tx.send(Err(e)).await;
                return;
            }
            if ship(&mut writer, &mut tx).await.is_err() {
                return;
            }
            next = batches.next().await;
        }
        if let Err(e) = writer.finish() {
            let _ = tx.send(Err(std::io::Error::other(e))).await;
            return;
        }
        let _ = ship(&mut writer, &mut tx).await;
    });
    Body::from_stream(rx)
}

/// Drain the writer's buffer into the channel; a gone receiver (client
/// hung up) errors, the task returns, and dropping the batch stream
/// cancels the engine's work.
async fn ship(
    writer: &mut StreamWriter<Vec<u8>>,
    tx: &mut mpsc::Sender<Result<Bytes, std::io::Error>>,
) -> Result<(), ()> {
    let chunk = std::mem::take(writer.get_mut());
    if chunk.is_empty() {
        return Ok(());
    }
    tx.send(Ok(Bytes::from(chunk))).await.map_err(|_| ())
}
