//! The actor: who a connection speaks as (SPEC.md §1). Every write the
//! engine lands is stamped with it; there is no BY clause anywhere. The
//! doors read it off the gate and hand it to the engine with the call.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActorKind {
    Agent,
    Human,
}

impl ActorKind {
    pub fn as_str(self) -> &'static str {
        match self {
            ActorKind::Agent => "agent",
            ActorKind::Human => "human",
        }
    }
}

impl std::fmt::Display for ActorKind {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(self.as_str())
    }
}

/// The connection's actor: the kind the door it came through says, the
/// id the token says.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Actor {
    pub kind: ActorKind,
    pub id: String,
}
