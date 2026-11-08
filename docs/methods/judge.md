# Candidates and judgment

Every measurement in glossdb proposes; none decides. The statistical
pass aims for recall and returns everything it found. The agent that
reads the result removes the false positives against the data.
Judgment lives in the reader, in detectors and in read policy, never
inside a result.

## Why the work is split this way

A threshold hidden inside machinery is a judgment nobody can argue
with. It is made once, by the author, without the data in view. So the
thresholds that matter sit in the measurement's own SQL, where a
reader sees them: the derivation function's `match_rate >= 0.95 AND
support >= 20`. The screens underneath prune only on cost and algebra.
The derivation screen skips triples whose operand magnitudes cannot
land within 30× of the target. The relationship screen's 0.5
containment floor bounds the output size; it judges nothing. Both
screens are in the quality kit (`kits/quality`).

The split works in both directions. A reader with context declares
relationships no value statistic can see, and rejects coincidences no
statistic can spot. That is why every measurement returns candidates,
never conclusions.

## Rules

- **Abstaining is a complete answer.** A function that cannot ground
  its output names the missing inputs (`missing_aspects`) instead of
  guessing. When a judgment fails, the statistics remain.
- **No statistic ships without a test of its accuracy.** Every kit
  carries acceptance tests over data whose truth is known by
  construction (the extension's `test/sql/`). The glossval suite grades
  them on corpora with declared truth. A measurement whose accuracy
  cannot be measured does not ship.
- **Every result has a reader.** No aspect is declared that nothing
  reads.
- **Red appears only where a detector computes it.** People do not
  report disagreement on their own. Triage is as good as the detector
  library.
- **Functions do not write FACT values.** Ranking a measured value
  against stated values brings calibration back in. A measurement is
  evidence the agent reads before it annotates.

## Limits

The split moves cost to the reader. A generous candidate list is only
as good as the judgment that prunes it. The reader's attention is the
scarce resource, so results are served as summaries and the detail is
read on demand.
