with source as (
    select * from {{ source('de_raw', 'assessment_sittings') }}
)

select
    session_id,
    pupil_id,
    assessment_id,
    session_type,
    style,
    year_group_at_sitting as year_group,
    total_questions,
    -- Unknown completeness counts as incomplete, so an unverified sitting never scores
    coalesce(is_complete, false) as is_complete,
    coalesce(is_deleted, false) as is_deleted,
    started_at,
    finished_at
from source
