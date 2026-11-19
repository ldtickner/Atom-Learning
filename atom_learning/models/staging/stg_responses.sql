with source as (
    select * from {{ source('de_raw', 'responses') }}
)

select
    response_id,
    pupil_id,
    session_id,
    question_id,
    is_correct,
    is_no_attempt,
    seconds_taken,
    question_number,
    answered_at,
    -- UK date, to match as_of_date and the 1 September academic year start
    date(answered_at, 'Europe/London') as answered_date
    -- session_type left out: always MOCK_TEST and contradicts assessment_sittings.session_type
from source
