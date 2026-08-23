with source as (
    select * from {{ source('raw', 'raw_branches') }}
)

select
    branch_id,
    branch_name,
    city,
    state,
    ifsc_code,
    opened_date
from source
