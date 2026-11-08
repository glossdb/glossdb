-- One source: its settings as declared, newest declaration.
SELECT s.name,
       coalesce(json_extract_string(s.settings, '$.type'), '') AS type,
       coalesce(json_extract_string(s.settings, '$.location'), '') AS location,
       coalesce(json_extract_string(s.settings, '$.via'), '') AS via,
       s.settings::VARCHAR AS settings,
       strftime(s.declared_at, '%Y-%m-%d %H:%M') AS declared
FROM sources s
WHERE s.name = CAST($source AS VARCHAR)
QUALIFY row_number() OVER (PARTITION BY s.name ORDER BY s.seq DESC) = 1
