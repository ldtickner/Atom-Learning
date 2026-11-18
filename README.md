# Atom Learning — SATs score model

A SATs-equivalent score (80–120) for every pupil, in every SATs subject, re-runnable and reproducible as at any point in time. Built in dbt on BigQuery.

## Setup

```bash
python -m venv .venv && .venv/Scripts/activate   # Windows
pip install -r requirements.txt
gcloud auth application-default login
cd atom_learning && dbt build
```

Expects a `~/.dbt/profiles.yml` profile named `atom_learning` (BigQuery, OAuth, project `atom-analytics-candidates`, location `EU`).

## Layout

| Layer | Materialisation | Purpose |
|---|---|---|
| `models/staging` | view | 1:1 with raw sources: rename, cast, flag |
| `models/intermediate` | incremental | Response → sitting aggregation |
| `models/marts` | table | Score history + current scores (app-ready) |
| `seeds` | — | GOV.UK KS2 raw → scaled score conversion tables |

## Decisions

1. **Subjects** — only those with a real KS2 SATs equivalent: Maths → Maths, English → Reading. Science, Verbal/Non-Verbal Reasoning, Screeners and Wellbeing are excluded: there's no SATs scale to anchor them to.
2. **Year groups** — every Year 1–6 pupil is scored as "on track for KS2", assuming assessments are pitched at the pupil's year group. `year_group` is kept on every row so the score is read as a projection below Year 6. Year groups 11/14/15 are treated as bad data.
3. **Evidence window** — percentage correct across the academic year to date (1 Sept → as-of timestamp). Resets when year group changes.
4. **Mapping** — [GOV.UK 2026 KS2 raw → scaled conversion tables](https://www.gov.uk/government/publications/key-stage-2-tests-2026-scaled-scores/2026-key-stage-2-scaled-score-conversion-tables) (Reading, Maths) seeded in `seeds/ks2_scaled_score_conversion.csv`, raw marks converted to % of max, linearly interpolated.
5. **Point-in-time** — score history with `valid_from` / `valid_to` (a new version whenever a sitting changes a score). `as at T` = `T >= valid_from and (T < valid_to or valid_to is null)`. A current-scores table is the shape for the production app DB.

Defaults applied: complete, non-deleted sittings for non-deleted pupils only; survey and adaptive sittings excluded; `is_no_attempt` counts as incorrect; percentages below the lowest GOV.UK mark that has a scaled score (raw 0–2 = "no scaled score") are clamped to 80 and flagged `below_scale`; scores carry `n_questions` and a `low_evidence` flag (< 20 questions).

## Data quality issues

| Issue | Handling |
|---|---|
| `responses.session_type` is always `MOCK_TEST`, disagreeing with `assessment_sittings.session_type` | Join on `session_id`, ignore response-level `session_type` |
| Year groups 11, 14, 15 in a primary dataset | Excluded |
| 7 subjects, only 2 map to SATs | See decision 1 |
| Mixed sitting styles (fixed / survey / adaptive / non-adaptive) | Survey + adaptive excluded |

## Step 3 — predicting GCSE results

_TODO_

## What I'd do next

_TODO_

## AI usage

Claude Code chat logs are in `ai-logs/`.
