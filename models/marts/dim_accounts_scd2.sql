-- Full SCD Type 2 history of accounts, sourced from the dbt snapshot.
-- Every interest-rate change or status change (e.g. ACTIVE -> DORMANT) gets
-- its own row with valid_from / valid_to, so historical balances/interest
-- can always be reconstructed as-of any date.

select
    account_id,
    customer_id,
    branch_id,
    account_type,
    account_status,
    interest_rate,
    opened_date,
    closed_date,
    dbt_valid_from                                  as valid_from,
    dbt_valid_to                                     as valid_to,
    case when dbt_valid_to is null then true else false end as is_current
from {{ ref('accounts_snapshot') }}
