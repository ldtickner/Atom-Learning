with source as (
    select * from {{ source('de_raw', 'pupils') }}
)

select
    pupil_id,
    -- Null treated as not deleted, so a pupil is never silently dropped by a filter
    coalesce(is_deleted, false) as is_deleted
from source
