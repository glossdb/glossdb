-- The reads over stored rows: nothing here is stored or kept. A dataset ds, narrowed to a
-- subject subj and what lies under it (NULL: the whole dataset).

-- The check of the results in scope, walked forward from each over the results it read:
-- out of date (a node it read changed after it read), possibly (a result it read is)
CREATE OR REPLACE MACRO g_check_of(ds, subj) AS TABLE
WITH RECURSIVE roots AS (SELECT id FROM g_result WHERE end_snapshot IS NULL AND dataset = ds
                         AND (subj IS NULL OR subject = subj OR subject LIKE subj || '.%')),
walk(root, id) AS (SELECT id, id FROM roots UNION
  SELECT w.root, q.id FROM walk w JOIN (SELECT * FROM g_read WHERE what LIKE 'result %') e ON e.result = w.id
  JOIN g_result q ON q.subject = e.asset AND 'result ' || q.function = e.what AND q.end_snapshot IS NULL),
bad AS (SELECT DISTINCT w.root, w.id FROM walk w JOIN g_result r ON r.id = w.id JOIN g_read e ON e.result = w.id
        JOIN g_changed n ON n.asset = e.asset AND n.what = e.what WHERE n.changed_at > r.read_at)
SELECT root AS id, CASE WHEN bool_or(id = root) THEN 'out of date' ELSE 'possibly' END AS state FROM bad GROUP BY root;

-- TESTS(): the stored results of the tests, each with its current mark
CREATE OR REPLACE MACRO g_tests(ds, subj) AS TABLE
SELECT r.subject, d.body::JSON->>'property' AS aspect, r.function AS test, r.value::JSON->>'state' AS state,
       (r.value::JSON->>'score')::DOUBLE AS score, (d.body::JSON->>'threshold')::DOUBLE AS threshold, r.error,
       k.state IS NULL AS current, coalesce(k.state, 'current') AS result_state
FROM g_result r JOIN g_declaration d ON d.asset = r.function AND d.kind = 'test' AND d.end_snapshot IS NULL
LEFT JOIN g_check_of(ds, subj) k ON k.id = r.id
WHERE r.end_snapshot IS NULL AND r.dataset = ds AND (subj IS NULL OR r.subject = subj OR r.subject LIKE subj || '.%');

-- GLOSSARY(), collapsed: the precedence pick per (subject, property), withheld while two actors'
-- values are current and the stored test's score exceeds its threshold; stale where the
-- definition of its subject changed after the annotation began; a function value marked by
-- the check; missing where a test's grain requires a value and none is there
CREATE OR REPLACE MACRO g_collapsed(ds, subj) AS TABLE
WITH fr AS (SELECT asset AS function, body::JSON->>'returns' AS aspect FROM g_declaration
            WHERE kind = 'function' AND end_snapshot IS NULL AND body::JSON->>'returns' IS NOT NULL),
v AS (SELECT asset AS subject, property AS aspect, actor, body, begin_snapshot, NULL::BIGINT AS id FROM g_annotation
      WHERE end_snapshot IS NULL AND dataset = ds AND (subj IS NULL OR asset = subj OR asset LIKE subj || '.%')
      UNION ALL SELECT r.subject, f.aspect, 'function', r.value, r.begin_snapshot, r.id FROM g_result r JOIN fr f ON f.function = r.function
      WHERE r.end_snapshot IS NULL AND r.error IS NULL AND r.dataset = ds AND (subj IS NULL OR r.subject = subj OR r.subject LIKE subj || '.%')),
picked AS (SELECT * FROM v QUALIFY row_number() OVER (PARTITION BY subject, aspect
           ORDER BY CASE actor WHEN 'human' THEN 0 WHEN 'agent' THEN 1 ELSE 2 END, begin_snapshot DESC) = 1),
n AS (SELECT subject, aspect, count(DISTINCT actor) AS n FROM v GROUP BY ALL),
t AS (SELECT r.subject, d.body::JSON->>'property' AS aspect, r.value::JSON->>'state' AS state,
             (r.value::JSON->>'score')::DOUBLE AS score, (d.body::JSON->>'threshold')::DOUBLE AS threshold
      FROM g_result r JOIN g_declaration d ON d.asset = r.function AND d.kind = 'test' AND d.end_snapshot IS NULL
      WHERE r.end_snapshot IS NULL AND r.dataset = ds AND (subj IS NULL OR r.subject = subj OR r.subject LIKE subj || '.%')
      QUALIFY row_number() OVER (PARTITION BY r.subject, aspect ORDER BY r.error IS NOT NULL, score DESC) = 1),
cols AS (SELECT asset FROM g_columns WHERE dataset = ds AND (subj IS NULL OR asset = subj OR asset LIKE subj || '.%')),
dc AS (SELECT node, changed_at FROM g_def_changed WHERE dataset = ds),
fk AS (SELECT * FROM g_check_of(ds, subj) WHERE id IN (SELECT id FROM picked)),
tested AS (SELECT DISTINCT body::JSON->>'property' AS aspect FROM g_declaration
           WHERE kind = 'test' AND end_snapshot IS NULL AND body::JSON->>'grain' = 'column')
SELECT p.subject, p.aspect, CASE WHEN j.score > j.threshold AND n.n > 1 THEN NULL ELSE p.body END AS value,
       j.state AS test_state, j.score,
       CASE WHEN j.score > j.threshold AND n.n > 1 THEN 'conflict'
            WHEN p.actor <> 'function' AND p.begin_snapshot < d.changed_at THEN 'stale'
            WHEN k.state = 'out of date' THEN 'stale' WHEN k.state = 'possibly' THEN 'possibly'
            ELSE 'current' END AS state
FROM picked p LEFT JOIN t j USING (subject, aspect) LEFT JOIN n USING (subject, aspect)
LEFT JOIN cols c ON c.asset = p.subject
LEFT JOIN dc d ON d.node = CASE WHEN c.asset IS NOT NULL THEN c.asset WHEN p.subject LIKE '%.%'
                                THEN split_part(p.subject, '.', 1) || '.' || split_part(p.subject, '.', 2) END
LEFT JOIN fk k ON k.id = p.id
UNION ALL SELECT c.asset, t.aspect, NULL, NULL, NULL, 'missing' FROM cols c, tested t
WHERE NOT EXISTS (SELECT 1 FROM picked p WHERE p.subject = c.asset AND p.aspect = t.aspect);

-- A stand-in for view_summary(): per view, its period and value columns, additivity and
-- its state, its dimensions, whether a series can be served; from the collapsed read
CREATE OR REPLACE MACRO g_view_summary(ds) AS TABLE
WITH views AS (SELECT asset AS view FROM g_definition WHERE dataset = ds AND kind = 'view' AND end_snapshot IS NULL),
c AS MATERIALIZED (SELECT split_part(subject, '.', 1) || '.' || split_part(subject, '.', 2) AS view,
             split_part(subject, '.', 3) AS col, aspect, value::JSON->>'value' AS value, state
      FROM g_collapsed(ds, NULL) WHERE aspect IN ('role', 'additivity', 'dimension') AND len(string_split(subject, '.')) = 3),
roles AS (SELECT view, max(col) FILTER (WHERE aspect = 'role' AND value = 'timestamp') AS period_column,
                 max(col) FILTER (WHERE aspect = 'role' AND value = 'measure') AS value_column,
                 list(col ORDER BY col) FILTER (WHERE aspect = 'role' AND value = 'dimension') AS dims
          FROM c GROUP BY view)
SELECT v.view, r.period_column, r.value_column, r.dims, a.value AS additivity, coalesce(a.state, 'none') AS additivity_state,
       r.period_column IS NOT NULL AND r.value_column IS NOT NULL AND a.value IS NOT NULL AS applicable
FROM views v LEFT JOIN roles r USING (view)
LEFT JOIN c a ON a.view = v.view AND a.col = r.value_column AND a.aspect = 'additivity';

-- A stand-in for view_tests(): per view, the tests on it and its columns, and on the tables and
-- columns its stored lineage says it reads, with the evidence the check stored
CREATE OR REPLACE MACRO g_view_tests(ds) AS TABLE
WITH views AS (SELECT asset AS view FROM g_definition WHERE dataset = ds AND kind = 'view' AND end_snapshot IS NULL),
t AS MATERIALIZED (SELECT * FROM g_tests(ds, NULL)),
reads AS (SELECT e.src AS view, e.dst AS subject FROM g_lineage(ds) e WHERE e.kind = 'reads'),
fr AS (SELECT asset AS function, body::JSON->>'returns' AS aspect FROM g_declaration
       WHERE kind = 'function' AND end_snapshot IS NULL AND body::JSON->>'returns' IS NOT NULL),
ev AS (SELECT r.subject, f.aspect, r.value FROM g_result r JOIN fr f ON f.function = r.function
       WHERE r.end_snapshot IS NULL AND r.dataset = ds),
rows AS (SELECT r.view, t.* FROM reads r JOIN t ON t.subject = r.subject
         UNION ALL SELECT v.view, t.* FROM views v JOIN t ON t.subject = v.view OR t.subject LIKE v.view || '.%')
SELECT r.view, r.test, r.aspect, r.subject, r.state, r.current, r.score, e.value AS evidence
FROM rows r LEFT JOIN ev e ON e.subject = r.subject AND e.aspect = r.aspect
ORDER BY CASE r.state WHEN 'red' THEN 0 WHEN 'yellow' THEN 2 ELSE 4 END, r.current, r.view, r.test, r.subject;
