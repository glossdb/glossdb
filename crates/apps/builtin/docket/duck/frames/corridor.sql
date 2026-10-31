-- A metric's corridor as a picture: the futures kit's walk. Until it is
-- loaded, no point is served.
SELECT CAST(NULL AS TIMESTAMP) AS period, CAST(NULL AS VARCHAR) AS series, CAST(NULL AS DOUBLE) AS value,
       CAST(NULL AS DOUBLE) AS low, CAST(NULL AS DOUBLE) AS high, CAST(NULL AS BOOLEAN) AS outside
WHERE false
