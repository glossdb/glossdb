# Validations — read when a number needs a check that says why it holds

## Set up validations

The authored expectation is a FACT annotation; the check is a
function's measurement on the same aspect; a detector scores the two
values against each other; `ATTEST` shows the result.

```glossql
DECLARE ASPECT hours_reconcile WITH $${
  "type": "object", "required": ["outcome"],
  "properties": {"outcome": {"type": "string"}, "tolerance": {"type": "number"},
                 "breach_rate": {"type": "number"}}
}$$ AS FACT ON TABLE WHEN entity = 'work log line';
DECLARE WITNESS hours_w ON hours_reconcile BY (AGENT, HUMAN)
  DETECTOR rate_tolerance THRESHOLD 0.0;
GLOSS hours_reconcile ON work_logs AS $${
  "outcome": "Logged minutes match the order's recorded duration, exactly.", "tolerance": 0.0}$$;
```

- **The test (`WITNESS`) first, and its `BY` list names every actor.**
  A test on the aspect controls who may write it: an agent annotating
  the expectation itself must be in `BY`, or the annotation is
  refused. Declare it before the annotation, `BY (AGENT, HUMAN)`.
- **A number the check measures is omitted until the check runs,
  never null.** `breach_rate` is the measurement's field; the expectation
  carries `outcome` and `tolerance`. The schema types every property
  and null is not a number — the same for any property you cannot
  fill: leave it out.
- **Scope the check with `WHEN`.** A check declared bare `ON TABLE`
  requires a value on every table in the workspace, each an
  unassessed row — a handful of unscoped checks fills the backlog
  with rows nobody can fill.
- **`breach_rate` is the violation share.** 0.0 is fully passing, and
  it is compared against `tolerance` upward. Reporting a pass rate
  under that key bands red.
- **The expectation is the rate you measured, never an assumed zero.**
  Nobody knows a source's defects in advance. You measured them at
  load; author that rate as the tolerance, so the check is green
  today and red when the source drifts. A check reporting 0.0 where
  the profile showed dirt does not see the dirt — fix the check's SQL.
  The console's Quality tab is where the person sees both: what each
  load dropped and nulled, and every check with its band.
- **Promote confirmed reconciliations.** A data test that settled a
  behaviour claim — an event table's movements reconciling with a
  level — is a permanent invariant; make it a check.
- **A window has two bounds.** A readmission, a return, a repeat
  within N days tests the next event against both ends: after the
  index event and inside the window. Probe the rows that pass with a
  negative interval — an event that begins inside the index event
  counts when only the upper bound is tested.
- **Promote basis claims.** An assumption in a metric definition whose
  basis names a second route to the number — "ties to GL 4* net" — is
  a reconciliation in prose. Author the route as the check's
  measurement and score its residual against the served frame; the
  claim then runs again whenever the data version moves instead of
  drifting from the SQL it describes.

**The check half is a function, and you write it here** — the body
is part of its declaration, so an expectation without a measuring
function is a choice rather than a limit. `glossql-functions` has the
contract and the abstention rule; `rate_tolerance` is the detector
that scores an authored expectation against a check's measurement:

```glossql
DECLARE FUNCTION hours_reconcile_check FOR ops AS $$
  SELECT 'measured: logged minutes against recorded durations' AS outcome,
         CASE WHEN count(*) = 0 THEN 0.0
              ELSE CAST(count(*) FILTER (WHERE abs(logged - recorded) > 0.5) AS DOUBLE) / count(*)
         END AS breach_rate
  FROM (SELECT order_id, sum(minutes) AS logged, max(duration_min) AS recorded
        FROM work_logs GROUP BY order_id)
$$ RETURNS hours_reconcile;
```

A measurement uses the aspect's own schema — `outcome` like any
annotation, the measured number beside it. One schema, every actor.
