# IAM Migration Pack

**This folder is all you need.** Copy it to CloudShell (or your machine). Nothing outside this folder is required. No config files, no other repos.

- **For a short, presentable summary** of what you get and how it solves the migration: see **[WHAT_YOU_GET.md](WHAT_YOU_GET.md)**.
- **To run the full workflow:** use **[run_migration_workflow.sh](run_migration_workflow.sh)** — one script for both phases (see below).
- **To show your boss “almost done”:** after running the central phase, open **audit/MIGRATION_STATUS.md** (generated from the run; see below).

---

## Get this repo (download or clone)

Repo: **https://github.com/Cyborg-Hawk-AI/iam-mgmt-accounts**  
This pack is in the **`identity-center-migration-pack/`** subdirectory.

### Bash (Linux / macOS / Git Bash)

**Download as ZIP (no Git):**
```bash
curl -L -o iam-mgmt-accounts.zip https://github.com/Cyborg-Hawk-AI/iam-mgmt-accounts/archive/refs/heads/main.zip
unzip iam-mgmt-accounts.zip
cd iam-mgmt-accounts-main/identity-center-migration-pack
```

**Clone with Git (first time):**
```bash
git clone https://github.com/Cyborg-Hawk-AI/iam-mgmt-accounts.git
cd iam-mgmt-accounts/identity-center-migration-pack
```

**Pull latest (already cloned):**
```bash
cd iam-mgmt-accounts
git pull origin main
```

### PowerShell (Windows)

**Download as ZIP (no Git):**
```powershell
Invoke-WebRequest -Uri "https://github.com/Cyborg-Hawk-AI/iam-mgmt-accounts/archive/refs/heads/main.zip" -OutFile "iam-mgmt-accounts.zip" -UseBasicParsing
Expand-Archive -Path "iam-mgmt-accounts.zip" -DestinationPath "." -Force
cd iam-mgmt-accounts-main\identity-center-migration-pack
```

**Clone with Git (first time):**
```powershell
git clone https://github.com/Cyborg-Hawk-AI/iam-mgmt-accounts.git
cd iam-mgmt-accounts\identity-center-migration-pack
```

**Pull latest (already cloned):**
```powershell
cd iam-mgmt-accounts
git pull origin main
```

**Using real curl.exe (if installed):**
```powershell
curl.exe -L -o iam-mgmt-accounts.zip "https://github.com/Cyborg-Hawk-AI/iam-mgmt-accounts/archive/refs/heads/main.zip"
Expand-Archive -Path "iam-mgmt-accounts.zip" -DestinationPath "." -Force
```

---

## What problem this solves

You are moving **human user access** from one Identity Center org to another. You need to:

- Know exactly **which permission sets** to create in the new org (and what policies to attach).
- Have **custom (customer-managed) policies** saved as separate files so you can recreate them in the target accounts.
- Get a **human-readable guide** so you can manually create permission sets and groups and assign users without losing access.

This pack does that: it discovers and audits **only SSO roles** (Identity Center–created roles, `AWSReservedSSO_*`) in each account, extracts the policies attached to each, and produces one migration guide plus exported custom policies.

---

## Scope: Identity Center user access only

- **In scope:** Permission sets and the policies attached to them — i.e. what **human users** get when they sign in via Identity Center. We only discover **SSO roles** (`AWSReservedSSO_*`) and their managed/inline policies.
- **Out of scope (unchanged):** IAM users, IAM groups, service roles (e.g. EC2, Lambda), and any other IAM roles. They stay as-is in each account. This pack does not collect or migrate them.
- **Default:** `run_migration_workflow.sh --per-account` uses **SSO-only discovery** so only Identity Center roles and their policies are collected. Use `discover_and_upload.sh` without `--sso-only` only if you need full IAM discovery for other purposes.

---

## What you get at the end

After you run the steps below, you get a single place to look:

| You get | Where |
|--------|--------|
| **Human-readable migration guide** | `audit/MIGRATION_PACK.md` – lists each permission set to create, what to attach (AWS vs custom), and where custom policy JSONs live. |
| **Custom policies to recreate** | `audit/customer-policies/*.json` – one file per customer-managed policy; use these to create the same policy in the new account, then attach by ARN. |
| **Reference list for custom policies** | `audit/customer-policies/manifest.json` – maps policy ARN → filename. |
| **Machine-readable definitions** | `audit/permission_sets_to_create.json` – same info for scripts or copy-paste. |
| **Generated status report** | `audit/MIGRATION_STATUS.md` – created by the workflow from real data; show your boss what’s done and what’s left. |

You then **manually** in the new org: create permission sets (using the guide), recreate custom policies from the JSON files, create groups, assign groups to permission sets and accounts, and add users to groups.

---

## How you get it (two phases)

### Phase 1: In each account (e.g. CloudShell in Account 1, then 2, … 6)

1. Put **this whole folder** in that account’s environment.
2. In that folder run:
   ```bash
   ./run_migration_workflow.sh --per-account
   ```
   (This runs **SSO-only** discovery — only Identity Center roles and their policies — and creates the bundle; same as `./discover_and_upload.sh --bundle --sso-only`.)
3. Download the file it creates: `XXXXXXXXXXXX-iam-discovery.tar.gz` (12-digit account ID).
4. Repeat in the other 5 accounts. You should have **6 tarballs**.

**What this does:** In that account it discovers **only SSO roles** (Identity Center permission-set roles) and their policies, then packs that into one tarball per account. IAM users, service roles, and other IAM are not collected. It only reads from AWS; it does not change anything.

---

### Phase 2: In one central place (laptop or a single CloudShell)

1. Put **this whole folder** (same 8 items) in one directory.
2. Copy the **6 tarballs** from Phase 1 into that same directory.
3. Run the central phase (unpacks tarballs, then aggregate → audit → migration pack):
   ```bash
   ./run_migration_workflow.sh --central
   ```
   If account dirs are already unpacked: `./run_migration_workflow.sh --central-only`

**What this does:** Unpacks the 6 account dumps, merges them into one discovery file, finds all Identity Center SSO roles and their policies, then builds the human-readable guide and exports each custom policy into its own JSON file under `audit/customer-policies/`.

---

## What’s in this folder

| File | Role |
|------|------|
| **run_migration_workflow.sh** | **Main entry point.** Use `--per-account` in each account, then `--central` where tarballs are. |
| **README.md** | This file – what you get, how you get it, how it solves the issue. |
| **WHAT_YOU_GET.md** | Presentable summary of deliverables for your team. |
| **generate_boss_report.sh** | Generates audit/MIGRATION_STATUS.md from real data (run automatically in --central). |
| **discover_sso_only.sh** | **Used by default for migration.** Discovers only SSO roles (`AWSReservedSSO_*`) and their policies; no IAM users or service roles. |
| **discover_iam.sh** | Full IAM discovery (users, roles, groups, policies); use only if you need it for other purposes. |
| **analyze_policies.sh** | Called by workflow: analyzes policy overlaps (used for reports). |
| **generate_reports.sh** | Called by workflow: writes CSV reports. |
| **discover_and_upload.sh** | Used by run_migration_workflow.sh --per-account. |
| **aggregate_all_accounts.sh** | Used by run_migration_workflow.sh --central. |
| **audit_sso_roles.sh** | Used by run_migration_workflow.sh --central. |
| **generate_migration_pack.sh** | Used by run_migration_workflow.sh --central. |
| **export_all_identity_center.sh** | Run in **management account**. One-shot: runs all IdC exports. Outputs JSON + CSV under identity_center/. Read-only. |
| **export_identity_center_context.sh** | IdC instance + permission sets → context.json + .csv. Read-only. |
| **export_identity_center_assignments.sh** | Who has which permission set in which account → assignments.json + .csv. Needs context.json and accounts.txt. Read-only. |
| **export_identity_center_users_groups.sh** | Users, groups, memberships → .json + .csv each. Needs context.json. Read-only. |
| **export_organization_accounts.sh** | Optional: org accounts → org_accounts.json + .csv. Read-only. |
| **accounts.txt.example** | Example account list (one ID per line). Copy to accounts.txt for assignment export. |

**Requirements:** `jq` and `aws` CLI (CloudShell has them). `bc` is used by the analysis script (often preinstalled; if not: `sudo yum install bc`).

---

## One-page command summary

**In each of the 6 accounts:**
```bash
./run_migration_workflow.sh --per-account
# Download the created *-iam-discovery.tar.gz
```

**In central (same folder + 6 tarballs):**
```bash
./run_migration_workflow.sh --central
```

**Then open:** `audit/MIGRATION_PACK.md` (migration plan) and `audit/MIGRATION_STATUS.md` (generated status for your boss).

---

## Single-account variant

If you only have **one** account to migrate:

**In that account:**
```bash
./discover_and_upload.sh
```

**Then (same account or copy the account folder out):**
```bash
./audit_sso_roles.sh --input ACCOUNT_ID/data/raw/iam_discovery.json
./generate_migration_pack.sh --audit-dir audit --discovery ACCOUNT_ID/data/raw/iam_discovery.json
```

Replace `ACCOUNT_ID` with the 12-digit id (e.g. `123456789012`).

---

You don’t need anything outside this folder. This README plus the scripts are the full set.

---

## Testing / validation

The pipeline has been tested with:

- **SSO-only discovery data:** One account with 2 SSO roles (AdminAccess, ReadOnlyAccess) and 1 customer-managed policy. Aggregate → audit → migration pack → boss report all complete successfully; `audit/MIGRATION_PACK.md`, `audit/MIGRATION_STATUS.md`, `audit/permission_sets_to_create.json`, and `audit/customer-policies/` contain the expected content.
- **Full workflow entry point:** `./run_migration_workflow.sh --central-only` with account dirs present runs all steps and prints the deliverables.
- **No mode:** `./run_migration_workflow.sh` with no arguments prints an error and usage (exit 1).
- **Per-account SSO-only:** `./discover_and_upload.sh --bundle --sso-only` runs SSO-only discovery and creates the tarball (analyze/reports skipped); `run_migration_workflow.sh --per-account` uses this by default.
- **Mixed accounts:** Central run with one account that has SSO roles and one with zero SSO roles; aggregate and audit produce correct counts and permission set list.

---

## Addendum: Information needed for deployment (run these to get it)

**Scope (clear):** Only **Identity Center (SSO)** is in scope. The reserved SSO roles in member accounts are Identity Center users; those are the only things migrating. Standard IAM users in those individual accounts are **not** in scope.

The following scripts run in the **management account** and are **read-only** (list/describe only; no create/update/delete). They output **both JSON and CSV** so you can supply the data in another session (e.g. paste or attach the `identity_center/` folder). **Do not change** your requirements Excel/CSV; these exports are in addition to it.

### What you already have (from Phases 1 and 2)

- **Per account:** SSO roles and all policies attached (from `./run_migration_workflow.sh --per-account` and the tarballs).
- **Central:** Aggregated permission set definitions, migration pack, and all policy JSON (from `./run_migration_workflow.sh --central`).
- **Requirements artifact:** Your Excel/CSV (e.g. *IAM Users Requirements (002).xlsx*) with accounts, console users, permission sets, customer managed policies, and future IAM groups — keep that as the source of truth; we do not modify it.

### What is still needed (and which scripts get it)

| Needed for deployment | Script that produces it | Where to run |
|------------------------|-------------------------|---------------|
| Identity Center instance ARN + identity store ID + list of permission set ARNs/names | `export_identity_center_context.sh` | **Management account only** |
| Who (user/group) is assigned which permission set in which account | `export_identity_center_assignments.sh` | **Management account only** |
| Users and groups in the identity store (to map Console Users → IdC principals) | `export_identity_center_users_groups.sh` | **Management account only** |
| Optional: full list of org accounts (ID, name, email) | `export_organization_accounts.sh` | **Management account only** |

All of these run in the **management account** (where IAM Identity Center lives). They write into the `identity_center/` directory. **Each script produces both JSON and CSV** (e.g. context.json + context_permission_sets.csv, assignments.json + assignments.csv, users.json + users.csv, groups.json + groups.csv, group_memberships.json + group_memberships.csv). That directory is gitignored; copy or zip it and supply it in your next session so deployment logic has everything.

---

### Exact scripts to run, in order

**Step 1 — Per account (each account you want to migrate)**

Run this in **each** of your target accounts (e.g. the accounts with *Migrate? = YES* in your requirements sheet). Example for 10 accounts: do this once in each of the 10.

| # | Where | Exact command | What you get |
|---|--------|----------------|--------------|
| 1 | Account **897951724172** (e.g. aws-mng-master01-hipaa) | `./run_migration_workflow.sh --per-account` | `897951724172-iam-discovery.tar.gz` — download it. |
| 2 | Account **145716576155** (e.g. aws-mng-network) | `./run_migration_workflow.sh --per-account` | `145716576155-iam-discovery.tar.gz` — download it. |
| 3 | Account **014756875833** (e.g. aws-mng-security) | `./run_migration_workflow.sh --per-account` | `014756875833-iam-discovery.tar.gz` — download it. |
| 4 | Account **224053811153** (e.g. aws-mng-sharedservices) | `./run_migration_workflow.sh --per-account` | `224053811153-iam-discovery.tar.gz` — download it. |
| 5 | Account **733961910710** (e.g. aws-mng-dev01-hipaa) | `./run_migration_workflow.sh --per-account` | `733961910710-iam-discovery.tar.gz` — download it. |
| 6 | Account **120529854533** (e.g. aws-mng-prod01-hipaa) | `./run_migration_workflow.sh --per-account` | `120529854533-iam-discovery.tar.gz` — download it. |
| 7 | Account **447465199726** (e.g. aws-mng-qa01-hipaa) | `./run_migration_workflow.sh --per-account` | `447465199726-iam-discovery.tar.gz` — download it. |
| 8 | Account **182461150491** (e.g. aws-mng-bio-prod01-hipaa) | `./run_migration_workflow.sh --per-account` | `182461150491-iam-discovery.tar.gz` — download it. |
| 9 | Account **270812177724** (e.g. aws-mng-bio-qa01-hipaa) | `./run_migration_workflow.sh --per-account` | `270812177724-iam-discovery.tar.gz` — download it. |
| 10 | Account **210505675092** (e.g. aws-mng-bio-dev01-hipaa) | `./run_migration_workflow.sh --per-account` | `210505675092-iam-discovery.tar.gz` — download it. |

Use the same pack (this folder) in each account; only the account ID and output tarball name change. If your requirements list different or fewer accounts, run **only** in those accounts; the table above matches the *Migrate? = YES* rows from *IAM Users Requirements (002).xlsx*.

**Step 2 — Central (one place, e.g. laptop or single CloudShell)**

1. Put this folder and all 10 (or your number of) tarballs in one directory.
2. Run:
   ```bash
   ./run_migration_workflow.sh --central
   ```
   You get: `audit/MIGRATION_PACK.md`, `audit/permission_sets_to_create.json`, `audit/customer-policies/*.json`, and the rest of the migration pack.

**Step 3 — Management account only (Identity Center exports)**

Use the **same** pack folder (or a copy) in the **management account** (e.g. 897951724172 if that is your IdC management account). Run these in order:

| Order | Exact command | Produces |
|-------|----------------|----------|
| 3a | `cp accounts.txt.example accounts.txt` | (Optional) Edit so one account ID per line for assignments export. |
| 3b | `./export_identity_center_context.sh` | context.json + context_instance.csv + context_permission_sets.csv. |
| 3c | `./export_identity_center_assignments.sh` | assignments.json + assignments.csv. Requires context.json and accounts.txt. |
| 3d | `./export_identity_center_users_groups.sh` | users, groups, group_memberships (each .json + .csv). Requires context.json. |
| 3e | `./export_organization_accounts.sh` | (Optional) org_accounts.json + org_accounts.csv. |
| **One-shot** | `./export_all_identity_center.sh` | Runs 3b, 3c (if accounts.txt exists), 3d, 3e. All outputs in identity_center/ as JSON and CSV. |

**Step 4 — Copy everything to one place**

Copy the `identity_center/` directory (context, assignments, users, groups, group_memberships, and optionally org_accounts) into the same central location where you have the unpacked account dirs and the `audit/` folder. That gives deployment scripts (or a human) everything in one place:

- Discovery and migration pack (permission set definitions + policy JSON).
- IdC instance and permission set ARNs.
- Current assignments per account.
- Users and groups in the identity store (to map “Console Users” to IdC principals).

No changes are made to your requirements Excel/CSV; it remains the source of truth. The scripts above only **read** from AWS and from your accounts list to produce the extra files needed for deployment.

---

## How to get this information (APIs and output files)

This section is the **single reference** for what the management-account export scripts do, which AWS APIs they call, and exactly which files they produce. Use it to verify you have everything needed for deployment.

**Scope:** Only **Identity Center (SSO)** is in scope. The scripts below read **only** from IAM Identity Center and (optionally) AWS Organizations. They do not create, update, or delete any resources.

### Prerequisites

- **Where to run:** Management account (the account that owns IAM Identity Center).
- **CLI:** `aws` and `jq`. Ensure your profile or env targets the management account.
- **Optional:** Copy `accounts.txt.example` to `accounts.txt` and put one account ID per line (the member accounts you want assignment data for). If `accounts.txt` is missing, `export_identity_center_assignments.sh` is skipped by `export_all_identity_center.sh`.

### Commands to run (order matters)

Run from the **identity-center-migration-pack** folder:

```bash
# Optional: list member accounts to export assignments for
cp accounts.txt.example accounts.txt
# Edit accounts.txt so it has one 12-digit account ID per line.

# 1) Instance + permission sets (required for the next two)
./export_identity_center_context.sh

# 2) Assignments per account (needs context.json + accounts.txt)
./export_identity_center_assignments.sh

# 3) Users, groups, and group memberships (needs context.json)
./export_identity_center_users_groups.sh

# 4) Optional: all org accounts
./export_organization_accounts.sh
```

**One-shot (runs 1–4 in order):**

```bash
./export_all_identity_center.sh
```

All outputs go under **`identity_center/`** (created if missing; gitignored). Copy or zip that folder and supply it for deployment (or your next session).

### APIs used (read-only, for audit)

| Script | AWS service | API calls | Pagination |
|--------|-------------|-----------|------------|
| `export_identity_center_context.sh` | sso-admin | `list-instances` | — |
| | sso-admin | `list-permission-sets` | Yes (`NextToken` → `--starting-token`) |
| | sso-admin | `describe-permission-set` | One per permission set |
| `export_identity_center_assignments.sh` | sso-admin | `list-account-assignments` | Yes, per (account, permission set) |
| `export_identity_center_users_groups.sh` | identitystore | `list-users` | Yes |
| | identitystore | `list-groups` | Yes |
| | identitystore | `list-group-memberships` | Yes, per group |
| `export_organization_accounts.sh` | organizations | `list-accounts` | Yes (CLI default) |

All paginated calls are looped until `NextToken` is empty so you get **all** instances, permission sets, assignments, users, groups, and memberships.

### Output files (exact names under `identity_center/`)

| Script | JSON | CSV |
|--------|------|-----|
| Context | `context.json` | `context_instance.csv`, `context_permission_sets.csv` |
| Assignments | `assignments.json` | `assignments.csv` |
| Users | `users.json` | `users.csv` |
| Groups | `groups.json` | `groups.csv` |
| Group memberships | `group_memberships.json` | `group_memberships.csv` |
| Org accounts | `org_accounts.json` | `org_accounts.csv` |

**Checklist before handing off:** Ensure `identity_center/` contains at least `context.json`, `assignments.json`, `users.json`, `groups.json`, and `group_memberships.json` (and their CSV counterparts). Optionally include `org_accounts.json` / `org_accounts.csv`. Then zip or copy the folder for deployment.
