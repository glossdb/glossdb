//! The shipped system, embedded at compile time — the same lockstep as
//! the teaching resources: what this build ships is what this build
//! declares. A fresh workspace receives the KPI kit (the semantic
//! vocabulary), the global measurement library, and the shipped
//! witness plane — in that order: the library's column evidence
//! conditions on the kit's `role`, and a witness names an aspect and
//! a detector that must already stand. What stays the agent's work is
//! the company's own vocabulary — metrics, validations, scenarios.

use crate::engine::Actor;

use crate::Plane;

/// Declare the shipped system into a workspace. Idempotent — every
/// boot calls it.
///
/// Nothing lands on disk: a function's body is data
/// (fixture 24), so the reference library arrives as
/// fourteen ordinary declarations and reads back through the `functions`
/// relation like anything else an agent wrote.
pub async fn bootstrap(
    _plane: &Plane,
    _actor: Actor,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    // The kits are declared when the workspace opens (`glossql_duck::Plane::open`).
    Ok(())
}
