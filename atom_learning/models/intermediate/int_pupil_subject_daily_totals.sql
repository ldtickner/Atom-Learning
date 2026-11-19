{{
    config(
        incremental_strategy='insert_overwrite',
        partition_by={'field': 'sitting_date', 'data_type': 'date', 'granularity': 'day'},
        cluster_by=['pupil_id', 'subject_name']
    )
}}

with answers as (
    select
        sitting_date,
        pupil_id,
        subject_name,
        year_group,
        is_correct,
        is_no_attempt
    from {{ ref('int_sitting_answers') }}
    {% if is_incremental() %}
    -- Upstream partitions hold whole sittings, so no extra look-back for long sittings is needed
    where sitting_date >= date_sub(_dbt_max_partition, interval {{ var('lookback_days') }} day)
    {% endif %}
)

select
    sitting_date,
    pupil_id,
    subject_name,
    year_group,
    count(*) as n_questions,
    countif(is_correct) as n_correct,
    countif(is_no_attempt) as n_not_attempted
from answers
group by
    sitting_date,
    pupil_id,
    subject_name,
    year_group
