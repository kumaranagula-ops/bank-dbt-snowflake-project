select
    customer_id,
    first_name,
    last_name,
    first_name || ' ' || last_name as full_name,
    dob,
    age,
    email,
    phone,
    address,
    city,
    state,
    kyc_status,
    created_at as customer_since
from {{ ref('stg_customers') }}
