{{ config(
    materialized = 'incremental',
    incremental_strategy = 'insert_overwrite',
    partition_by = {'field': 'as_of_date', 'data_type': 'date'},
    cluster_by = ['pupil_id', 'subject_name'],
    full_refresh = false
) }}

{% set as_of_var = var('as_of_date', none) %}

with daily as (
    select * from {{ ref('int_pupil_subject_daily_totals') }}
),

pupils as (
    select * from {{ ref('stg_pupils') }}
),

hierarchy as (
    select * from {{ ref('stg_course_hierarchy') }}
),

conversion as (
    select * from {{ ref('ks2_scaled_score_conversion') }}
),

as_of as (
    select
        {% if as_of_var %}
            date('{{ as_of_var }}')
        {% else %}
            (select max(sitting_date) from daily)
        {% endif %} as as_of_date
),

params as (
    select
        as_of_date,
        date(
            extract(year from as_of_date)
                - if(extract(month from as_of_date) >= 9, 0, 1),
            9, 1
        ) as academic_year_start
    from as_of
),

window_totals as (
    select
        daily.pupil_id,
        daily.subject_name,
        daily.year_group,
        daily.sitting_date,
        daily.n_questions,
        daily.n_correct,
        daily.n_not_attempted
    from daily
    cross join params
    where daily.sitting_date between params.academic_year_start and params.as_of_date
),

latest_year_group as (
    select
        pupil_id,
        year_group
    from window_totals
    qualify row_number() over (
        partition by pupil_id
        order by sitting_date desc, year_group desc
    ) = 1
),

pupil_subject_totals as (
    select
        window_totals.pupil_id,
        window_totals.subject_name,
        sum(window_totals.n_questions) as n_questions,
        sum(window_totals.n_correct) as n_correct,
        sum(window_totals.n_not_attempted) as n_not_attempted
    from window_totals
    inner join latest_year_group
        on window_totals.pupil_id = latest_year_group.pupil_id
        and window_totals.year_group = latest_year_group.year_group
    group by 1, 2
),

subjects as (
    select distinct subject_name
    from hierarchy
),

ks2_tests as (
    select distinct
        subject_name,
        ks2_test,
        max_raw_score
    from conversion
),

spine as (
    select
        pupils.pupil_id,
        subjects.subject_name
    from pupils
    cross join subjects
    where not pupils.is_deleted
),

calculated as (
    select
        spine.pupil_id,
        spine.subject_name,
        params.as_of_date,
        latest_year_group.year_group,
        ks2_tests.ks2_test,
        coalesce(totals.n_questions, 0) as n_questions,
        coalesce(totals.n_correct, 0) as n_correct,
        coalesce(totals.n_not_attempted, 0) as n_not_attempted,
        if(
            totals.n_questions > 0,
            cast(totals.n_correct as numeric) / totals.n_questions,
            null
        ) as percent_correct,
        ks2_tests.max_raw_score
    from spine
    cross join params
    left join pupil_subject_totals as totals
        on spine.pupil_id = totals.pupil_id
        and spine.subject_name = totals.subject_name
    left join latest_year_group
        on spine.pupil_id = latest_year_group.pupil_id
    left join ks2_tests
        on spine.subject_name = ks2_tests.subject_name
),

with_raw_mark as (
    select
        calculated.*,
        cast(round(percent_correct * max_raw_score) as int64) as equivalent_raw_mark
    from calculated
),

final as (
    select
        with_raw_mark.pupil_id,
        with_raw_mark.subject_name,
        with_raw_mark.as_of_date,
        with_raw_mark.year_group,
        with_raw_mark.ks2_test,
        with_raw_mark.n_questions,
        with_raw_mark.n_correct,
        with_raw_mark.n_not_attempted,
        with_raw_mark.percent_correct,
        with_raw_mark.equivalent_raw_mark,
        case
            when with_raw_mark.ks2_test is null then null
            when with_raw_mark.n_questions = 0 then null
            else coalesce(conversion.scaled_score, 80)
        end as sats_scaled_score,
        case
            when with_raw_mark.ks2_test is null then 'no_sats_equivalent'
            when with_raw_mark.n_questions = 0 then 'no_answers'
            when conversion.scaled_score is null then 'below_scale'
            when with_raw_mark.n_questions < {{ var('low_evidence_questions', 20) }} then 'low_evidence'
            else 'scored'
        end as score_status
    from with_raw_mark
    left join conversion
        on with_raw_mark.subject_name = conversion.subject_name
        and with_raw_mark.equivalent_raw_mark = conversion.raw_score
)

select * from final