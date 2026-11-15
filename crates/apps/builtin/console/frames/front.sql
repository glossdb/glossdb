-- The Questions counts: what holds open for a human, straight from
-- `open_questions` — the same rows the interface asks as forms; the review decisions
-- that stand, from `review_decisions`; and the rows of `next` that the
-- agent must or should work on. All three scope to the bound dataset.
SELECT
  (SELECT count(*) FROM open_questions q JOIN current_dataset d ON d.dataset = q.dataset) AS open,
  (SELECT count(*) FROM review_decisions r JOIN current_dataset d ON d.dataset = r.dataset) AS decided,
  (SELECT count(*) FROM next WHERE who = 'agent' AND level <> 'could') AS waiting
