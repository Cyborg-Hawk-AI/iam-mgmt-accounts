# Architecture Documentation

**Last Updated:** 2025-01-27  
**Status:** 🟡 Planning Phase

---

## System Architecture Overview

This document describes the architecture of the IAM Permission Consolidation & Identity Center Migration Helper tool.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    User / Operator                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Configuration Layer                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  config/accounts.yaml                                 │  │
│  │  - Account IDs                                        │  │
│  │  - AWS Profiles                                       │  │
│  │  - Role ARNs                                          │  │
│  └──────────────────────────────────────────────────────┘  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Execution Layer                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Discovery   │→ │  Analysis    │→ │  Reporting   │      │
│  │  Module      │  │  Module      │  │  Module      │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                 │                  │              │
│         └─────────────────┴──────────────────┘              │
│                            │                                │
│                            ▼                                │
│              ┌──────────────────────┐                       │
│              │   AWS Utilities      │                       │
│              │   (Multi-Account)    │                       │
│              └──────────────────────┘                       │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              AWS Accounts (Multiple)                         │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                 │
│  │ Account 1│  │ Account 2│  │ Account N│                 │
│  │  - IAM   │  │  - IAM   │  │  - IAM   │                 │
│  │  - Users │  │  - Users │  │  - Users │                 │
│  │  - Roles │  │  - Roles │  │  - Roles │                 │
│  │  - Groups│  │  - Groups│  │  - Groups│                 │
│  └──────────┘  └──────────┘  └──────────┘                 │
└─────────────────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              Data Storage Layer                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ data/raw/    │  │ data/       │  │ output/      │      │
│  │ {account}/   │  │ processed/  │  │ reports/     │      │
│  │ *.json       │  │ *.json      │  │ *.csv        │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Details

### 1. Configuration Layer

**File:** `config/accounts.yaml`

**Purpose:** Define which AWS accounts to analyze

**Structure:**
```yaml
accounts:
  - account_id: "123456789012"
    profile: "default"
    role_arn: null
  - account_id: "987654321098"
    profile: "prod-profile"
    role_arn: "arn:aws:iam::987654321098:role/ReadOnlyRole"
```

**Responsibilities:**
- Store account identifiers
- Define authentication method (profile/role)
- Support multiple account configurations

---

### 2. AWS Utilities Module

**File:** `scripts/utils_aws.py`

**Purpose:** Abstract multi-account AWS session management

**Key Components:**
- Session factory for different auth methods
- Account iteration helper
- Permission validation
- Error handling for auth failures

**Responsibilities:**
- Create boto3 sessions per account
- Handle SSO, profile, and role-based auth
- Validate IAM read permissions
- Provide consistent error handling

---

### 3. Discovery Module

**File:** `scripts/discover_iam.py`

**Purpose:** Read-only enumeration of IAM resources

**Data Collected:**
- IAM Users (with attached/inline policies)
- IAM Roles (with attached/inline policies)
- IAM Groups (with attached/inline policies)
- Policy documents (managed and inline)
- Access Advisor data (last-used timestamps)

**Output:**
- Raw JSON files per account in `data/raw/{account_id}/`
- Structured data for analysis

**AWS APIs Used:**
- `iam.list_users()`
- `iam.list_roles()`
- `iam.list_groups()`
- `iam.list_attached_user_policies()`
- `iam.get_user_policy()`
- `iam.get_policy()`
- `iam.get_policy_version()`
- `iam.generate_service_last_accessed_details()`

---

### 4. Analysis Module

**File:** `scripts/analyze_policies.py`

**Purpose:** Process discovered data to find patterns and overlaps

**Key Operations:**
1. **Policy Normalization**
   - Convert all policies to standard format
   - Extract actions, resources, conditions
   - Handle wildcards and ARN patterns

2. **Overlap Computation**
   - Compare policies pairwise
   - Calculate Jaccard similarity
   - Identify redundant policies

3. **Clustering**
   - Group similar permission sets
   - Identify common patterns
   - Detect outliers

4. **Usage Analysis**
   - Correlate Access Advisor data
   - Flag unused permissions
   - Identify high-risk unused permissions

**Output:**
- Processed JSON in `data/processed/`
- Overlap matrices
- Cluster assignments
- Usage statistics

---

### 5. Reporting Module

**File:** `scripts/generate_reports.py`

**Purpose:** Generate human-readable outputs

**Report Types:**

1. **Principal Permissions Report** (`principal_permissions.csv`)
   - Account ID
   - Principal type (user/role/group)
   - Principal name
   - Policy ARN/name
   - Policy type (managed/inline)
   - Effective permissions summary
   - Last used status

2. **Policy Overlap Report** (`policy_overlap_report.csv`)
   - Policy A name
   - Policy B name
   - Overlap percentage
   - Unique actions in A
   - Unique actions in B

3. **Summary Report** (`summary_report.json`)
   - Total principals per account
   - Total distinct policies
   - Clustering results
   - Candidate permission sets

4. **Permission Set Proposals** (`permissionset_*.json`)
   - Identity Center-compatible definitions
   - Terraform/CloudFormation skeletons

**Output Location:** `output/reports/` and `output/proposals/`

---

## Data Flow

### Phase 1: Discovery
```
Config → AWS Utils → Discovery Module → AWS IAM APIs
                                              ↓
                                    data/raw/{account}/*.json
```

### Phase 2: Analysis
```
data/raw/{account}/*.json → Analysis Module
                                    ↓
                          data/processed/{account}/*.json
```

### Phase 3: Reporting
```
data/processed/{account}/*.json → Reporting Module
                                          ↓
                                output/reports/*.csv
                                output/proposals/*.json
```

---

## Security Architecture

### Authentication Methods
1. **AWS SSO** (`aws sso login`)
2. **AWS Profiles** (credentials file)
3. **IAM Role Assumption** (cross-account)

### Permissions Required
- `iam:ListUsers`
- `iam:ListRoles`
- `iam:ListGroups`
- `iam:GetUserPolicy`
- `iam:GetRolePolicy`
- `iam:GetGroupPolicy`
- `iam:ListAttachedUserPolicies`
- `iam:ListAttachedRolePolicies`
- `iam:ListAttachedGroupPolicies`
- `iam:GetPolicy`
- `iam:GetPolicyVersion`
- `iam:GenerateServiceLastAccessedDetails`
- `iam:GetServiceLastAccessedDetails`

### Security Principles
- **Read-only operations** (no modifications)
- **No credential storage** (use AWS SDK defaults)
- **Audit logging** (all operations logged)
- **Least privilege** (minimal required permissions)

---

## Error Handling

### Account-Level Errors
- Authentication failures → Skip account, log error
- Permission denied → Skip account, log warning
- Rate limiting → Implement exponential backoff

### Resource-Level Errors
- Missing policy → Log warning, continue
- Access denied → Log warning, continue
- Timeout → Retry with backoff

### Data Integrity
- Validate JSON structure before writing
- Checksum verification for large files
- Atomic writes (write to temp, then rename)

---

## Scalability Considerations

### Multi-Account Processing
- Sequential processing (safe, simple)
- Optional: Parallel processing with rate limit awareness
- Progress tracking per account

### Large Account Handling
- Pagination for all list operations
- Streaming JSON for large outputs
- Chunked processing for analysis

### Performance Optimization
- Cache policy documents (avoid re-fetching)
- Batch API calls where possible
- Lazy loading for large datasets

---

## Future Enhancements

### Phase 2 Features
- Interactive CLI for account selection
- Real-time progress indicators
- Resume capability (checkpoint/restart)

### Phase 3 Features
- Web dashboard for visualization
- Diff analysis (before/after migration)
- Automated migration plan generation

### Phase 4 Features
- Terraform module generation
- CloudFormation template generation
- Migration execution (with dry-run mode)

---

## Dependencies

### Python Packages
- `boto3` - AWS SDK
- `botocore` - AWS SDK core
- `pyyaml` - YAML parsing (for config)
- `python-dateutil` - Date parsing (for Access Advisor)

### External Services
- AWS IAM APIs
- AWS Access Analyzer (optional, for advanced analysis)

### System Requirements
- Python 3.8+
- AWS CLI configured (for profiles)
- Network access to AWS APIs

---

**Architecture Version:** 1.0  
**Last Updated:** 2025-01-27T00:00:00Z

