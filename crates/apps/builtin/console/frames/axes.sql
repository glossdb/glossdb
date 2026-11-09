-- The metric's fact row: what the catalog says its columns are and
-- whether a series can be served — the floor its cells stand at (the
-- time_grains's, else the measured cadence; served as `resolution` for the
-- window control), the rung at that floor, the additivity, the slices,
-- and the reason where it serves none. Record-class: a gloss on the
-- view's columns refreshes it.
SELECT metric, applicable,
  coalesce(reason, '') AS reason,
  coalesce(additivity, '') AS additivity,
  coalesce(floor, '') AS resolution,
  coalesce(CAST(rung AS VARCHAR) || ' ' || floor || 's', '') AS window,
  coalesce(array_to_string(dims, ' · '), '') AS dims,
  '' AS bucketed,
  '' AS alternative,
  CASE WHEN applicable AND additivity IS NULL THEN 'no additivity is annotated on ' || value_column || ': a coarser grain and a total over members wait on it'
       ELSE '' END AS alternative_error
FROM metric_summary()
WHERE metric = CAST($metric AS VARCHAR)
