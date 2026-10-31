//! One test binary for the crate: every file beside this one is a
//! module of it. A binary per file would link datafusion once more
//! each — half a gigabyte and a link step per file — and run its
//! tests in a process of its own, one process after another; one
//! binary links once and runs them all concurrently.

// The shipped system's landing and the judge pattern run the session
// engine's runtime; the DuckDB build declares its kits at open.
#[cfg(not(feature = "duck"))]
mod bootstrap;
mod common;
mod conformance;
mod docs;
mod doors;
// The routes on the DuckDB engine, read through the bound agent door.
#[cfg(not(feature = "duck"))]
mod judge;
#[cfg(feature = "duck")]
mod routes;
// The routes read the record through the session engine's shipped
// reads over tables landed in memory; the DuckDB build ports them in a
// later step.
#[cfg(not(feature = "duck"))]
mod next;
mod skills;
