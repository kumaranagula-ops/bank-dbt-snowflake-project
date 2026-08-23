with source as (
    select * from {{ source('raw', 'raw_customers') }}
)

select
    customer_id,
    initcap(trim(first_name))              as first_name,
    initcap(trim(last_name))               as last_name,
    dob,
    datediff('year', dob, current_date())  as age,
    lower(trim(email))                     as email,
    phone,
    address,
    city,
    state,
    kyc_status,
    created_at
from source
where customer_id is not null
