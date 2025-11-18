# Codebase Index & Analysis

**Last Updated:** 2025-01-27  
**Status:** 🟡 Initial Phase - Planning & Discovery

---

## Project Overview

**Project Name:** IAM Permission Consolidation & Identity Center Migration Helper  
**Purpose:** Migrate legacy IAM users/roles across multiple AWS accounts into AWS Identity Center (SSO) with clean, consolidated permission sets.

**Key Objectives:**
- Analyze existing IAM permissions across multiple AWS accounts
- Normalize and consolidate overlapping permissions
- Design standardized permission sets for AWS Identity Center
- Generate migration plans without breaking access

---

## Current Codebase Status

### Existing Files

| File | Purpose | Status |
|------|---------|--------|
| `README.md` | Project documentation, goals, constraints, and proposed structure | ✅ Complete |

### Planned Structure (Not Yet Implemented)

```
.
├── README.md                          ✅ EXISTS
├── CODEBASE_INDEX.md                  ✅ EXISTS (this file)
├── requirements.txt                   ⏳ PLANNED
├── config/
│   └── accounts.yaml                  ⏳ PLANNED - Account/profiles/roles to scan
├── scripts/
│   ├── discover_iam.py                ⏳ PLANNED - IAM discovery tool
│   ├── analyze_policies.py            ⏳ PLANNED - Policy analysis & clustering
│   ├── generate_reports.py            ⏳ PLANNED - Report generation
│   └── utils_aws.py                  ⏳ PLANNED - AWS session helpers
├── data/
│   ├── raw/                           ⏳ PLANNED - Per-account raw JSON dumps
│   └── processed/                     ⏳ PLANNED - Normalized outputs
└── output/
    ├── reports/                       ⏳ PLANNED - CSV/HTML reports
    └── proposals/                     ⏳ PLANNED - Candidate policy sets
```

---

## Component Analysis

### 1. Discovery Module (`scripts/discover_iam.py`)

**Purpose:** Read-only enumeration of IAM resources across accounts

**Key Functions (Planned):**
- `enumerate_users()` - List all IAM users
- `enumerate_roles()` - List all IAM roles
- `enumerate_groups()` - List all IAM groups
- `get_attached_policies(principal)` - Get managed policies
- `get_inline_policies(principal)` - Get inline policies
- `get_access_advisor_data(principal)` - Get last-used information
- `fetch_policy_document(policy_arn)` - Retrieve policy JSON

**Dependencies:**
- `boto3` (IAM, Access Analyzer)
- `utils_aws.py` for multi-account iteration

**Output:**
- Raw JSON dumps in `data/raw/{account_id}/`

---

### 2. Analysis Module (`scripts/analyze_policies.py`)

**Purpose:** Compute overlaps, clusters, and candidate permission sets

**Key Functions (Planned):**
- `normalize_policy_document(policy)` - Standardize policy format
- `extract_actions(policy)` - Extract all IAM actions
- `compute_overlap(policy_a, policy_b)` - Calculate % overlap
- `cluster_similar_policies(policies)` - Group similar permissions
- `suggest_permission_sets(clusters)` - Generate candidate sets
- `identify_unused_permissions(principal, access_advisor)` - Flag unused actions

**Dependencies:**
- Policy parsing logic
- Clustering algorithm (simple similarity or ML-based)

**Output:**
- Processed data in `data/processed/`
- Overlap matrices
- Cluster assignments

---

### 3. Reporting Module (`scripts/generate_reports.py`)

**Purpose:** Generate human-readable reports and proposals

**Key Functions (Planned):**
- `generate_principal_permissions_csv(account_data)` - Principal → permissions mapping
- `generate_overlap_report(overlaps)` - Policy overlap analysis
- `generate_summary_report(analysis)` - High-level summaries
- `generate_permission_set_proposals(clusters)` - Identity Center proposals

**Output Formats:**
- CSV reports in `output/reports/`
- JSON proposals in `output/proposals/`
- Optional HTML dashboards

---

### 4. AWS Utilities (`scripts/utils_aws.py`)

**Purpose:** Multi-account session management and helpers

**Key Functions (Planned):**
- `get_session(account_id, profile, role)` - Create boto3 session
- `iterate_accounts(config)` - Loop through accounts from config
- `assume_role_session(account_id, role_name)` - Assume role helper
- `validate_access(session)` - Verify IAM read permissions

**Dependencies:**
- `boto3`
- `config/accounts.yaml`

---

## Data Flow

```
1. CONFIG → accounts.yaml
   ↓
2. DISCOVERY → scripts/discover_iam.py
   ↓
   data/raw/{account_id}/*.json
   ↓
3. ANALYSIS → scripts/analyze_policies.py
   ↓
   data/processed/{account_id}/*.json
   ↓
4. REPORTING → scripts/generate_reports.py
   ↓
   output/reports/*.csv
   output/proposals/*.json
```

---

## Key Constraints & Requirements

### Hard Requirements
1. **Read-first approach** - Initial tooling must be read-only
2. **No surprise outages** - Discover → Analyze → Propose → Dry-run → Implement
3. **Multi-account support** - Handle multiple AWS accounts/profiles/roles
4. **Auditability** - Every decision must be traceable
5. **Safety checks** - Question dangerous assumptions

### Technical Stack
- **Language:** Python 3
- **Libraries:** `boto3`, `botocore`, `json`, `argparse`
- **Minimal dependencies** - Avoid heavy libraries unless necessary

---

## Implementation Phases

### Phase 1: Foundation ⏳
- [ ] Create project structure (directories)
- [ ] Set up `requirements.txt`
- [ ] Implement `utils_aws.py` for multi-account support
- [ ] Create `config/accounts.yaml` template

### Phase 2: Discovery ⏳
- [ ] Implement `discover_iam.py`
- [ ] Test against single account
- [ ] Validate read-only operations
- [ ] Generate raw data dumps

### Phase 3: Analysis ⏳
- [ ] Implement policy normalization
- [ ] Build overlap computation
- [ ] Create clustering logic
- [ ] Generate candidate permission sets

### Phase 4: Reporting ⏳
- [ ] Implement CSV report generation
- [ ] Create summary reports
- [ ] Generate Identity Center proposals
- [ ] Optional: HTML dashboard

### Phase 5: Migration Planning ⏳
- [ ] Create migration plan templates
- [ ] Generate Terraform/CloudFormation skeletons
- [ ] Document migration steps

---

## Key Metrics & Reports

### Discovery Metrics
- Total users per account
- Total roles per account
- Total groups per account
- Policy attachment counts
- Inline vs managed policy ratio

### Analysis Metrics
- Policy overlap percentage
- Number of distinct permission clusters
- Unused permission count (based on access advisor)
- Redundant policy count

### Target Metrics
- Proposed permission set count
- Permission consolidation ratio
- Migration complexity score

---

## Security Considerations

- **No write operations** in initial phase
- **Read-only IAM permissions** required
- **No credential storage** - use AWS profiles/SSO
- **Audit trail** for all operations
- **Data privacy** - no PII in logs/reports

---

## Next Steps

1. **Review this index** - Validate structure and approach
2. **Create directory structure** - Set up folders per planned layout
3. **Implement Phase 1** - Foundation utilities
4. **Begin Phase 2** - Discovery tooling

---

## Notes

- This is a **greenfield project** - currently only README exists
- All components are **planned but not implemented**
- Focus on **read-only operations** initially
- **Multi-account** support is critical from the start
- **Safety and auditability** are non-negotiable

---

**Index Generated:** 2025-01-27T00:00:00Z  
**Maintainer:** Update this file as the codebase evolves

