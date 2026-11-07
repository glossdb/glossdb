# How glossdb works

Coding agents work inside a harness. Types say what a value is. The
compiler rejects what does not fit. Linters and tests find what is
wrong. CI runs them again on every change. A reviewer decides what the
tools cannot. The agent knows where it stands because the harness
tells it.

Data has none of this. A column called `amount` does not say whether
it is net of tax, a balance or a movement, or which currency it is in.
No query fails when an agent guesses. The meaning lives in people's
heads and in production, not in the rows.

glossdb builds the harness for data, inside the database. It runs on
the live data and its versions, because that is the only place data
can be tested.

## The parts, side by side

| Coding harness | Data harness | In glossql |
|---|---|---|
| type system | the harness schema: what must be known about each dataset, table, column and metric | `ASPECT` |
| type annotations, docstrings | annotations: what one row is, a column's unit, a measure's additivity | `GLOSS` |
| compiler error | validation on write against the aspect's JSON Schema | |
| linter | quality screens: keys, joins, hierarchies, stock or flow | the `quality` kit |
| unit test | measurements and tests on the data | `FUNCTION`, `WITNESS` |
| test coverage | coverage of required annotations | `GLOSSARY()` state `unassessed` |
| CI on every commit | results tied to the data version they read; stale when it changes | |
| git history | snapshots of the data and the catalog together | DuckLake |
| code review | the review queue: a person decides | `open_questions` |
| rule packs | kits: a domain's schema, measurements and tests | `kits/` |
| the failing test that says what to fix | next steps after every call | `next` |
| IDE | the console | `/<dataset>/app` |

## Each part

**The harness schema.** An aspect is one property the harness asks
for, such as a column's unit or a table's grain. It has a JSON Schema
for its values, the assets it applies to, and a condition for when it
is required. An aspect is asserted (`FACT`), computed
(`MEASUREMENT`), or a view (`QUERY`): a metric definition, a scalar,
or a derived relation. See [aspects](../usage/describing-data.md).

**Annotations.** A gloss is one actor's value for one aspect on one
asset. It is validated against the aspect's schema when it is written,
and stored with its actor and the data snapshot it describes. A value
that does not fit the schema is refused, as a compiler refuses a type
error. See [validation](../usage/data-tests.md).

**Measurements.** A function is one SQL query that measures the data:
profiling, relationship discovery, derivation tests, stock-or-flow
evidence. Its result is stored with the versions of everything it
read. It is reused while those are unchanged, and runs again once they
change. See [measurements](../usage/measurements.md).

**Tests.** A test (`WITNESS` in the grammar) is declared on one
aspect. It collects every value for that aspect on an asset: the
measurements, the agent's annotation, a person's annotation. A
detector function scores how far they agree, and returns a band
(green to red) and a score. When the score crosses the threshold and
the values differ, the glossary marks the asset `contested`.
`ATTEST()` returns the results. Tests run when they are read and never
write into the data.

**Coverage.** Every required aspect that nobody has annotated is
`unassessed` in `GLOSSARY()`. Coverage, conflicts, failing tests and
open questions are the agent's score.

**Versions.** The workspace is a DuckLake. Every load is a snapshot.
An annotation carries the snapshot it was written at and reads as
`stale` once its column changes. History is the lake's.

**Review.** An assumption in a metric definition held below full
confidence becomes a question for a person. The person answers in the
console or in the agent's client. The answer is stored as the
person's annotation and outranks every agent's. See
[questions](../usage/review.md).

**Kits.** A kit packages a domain's aspects, measurements and tests,
with a skill that teaches an agent its words. The `kpi` kit is the
semantic layer's vocabulary; the `quality` kit holds the screens. See
[the KPI kit](../reference/kpi-kit.md) and [kits](../extending/kits.md).

**Next steps.** Every result over MCP ends with a `next:` line: one
action per goal (structure, metrics, slices, bands, checks, app, plan,
rulings), each filled from the catalog. The agent does not need the
chat history to know what is left. See [reads](../reference/reads.md).

**The console.** People see the same catalog in the browser: the
review queue, metrics, quality, a page per table and column, lineage,
export and a query pane. See [the console](../usage/console.md).

Words used here and their industry names: [terms](terms.md).
