-- One check, both faces: the witness's own declaration — the aspect it
-- adjudicates, who may speak on it, its detector and threshold — and
-- its verdicts as ATTEST() holds them now: how many, by band, the worst
-- as the chip, the highest score, when the newest was measured and
-- whether every one stands at this pin.
WITH w AS (
  SELECT * FROM witnesses WHERE name = $check
  QUALIFY row_number() OVER (PARTITION BY name ORDER BY seq DESC) = 1),
v AS (
  SELECT a.band, a.score, a.computed_at, a.current,
         CASE a.band WHEN 'red' THEN 4 WHEN 'orange' THEN 3 WHEN 'yellow' THEN 2 WHEN 'error' THEN 1 ELSE 0 END AS severity
  FROM ATTEST() a WHERE a.witness = $check),
folded AS (
  SELECT count(v.band) AS n,
         count(*) FILTER (WHERE v.band = 'green') AS green,
         count(*) FILTER (WHERE v.band = 'yellow') AS yellow,
         count(*) FILTER (WHERE v.band = 'orange') AS orange,
         count(*) FILTER (WHERE v.band = 'red') AS red,
         count(*) FILTER (WHERE v.band = 'error') AS errors,
         coalesce(max(v.severity), -1) AS worst,
         max(v.score) AS score,
         max(v.computed_at) AS measured_at,
         coalesce(bool_and(v.current), true) AS standing
  FROM v)
SELECT w.name AS witness,
       w.aspect,
       coalesce(nullif(array_to_string(w.speakers, ', '), ''), 'function voices alone') AS speakers,
       coalesce(w.detector, '') AS detector,
       coalesce(CAST(w.threshold AS VARCHAR), 'none') AS threshold,
       CASE w.detector
         WHEN 'slot_entropy' THEN 'Do the voices on ' || w.aspect || ' agree, column by column? The score is the share of extra distinct values across a column''s slots: 0 when every voice agrees.'
         ELSE 'Does ' || coalesce(w.detector, 'nobody') || ' pass on ' || w.aspect || '?' END AS asks,
       CASE WHEN f.n = 0 THEN 'no verdict yet' ELSE
         CAST(f.n AS VARCHAR) || CASE WHEN f.n = 1 THEN ' verdict: ' ELSE ' verdicts: ' END || concat_ws(' · ',
           CASE WHEN f.red > 0 THEN CAST(f.red AS VARCHAR) || ' red' END,
           CASE WHEN f.orange > 0 THEN CAST(f.orange AS VARCHAR) || ' orange' END,
           CASE WHEN f.yellow > 0 THEN CAST(f.yellow AS VARCHAR) || ' yellow' END,
           CASE WHEN f.errors > 0 THEN CAST(f.errors AS VARCHAR) || ' error' END,
           CASE WHEN f.green > 0 THEN CAST(f.green AS VARCHAR) || ' green' END) END AS measured,
       CASE f.worst WHEN 4 THEN 'red' WHEN 3 THEN 'orange' WHEN 2 THEN 'yellow' WHEN 1 THEN 'error' WHEN 0 THEN 'green' ELSE 'none' END AS band,
       CASE WHEN f.worst = 0 THEN 'ok' WHEN f.worst < 0 THEN '' ELSE 'warn' END AS bcls,
       coalesce('score ' || CAST(round(f.score * 1000) / 1000 AS VARCHAR), '') AS score,
       coalesce('measured ' || strftime(f.measured_at, '%Y-%m-%d %H:%M'), '') AS "at",
       CASE WHEN f.standing THEN '' ELSE ' · from before the last change — re-measure' END AS stale
FROM w CROSS JOIN folded f
