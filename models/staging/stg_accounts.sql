with source as (
    select * from {{ source('raw', 'raw_accounts') }}
)

select
    account_id,
    customer_id,
    branch_id,
    account_type,
    account_status,
    interest_rate,
    opened_date,
    closed_date,
    updated_at
from source
