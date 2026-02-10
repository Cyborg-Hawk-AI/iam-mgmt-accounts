# IAM Migration Pack

**This folder is all you need.** Copy it to CloudShell (or your machine). Nothing outside this folder is required. No config files, no other repos.

- **For a short, presentable summary** of what you get and how it solves the migration: see **[WHAT_YOU_GET.md](WHAT_YOU_GET.md)**.
- **To run the full workflow:** use **[run_migration_workflow.sh](run_migration_workflow.sh)** — one script for both phases (see below).
- **To show your boss “almost done”:** after running the central phase, open **audit/MIGRATION_STATUS.md** (generated from the run; see below).

---

## What problem this solves

You are moving **several AWS accounts** from one Identity Center org to another. You need to:

- Know exactly **which permission sets** to create in the new org (and what policies to attach).
- Have **custom (customer-managed) policies** saved as separate files so you can recreate them in the target accounts.
- Get a **human-readable guide** so you can manually create permission sets and groups and assign users without losing access.

This pack does that: it audits the **SSO roles** (Identity Center–created roles) in your accounts, extracts the policies attached to each, and produces one migration guide plus exported custom policies.

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
   (This runs discovery and creates the bundle; same as `./discover_and_upload.sh --bundle`.)
3. Download the file it creates: `XXXXXXXXXXXX-iam-discovery.tar.gz` (12-digit account ID).
4. Repeat in the other 5 accounts. You should have **6 tarballs**.

**What this does:** In that account it discovers IAM (users, roles, groups, policies), runs analysis and reports, and packs everything into one tarball per account. It only reads from AWS; it does not change anything.

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
| **discover_iam.sh** | Called by workflow: lists IAM users, roles, groups, and policies in one account. |
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

You don’t need anything outside this folder. This README plus the 7 scripts are the full set.
