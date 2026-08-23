with transactions as (
    select * from {{ ref('stg_transactions') }}
)

select
    transaction_id,
    account_id,
    txn_date,
    txn_date_key,
    txn_type,
    signed_amount,
    amount,
    channel,
    -- running balance per account, chronological order
    sum(signed_amount) over (
        partition by account_id
        order by txn_date, transaction_id
        rows between unbounded preceding and current row
    ) as running_balance
from transactions
