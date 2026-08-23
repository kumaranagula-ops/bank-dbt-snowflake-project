{% snapshot accounts_snapshot %}

{{
    config(
        target_schema='snapshots',
        unique_key='account_id',
        strategy='timestamp',
        updated_at='updated_at',
        invalidate_hard_deletes=True
    )
}}

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
from {{ source('raw', 'raw_accounts') }}

{% endsnapshot %}
