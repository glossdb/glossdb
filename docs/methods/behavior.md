# Stock or flow

`behavior_evidence` measures whether a numeric column behaves as a
stock or a flow. A stock is a level that is correct at a point in time,
such as a balance. A flow is a movement that sums over a period, such
as sales. It runs on a column
(`SELECT behavior_evidence() FROM balances.balance`) and returns a
summary:

- the reading that won, and the anchor that decided it, with its
  convention, support and number of votes;
- the fit of both readings (`r_flow`, `r_stock`);
- the sign partition.

Every anchor can be read in full through
`GLOSSARY(table.column::behavior_evidence)`.

Summing a stock corrupts a metric silently. The metrics kit rolls a
metric up to a coarser grain by the `behavior` annotated on its value
column, and refuses where none is annotated. This measurement is what
the agent reads before writing that annotation. It never counts as a
value in its own right: ranking a measured value against people's
statements would bring calibration back in
([candidates and judgment](judge.md)).

## What it answers

A column's own history cannot tell a stock from a flow: a trending flow
and a mean-reverting stock look alike. The evidence has to come from
another table. glossdb takes an independent movement per entity and
period, summed from a related event table, and scores both readings
with scale-free residuals:

- **Flow** when the level matches the movement: `Σ|y − m| / Σ|m|`.
- **Stock** when the change in level matches it: `Σ|Δy − m| / Σ|m|`.

The reading that reconciles wins, and the other stays visible.

## How a reading is decided

- **An entity votes** when the winning residual is under 0.05 and the
  losing one is off by a third of their sum. The residual limit is the
  null model: two unrelated positive series of similar size sit near
  0.4 on the flow residual, a true reconciliation under 0.01.
- **An entity abstains** when it has fewer than four periods, a level
  that never moves, or a movement that is all zero.
- **A convention decides an anchor** when at least two entities voted,
  four in five agree, and the winners are a majority of the entities
  both sides carry.
- **Conventions are ranked** by Wilson's lower bound over those
  entities. A tie in support goes to the one with fewer terms, unless
  the pair's fit is decisive (ΔBIC over 10).

## How it works

**Cells.** The engine function `glossql_behavior_cells` turns the
catalog's names into cells. For every way the column's table aligns
with an event table over the declared relationships, it returns the
level per entity and day on the measure side, and each movement
column's sum per entity and day on the event side. Tables align by:

- a declared relationship between the two tables;
- two relationships meeting at one dimension key;
- an entity borrowed one hop away: a measure table whose every
  relationship lands on a document keys on the document's dimension,
  and an event table that aligns no other way keys through its master.

A side's time axis is its own date column, else one borrowed over a
relationship.

**Anchors.** The quality kit's `behavior_anchors` screen is SQL over the
cells.

- It rolls them up to the anchor's grain, the coarser of the two
  sides' grains (a month beside a day). It scopes by year where the
  grain allows, since a running total that resets each year is a stock
  only inside its year.
- Movement candidates are what the catalog says are measures: the event
  table's columns annotated with `role` measure, minus the columns of
  declared relationships, and every ordered difference of two of them,
  on a pool of eight terms or fewer. Nothing is guessed from a type.
- An event table with numeric columns and no measure annotated makes
  every anchor on it abstain, naming the action to take: annotate
  `role` on its columns. The table's identifiers (relationship columns
  and key-shaped integers) are listed on each anchor as
  `identifier_columns`.
- The event side is summed only for the entities the measure side has
  on four days or more, so a large event table costs what the
  alignment needs. An alignment that matches nothing abstains, saying
  so.
- One anchor per alignment and scope reads the measure's own shape:
  entities that never decrease over four or more periods at the native
  grain vote stock under the convention `monotone`, counting only
  entities that move. It is the only evidence a running total with
  nothing to reconcile against can give. On equal support a
  reconciliation outranks it: the movement explains the level, the
  shape only describes it.

**The summary.** The winner is chosen by one layered rule: support
first (within a billionth), then a reconciliation over the monotone
reading, then the wider vote, then the event table's name. Where
supports tied, the summary names the layer that decided as `tiebreak`.
Where every anchor abstains, the summary carries the reason of the one
that came closest.

On a 731,000-row event table with six movement columns and a thousand
entities, the screen answers in about a second.

## Limits

- Reconciliation needs a viable alignment: at least two entities with
  at least four periods. Where none exists the anchors abstain with
  `viable_entities`, and the column gets an abstention, not a reading.
  A calendar gap between kept cells makes the change span the gap and
  read as noise; the abstention covers that case.
- The reading is per column, against its dataset's declared
  relationships and annotated roles. These return `applicable: false`
  with the reason and exact counts:
  - a table with no relationship to an event table;
  - a table with no time axis;
  - a column that is not a number;
  - an identifier: a relationship column, or an integer distinct on
    nine filled rows in ten.

  The refusal is a measurement row like any other: reused while the
  table it counted and the catalog rows it read are unchanged,
  computed again when one changes.
- A flow that rises every period for every entity, with no movement
  column reconciling it, reads as a stock through the monotone anchor.
  The returned convention says so, and the agent reads the anchor
  before annotating.
- A column that is a stock in one ledger convention and a flow in
  another is a vocabulary question, not a measurement. The sign
  partition says how many votes appear only under the negated
  movement, the ledger-signed reading.
