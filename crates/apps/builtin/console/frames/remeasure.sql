-- One row while a measurement the metrics read is missing or out of
-- date (`results_due(preview := true)`): the server computes the others
-- after each write, so a row here is a preview measurement, which calls
-- the model service, or one that could not be computed. Catalog-class:
-- the banner appears with the write that caused it and clears when
-- re-measure lands.
SELECT count(*) AS n,
       string_agg(DISTINCT function, ', ' ORDER BY function) AS functions,
       count(*) || ' measurements are missing or out of date (' || string_agg(DISTINCT function, ', ' ORDER BY function)
         || ') — the numbers are current; the column roles, the slices and the test results may not be.' AS hint
FROM results_due(preview := true)
HAVING count(*) > 0
