"""
Generates sample source data for the Bank Savings Account dbt+Snowflake project.
Simulates files that would land in S3 (raw/bronze layer).

Outputs:
  branches.csv              - 8 branches (static reference)
  customers.csv             - 3,000 customers
  accounts_day1.csv         - 3,500 accounts, initial load (snapshot source v1)
  accounts_day2.csv         - same 3,500 accounts, ~400 changed (interest rate /
                               status changes) to demonstrate SCD Type 2 via dbt snapshot
  transactions_batch1.csv   - 40,000 transactions (initial/full load)
  transactions_batch2.csv   - 10,000 transactions (incremental/delta load, later txn_date)
                               -> combined = 50,000 transactions total
"""
import csv
import random
from datetime import datetime, timedelta
from faker import Faker

fake = Faker("en_IN")
Faker.seed(42)
random.seed(42)

OUT = "/home/claude/bank_dbt_project/sample_data"

# ---------------------------------------------------------------------------
# 1. BRANCHES (small static dimension)
# ---------------------------------------------------------------------------
cities = [("Mumbai", "MH"), ("Bangalore", "KA"), ("Hyderabad", "TS"), ("Pune", "MH"),
          ("Chennai", "TN"), ("Delhi", "DL"), ("Kolkata", "WB"), ("Ahmedabad", "GJ")]

branches = []
for i, (city, state) in enumerate(cities, start=1):
    branches.append({
        "branch_id": f"BR{i:03d}",
        "branch_name": f"{city} Main Branch",
        "city": city,
        "state": state,
        "ifsc_code": f"BANK0{i:06d}",
        "opened_date": fake.date_between(start_date="-15y", end_date="-5y").isoformat(),
    })

with open(f"{OUT}/branches.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=branches[0].keys())
    w.writeheader()
    w.writerows(branches)

# ---------------------------------------------------------------------------
# 2. CUSTOMERS
# ---------------------------------------------------------------------------
N_CUSTOMERS = 3000
kyc_statuses = ["VERIFIED", "VERIFIED", "VERIFIED", "PENDING", "REJECTED"]  # weighted

customers = []
for i in range(1, N_CUSTOMERS + 1):
    created = fake.date_time_between(start_date="-4y", end_date="-30d")
    customers.append({
        "customer_id": f"CUST{i:06d}",
        "first_name": fake.first_name(),
        "last_name": fake.last_name(),
        "dob": fake.date_of_birth(minimum_age=18, maximum_age=75).isoformat(),
        "email": fake.email(),
        "phone": fake.msisdn()[:10],
        "address": fake.street_address().replace("\n", ", "),
        "city": random.choice(cities)[0],
        "state": random.choice(cities)[1],
        "kyc_status": random.choice(kyc_statuses),
        "created_at": created.isoformat(sep=" "),
    })

with open(f"{OUT}/customers.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=customers[0].keys())
    w.writeheader()
    w.writerows(customers)

# ---------------------------------------------------------------------------
# 3. ACCOUNTS  -> two versions to demonstrate SCD2 via dbt snapshot
# ---------------------------------------------------------------------------
N_ACCOUNTS = 3500  # some customers have 2 accounts
account_types = ["REGULAR SAVINGS", "SALARY SAVINGS", "SENIOR CITIZEN SAVINGS"]

accounts_v1 = []
for i in range(1, N_ACCOUNTS + 1):
    cust = random.choice(customers)
    branch = random.choice(branches)
    opened = fake.date_between(start_date="-3y", end_date="-60d")
    interest_rate = round(random.choice([2.75, 3.0, 3.5, 4.0]), 2)
    status = random.choices(["ACTIVE", "DORMANT", "CLOSED"], weights=[85, 10, 5])[0]
    accounts_v1.append({
        "account_id": f"ACC{i:06d}",
        "customer_id": cust["customer_id"],
        "branch_id": branch["branch_id"],
        "account_type": random.choice(account_types),
        "account_status": status,
        "interest_rate": interest_rate,
        "opened_date": opened.isoformat(),
        "closed_date": "" if status != "CLOSED" else fake.date_between(start_date=opened, end_date="today").isoformat(),
        "updated_at": datetime(2026, 6, 1, 9, 0, 0).isoformat(sep=" "),
    })

with open(f"{OUT}/accounts_day1.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=accounts_v1[0].keys())
    w.writeheader()
    w.writerows(accounts_v1)

# Day 2 snapshot: ~400 accounts get a change (interest rate hike, status change -> SCD2 target)
accounts_v2 = []
changed_ids = set(random.sample(range(len(accounts_v1)), 400))
for idx, row in enumerate(accounts_v1):
    new_row = dict(row)
    if idx in changed_ids:
        if row["account_status"] == "ACTIVE" and random.random() < 0.3:
            new_row["account_status"] = "DORMANT"
        else:
            new_row["interest_rate"] = round(row["interest_rate"] + random.choice([0.25, 0.5]), 2)
        new_row["updated_at"] = datetime(2026, 7, 1, 9, 0, 0).isoformat(sep=" ")
    accounts_v2.append(new_row)

with open(f"{OUT}/accounts_day2.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=accounts_v2[0].keys())
    w.writeheader()
    w.writerows(accounts_v2)

# ---------------------------------------------------------------------------
# 4. TRANSACTIONS -> 40k initial batch + 10k incremental batch = 50k total
# ---------------------------------------------------------------------------
txn_types = ["DEPOSIT", "WITHDRAWAL", "INTEREST_CREDIT", "FEE_DEBIT", "UPI_TRANSFER"]
channels = ["BRANCH", "ATM", "ONLINE", "UPI", "MOBILE_APP"]

active_accounts = [a for a in accounts_v2 if a["account_status"] != "CLOSED"]

def gen_transactions(n, start_id, date_start, date_end):
    rows = []
    for i in range(n):
        acc = random.choice(active_accounts)
        txn_type = random.choices(txn_types, weights=[35, 30, 5, 5, 25])[0]
        amount = round(random.uniform(100, 75000), 2)
        if txn_type in ("WITHDRAWAL", "FEE_DEBIT", "UPI_TRANSFER"):
            amount = -amount if random.random() < 0.5 else amount  # sign handled by type, keep positive amt, direction via type
            amount = abs(amount)
        txn_date = fake.date_time_between(start_date=date_start, end_date=date_end)
        rows.append({
            "transaction_id": f"TXN{start_id + i:08d}",
            "account_id": acc["account_id"],
            "txn_date": txn_date.isoformat(sep=" "),
            "txn_type": txn_type,
            "amount": amount,
            "channel": random.choice(channels),
            "created_at": txn_date.isoformat(sep=" "),
        })
    return rows

batch1 = gen_transactions(40000, 1, "-90d", "-31d")
batch2 = gen_transactions(10000, 40001, "-30d", "now")

with open(f"{OUT}/transactions_batch1.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=batch1[0].keys())
    w.writeheader()
    w.writerows(batch1)

with open(f"{OUT}/transactions_batch2.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=batch2[0].keys())
    w.writeheader()
    w.writerows(batch2)

print("Generated:")
print(f"  branches.csv              : {len(branches)} rows")
print(f"  customers.csv              : {len(customers)} rows")
print(f"  accounts_day1.csv          : {len(accounts_v1)} rows")
print(f"  accounts_day2.csv          : {len(accounts_v2)} rows ({len(changed_ids)} changed)")
print(f"  transactions_batch1.csv    : {len(batch1)} rows")
print(f"  transactions_batch2.csv    : {len(batch2)} rows")
print(f"  TOTAL TRANSACTIONS         : {len(batch1) + len(batch2)} rows")
