-- The plan beside one metric: every plan declared on it, period by
-- period at the plan's own grain — the planned number, the actual
-- where the period has begun, the variance (actual minus plan) where
-- the period is complete, and the forecast's median with its 80% band
-- where it covers the rest: the step's band at the metric's own grain,
-- at a coarser grain the actual to date plus the total that runs to
-- the period's end. `plan_points()` is the read; the wording, the
-- rounding and the chip's class are this frame's. Below or above: the
-- band does not hold the plan, which is what the next read's plan goal
-- asks a judgment on. A year row of a plan whose rows cover part of
-- the year says how much, and takes no band.
SELECT plan, grain, label, strftime(period, '%Y-%m-%d') AS period,
       fmt_number(value) AS planned,
       coalesce(fmt_number(actual), '—') AS actual,
       CASE
         WHEN variance IS NULL THEN ''
         WHEN variance >= 0 THEN '+' || fmt_number(variance)
         ELSE fmt_number(variance) END AS variance,
       CASE
         WHEN expected IS NULL THEN ''
         ELSE fmt_number(expected) || ' (' || fmt_number(low)
              || ' to ' || fmt_number(high) || ')' END AS expected,
       CASE stands
         WHEN 'inside' THEN 'inside the band'
         WHEN 'below' THEN 'below the band'
         WHEN 'above' THEN 'above the band'
         ELSE stands END || coalesce(', covers ' || covers, '') AS stands,
       CASE stands WHEN 'below' THEN 'warn' WHEN 'above' THEN 'warn' ELSE 'ok' END AS scls,
       coalesce(
         CAST(CAST(round(held_80 * 100) AS INT) AS VARCHAR) || '% of such bands held (' || held_from || ')',
         '') AS held
FROM plan_points()
WHERE metric = CAST($metric AS VARCHAR)
ORDER BY plan, CASE grain WHEN 'year' THEN 0 ELSE 1 END, period
