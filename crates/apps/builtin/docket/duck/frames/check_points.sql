-- A corridor check's evidence: the futures kit's walk. Until it is
-- loaded, no point is served.
SELECT CAST(NULL AS VARCHAR) AS title, CAST(NULL AS VARCHAR) AS metric, CAST(NULL AS VARCHAR) AS period,
       CAST(NULL AS VARCHAR) AS actual, CAST(NULL AS VARCHAR) AS corridor, CAST(NULL AS VARCHAR) AS displacement,
       CAST(NULL AS VARCHAR) AS side, CAST(NULL AS VARCHAR) AS band, CAST(NULL AS VARCHAR) AS bcls,
       CAST(NULL AS VARCHAR) AS note, CAST(NULL AS VARCHAR) AS link
WHERE false
