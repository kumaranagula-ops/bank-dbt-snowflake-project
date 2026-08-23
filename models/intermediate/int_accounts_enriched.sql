with accounts as (
    select * from {{ ref('stg_accounts') }}
),

customers as (
    select * from {{ ref('stg_customers') }}
),

branches as (
    select * from {{ ref('stg_branches') }}
)

select
    a.account_id,
    a.customer_id,
    c.first_name,
    c.last_name,
    c.kyc_status,
    a.branch_id,
    b.branch_name,
    b.city                 as branch_city,
    a.account_type,
    a.account_status,
    a.interest_rate,
    a.opened_date,
    a.closed_date,
    datediff('day', a.opened_date, coalesce(a.closed_date, current_date())) as account_age_days
from accounts a
left join customers c on a.customer_id = c.customer_id
left join branches  b on a.branch_id  = b.branch_id
