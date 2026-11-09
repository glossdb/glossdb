---
name: glossql-prose
description: How to write prose in this repo — README, docs/, skills/, comments, console labels, agent-facing text. Plain words a data engineer already uses, the coding-harness analogy, the terms table; Hemingway rules from the project lead. Use before writing or editing any text a human or agent reads.
---

# Prose

The reader is a data engineer or a buyer who has never seen this
project. Write in the words they already use. Write like Ernest
Hemingway: short sentences, simple words, direct facts.

## The story

glossdb is a harness framework for data agents. glossql is the
language for writing data harnesses. Coding agents work inside a
harness: types, a compiler, linters, tests, CI, review. Data never had
one, because its meaning exists only in production. glossdb builds
that harness inside the database, on the live data and its versions.

| Coding harness | Data harness | glossql |
|---|---|---|
| type system | the harness schema: what must be known per dataset, table, column, metric | aspect |
| type annotations, docstrings | annotations | gloss |
| compiler error | validation on write against a JSON Schema | |
| linter | quality screens | the `quality` kit |
| unit test | a measurement, a test | function, `TEST` |
| test coverage | coverage of required annotations | `open_items`, `missing` |
| CI on every commit | recomputed on every load; stale when the data changes | |
| git history | snapshots of data and catalog together | DuckLake |
| code review | the review queue | `open_questions` |
| rule packs | kits | kit |
| the failing test that says what to fix next | next steps after every call | `next` |
| IDE | the console | |

Use the analogy where a reader needs a foothold, not on every page.

## The terms

Industry word first. Our keyword once, beside it, where the reader will
type it. Never a project word the reader cannot look up.

| Write | Not | Our keyword, where it is real |
|---|---|---|
| interface, endpoint (MCP interface, query endpoint) | door | |
| console | docket | the `console` path |
| review decision | ruling | |
| review queue | open questions, the round | `open_questions` |
| missing, required; coverage | owed | `open_items` |
| metric definition | grounding | |
| load | landing, land | `IMPORT` |
| load query | recipe (in prose) | `RECIPE` |
| the catalog | the record, the store | `glossql_*` tables |
| value, annotation | slot, voice | |
| provenance, inputs | pin, reads, legs | `pin`, `reads` columns |
| confidence | band | `band` column |
| time grains | time_grains | |
| is current, holds | stands | |
| next steps | routes | `next` |
| asset (a dataset, table, column) | — | subject, in the grammar |
| annotation; annotate | — | `GLOSS` |
| the glossary | — | `GLOSSARY()` |
| property of the harness schema | — | `ASPECT` |
| test | witness | `DECLARE TEST` |
| test results | attestation | `TESTS()` |
| view (a metric, a scalar, a derived relation) | query aspect | kind `VIEW` (`AS VIEW`); `x-kind: scalar` for a single value |
| preview, dry run | probe | `PREVIEW` |

Name the statement where the reader will type it, once: "a test
(`DECLARE TEST`)", "a view aspect (`AS VIEW`)". Do not repeat the
keyword as its own explanation: not "a test (`TEST`)".

## The rules

- Cut the fat. Delete every word that does not do work.
- Use active verbs. The server processes the request.
- Keep sentences short. Say one thing. Then say the next thing.
- Use simple words. Say "send", not "utilize transmission protocols".
- Show the code. Let the code speak.
- No drama. The answer is stored. It does not "join the record". A
  fixture was checked. It did not "survive".
- No house idioms. Not "what stands", "speaks", "lands", "the
  record", "owed", "the X's Y of Z". Say what happens, in the words
  above.
- Define by what it does, never by other terms of ours. Bad: "a
  disclosed grounding assumption held below full confidence".
  Good: "an assumption in a metric definition that a person should
  confirm".
- Write for the reader, not the project. No history, no research
  notes, no "not built on purpose", no "proof of concept". Status is
  per feature: stable, preview, planned.

## What stays

- Precision beats brevity. The docs pages are served to agents as
  context (`doc://docs/…`). A rewrite must not drop a constraint, a
  condition, or a definition. When unsure, keep the sentence and
  change only its words and grammar.
- When editing near old prose, rewrite it in these words. Do not match
  it.

## Hard limits

- Do not edit fenced code blocks or tables in a prose pass. The test
  suite parses and plans every ```glossql and ```sql block under
  `docs/` and `skills/`, and parses the served SPEC.md's.
- Keep every H1 unless the change is a page move. The MCP interface
  serves each docs page as a resource titled by its H1.
- `docs/reference/reads.md` keeps its path and the literal
  `metric_summary()`: an interface test asserts both.
- Workspace `cargo test` green after any docs change.

## Example

Bad: "At the MCP door the round rides the agent's own calls; the
answer lands as a ruling with human standing."

Good: "The review queue comes back with the agent's calls. A person
confirms or corrects each assumption. The decision is stored as the
person's annotation and outranks the agent's."
