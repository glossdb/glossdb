-- Where a breached metric's move is: the futures kit's walk names the
-- months; until it is loaded, no mover is served.
SELECT CAST(NULL AS VARCHAR) AS axis, CAST(NULL AS VARCHAR) AS member,
       CAST(NULL AS DOUBLE) AS before, CAST(NULL AS DOUBLE) AS after,
       CAST(NULL AS VARCHAR) AS sign, CAST(NULL AS DOUBLE) AS moved,
       CAST(NULL AS VARCHAR) AS rest, CAST(NULL AS VARCHAR) AS rest_sign, CAST(NULL AS DOUBLE) AS rest_moved
WHERE false
