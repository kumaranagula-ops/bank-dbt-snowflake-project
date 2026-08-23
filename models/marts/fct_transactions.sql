{{
    config(
        materialized='incremental',
        unique_key='transaction_id',
        incremental_strategy='merge',
        on_schema_change='append_new_columns',
        cluster_by=['txn_date_key'],
        snowflake_warehouse='BANK_WH'
    )
}}

with transactions as (
    select * from {{ ref('int_transactions_with_balance') }}
    {% if is_incremental() %}
    -- only process rows newer than what's already in the table
    -- (mirrors a new batch file landing in S3 each run)
    where txn_date > (select coalesce(max(txn_date), '1900-01-01') from {{ this }})
    {% endif %}
),

accounts as (
    select account_id, account_type, account_status, branch_id
    from {{ ref('stg_accounts') }}
)

select
    t.transaction_id,
    t.account_id,
    a.account_type,
    a.branch_id,
    t.txn_date,
    t.txn_date_key,
    t.txn_type,
    t.signed_amount,
    t.amount,
    t.channel,
    t.running_balance
from transactions t
left join accounts a on t.account_id = a.account_id
