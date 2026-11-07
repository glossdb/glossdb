# Logging and monitoring

glossdb logs to stdout and, when you name a collector, exports traces
and logs over OpenTelemetry.

## What is logged

At the default level, `info`, a call is logged with its actor, its
dataset, the digest and length of its statement text, and the spans of
the work it caused. The statement text itself is logged only at
`debug`, because statements and metric definitions carry data.
Refusals are logged with their reason, never with the token. Spans
close with their busy and idle time, which gives the durations.

## The level

`GLOSSDB_LOG` is a `tracing` filter. A bare level (`debug`) sets this
server's crates to that level, the libraries to `info` and the MCP
library to `warn`. Directives (`glossdb_duck=debug,rmcp=debug`) are
taken as written. `RUST_LOG` is used when `GLOSSDB_LOG` is unset;
`info` when neither is.

## OpenTelemetry

Set `OTEL_EXPORTER_OTLP_ENDPOINT` to a collector
(`http://127.0.0.1:4318`; `/v1/traces` and `/v1/logs` are appended)
and the server also exports there: spans as traces, events as logs,
OTLP, batched. Unset, nothing is exported.

An event inside a span goes both ways: on the span, so a trace reads
whole, and as a log record carrying the span's trace and span id, so a
log line leads back to its trace.

The exporter's other variables are the SDK's own:

| Variable | Meaning |
|---|---|
| `OTEL_EXPORTER_OTLP_PROTOCOL` | the transport: `http/protobuf` (the default) or `grpc` |
| `OTEL_EXPORTER_OTLP_HEADERS` | a hosted collector's credentials |
| `OTEL_RESOURCE_ATTRIBUTES` | names the deployment beyond `service.name=glossdb` |

## Health

`GET /healthz` answers `ok` without sign-in and is not logged as a
call ([deployment](deployment.md)).
