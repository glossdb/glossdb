-- An object's measurements: the newest result of each function on the
-- object, or on one of its columns when the object is a table. `$subject`
-- is the object's name inside the dataset (`orders`, `orders.amount`).
WITH d AS (SELECT dataset FROM current_dataset)
SELECT substr(m.subject, len(d.dataset) + 2) AS subject,
       m.function,
       m.aspect,
       left(m.value::VARCHAR, 160) || CASE WHEN length(m.value::VARCHAR) > 160 THEN '…' ELSE '' END AS value,
       strftime(m.computed_at, '%Y-%m-%d %H:%M') AS at
FROM measurements m JOIN d ON d.dataset = m.dataset
WHERE m.subject = d.dataset || '.' || CAST($subject AS VARCHAR)
   OR m.subject LIKE d.dataset || '.' || CAST($subject AS VARCHAR) || '.%'
QUALIFY row_number() OVER (PARTITION BY m.subject, m.function ORDER BY m.seq DESC) = 1
ORDER BY m.subject, m.function
