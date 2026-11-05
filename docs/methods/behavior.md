# Behavior — stock or flow, from the evidence

`behavior_evidence` measures whether a numeric column behaves as a
stock, a level correct at a point in time, or a flow, a movement that
sums over a period. It runs at column grain
(`SELECT behavior_evidence() FROM balances.balance`) and serves a
summary: the verdict, the anchor that decided, its convention, support
and voted count, the fit of both readings (`r_flow`, `r_stock`) and
the sign partition. Every anchor reads back whole through
`GLOSSARY(table.column::behavior_evidence)`.

Summing a stock corrupts a metric silently. The metrics kit folds a
metric at a coarser grain by the `behavior` glossed on its value
column, and refuses to fold where no claim stands. This instrument is
what the judge reads before glossing that claim; it is never a voice
in the slots. A measured voice ranked against human claims would put
calibration back into the record.

## Why reconciliation, not shape statistics

A column's own trajectory cannot decide stock from flow. A trending
flow and a mean-reverting stock look alike. The evidence must be
cross-table: an independent movement per entity and period, summed
from a related event table, scored against both readings with
scale-free residuals. Flow when the level matches the movement,
`Σ|y − m| / Σ|m|`. Stock when its change does, `Σ|Δy − m| / Σ|m|`.
The reading that reconciles wins, and the loser stays visible.

An entity votes when the winning residual is under 0.05 and the loser
stands off by a third of their sum. The residual gate is the null
model: two unrelated positive series of similar size sit near 0.4 on
the flow residual, a true reconciliation under 0.01. An entity with
fewer than four periods, a level that never moves or a movement that
is all zero abstains. A convention decides an anchor when two entities
or more voted, four in five agree, and the winners are a majority of
the entities both sides carry. Wilson's lower bound over those
entities ranks the conventions; a support tie goes to the fewer terms
unless the pair's fit is decisive, ΔBIC over 10.

## Mechanism

The engine's primitive, `glossql_behavior_cells`, turns the record's
names into cells: for every alignment of the column's table with an
event table over the declared relationships, the level per entity and
day on the measure side, and each movement column's sum per entity
and day on the event side. An alignment is a declared edge between
the two tables, two edges meeting at one dimension key, or an entity
borrowed one hop: a measure table whose every edge lands on a
document keys on the document's dimension, and an event table that
aligns no other way keys through its master. A side's time axis is
its own date column, else one borrowed over an edge.

The quality kit's `behavior_anchors` screen is SQL over the cells.
It folds them to the anchor's grain, the coarser of the two sides'
native grains, with a month beside a day, and scopes by year where
the grain allows, since a cumulative that resets is a stock only
inside its year. Movement candidates are what the record says are
measures: the event table's columns whose `role` claim stands as
measure, minus the legs of declared edges, and every ordered pair
difference of them on a pool of eight terms or fewer. Nothing is
guessed from a type. An event table with numeric columns and no
measure glossed makes every anchor on it abstain with the act to
take, gloss `role` on its columns; the table's identifiers, declared
legs and key-shaped integers, ride each anchor as
`identifier_columns`. The event side is summed for the entities the
measure side carries with four days or more, so a wide, long event
table costs what the alignment needs; an alignment that aligns
nothing abstains on viability by name. One anchor per alignment and
scope reads the
measure's own shape instead: entities that never decrease over four
periods or more at the native grain vote stock under the convention
`monotone`, movers only. It is the only evidence a cumulative with
nothing to reconcile against can offer. On equal support a
reconciliation outranks it: the movement explains the level, the
monotone shape only describes it.

The summary's winner is elected by one layered rule: support first
within a billionth, then a reconciliation over the monotone reading,
then the wider vote, then the event's name. Where supports tied, the
summary names the layer that decided as `tiebreak`. Where every anchor
abstains, the summary carries the reason of the one that came
closest.

Measured on a 731,000-row event table with six movement columns and
a thousand entities, the screen answers in about a second.

## Limits

- Reconciliation needs a viable alignment: two entities or more with
  four periods or more. Where none exists the anchors abstain with
  `viable_entities`, and the column gets an abstention, not a
  verdict. A calendar gap between kept cells makes the change span it
  and read as noise; the abstention covers that miss.
- The verdict is per column against its dataset's declared edges and
  glossed roles. A table with no edge to an event table, no time axis,
  a column that is no number, or an identifier, a leg of a declared
  relationship or an integer distinct on nine filled rows in ten, is
  `applicable: false` with its reason, the counts stated exactly.
- A flow that rises every period for every entity, with no movement
  column reconciling it, reads as a stock through the monotone
  anchor. The served convention says so, and the judge reads the
  anchor before glossing.
- A column that is a stock in one ledger convention and a flow in
  another is a vocabulary question, not a measurement question. The
  sign partition says how many voters fire only under the negated
  movement, the ledger-signed reading.
