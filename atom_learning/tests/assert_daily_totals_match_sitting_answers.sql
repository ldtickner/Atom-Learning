-- Every answer in int_sitting_answers is counted exactly once in the daily totals.
-- Catches a broken incremental window, which would drop or double-count a partition.
with answers as (
    select
        sitting_date,
        count(*) as n_questions
    from {{ ref('int_sitting_answers') }}
    group by sitting_date
),

totals as (
    select
        sitting_date,
        sum(n_questions) as n_questions
    from {{ ref('int_pupil_subject_daily_totals') }}
    group by sitting_date
)

select
    coalesce(answers.sitting_date, totals.sitting_date) as sitting_date,
    answers.n_questions as answers_n_questions,
    totals.n_questions as totals_n_questions
from answers
full outer join totals on answers.sitting_date = totals.sitting_date
where answers.n_questions is distinct from totals.n_questions
