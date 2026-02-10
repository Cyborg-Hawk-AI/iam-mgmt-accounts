# What You Get — Team Summary

**Purpose:** One-page view of the **deliverables** from the IAM migration pack: what the tooling produces, how it’s run, and how it supports the migration.

---

## The goal

- Migrate **multiple AWS accounts** from the current Identity Center (IdC) org to a **new IdC org**.
- **No one loses access:** we know exactly which permission sets and policies to recreate.
- **Custom (customer-managed) policies** are exported as JSON so they can be recreated in the target accounts and attached to the right permission sets.

---

## What you get (deliverables)

After running the pack (see “How you get it” below), you have a single place to work from: the **`audit/`** folder.

| Deliverable | Format | Use |
|-------------|--------|-----|
| **Migration guide** | `audit/MIGRATION_PACK.md` | Human-readable: list of permission sets to create, which AWS vs custom policies to attach, and where each custom policy document lives. **Primary doc to share and present.** |
| **Permission set definitions** | `audit/permission_sets_to_create.json` | Machine-readable: one object per permission set with `aws_managed_policy_arns`, `customer_managed_policy_arns`, and `inline_policies`. Use for automation or copy-paste. |
| **Custom policy documents** | `audit/customer-policies/<name>.json` | One JSON file per customer-managed policy. Recreate each policy in the target account, then attach by ARN to the matching permission set. |
| **Custom policy index** | `audit/customer-policies/manifest.json` | Maps policy ARN → filename so you know which file to use for each custom policy. |
| **SSO role audit (detail)** | `audit/sso_roles_audit.json` | Full list of Identity Center–created roles and their attached policies (for review or debugging). |
| **SSO role audit (table)** | `audit/sso_roles_audit.csv` | Same audit in CSV for spreadsheets or reporting. |
| **Status report (for your boss)** | `audit/MIGRATION_STATUS.md` | **Generated** by the workflow from real data: counts, permission set list, custom policy list, what’s done, what’s left. Re-run the central phase to refresh. |

**Presentable takeaway:**  
*“We get a single markdown guide (`MIGRATION_PACK.md`) that tells us exactly which permission sets to create and what to attach, plus a folder of custom policy JSONs to recreate so no access is lost.”*

---

## How you get it (high level)

1. **Per account (e.g. CloudShell in each of the 6 accounts)**  
   - Run: `./discover_and_upload.sh --bundle`  
   - Download the generated `{account_id}-iam-discovery.tar.gz` for that account.

2. **Central place (one machine or CloudShell)**  
   - Unpack all 6 tarballs into the same directory as the scripts (or use account dirs already there).  
   - Run: `./run_migration_workflow.sh --central` (or `--central-only` if already unpacked).  
   - This runs aggregate → audit → migration pack → **generates** `audit/MIGRATION_STATUS.md`.  

3. **Use the outputs**  
   - Open `audit/MIGRATION_PACK.md` for the migration plan.  
   - Open `audit/MIGRATION_STATUS.md` to show your boss what’s done and what’s left (all from this run).  
   - Recreate permission sets and custom policies in the new IdC org as described there.

---

## How it solves the problem

| Problem | How the pack helps |
|--------|---------------------|
| “We don’t know what’s in each account.” | Discovery (per account) captures IAM users, roles, groups, and policies. |
| “We don’t know which permission sets to create in the new org.” | The audit finds all Identity Center SSO roles and derives permission set names and attached policies → `permission_sets_to_create.json` and `MIGRATION_PACK.md`. |
| “Custom policies might be lost or mis-attached.” | Customer-managed policies are exported to `audit/customer-policies/*.json` and referenced in the guide so you recreate them and attach the right ARNs. |
| “We need something to hand to the team / management.” | `MIGRATION_PACK.md` is the single, shareable guide; CSVs and JSONs support automation or detailed review. |

---

## Scripts and APIs (vetted)

- **discover_iam.sh** — Uses standard IAM read-only APIs: `list-users`, `list-roles`, `list-groups`, `get-policy`, `get-policy-version`, `list-attached-*`, `list-*-policies`, `get-*-policy`. No writes.  
- **audit_sso_roles.sh** — Reads discovery JSON (or live IAM with `list-roles`, `list-attached-role-policies`, `list-role-policies`, `get-role-policy`). No writes.  
- **generate_migration_pack.sh** — Reads audit output and discovery/aggregated JSON; writes only to local `audit/` (markdown, manifest, policy JSONs).  
- **aggregate_all_accounts.sh** — Reads only local discovery files; writes only to local `aggregated/`.  

**Dry run:** The pipeline has been run end-to-end with minimal test data (one account, two SSO roles, one AWS-managed and one customer-managed policy). All steps complete successfully and produce the deliverables above.

---

## One-line summary for your team

*“We run discovery in each account, aggregate in one place, then run the audit and migration pack scripts. We get a clear migration guide plus exported custom policies so we can recreate permission sets and policies in the new Identity Center without losing access.”*
