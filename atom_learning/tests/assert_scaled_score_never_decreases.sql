-- A higher raw mark must never give a lower scaled score.
-- Returns the rows that break this; the test passes when none come back.
with scored as (
    select
        ks2_test,
        raw_score,
        scaled_score,
        lag(scaled_score) over (partition by ks2_test order by raw_score) as previous_scaled_score
    from {{ ref('ks2_scaled_score_conversion') }}
    where scaled_score is not null
)

select
    ks2_test,
    raw_score,
    scaled_score,
    previous_scaled_score
from scored
where scaled_score < previous_scaled_score
