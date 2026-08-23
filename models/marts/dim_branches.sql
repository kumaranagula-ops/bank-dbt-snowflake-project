select
    branch_id,
    branch_name,
    city,
    state,
    ifsc_code,
    opened_date
from {{ ref('stg_branches') }}
