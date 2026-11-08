-- The dataset's history, newest first: loads, annotations, review
-- decisions and declarations, one row each, with the object it touched
-- and a one-line summary. `$kind` (load | annotation | decision |
-- declaration) and `$object` (an asset without the dataset's prefix; a
-- table includes its columns) narrow it, empty for all. `total` counts
-- what the filters let through; the newest 300 are served.
WITH d AS (SELECT dataset FROM current_dataset),
base AS (SELECT '/' || dataset || '/app/console/p/' AS b FROM d),
f AS (SELECT CAST($kind AS VARCHAR) AS k, CAST($object AS VARCHAR) AS o),
metrics AS (SELECT name FROM metric_surfaces),
loads AS (
  SELECT i.imported_at AS ts, 'load' AS kind, i.table_name AS object, 'the load query' AS who,
         fmt_number(i.rows) || ' rows (' || i.mode || ')'
           || CASE WHEN coalesce(i.dropped_rows_count, 0) > 0
                   THEN ', ' || fmt_number(i.dropped_rows_count) || ' dropped' ELSE '' END AS summary
  FROM imports i JOIN d ON d.dataset = i.dataset),
written AS (
  SELECT g.written_at AS ts,
         CASE WHEN g.aspect = 'review_decision' THEN 'decision' ELSE 'annotation' END AS kind,
         substr(g.subject, len(d.dataset) + 2) AS object,
         CASE g.actor_kind WHEN 'human' THEN 'a person' WHEN 'agent' THEN 'the agent' ELSE g.actor_kind END
           || coalesce(' · ' || g.actor_id, '') AS who,
         CASE
           WHEN g.aspect = 'review_decision' THEN array_to_string(list_transform(
             from_json(json_extract(g.body, '$.decisions'), '[{"aspect": "VARCHAR", "key": "VARCHAR", "stance": "VARCHAR"}]'),
             lambda x: x.aspect || ' · ' || x.key || ': ' || x.stance), '; ')
           WHEN g.aspect = 'definitions' THEN 'definitions: '
             || array_to_string(json_keys(json_extract(g.body, '$.definitions')), ', ')
           ELSE g.aspect || ': ' || coalesce(
             json_extract_string(g.body, '$.value'),
             CASE WHEN json_extract(g.body, '$.sql') IS NOT NULL THEN 'a metric definition' END,
             left(g.body::VARCHAR, 120) || CASE WHEN length(g.body::VARCHAR) > 120 THEN '…' ELSE '' END)
         END AS summary
  FROM glossary g JOIN d ON d.dataset = g.dataset),
declared AS (
  SELECT declared_at AS ts, 'declaration' AS kind, name AS object, '' AS who,
         'property ' || name || ' (' || lower(kind) || ')' AS summary
  FROM aspects
  UNION ALL
  SELECT declared_at, 'declaration', name, '',
         'test ' || name || ' on ' || aspect
  FROM tests
  UNION ALL
  SELECT r.declared_at, 'declaration', r.table_name, '',
         'load query for ' || r.table_name || ' from ' || r.source
  FROM recipes r JOIN d ON d.dataset = r.dataset
  UNION ALL
  SELECT r.declared_at, 'declaration',
         substr(r.left_side, len(d.dataset) + 2), '',
         'key ' || substr(r.left_side, len(d.dataset) + 2) || ' ' || r.op || ' ' || substr(r.right_side, len(d.dataset) + 2)
  FROM relationships r JOIN d ON d.dataset = r.dataset),
events AS (
  SELECT * FROM loads UNION ALL SELECT * FROM written UNION ALL SELECT * FROM declared),
kept AS (
  SELECT e.*, count(*) OVER () AS total
  FROM events e, f
  WHERE (f.k = '' OR e.kind = f.k)
    AND (f.o = '' OR e.object = f.o OR e.object LIKE f.o || '.%'))
SELECT strftime(ts, '%Y-%m-%d %H:%M') AS "at",
       kind,
       CASE WHEN object = '' THEN 'the dataset' ELSE object END AS object,
       (SELECT b FROM base) || CASE
         WHEN object = '' THEN 'history'
         WHEN kind = 'declaration' AND starts_with(summary, 'property ') THEN 'glossary?aspect=' || object
         WHEN kind = 'declaration' AND starts_with(summary, 'test ') THEN 'quality?check=' || object
         WHEN object IN (SELECT name FROM metrics) THEN 'metrics?metric=' || object
         WHEN contains(object, ' ') THEN 'lineage'
         WHEN contains(object, '.') THEN 'glossary?column=' || object
         ELSE 'glossary?table=' || object END AS link,
       who, summary, total
FROM kept
ORDER BY ts DESC, kind, object
LIMIT 300
