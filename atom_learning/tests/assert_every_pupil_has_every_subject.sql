-- Each as_of_date must have one row per active pupil per subject.
-- Returns dates that break this. The test passes when none come back.
with expected as (
    select
        (select count(*) from {{ ref('stg_pupils') }} where not is_deleted)
        * (select count(distinct subject_name) from {{ ref('stg_course_hierarchy') }})
        as expected_rows
)

select
    fct.as_of_date,
    count(*) as actual_rows,
    expected.expected_rows
from {{ ref('fct_pupil_subject_sats_score') }} as fct
cross join expected
group by fct.as_of_date, expected.expected_rows
having count(*) != expected.expected_rows