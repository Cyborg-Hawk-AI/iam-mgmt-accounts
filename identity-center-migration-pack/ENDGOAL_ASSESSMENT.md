# Assessment: IAM Users Requirements (002).xlsx — End Goal Artifact

**Purpose:** Learn from the target deliverable. This file describes the structure and content of the Excel artifact so our discovery and migration tooling can align to the same “end goal” shape. The Excel file is **not** modified.

---

## 1. Artifact structure (6 sheets)

| Sheet | Purpose | Key columns / structure |
|-------|---------|--------------------------|
| **Accounts** | Account inventory and migration scope | AWS Account, Account Name, Root Email, **Migrate?** (YES/NO), Description; grouped by Core / Workloads |
| **Console Users** | Who has access and which permission sets | Username, Name, Email, **Current Permission Sets** (comma-separated) |
| **SSO Permission Sets** | Full definition of each permission set | Permission Set, Policy, Type (AWS managed / Inline / Customer Managed), Inline Policy (JSON or “see Customer Managed tab”), **Account matrix** (Master, SS, Network, Security, Audit, LogArchive, Prod, QA, Dev, BioProd, BioQA, BioDev = 1/0), NOTES |
| **Customer Managed Policies** | Policy name + JSON document **per account** where it varies | Policy name; columns = Master, BioProd, BioQA, BioDev with full JSON (or reference) |
| **Future IAM Groups** | Proposed IAM groups and their policies | Group Name, Attached Policies, AWSManaged (True/blank), **Account matrix** (SS, Network, Master, …), notes |
| **ImpactedBucketPolicies** | (Empty in sample) — likely S3 bucket policy impact | — |

---

## 2. Learnings (what the end goal contains)

### 2.1 Accounts
- **Migrate?** drives scope: only “YES” accounts are in scope for IdC migration.
- Clear split: Core (master, audit, log archive, network, security) vs Workloads (shared services, dev/qa/prod, bio-*).
- Root email and description support ops and handover.

### 2.2 Console users (people → permission sets)
- One row per **user**: Username, display Name, Email.
- **Current Permission Sets** = comma-separated list of **permission set names** (e.g. `AWSAdministratorAccess`, `MNGITDeveloper`, `BioinformaticsDeveloper`).
- This is the **user–to–permission-set mapping** we need to preserve or recreate in the new Identity Center (e.g. who gets which assignment).

### 2.3 SSO Permission Sets (permission set → policies + account matrix)
- One **logical** permission set has **multiple rows**: one per **policy** (AWS managed, customer managed, or inline).
- Columns:
  - **Permission Set** — name (e.g. `AWSAdministratorAccess`, `BioinformaticsDeveloper`).
  - **Policy** — ARN name (e.g. `AdministratorAccess`, `PowerUserAccess`) or `INLINE`.
  - **Type** — e.g. “AWS managed”, “AWS managed - job function”, “Inline Policy”, “Customer Managed”.
  - **Inline Policy** — full JSON for inline; “see Customer Managed tab” for customer-managed.
- **Account matrix** — which accounts get this permission set: 1 = assigned, 0 = not. Columns map to account roles (Master, SharedServices, Network, Security, Audit, LogArchive, Prod, QA, Dev, BioProd, BioQA, BioDev).
- **NOTES** — short human notes (e.g. “IAM Create Edit MNG roles, Code Artifact, ECR”).

So the end goal is:
- **Per permission set:** list of policies (AWS + customer + inline) **and** which accounts that permission set is assigned to.

### 2.4 Customer Managed Policies
- **Policy name** (e.g. `mng-policy-bio-user-operations`, `mng-policy-bio-user-operations-kms`).
- **Per-account columns** (Master, BioProd, BioQA, BioDev): full **policy document JSON** when it differs by account (e.g. different account IDs in ARNs).
- Some cells: “see Customer Managed tab” in the Permission Sets sheet; the actual JSON lives here.
- So: customer-managed policies are **named**, and we need **retrievable JSON per policy** (and per account when it varies).

### 2.5 Future IAM Groups
- **Proposed** groups (e.g. `MNGBioinformaticsAssistant`, `MNGITDeveloper`).
- **Attached Policies** — mix of AWS managed (e.g. `ViewOnlyAccess`, `AdministratorAccess`) and customer-managed (e.g. `mng-policy-bio-user-operations-iam`).
- **Account matrix** — which accounts each group gets access to (1 = yes).
- Optional notes (e.g. “s3, efs”, “batch, cloudwatch, ec2, …”).
- This is the **target state** for IAM groups (or IdC groups) and their policies per account.

---

## 3. Mapping: our tooling → end goal

| End-goal element | Our current output | Gap / note |
|------------------|--------------------|------------|
| **Accounts** | Not produced by scripts; manual or separate inventory. | Could add: account list + “Migrate? ” from config or a small accounts input file. |
| **Console Users** (user → permission sets) | We do **not** discover IdP/users or their assignments. | Identity Center user/group assignments live in IdC; we only discover **SSO roles and their policies**. To get “Console Users” we need IdC API (list users/groups, list assignments) or manual export. |
| **SSO Permission Sets** (name + policies + account matrix) | **Partially:** We have permission set **name** (from role name), **policies per role** (AWS + customer + inline), and **JSON for inline/customer**. We do **not** have the **account matrix** (which accounts get which permission set) in one place; we have it implicitly per-account (each account’s discovery shows which SSO roles exist there). | Central aggregation gives “which permission sets exist and what policies they have”; to get the matrix we need “per account, which permission sets are assigned” (from IdC assignments or from per-account discovery). |
| **Customer Managed Policies** (name + JSON per account) | We export **customer-managed policy documents** to `customer-policies/<name>.json` (and inline to `inline-<Role>-<Name>.json`). We do **not** currently vary JSON by account in one table; we have one JSON per policy per account where we discovered it. | Structure is compatible: we have “policy name + JSON file”. Per-account variation (e.g. different ARNs) would require either one JSON per (policy, account) or a note that “see account X for variant”. |
| **Future IAM Groups** | Not produced; this is **design** (proposed groups and policies). | Out of scope for discovery; could be a separate “target design” template or sheet. |
| **ImpactedBucketPolicies** | Not produced. | Out of scope for current SSO-only discovery. |

---

## 4. Summary: what we have vs what the Excel is

- **We have (and align with):**
  - **SSO roles** (permission sets) and **all policies attached** (AWS-managed, customer-managed, inline).
  - **Policies per role** in human-readable form (SSO_ROLES_AND_POLICIES.md) and table form (policies_per_role_table.md/csv).
  - **All policy JSON** stored and retrievable (customer-policies/*.json, inline-*.json).
  - **Per-account** and **central** views (per-account report + aggregated audit + migration pack).

- **We do not produce (and would need elsewhere or as an add-on):**
  - **Accounts** sheet (account list + Migrate? + description) — manual or small input.
  - **Console Users** sheet (user → permission sets) — requires Identity Center (or IdP) list of users/groups and their assignments.
  - **Account matrix** (which permission set is in which account) in one table — derivable from per-account discovery (each account’s SSO roles) or from IdC assignment list.
  - **Customer Managed** with per-account JSON columns — we have JSON per policy; organizing by account when the document varies is a presentation/template step.
  - **Future IAM Groups** — design only.
  - **ImpactedBucketPolicies** — not in scope.

- **The Excel also includes:** full **inline policy JSON** in the Permission Sets sheet and full **customer-managed policy JSON** in the Customer Managed sheet (including per-account variants). We already store “all policy JSON” in files; the Excel is a **single-file, human-editable** packaging of the same idea (plus user list and account matrix).

---

## 5. Recommendations (audit)

1. **Keep producing:** SSO roles only, policies per role, human-readable + table + JSON; no change to the Excel.
2. **Optional enhancements to get closer to the Excel shape:**
   - **Account matrix:** From aggregated discovery, emit a small table: rows = permission set name, columns = account id/name, value = 1/0 (present in that account).
   - **Single “requirements” export:** Optional script that, from aggregated + audit output, generates a CSV or simple Excel-friendly format: Permission Set, Policy, Type, [account columns], Notes — so someone can paste or link into an “SSO Permission Sets” style sheet.
   - **Console Users:** Document that this must come from Identity Center (list-assignment-for-account, list-users-in-group, etc.) or from the IdP; we do not discover user identities from IAM.
3. **Customer-managed per-account:** When the same policy name exists in multiple accounts with different JSON (e.g. different ARNs), we could add a convention: `customer-policies/<name>--<account_id>.json` and mention it in the report.
4. **Future IAM Groups:** Leave as design-only; no discovery needed.

---

*Assessment date: 2025-02-09. Source: IAM Users Requirements (002).xlsx — read-only analysis.*
