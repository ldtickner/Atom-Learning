# Atom Learning: SATs score model
 
A SATs-equivalent score (80 to 120) for every pupil, in every subject. The models are re-runnable and can rebuild any past date exactly. Built with dbt on BigQuery.
 
## Setup
 
```bash
python -m venv .venv && .venv/Scripts/activate   # Windows
pip install -r requirements.txt
gcloud auth application-default login
cd atom_learning
dbt deps
dbt build --vars 'as_of_date: 2026-07-21'   # full 2025/26 academic year
dbt build                                    # latest date in the data
```
 
This expects a `~/.dbt/profiles.yml` profile named `atom_learning` (BigQuery, OAuth, project `atom-analytics-candidates`, location `europe-west2`).
 
Built with dbt Core 1.12.7 and dbt-bigquery 1.12.4.
 
## How the models fit together
 
| Layer | Models | Materialisation | Purpose |
|---|---|---|---|
| Seeds | `ks2_scaled_score_conversion` | table | GOV.UK 2026 KS2 raw mark to scaled score tables |
| Staging | `stg_pupils`, `stg_assessment_sittings`, `stg_responses`, `stg_course_hierarchy` | view | One view per raw table. Rename, cast and handle nulls. No filtering, so other models can reuse them |
| Intermediate | `int_sitting_answers` | incremental | One answer per question per scored sitting. Applies every sitting rule and the duplicate rule |
| Intermediate | `int_pupil_subject_daily_totals` | incremental | Questions, correct and not attempted per pupil, subject, year group and day. Partitioned by sitting finish date |
| Mart | `fct_pupil_subject_sats_score` | incremental | One row per pupil, subject and `as_of_date`. App-ready |
 
Each layer only reads the layer before it. The mart never reads raw responses, only the daily totals.
 
## Decisions
 
1. **Subjects.** Only subjects with a real KS2 SATs test are scored: Maths to Mathematics, English to English reading. Science, Verbal Reasoning, Non-Verbal Reasoning, Screeners and Wellbeing have no SATs scale to anchor them to. They still get a row per pupil with `score_status = no_sats_equivalent`. So the table covers "every pupil, in every subject", as the brief asks.
2. **Year groups.** Every Year 1 to 6 pupil is scored as "on track for KS2". This assumes assessments are pitched at the pupil's year group. `year_group` is kept on every row, so a score below Year 6 reads as a projection. Year groups 11, 14 and 15 are treated as bad data.
3. **Evidence window.** The score uses the percentage correct across the academic year to date (1 September to `as_of_date`). Only evidence from the pupil's latest year group in the window counts. 4 pupils change year group within 2025/26, so their earlier answers drop out of later scores ([data quality #12](docs/data_quality.md)).
4. **Mapping.** The [GOV.UK 2026 KS2 conversion tables](https://www.gov.uk/government/publications/key-stage-2-tests-2026-scaled-scores/2026-key-stage-2-scaled-score-conversion-tables) are seeded in `seeds/ks2_scaled_score_conversion.csv`. The pupil's percentage correct becomes an equivalent raw mark: percentage × the test's maximum (50 for reading, 110 for maths). This is rounded half up to a whole mark, then looked up. So every score is an exact GOV.UK value, as a real pupil would get.
5. **Point in time.** A sitting counts from the UK date it finishes. One row exists per pupil, subject and `as_of_date`. `as_of_date` is a dbt variable that defaults to the latest sitting date in the data, never today. Each run replaces only that date's partition, so history builds up and any past date can be rebuilt by re-running it. This was chosen over a `valid_from` / `valid_to` history, which is harder to keep correct when answers arrive late.
6. **Incremental windows.** Each run rebuilds the last 3 days of sittings (`lookback_days`), to catch late answers. It reads responses 31 days further back (`max_sitting_days`), because a scored sitting can stay open for up to 19 days. A test fails if any scored sitting runs longer than this.
7. **Schema changes.** Incremental models use `on_schema_change: fail`. A new column stops the run, instead of being silently dropped or left empty in old partitions. This stops one table mixing old and new logic.
### Rules applied
 
- All dates are UK dates (Europe/London), not UTC.
- Only complete, non-deleted sittings for non-deleted pupils count. A null `is_deleted` counts as not deleted.
- Only `summative_assessment` sittings count. `entrance_exam` and `mock_session` (40 sittings) are assumed to have a different purpose. To confirm with the product team.
- Survey and adaptive sittings are excluded.
- Answers with no matching sitting are excluded.
- Answers logged 1 second after `finished_at` are kept (timestamp rounding).
- `is_no_attempt` counts as incorrect.
- Duplicate answers to one question in one sitting collapse to one answer. It is correct if any copy is correct. It is skipped only if every copy is skipped.
- Raw marks of 0 to 2 have no GOV.UK scaled score. They are set to 80 and flagged `below_scale`.
- Fewer than 20 questions gives a `low_evidence` flag (`low_evidence_questions`).
- If more than one status applies, the first in this order wins: `no_sats_equivalent`, `no_answers`, `below_scale`, `low_evidence`, `scored`.
## Data quality issues
 
| Issue | Handling |
|---|---|
| `responses.session_type` is always `MOCK_TEST`, disagreeing with `assessment_sittings.session_type` | Dropped in `stg_responses`. Sitting type comes from `assessment_sittings` |
| Year groups 11, 14 and 15 in a primary dataset | Excluded |
| 7 subjects, only 2 map to SATs | See decision 1 |
| Mixed sitting styles (fixed, survey, adaptive, non-adaptive) | Survey and adaptive excluded |
| 2,082 question-in-sitting groups answered 2 to 5 times at the same timestamp; 965 disagree on `is_correct` | One answer per question per sitting, correct if any copy is correct. Root cause to investigate |
| 1,433 answers (56 sessions) with no matching sitting | Excluded |
| 1,608 answers logged exactly 1 second after `finished_at` | Kept: timestamp rounding |
| Session types `entrance_exam` (26) and `mock_session` (14) alongside `summative_assessment` (2,469) | Only `summative_assessment` counts |
| 145 of 2,496 complete sittings have answers on an earlier day than they finished, up to 47 days earlier. 43 are scored, at most 19 days | Sitting counts from its finish date. See decision 6 |
| 4 pupils change year group within 2025/26 | Latest year group only. See decision 3 |
| 78 of 242 pupils have no answers | Still get a row, with `score_status = no_answers` |
| Data ends 16 Sep 2026, one week into 2026/27 | The default date scores only 26 pupils. Build `2026-07-21` for the full 2025/26 year |
 
Full row counts and queries: [docs/data_quality.md](docs/data_quality.md).
 
## Proving it works
 
- **Re-runnable.** Build `2026-07-21` twice and compare the results with `EXCEPT DISTINCT` both ways round. Both return zero rows. The queries are in `analyses/check_rerun.sql`.
- **Tests.** `dbt build` runs every test, including one that checks each `as_of_date` has one row per pupil per subject.
## Production readiness
 
### Loading into the application database
 
The table loads into Postgres with a composite primary key of `pupil_id`, `subject_name` and `as_of_date`. Types map directly:
 
| BigQuery | Postgres |
|---|---|
| `STRING` | `TEXT` |
| `INT64` | `BIGINT` |
| `NUMERIC` | `NUMERIC(38, 9)` |
| `DATE` | `DATE` |
 
An empty score always has a `score_status` that explains why. A `CHECK` constraint limits the status to known values. The app reads a view of the latest `as_of_date`, so a teacher always sees the newest score.
 
### Daily load
 
A daily job runs `dbt build`. It updates every layer incrementally and adds a snapshot for the new `as_of_date`. Re-running it is safe, because `insert_overwrite` replaces that date's rows with the same result. The job then copies only that date to Postgres. It deletes and re-inserts that date's rows in one transaction. So the app never sees partial data, and a repeat copy changes nothing.
 
### Scaling to 100 million more responses
 
Each run reads a fixed window, not all history (decision 6). The intermediate tables are partitioned by date, so BigQuery skips older days. They are clustered by pupil and subject, so lookups stay small. The mart reads the daily totals, never the raw responses. So cost grows with each day's new data, not with the total size.
 
In production, the raw `responses` table should also be partitioned by answer date. Then the window saves cost from the very first step.
 
### Changing the mart's columns
 
`fct_pupil_subject_sats_score` holds one partition per `as_of_date`, so it has `full_refresh: false`. A `--full-refresh` would rebuild it with only the current date and delete all history. With `on_schema_change: fail`, a column change stops the run, and `--full-refresh` cannot fix it. To change columns safely:
 
1. List the dates held: `select distinct as_of_date from liam_tickner.fct_pupil_subject_sats_score`.
2. Copy the table to a backup (`bq cp liam_tickner.fct_pupil_subject_sats_score liam_tickner.fct_pupil_subject_sats_score_backup`), then drop the original.
3. Rebuild each date: `dbt build --select fct_pupil_subject_sats_score --vars 'as_of_date: <date>'`.
4. Check that row counts per date match the backup, then drop the backup.
Rebuilt dates match the originals, because the intermediate tables keep all history. They differ only if answers for those dates arrived late.
 
## Step 3: predicting GCSE results
 
I would predict a grade per GCSE subject. Each subject gets its own model, because each one depends on maths and reading in different amounts. I would start with a guess, such as History leaning on reading, then use past results to measure the real link.
 
To learn the link, I need pupils with both KS2 and GCSE results. My first choice would be Quest itself. I assume schools record real SATs results there, and that the pupil keeps one ID when they move to secondary school. If Quest does not follow pupils that far, I would use the National Pupil Database. It links KS2 and GCSE results for state school pupils, but access needs approval. I would also use what happens in between, such as mock exams and learning activity, to update predictions over time.
 
The main assumption is that KS2 results still predict GCSE results five years later. A lot changes in that time: pupils develop, and they move to a new school. I also assume past year groups predict future ones, though exam changes and missing COVID-era SATs make this harder. I assume Atom's estimated SATs scores behave like real ones, and that schools record real SATs results in Quest. Atom's pupils may also differ from pupils nationally. Finally, a prediction can change what happens, so I would use it to target support, never to label a pupil.
 
Before trusting the model, I would test it on a past year group whose GCSE results we already know. I would hide that group, train on older years, and compare the predictions with their real grades. The model must beat a simple guess, such as the national average grade. It should also be accurate for every group of pupils, not just on average. After launch, I would follow pupils through the years, check predictions against real progress, and retrain when they drift. I would also add new factors when events like COVID affect results.
 
## What I'd do next
 
- **Find the cause of duplicate answers.** 2,082 question-in-sitting groups repeat with identical timestamps, and 965 disagree on `is_correct`. The interim rule gives the pupil the benefit of the doubt but does not fix the source. Next: add a sequential answer ID or a sub-second timestamp, check whether the repeats are rapid clicks, and look for race conditions in how answers are written.
- **Ask why some sittings stay open for weeks.** 145 sittings have answers up to 47 days before they finish. This could be pupils pausing, or sittings never closed properly.
- **Confirm the sitting types with the product team.** Should `entrance_exam` and `mock_session` count towards a score?
- **Partition the raw `responses` table by answer date,** so incremental runs scan less data.
 
## AI usage
 
I used AI throughout, as the brief encourages:
 **Claude Code** to profile the data and write models with me. My `CLAUDE.md` asked it to explain each choice and let me make every design decision. I wrote the final score model myself.
The chat logs are in `ai_logs/`.
 