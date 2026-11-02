-- One column's head: its table, its engine type, its judged role and
-- meaning (a person's over the agent's), and the metrics that read it.
-- One row, or none for a name no landed column carries. `$column` is
-- `table.column`, spelled without the dataset.
WITH d AS (SELECT dataset FROM current_dataset),
slots AS (
  SELECT g.aspect, g.actor_kind, g.body,
         row_number() OVER (PARTITION BY g.aspect
           ORDER BY CASE g.actor_kind WHEN 'human' THEN 0 ELSE 1 END, g.seq DESC) AS rn
  FROM glossary g JOIN d ON d.dataset = g.dataset
  WHERE g.subject = d.dataset || '.' || CAST($column AS VARCHAR) AND g.aspect IN ('role', 'meaning')
    AND g.actor_kind IN ('human', 'agent')),
cur AS (SELECT aspect, json_extract_string(body, '$.value') AS value FROM slots WHERE rn = 1),
col AS (
  SELECT c.table_name, c.column_name, c.data_type
  FROM information_schema.columns c JOIN d ON d.dataset = c.table_schema
  WHERE c.table_catalog = current_database() AND c.table_name || '.' || c.column_name = CAST($column AS VARCHAR)),
a AS (
  SELECT name, schema FROM aspects
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
reads AS (
  SELECT string_agg(DISTINCT coalesce(json_extract_string(a.schema, '$.title'), ms.metric), ', ') AS metrics
  FROM metric_sources() ms LEFT JOIN a ON a.name = ms.metric
  WHERE ms.source = CAST($column AS VARCHAR))
SELECT col.table_name,
       col.column_name AS name,
       lower(col.data_type) AS typed,
       coalesce(r.value, 'no role judged') AS role,
       coalesce(m.value, 'not yet said') AS meaning,
       coalesce('read by ' || rd.metrics, '') AS read_by,
       '' AS refused,
       '?table=' || col.table_name AS link_table
FROM col
CROSS JOIN reads rd
LEFT JOIN cur r ON r.aspect = 'role'
LEFT JOIN cur m ON m.aspect = 'meaning'
