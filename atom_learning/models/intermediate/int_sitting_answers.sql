{{
    config(
        incremental_strategy='insert_overwrite',
        partition_by={'field': 'sitting_date', 'data_type': 'date', 'granularity': 'day'},
        cluster_by=['pupil_id', 'subject_name']
    )
}}

with scored_subjects as (
    select distinct subject_name
    from {{ ref('ks2_scaled_score_conversion') }}
),

sittings as (
    select
        session_id,
        pupil_id,
        year_group,
        finished_date as sitting_date
    from {{ ref('stg_assessment_sittings') }}
    where is_complete
        and not is_deleted
        and session_type = 'summative_assessment'
        -- Allow-list, so a new style stays unscored until someone checks it
        and style in ('fixed_question', 'non_adaptive')
        and year_group between 1 and 6
        {% if is_incremental() %}
        and finished_date >= date_sub(_dbt_max_partition, interval {{ var('lookback_days') }} day)
        {% endif %}
),

pupils as (
    select pupil_id
    from {{ ref('stg_pupils') }}
    where not is_deleted
),

responses as (
    select
        session_id,
        question_id,
        is_correct,
        is_no_attempt
    from {{ ref('stg_responses') }}
    {% if is_incremental() %}
    -- A sitting can stay open for weeks, so read its early answers too
    where answered_date >= date_sub(
        _dbt_max_partition,
        interval {{ var('lookback_days') + var('max_sitting_days') }} day
    )
    {% endif %}
),

questions as (
    select
        question_id,
        subject_name
    from {{ ref('stg_course_hierarchy') }}
)

select
    sittings.sitting_date,
    sittings.session_id,
    sittings.pupil_id,
    questions.subject_name,
    sittings.year_group,
    responses.question_id,
    -- Duplicate copies share a timestamp, so no copy is "first": correct if any copy is correct
    logical_or(responses.is_correct) as is_correct,
    -- Skipped only if every copy was skipped, so a correct answer is never also skipped
    logical_and(responses.is_no_attempt) as is_no_attempt
from responses
-- Inner join drops answers whose session_id has no sitting row
inner join sittings on responses.session_id = sittings.session_id
inner join pupils on sittings.pupil_id = pupils.pupil_id
inner join questions on responses.question_id = questions.question_id
inner join scored_subjects on questions.subject_name = scored_subjects.subject_name
group by
    sittings.sitting_date,
    sittings.session_id,
    sittings.pupil_id,
    questions.subject_name,
    sittings.year_group,
    responses.question_id
