# The harness plan

glossdb's surface works: agents load data, write views and apps, and
the review loop (an assumption, a person's decision, the definition
recorded again) is the strongest part, with the history behind it.
What is weak is the guidance. `next` is a ladder of steps per goal
built on coverage rules, so it counts chores (a meaning on every
column a metric reads) and misses the risks that break a number (a
join that fans out, an effective-dated table joined without its
dates). Agents and people cannot tell what can be done, why, or when.
This plan replaces that guidance with a risk register and shortens the
path from a metric's SQL to a served metric. The target is less code
and fewer rules than today, not more.

Today `next` is 56 step arms across `kits/goals`, `kits/metrics` and
`kits/outlook`, plus the brief, review and situation lines built in
`crates/serverd/src/mcp.rs` and `window.rs`.

## The table

| Row | Risk | What it touches | Issue |
|---|---|---|---|
| 0. Smoke-test fixes: `*` reads tables only, so a new view leaves `*` measurements current; cardinality from both sides; an unknown function on a column refuses by name; a dataset is not offered another dataset's metric | Low | extension `src/glossql_store.cpp`, `src/glossql_runner.cpp`, `kits/quality`; `kits/metrics` here | glossql #20, glossdb PR |
| 1. The risk register: per served metric, the risks its lineage carries, each with the check that settles it and a state (checked, accepted by a person, open). Replaces the step arms, the brief's counts and `workspace_next`'s open column; coverage becomes an optional figure. Prototype on `hr` and two glossval seats before rewriting the kits | High: the core of what agents read; the route and door suites assert today's steps | `kits/goals`, `kits/metrics`, `kits/outlook`, `kits/core` (`workspace_next`, `open_items`), `crates/serverd/src/mcp.rs`, `window.rs`, the routes suite | drafted below |
| 2. Effective-dated tables: a property in the metrics kit (`valid_from`, `valid_to`, the open-end value), and the risk "joined without its dates" in the register | Medium: a new property and one detector | `kits/metrics`, the register | after 1 |
| 3. A metric definition carries its time column, measure with behaviour, and dimensions inline; a person's decision is applied by the server, not re-sent by the agent | Medium: the GLOSS body's schema, `metric_axes()`, the review path | `kits/metrics`, `kits/core`, `crates/duck/src/rulings.rs`, the skills | after 1 |
| 4. The console: a Semantic model view (entities with grain, identity and time axis, relationships, the metrics on them with definitions and decisions) and a Lineage view (sources, load queries, tables, views, metrics at column level, loads over time), linked by object | Medium | `crates/apps/builtin/console/` | after 2 |
| 5. The skills streamlined around the register: what can be done, why, when, in the prose skill's words | Low | `skills/` | after 1 |

## Row 1: the register

A risk is derived from what exists, never from a coverage rule. Each
names its check, a function or a test, and a person can accept it.

| Risk | Derived from | Settled by |
|---|---|---|
| a join fans out | a metric's lineage joins along an edge whose target repeats the key | the relationship's cardinality and a row-count check |
| a stock summed over time | a measure with no behaviour, read at a coarser grain | `behavior_evidence()`, or the behaviour annotated |
| an effective-dated table joined without its dates | row 2's property on a table the metric reads | a check on the join predicate |
| a placeholder value | a profile's top values or extremes in a date or measure column the metric reads | `column_profile()`, then the load query or an assumption |
| a partial last period | the metric's last period against its table's last load | `temporal()` |
| orphaned keys | a declared edge the metric reads | `relationship_coherence()` |
| drift since the last test | a load after the test's last result | `TESTS()` |
| a judgment call | an assumption below full confidence | the review |

What leaves: the per-goal step ladders where a risk covers them, the
coverage counts in `open`, the claim and cadence ceremonies row 3
removes.

Draft issue, row 1:

> **next: a risk register per served metric instead of step ladders.**
> What it buys: the agent and the person see what can break each
> number and what settled it; `open` counts open risks, not
> annotations missing. What is there: the step arms (`kits/goals/kit.sql`,
> `routes_metrics()` at `kits/metrics/kit.sql:437`, `routes_outlook()` at `kits/outlook/kit.sql:1203`),
> `workspace_next` and `open_items` (`kits/core/kit.sql`), the brief
> (`crates/serverd/src/mcp.rs:34`, `:1250`), the line
> (`crates/serverd/src/window.rs:117`). Done when: a read lists the
> risks per metric with check and state on `hr` and two glossval seats;
> `next` and the brief read from it; the step arms it replaces are
> deleted; the suites hold.

## Not in this plan

- Backlog issues: the workspace as code, an optional `references` kit,
  the dbt importer together with reading in place.
- A short form for data tests is a language question: a corpus fork in
  the extension, SPEC §9.
- How a bare name resolves when it is both a table of the bound dataset
  and another dataset or a source: a ruling for the lead.
