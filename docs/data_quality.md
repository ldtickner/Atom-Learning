# Data quality

Profiled on 2026-11-18 against `atom-analytics-candidates.de_raw` (europe-west2). Read-only queries.

## Table sizes and keys

| Table | Rows | Key | Distinct keys | Null keys | Deleted |
|---|---|---|---|---|---|
| pupils | 242 | `pupil_id` | 242 | 0 | 0 |
| assessment_sittings | 2,509 | `session_id` | 2,509 | 0 | 0 |
| course_hierarchy | 10,552 | `question_id` | 10,552 | 0 | - |
| responses | 63,707 | `response_id` | 63,707 | 0 | - |

Every column is nullable in the schema, but no key is null. No pupils or sittings are deleted today; the `is_deleted` filters stay for production data.

`pupils` holds only `pupil_id` and `is_deleted`. Year group comes from `assessment_sittings.year_group_at_sitting`; 6 pupils have more than one.

## Issues and decisions

| # | Issue | Rows | Decision |
|---|---|---|---|
| 1 | Same question answered 2–5 times in one sitting, all copies with the same `answered_at` and `question_number` | 2,082 groups (2,411 extra rows) | Collapse to one answer per `session_id` + `question_id`, correct if any copy is correct |
| 1a | ...of which copies disagree on `is_correct` | 965 groups | As above. Root cause to investigate (see README, "What I'd do next") |
| 2 | `responses.session_id` not in `assessment_sittings` | 1,433 answers, 56 sessions, Nov 2025 – Jun 2026 | Excluded: completeness, style, type and year group cannot be checked |
| 3 | Answer logged after the sitting's `finished_at` | 1,608 answers, 236 sittings, all exactly 1 s late | Kept: timestamp rounding |
| 4 | Incomplete sittings (`is_complete = false`); 13 sittings also have null `finished_at` | 13 | Excluded |
| 4a | Sittings with null `started_at` | 12, all incomplete (11 `entrance_exam` with no answers, 1 `summative_assessment` with 25 answers) | Already excluded as incomplete. Test requires start and finish times only on complete sittings |
| 5 | Year groups 11, 14, 15 in primary data | 25 sittings | Excluded |
| 6 | Sitting styles: `fixed_question` 2,370, `survey` 125, `non_adaptive` 8, `adaptive` 6 | - | `survey` and `adaptive` excluded |
| 7 | Session types: `summative_assessment` 2,469, `entrance_exam` 26, `mock_session` 14 | - | Only `summative_assessment` counts (assumption; to confirm with product) |
| 8 | Subjects (questions per subject): English 4,699, Maths 3,593, Non-Verbal Reasoning 844, Verbal Reasoning 807, Science 335, Screeners 181, Wellbeing 93 | - | Only Maths and English (→ Reading) are scored |
| 9 | Pupils with no answers at all | 78 of 242 | Still get a row per subject, `score_status = no_answers` |
| 10 | Answers span 2025-11-10 → 2026-09-16; 2026/27 has 1,747 answers from 26 pupils (10–16 Sep) | - | Academic-year window; default `as_of_date` gives a thin score (README decision 3) |
| 11 | Complete sittings with answers on an earlier UK date than they finished | 145 of 2,496 sittings, up to 47 days; 43 are scored, at most 19 days | Partition by sitting finish date; incremental runs read responses `max_sitting_days` (31) further back; a test fails if a scored sitting exceeds it |
| 12 | Scored pupils whose year group changes within an academic year | 4 pupils in 2025/26: three Year 2 → 3 (Feb → May), one Year 2 → 6 (Nov → Feb); no switching back | Score uses only the latest year group in the window. Question for product: is `year_group_at_sitting` the pupil's year or the assessment's level? |

## Checked and clean

- No null `answered_at` or `is_correct`.
- `is_no_attempt` (3,279 rows) is never also `is_correct`.
- Duplicate copies never disagree on `is_no_attempt` (0 of 2,082 groups).
- Every response's `pupil_id` and `question_id` exist in their tables.
- Response `pupil_id` always matches the sitting's `pupil_id`.
- No answer is logged before its sitting's `started_at`.
- Repeat answers only happen within a sitting, never across sittings.
