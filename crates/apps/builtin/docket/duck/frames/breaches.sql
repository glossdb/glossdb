-- The findings' first rows: the walked metrics outside their corridor.
-- The futures kit's walk; until it is loaded, no breach is served.
SELECT CAST(NULL AS VARCHAR) AS title, CAST(NULL AS VARCHAR) AS metric, CAST(NULL AS VARCHAR) AS headline,
       CAST(NULL AS DOUBLE) AS actual, CAST(NULL AS DOUBLE) AS lo, CAST(NULL AS DOUBLE) AS hi,
       CAST(NULL AS VARCHAR) AS side, CAST(NULL AS VARCHAR) AS displacement, CAST(NULL AS VARCHAR) AS others,
       CAST(NULL AS VARCHAR) AS band, CAST(NULL AS VARCHAR) AS bcls, CAST(NULL AS VARCHAR) AS meta,
       CAST(NULL AS VARCHAR) AS at, CAST(NULL AS VARCHAR) AS stale, CAST(NULL AS VARCHAR) AS link_check,
       CAST(NULL AS VARCHAR) AS link_metric, CAST(NULL AS VARCHAR) AS axis
FROM owed WHERE false
