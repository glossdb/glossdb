-- The plan beside one metric, period by period: the futures kit's
-- read. Until it is loaded, no plan is served here, and the page's
-- empty text says where a plan comes from.
SELECT CAST(NULL AS VARCHAR) AS plan, CAST(NULL AS VARCHAR) AS grain, CAST(NULL AS VARCHAR) AS label,
       CAST(NULL AS VARCHAR) AS period, CAST(NULL AS VARCHAR) AS planned, CAST(NULL AS VARCHAR) AS actual,
       CAST(NULL AS VARCHAR) AS variance, CAST(NULL AS VARCHAR) AS expected, CAST(NULL AS VARCHAR) AS stands,
       CAST(NULL AS VARCHAR) AS scls, CAST(NULL AS VARCHAR) AS held
FROM owed WHERE false
