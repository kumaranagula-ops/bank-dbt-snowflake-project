select
    account_id,
    date_trunc('month', txn_date)          as txn_month,
    count(transaction_id)                   as txn_count,
    sum(case when signed_amount > 0 then signed_amount else 0 end) as total_deposits,
    sum(case when signed_amount < 0 then abs(signed_amount) else 0 end) as total_withdrawals,
    sum(signed_amount)                      as net_change,
    max(running_balance)                    as month_end_balance
from {{ ref('fct_transactions') }}
group by 1, 2
