-- Singular test: savings accounts (no overdraft facility) should never show
-- a running balance below -1 (small buffer for rounding). Fails the build if any do.

select
    account_id,
    transaction_id,
    running_balance
from {{ ref('fct_transactions') }}
where running_balance < -1
