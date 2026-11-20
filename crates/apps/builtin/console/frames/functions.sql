-- The overview's five functions of data intelligence, one row each,
-- with the question each answers. `have` is what exists, from the
-- catalog. `open` is what `next` lists as must or should for the kind
-- of work that belongs to the function, so the page and the agent read
-- the same list. Lineage has no work of its own: it results from the load
-- queries and the definitions. `link` opens the function's page.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d),
todo AS (SELECT kind AS work, who, count(*) AS n FROM next WHERE level <> 'could' GROUP BY ALL),
recipe AS (
  SELECT r.table_name, r.source FROM recipes r JOIN d ON d.dataset = r.dataset
  QUALIFY row_number() OVER (PARTITION BY r.table_name ORDER BY r.begin_snapshot DESC) = 1),
load AS (
  SELECT i.table_name, i.imported_at FROM imports i JOIN d ON d.dataset = i.dataset
  QUALIFY row_number() OVER (PARTITION BY i.table_name ORDER BY i.begin_snapshot DESC) = 1),
said AS (
  SELECT count(*) FILTER (WHERE state <> 'missing') AS written,
         count(*) FILTER (WHERE state = 'stale') AS outdated
  FROM GLOSSARY()
  WHERE property IN (SELECT name FROM properties WHERE upper(kind) = 'FACT')),
rel AS (SELECT count(*) AS n FROM relationships r JOIN d ON d.dataset = r.dataset),
t AS (
  SELECT count(*) AS n,
         count(*) FILTER (WHERE state = 'green') AS green,
         count(*) FILTER (WHERE state = 'red') AS red,
         count(*) FILTER (WHERE state IN ('orange', 'yellow')) AS amber,
         count(*) FILTER (WHERE state = 'error') AS errors
  FROM TESTS()),
q AS (
  SELECT (SELECT count(*) FROM open_questions o JOIN d ON d.dataset = o.dataset) AS waiting,
         (SELECT count(*) FROM review_decisions r JOIN d ON d.dataset = r.dataset) AS decided),
traced AS (
  SELECT count(*) FILTER (WHERE source IS NOT NULL) AS traced, count(*) AS n
  FROM (SELECT view, target_column, max(source_column) AS source FROM column_mapping()
        WHERE target_column IS NOT NULL GROUP BY ALL)),
-- the views the dataset serves; a plain view and a rule are kept, not served
v AS (
  SELECT count(*) AS n,
         count(*) FILTER (WHERE kind = 'table') AS tables,
         count(*) FILTER (WHERE kind = 'value') AS scalars,
         count(*) FILTER (WHERE kind = 'metric') AS metrics
  FROM view_definitions WHERE kind IN ('table', 'value', 'metric')),
rows(ord, kind, title, question, have, more, page) AS (
  SELECT 1, 'integrate', 'Integration', 'Which sources map?',
         (SELECT count(*) FROM load) || CASE WHEN (SELECT count(*) FROM load) = 1 THEN ' table' ELSE ' tables' END || ' from ' || (SELECT count(DISTINCT source) FROM recipe) || CASE WHEN (SELECT count(DISTINCT source) FROM recipe) = 1 THEN ' source' ELSE ' sources' END || ', ' || (SELECT n FROM v) || CASE WHEN (SELECT n FROM v) = 1 THEN ' view' ELSE ' views' END,
         coalesce(nullif(concat_ws(', ',
           CASE WHEN (SELECT tables FROM v) > 0 THEN (SELECT tables FROM v) || CASE WHEN (SELECT tables FROM v) = 1 THEN ' table' ELSE ' tables' END END,
           CASE WHEN (SELECT scalars FROM v) > 0 THEN (SELECT scalars FROM v) || CASE WHEN (SELECT scalars FROM v) = 1 THEN ' single value' ELSE ' single values' END END,
           CASE WHEN (SELECT metrics FROM v) > 0 THEN (SELECT metrics FROM v) || CASE WHEN (SELECT metrics FROM v) = 1 THEN ' metric' ELSE ' metrics' END END), ''), 'no view is defined yet')
           || coalesce(' · newest load ' || (SELECT strftime(max(imported_at), '%Y-%m-%d %H:%M') FROM load), ''),
         'views'
  UNION ALL
  SELECT 2, 'describe', 'Metadata', 'What does this mean?',
         (SELECT written FROM said) || CASE WHEN (SELECT written FROM said) = 1 THEN ' annotation' ELSE ' annotations' END || ', ' || (SELECT n FROM rel) || CASE WHEN (SELECT n FROM rel) = 1 THEN ' relationship' ELSE ' relationships' END,
         CASE WHEN (SELECT outdated FROM said) > 0
              THEN (SELECT outdated FROM said) || ' written before the newest change' ELSE 'the glossary and the semantic model' END,
         'glossary'
  UNION ALL
  SELECT 3, 'test', 'Quality', 'Can we trust this value?',
         CASE WHEN (SELECT n FROM t) = 0 THEN 'no test result yet'
              ELSE concat_ws(', ',
                CASE WHEN (SELECT red FROM t) > 0 THEN (SELECT red FROM t) || ' red' END,
                CASE WHEN (SELECT amber FROM t) > 0 THEN (SELECT amber FROM t) || ' orange or yellow' END,
                CASE WHEN (SELECT errors FROM t) > 0 THEN (SELECT errors FROM t) || ' with an error' END,
                (SELECT green FROM t) || ' green') END,
         (SELECT n FROM t) || CASE WHEN (SELECT n FROM t) = 1 THEN ' test result' ELSE ' test results' END,
         'quality'
  UNION ALL
  SELECT 4, 'review', 'Governance', 'Who decides?',
         (SELECT waiting FROM q) || CASE WHEN (SELECT waiting FROM q) = 1 THEN ' question waits for an owner' ELSE ' questions wait for an owner' END,
         (SELECT decided FROM q) || CASE WHEN (SELECT decided FROM q) = 1 THEN ' decision kept' ELSE ' decisions kept' END,
         'review'
  UNION ALL
  SELECT 5, '', 'Lineage', 'Where does this come from?',
         (SELECT traced FROM traced) || ' of ' || (SELECT n FROM traced) || CASE WHEN (SELECT n FROM traced) = 1 THEN ' view column traces to a source column' ELSE ' view columns trace to a source column' END,
         CASE WHEN (SELECT traced FROM traced) = (SELECT n FROM traced) THEN 'through the definitions and the load queries'
              ELSE ((SELECT n FROM traced) - (SELECT traced FROM traced)) || ' computed from several columns or from none' END,
         'lineage')
SELECT r.ord, r.title, r.question, r.have, r.more,
       CASE WHEN r.kind = '' THEN ''
            WHEN coalesce(a.n, 0) + coalesce(p.n, 0) = 0 THEN 'nothing open'
            ELSE concat_ws(' · ',
              CASE WHEN a.n > 0 THEN a.n || ' open for the agent' END,
              CASE WHEN p.n > 0 THEN p.n || ' open for a person' END) END AS open,
       CASE WHEN coalesce(a.n, 0) + coalesce(p.n, 0) = 0 THEN 'ok' ELSE 'warn' END AS scls,
       (SELECT b FROM base) || r.page AS link
FROM rows r
LEFT JOIN todo a ON a.work = r.kind AND a.who = 'agent'
LEFT JOIN todo p ON p.work = r.kind AND p.who = 'person'
ORDER BY r.ord
