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
