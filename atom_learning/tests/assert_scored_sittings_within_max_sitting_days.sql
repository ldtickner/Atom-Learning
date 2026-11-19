-- Incremental runs only read responses max_sitting_days back. A scored sitting open longer than that
-- would be rebuilt with some answers missing, so fail the build instead of losing them silently.
-- ponytail: scans all of stg_responses each build; limit to recent sitting_dates if test cost bites
with scored_sittings as (
    select distinct
        session_id,
        sitting_date
    from {{ ref('int_sitting_answers') }}
)

select
    scored_sittings.session_id,
    scored_sittings.sitting_date,
    min(stg_responses.answered_date) as first_answer_date
from scored_sittings
inner join {{ ref('stg_responses') }} as stg_responses
    on scored_sittings.session_id = stg_responses.session_id
group by
    scored_sittings.session_id,
    scored_sittings.sitting_date
having date_diff(scored_sittings.sitting_date, min(stg_responses.answered_date), day) > {{ var('max_sitting_days') }}
