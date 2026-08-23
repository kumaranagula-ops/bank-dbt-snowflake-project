with source as (
    select * from {{ source('raw', 'raw_transactions') }}
)

select
    transaction_id,
    account_id,
    txn_date,
    cast(txn_date as date)                     as txn_date_key,
    txn_type,
    -- normalize sign: money out is negative, money in is positive
    case
        when txn_type in ('WITHDRAWAL', 'FEE_DEBIT', 'UPI_TRANSFER') then -abs(amount)
        else abs(amount)
    end                                          as signed_amount,
    abs(amount)                                   as amount,
    channel,
    created_at
from source
where transaction_id is not null
  and account_id is not null
