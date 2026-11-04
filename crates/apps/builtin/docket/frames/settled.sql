-- The settled band: every standing ruling, in the human's own words,
-- with what the agent did about it. `folded_in` is derived: the ruling
-- stands unfolded while its key is still disclosed below full
-- confidence, and clears when the re-record lands.
SELECT r.aspect AS subj,
       CASE WHEN r.folded_in THEN 'rail settled' ELSE 'rail' END AS rcls,
       coalesce(r.dimension, '-') || ' · ' || r.key AS asp,
       r.assumption AS what,
       r.stance,
       CASE WHEN coalesce(r.note, '') = '' THEN '' ELSE '“' || r.note || '”' END AS note,
       CASE WHEN r.folded_in THEN 'folded in' ELSE 'awaiting the fold-in' END AS state,
       CASE WHEN r.folded_in THEN 'ok' ELSE 'warn' END AS scls,
       strftime(r.written_at, '%Y-%m-%d') AS "at",
       '/' || d.dataset || '/app/docket/p/metrics?metric=' || r.aspect AS link
FROM ruling_entries r
JOIN current_dataset d ON d.dataset = r.dataset
ORDER BY r.written_at DESC, subj
