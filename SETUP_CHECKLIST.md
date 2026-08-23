# Setup Checklist — Continuing This Project in Claude Code

## 1. Get the folder onto your machine
- Unzip `bank_savings_dbt_snowflake_project.zip` anywhere, e.g. `~/projects/bank_savings_dbt_snowflake_project`
- Open a terminal there and run:
  ```
  git init
  git add .
  git commit -m "Initial commit: dbt + Snowflake bank savings project"
  ```

## 2. Open it in Claude Code
```
cd ~/projects/bank_savings_dbt_snowflake_project
claude
```
Claude Code will pick up the whole repo as context automatically.

## 3. Local tooling Claude Code will need available
- Python 3.9+ and `pip install dbt-core dbt-snowflake`
- (Optional) `snowsql` CLI if you want to PUT files to a stage from the command line
- A Snowflake account — free trial is fine (snowflake.com/trial), or your work account
  if you have sandbox access

## 4. Give Claude Code your Snowflake credentials
- Copy `profiles_template.yml` → `~/.dbt/profiles.yml` and fill in your account/user/password
  (or set up key-pair auth — ask Claude Code to help configure it)
- **Never commit `profiles.yml`** — the `.gitignore` already excludes it, but double-check
- For AWS S3 (if you want the real external stage instead of the internal-stage quick-start),
  have your AWS access key or IAM role ARN ready

## 5. Good first prompts to give Claude Code
- "Run the Snowflake setup scripts in snowflake_setup/ in order, then load the sample_data CSVs"
- "Run dbt deps, dbt seed, dbt snapshot, then dbt run and show me any failures"
- "Walk me through what happens when I load accounts_day2.csv and re-run dbt snapshot"
- "Add a Streams + Tasks pipeline so new transaction files in the stage auto-trigger a load"
- "Set up a GitHub Actions workflow that runs dbt build on every push"

## 6. Natural next steps to extend the project (good interview-prep exercises)
- Add Snowflake Streams + Tasks for CDC-style automation (topic #16 from the Snowflake list)
- Add Time Travel / zero-copy clone demo scripts (topics #12–13)
- Wire up real CI/CD (GitHub Actions or Jenkins) running `dbt build` on PRs
- Swap the internal stage for a real S3 external stage + storage integration
- Add a `dbt_expectations` distribution test on transaction amounts
