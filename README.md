# IAM Permission Consolidation & Identity Center Migration Helper

This repo exists to help me migrate legacy IAM users/roles in **multiple existing AWS accounts** into a clean, **AWS Identity Center (SSO)** model, **without breaking anyone’s access**, and while **eliminating redundant / unused permissions**.

Cursor AI: your job is to help me **analyze**, **normalize**, and **consolidate** IAM permissions so I can design a small set of clean permission sets for Identity Center.

---

## High-Level Problem

- Today:
  - Accounts use **legacy IAM users, groups, and roles**.
  - There are **overlapping managed policies**, **inline policies**, and **permissions that may no longer be used**.
  - No clear, standardized naming or structure for permissions.

- Target state:
  - Accounts live under a **standardized Organizational Unit (OU)**.
  - Human access is via **AWS Identity Center permission sets**, not ad-hoc IAM users.
  - IAM policies are:
    - **Consolidated** (minimal distinct sets).
    - **Least-privilege** where realistic.
    - **Named and structured** according to a clear convention.

My job: **extract what people actually use**, cluster similar permissions, design **permission sets** that map to **job functions / environment types**, and produce a **migration plan**.

---

## Constraints & Non-Negotiables

Cursor, treat these as hard requirements:

1. **No surprise outages**
   - Do **not** remove or tighten permissions blindly.
   - Everything must be:
     - Discover → Analyze → Propose → Dry-run (where possible) → Implement.

2. **Read-first, write-later**
   - Initial tooling must be **read-only**: list/describe resources, fetch policy docs, access advisor, last-used data, etc.
   - Only later should we generate **Terraform / CloudFormation / JSON** outputs for changes.

3. **Multi-account**
   - Assume I will run this against **multiple AWS accounts**, often via:
     - `aws sso login` followed by `aws sts assume-role`, or
     - Direct IAM access profile.
   - Code should **support a list of account IDs / profiles**.

4. **Auditable**
   - Every decision must be traceable:
     - “This permission set came from these users/roles.”
     - “These actions appear unused based on last-accessed data.”

5. **You must question my assumptions**
   - If I ask for something dangerous or naive (e.g., “just remove unused permissions based on last 7 days”), push back and propose safer alternatives.

---

## Goals for This Repo

Cursor, help me build:

1. **Discovery tooling**
   - Enumerate:
     - IAM users
     - IAM roles
     - Groups
     - Attached **managed** and **inline** policies
   - Record:
     - Policy documents
     - Policy attachments (who uses what)
     - **Access Advisor / last-used** info where available.

2. **Analysis & Consolidation**
   - Compute:
     - Overlap between policies (same actions/resources expressed differently).
     - Clusters of **similar effective permissions**.
   - Suggest:
     - Candidate **“base” policy sets** (e.g., `readonly`, `developer`, `ops`, `admin`, `data-analyst`, etc.).
     - Environment-specific overlays (`-dev`, `-qa`, `-prod`).

3. **Reporting**
   - Generate **CSV / JSON reports** per account, for example:
     - `principal_permissions.csv`
       - `account_id`, `principal_type`, `principal_name`, `policy_arn_or_name`, `policy_type`, `effective_permissions_hash`, `used_recently (bool)`
     - `policy_overlap_report.csv`
       - `policy_name_a`, `policy_name_b`, `%_overlap`, `extra_actions_a`, `extra_actions_b`
   - Summaries:
     - “Top N distinct permission profiles in this account.”
     - “Likely candidates for standard permission sets.”

4. **Identity Center Target Mapping (Later Phase)**
   - Helpers to translate cluster results into **Identity Center permission set definitions** (JSON / Terraform skeletons).
   - Example:
     - `permissionset_developer_nonprod.json`
     - `permissionset_ops_prod.json`

---

## Proposed Tech Stack & Structure

**Primary language:** Python 3  
**Libraries:** `boto3`, `botocore`, `json`, `argparse`, basic data analysis code (no heavy deps unless needed).

Suggested repo structure:

```text
.
├── README.md
├── requirements.txt
├── config/
│   └── accounts.yaml         # list of accounts/profiles/roles to scan
├── scripts/
│   ├── discover_iam.py       # pulls all IAM principals + policies + usage
│   ├── analyze_policies.py   # computes overlaps, clusters, candidate sets
│   ├── generate_reports.py   # exports CSV/JSON reports
│   └── utils_aws.py          # shared session/account-iteration helpers
├── data/
│   ├── raw/                  # per-account raw dumps (JSON)
│   └── processed/            # normalized outputs, overlaps, clusters
└── output/
    ├── reports/              # human-readable CSV/HTML
    └── proposals/            # candidate policy sets, permission sets
