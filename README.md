# Atom Learning — SATs score model

A SATs-equivalent score (80–120) for every pupil, in every SATs subject, re-runnable and reproducible as at any point in time. Built in dbt on BigQuery.

## Setup

```bash
python -m venv .venv && .venv/Scripts/activate   # Windows
pip install -r requirements.txt
gcloud auth application-default login
cd atom_learning && dbt build
```

Expects a `~/.dbt/profiles.yml` profile named `atom_learning` (BigQuery, OAuth, project `atom-analytics-candidates`, location `europe-west2`).

## Layout

| Layer | Materialisation | Purpose |
|---|---|---|
| `models/staging` | view | 1:1 with raw sources: rename, cast, handle nulls. No filtering, so other models can reuse them |
| `models/intermediate` | incremental | Daily totals per pupil and subject (answered, correct), partitioned by answer date |
| `models/marts` | incremental | `fct_pupil_subject_sats_score`: one row per pupil, subject, `as_of_date` (app-ready) |
| `seeds` | — | GOV.UK KS2 raw → scaled score conversion tables |

## Decisions

1. **Subjects** — only those with a real KS2 SATs equivalent: Maths → Maths, English → Reading. Science, Verbal/Non-Verbal Reasoning, Screeners and Wellbeing are excluded: there's no SATs scale to anchor them to.
2. **Year groups** — every Year 1–6 pupil is scored as "on track for KS2", assuming assessments are pitched at the pupil's year group. `year_group` is kept on every row so the score is read as a projection below Year 6. Year groups 11/14/15 are treated as bad data.
3. **Evidence window** — percentage correct across the academic year to date (1 Sept → as-of timestamp). Resets when year group changes. The data ends 16 Sep 2026, so the default `as_of_date` scores only one week of 2026/27 (26 pupils); run with `--vars 'as_of_date: 2026-07-21'` for the full 2025/26 year.
4. **Mapping** — [GOV.UK 2026 KS2 raw → scaled conversion tables](https://www.gov.uk/government/publications/key-stage-2-tests-2026-scaled-scores/2026-key-stage-2-scaled-score-conversion-tables) (Reading, Maths) seeded in `seeds/ks2_scaled_score_conversion.csv`, raw marks converted to % of max, linearly interpolated.
5. **Point-in-time** — one row per pupil, subject and `as_of_date` (dbt var; defaults to the latest answer date in the data, never today). Each run replaces only that date's partition, so history accumulates and any past date can be rebuilt exactly by re-running it. Chosen over a `valid_from` / `valid_to` history, which is harder to keep correct incrementally when answers arrive late.

Defaults applied: all dates (`as_of_date`, the 1 September window start, answer dates) are UK dates (Europe/London), not UTC; complete, non-deleted sittings for non-deleted pupils only (a null `is_deleted` counts as not deleted); survey and adaptive sittings excluded; answers whose `session_id` has no sitting row are excluded; answers logged 1 second after `finished_at` are kept (timestamp rounding); only `summative_assessment` sittings count (`entrance_exam` and `mock_session`, 40 sittings, are assumed to have a different purpose and difficulty; to confirm with the product team); `is_no_attempt` counts as incorrect; duplicate answers to the same question in one sitting (identical timestamps) collapse to one answer, correct if any copy is correct; percentages below the lowest GOV.UK mark that has a scaled score (raw 0–2 = "no scaled score") are clamped to 80 and flagged `below_scale`; scores carry `n_questions` and a `low_evidence` flag (< 20 questions).

## Data quality issues

| Issue | Handling |
|---|---|
| `responses.session_type` is always `MOCK_TEST`, disagreeing with `assessment_sittings.session_type` | Dropped in `stg_responses`; sitting type comes from `assessment_sittings` via `session_id` |
| Year groups 11, 14, 15 in a primary dataset | Excluded |
| 7 subjects, only 2 map to SATs | See decision 1 |
| Mixed sitting styles (fixed / survey / adaptive / non-adaptive) | Survey + adaptive excluded |
| 2,082 question-in-sitting groups answered 2–5 times at the same timestamp; 965 disagree on `is_correct` | One answer per question per sitting, correct if any copy is correct. Root cause to investigate |
| 1,433 answers (56 sessions) with no matching sitting | Excluded |
| 1,608 answers logged exactly 1 s after `finished_at` | Kept: timestamp rounding |
| Session types `entrance_exam` (26) and `mock_session` (14) alongside `summative_assessment` (2,469) | Only `summative_assessment` counts |
| 78 of 242 pupils have no answers | Still get a row, with `score_status = no_answers` |
| Data ends 16 Sep 2026, one week into 2026/27 | Default score is thin; see decision 3 |

Full row counts and queries: [docs/data_quality.md](docs/data_quality.md).

## Step 3 — predicting GCSE results

_TODO_

## What I'd do next

- **Find the cause of duplicate answers.** 2,082 question-in-sitting groups repeat with identical timestamps, and 965 disagree on `is_correct`. The interim rule (correct if any copy is correct) gives the pupil the benefit of the doubt but does not fix the source. Next steps: add a sequential answer ID or a sub-second timestamp so the first answer can be identified; check whether the repeats are rapid clicks; and look for race conditions in how answers are written.

## AI usage

Claude Code chat logs are in `ai_logs/`.
