# Vocabulary — read before glossing a column: role first, additivity by evidence

## Annotate the columns — role first

Read the measurements before you annotate. Relevance is conditional: a
column needs `additivity` and `unit` only once its `role` says `measure`,
and `dimension` only on `role = 'dimension'` — so annotate role first
and the rest of the backlog follows from it.

- **meaning** — one sentence, specific to the business, saying what
  the column contains and how it is used; `term` is the name a report
  would print. Never state summability here — that judgment has one
  place.
- **role** — `key` · `measure` · `dimension` · `timestamp` ·
  `attribute`, judged from this table alone. Never call a column a
  foreign key here; references are `DECLARE RELATIONSHIP`.
- **additivity** — measures only. `semi-additive` (a stock) is a carried point-in-time
  level that must not be summed across periods; `additive` (a flow) accumulates;
  `ratio` re-divides its summed halves, `numerator` and `denominator`
  naming them; `non-additive` does not combine. A column's own trajectory
  cannot decide this — a trending flow and a mean-reverting stock
  look alike — so read the column's meaning and the table's grain:
  what one row is, and whether two rows of one period add up to
  something. Names lie either way — a column called "total" can
  carry a per-period movement. Say the grounds in the annotation. The
  annotation is used: a metric's series combines rows by the
  `additivity` on its value column and refuses while there is none.
- **unit** — where a magnitude has one; `source_column` names the
  column carrying it when it sits beside the value.

**When the meaning does not settle it** — a column whose rows could
be levels or movements — test it against the data: a related event
table whose period movements reconcile with the column's deltas says
stock, with the column's own values says flow; cite that test as the
basis. On an installation where a whole family of columns needs it,
author a workspace-scoped function that decides additivity the way
*this* dataset demands. That function is the installation's written-down
thinking — versioned, re-runnable, honest about its method. Not
willing to go that far? Don't annotate: absence shows as an honest
`missing` row, a guess does not.

"Does not apply" *within* relevance is still a judgment: a ratio is a
measure with no stock/flow nature, and that is stored as
`{"value": "non-additive", "grounds": "…"}`, never as a permanent missing
row.
