# glossql — workspace rules

The context language and its server. The server ships: a brew tap and
an image on GHCR, both cut at the workspace version. Grammar changes
follow the corpus-first process below.

## The map

- `SPEC.md` — the only normative language prose. Open questions live
  in §9 and close by transcription verdict, never by argument.
- `grammar.ebnf` — the machine-readable grammar; the source of truth
  for syntax.
- The routes the `next` read answers from: per goal, its steps as
  query arms over the record, one act per goal as a statement filled
  from the record — each kit's `routes_<kit>()` in the extension's
  `kits/`, the core's in `crates/duck/kits/door.sql`, composed at
  open; the door's two lines, `crates/serverd/src/window.rs`.
- `corpus/` — transcriptions of real artifacts, the language's
  acceptance record: ` ```glossql ` must parse, ` ```glossql-gap `
  documents a gap and must fail. It moves to the extension's
  repository with SPEC.md and the grammar, where the parser is.
- `crates/` — the server, a Cargo workspace: `duck` ·
  `apps` · `serverd`. What each is and how it is built: the crate
  headers and `docs/architecture/`. Directories unprefixed, packages
  `glossql-*`; the engine is the gloss extension (`../gloss`, pinned
  by `crates/duck/gloss.ref`) on DuckDB, compiled into every binary,
  and its kits are SQL in that repository, loaded at open; the arrow
  line is one (the workspace `Cargo.toml` comment).
- `docs/` — the curated statement of the system: what is implemented
  and what is planned (`start/`, `concepts/`, `reference/`,
  `methods/`, `architecture/`, and the concern pages). For agents and
  humans alike; enterprise-customer quality, constantly current.
  Never normative language prose.
- `.github/` — `workflows/ci.yml` checks the standing invariant on
  every push and pull request, with `deny.toml`, on the extension
  built from its pinned commit and kept in the actions cache; the
  release machinery: `workflows/release.yml` builds the image on a
  `v*` tag, `release-macos.sh` is the laptop half, the rendered tap
  formula sits beside them. The order and its sharp edges: the
  glossql-release skill.
- `skills/` — the product skills, a `SKILL.md` and its `references/`
  each, where a door-connected agent learns the language; embedded in
  serverd and served on the MCP door as resources and prompts, gated
  by the test suite. `.claude/skills/` keeps the skills for building
  the server: the substrate, the prose and the release.
- `vendor/` — DuckDB's SQL guide for the release the lock resolves,
  served on the door as `doc://vendor/duckdb/sql/…`.
  `vendor/duckdb/refresh.sh <version> <duckdb-web commit>` at every
  pin move; the serverd suite holds its VERSION to Cargo.lock.

## The record: issues, code, docs

GitHub issues (`glossdb/glossql`) are the work record. One issue is
one actionable unit at a uniform depth: what it buys, what stands
(`file:line`, fixtures), done-when. Apache Software Foundation
quality, and public: facts only — no session narrative, no run
anecdotes, no actor names, nothing private, no other vendor's product
as a reference point. Labels stay small: `bug` · `ruling-candidate` ·
`upstream` · `debt` · `docs`. Grammar and language questions never
become issues — SPEC.md §9 keeps that role.

Code and its comments are the source of truth for what is implemented
and live. A comment states a standing constraint or behavior the code
cannot show — never history, never a run anecdote.

Docs state what the system is and what is planned — never what was
rejected, reversed, or not built. Git history is the time machine;
what is written is the rule — no "ruled [date]" stamps anywhere.

Roadmapping is ad hoc within a phase: when an issue closes, the
project lead picks the next one or bundles a few in a session. The
kernel plan, `.claude/plans/kernel.md`, holds the evaluation behind
`docs/architecture/kernel.md` — what each element touches, how hard
it is, which phase — and is read when picking. It links its issues
and shrinks as they close; it is never loaded unasked.

A plan file is a table first: element, risk, what it touches, when,
issue. Build order is risk order. Under 150 lines. It states what
stands and what is next, never what was rejected and never a date.
It drafts an issue only for its next row, in the issue form; the
draft leaves when the issue opens. When the direction moves, the
plan is rewritten, not patched.

## Ground rules

- **Code is the work.** A task on the server ends in changed code and
  a passing suite. The rules under "The language" bind `SPEC.md` and
  `grammar.ebnf`; they do not gate server code.
- **Standing invariant.** Workspace `cargo test` passes: every fenced
  example under `docs/`, `skills/`, and `.claude/skills/` parses on
  the engine's grammar and every single read binds, and the door
  suites hold the execution semantics; the kits' own suites run in
  the extension's repository, and the corpus runs there once the
  language's record moves. A change that breaks it doesn't land.
- **Build on the engine.** A read, a measurement, a route is SQL in a
  kit; the extension owns the language and the record; the server
  owns the doors. Extend DuckDB and the extension at their own seams,
  never around them; the glossql-substrate skill carries the seam
  register and its rules.
- **Grounding.** The corpus fixtures are the empirical record;
  coverage and semantics questions settle against this repo's own
  code and runs.

## The language

- **One document.** SPEC.md is the only normative prose — no
  satellite design docs, no assumption files, no per-topic notes.
- **Ideation before prose.** No idea enters SPEC.md until it survives
  a corpus test: competing statement forms for the same real
  artifact, checked against grammar and real table shapes, the forks
  presented to the project lead. The surviving fork becomes a SPEC.md
  diff that shrinks or holds the spec, never grows it by essay.
- **Design authority.** The language has a single owner: the project
  lead. Every grammar change is reviewed by them; propose as SPEC.md
  edits with rationale — the grammar never drifts through
  implementation convenience. Sober voice everywhere: definition
  before significance, claims sized to named mechanisms, no selling.
