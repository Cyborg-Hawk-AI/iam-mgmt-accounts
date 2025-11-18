# CloudShell IAM Analysis Scripts

**Purpose:** AWS CLI-based scripts to discover, analyze, and consolidate IAM permissions across accounts - ready to run in AWS CloudShell.

---

## Quick Start

1. **Upload scripts to CloudShell** (or clone this repo)
2. **Make scripts executable:**
   ```bash
   chmod +x discover_iam.sh analyze_policies.sh generate_reports.sh utils.sh
   ```
3. **Run discovery:**
   ```bash
   ./discover_iam.sh
   ```
4. **Analyze policies:**
   ```bash
   ./analyze_policies.sh
   ```
5. **Generate reports:**
   ```bash
   ./generate_reports.sh
   ```

---

## Scripts Overview

| Script | Purpose | Output |
|--------|---------|--------|
| `discover_iam.sh` | Discover all IAM users, roles, groups, and policies | `data/raw/iam_discovery.json` |
| `analyze_policies.sh` | Analyze policy overlaps and identify consolidation opportunities | `data/processed/policy_analysis.json` |
| `generate_reports.sh` | Generate CSV reports for permissions and consolidation | `output/reports/*.csv` |
| `utils.sh` | Helper functions for common operations | (library) |

---

## Prerequisites

### Required AWS Permissions

Your CloudShell session needs these IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:ListUsers",
        "iam:ListRoles",
        "iam:ListGroups",
        "iam:GetUser",
        "iam:GetRole",
        "iam:GetGroup",
        "iam:ListAttachedUserPolicies",
        "iam:ListAttachedRolePolicies",
        "iam:ListAttachedGroupPolicies",
        "iam:ListUserPolicies",
        "iam:ListRolePolicies",
        "iam:ListGroupPolicies",
        "iam:GetUserPolicy",
        "iam:GetRolePolicy",
        "iam:GetGroupPolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:GenerateServiceLastAccessedDetails",
        "iam:GetServiceLastAccessedDetails",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

### CloudShell Setup

```bash
# Check AWS CLI version (should be v2)
aws --version

# Verify you're in the right account
aws sts get-caller-identity

# Create directories
mkdir -p data/raw data/processed output/reports output/proposals
```

---

## Script Details

### 1. discover_iam.sh

**What it does:**
- Discovers all IAM users, roles, and groups
- Collects attached managed policies
- Collects inline policies
- Fetches policy documents
- Optionally collects Access Advisor data (last-used info)

**Usage:**
```bash
# Basic discovery
./discover_iam.sh

# With Access Advisor (slower, but shows usage)
./discover_iam.sh --include-access-advisor

# Output to specific file
./discover_iam.sh --output custom_output.json
```

**Output:**
- `data/raw/iam_discovery.json` - Complete IAM inventory
- `data/raw/account_info.json` - Account metadata

**Time:** ~2-5 minutes per account (longer with Access Advisor)

---

### 2. analyze_policies.sh

**What it does:**
- Reads discovery data
- Normalizes policy documents
- Extracts all IAM actions
- Computes policy overlaps
- Identifies consolidation opportunities
- Groups similar permission sets

**Usage:**
```bash
# Analyze latest discovery
./analyze_policies.sh

# Analyze specific file
./analyze_policies.sh --input data/raw/iam_discovery.json

# Include similarity threshold (0.0-1.0)
./analyze_policies.sh --similarity-threshold 0.8
```

**Output:**
- `data/processed/policy_analysis.json` - Analysis results
- `data/processed/policy_overlaps.json` - Overlap matrix
- `data/processed/consolidation_candidates.json` - Suggested consolidations

**Time:** ~1-3 minutes depending on policy count

---

### 3. generate_reports.sh

**What it does:**
- Generates CSV reports from analysis
- Creates principal-to-permissions mapping
- Lists consolidation opportunities
- Produces summary statistics

**Usage:**
```bash
# Generate all reports
./generate_reports.sh

# Generate specific report
./generate_reports.sh --report-type consolidation
```

**Output:**
- `output/reports/principal_permissions.csv` - Who has what permissions
- `output/reports/policy_overlaps.csv` - Policy overlap analysis
- `output/reports/consolidation_opportunities.csv` - What can be consolidated
- `output/reports/summary_statistics.txt` - High-level summary

**Time:** ~30 seconds

---

## Workflow Example

### Step 1: Discover IAM Resources

```bash
# Run discovery (this takes a few minutes)
./discover_iam.sh --include-access-advisor

# Check output
cat data/raw/iam_discovery.json | jq '.summary'
```

### Step 2: Analyze Policies

```bash
# Run analysis
./analyze_policies.sh

# View consolidation candidates
cat data/processed/consolidation_candidates.json | jq '.top_opportunities[]'
```

### Step 3: Generate Reports

```bash
# Generate all reports
./generate_reports.sh

# View consolidation opportunities
cat output/reports/consolidation_opportunities.csv | column -t -s,
```

### Step 4: Review Results

```bash
# See summary
cat output/reports/summary_statistics.txt

# See what can be consolidated
less output/reports/consolidation_opportunities.csv
```

---

## Output Files Explained

### data/raw/iam_discovery.json

Complete IAM inventory:
```json
{
  "account_id": "123456789012",
  "discovered_at": "2025-01-27T00:00:00Z",
  "users": [...],
  "roles": [...],
  "groups": [...],
  "summary": {
    "total_users": 10,
    "total_roles": 25,
    "total_groups": 5,
    "total_managed_policies": 15,
    "total_inline_policies": 30
  }
}
```

### output/reports/consolidation_opportunities.csv

Shows which policies can be merged:
```csv
policy_a,policy_b,overlap_percent,unique_actions_a,unique_actions_b,recommendation
ReadOnlyAccess,ViewOnlyAccess,95.2,2,1,CONSOLIDATE
DeveloperPolicy,DevAccessPolicy,87.5,5,8,CONSOLIDATE
```

### output/reports/principal_permissions.csv

Shows who has what:
```csv
account_id,principal_type,principal_name,policy_name,policy_type,action_count,last_used
123456789012,user,john.doe,ReadOnlyAccess,managed,150,2025-01-15
123456789012,role,DevRole,DeveloperPolicy,inline,45,never
```

---

## Multi-Account Analysis

To analyze multiple accounts:

```bash
# Account 1
aws configure set profile.account1.region us-east-1
./discover_iam.sh --profile account1 --output data/raw/account1_iam.json

# Account 2
aws configure set profile.account2.region us-east-1
./discover_iam.sh --profile account2 --output data/raw/account2_iam.json

# Analyze both
./analyze_policies.sh --input data/raw/account1_iam.json,data/raw/account2_iam.json
```

---

## Troubleshooting

### "Access Denied" Errors

Check your permissions:
```bash
aws iam get-user 2>&1 | head -1
aws iam list-roles --max-items 1 2>&1 | head -1
```

### "Rate Limit" Errors

Scripts include retry logic, but if you hit limits:
```bash
# Wait a few minutes and retry
# Or reduce scope (analyze fewer policies at once)
```

### Large Accounts (1000+ policies)

For very large accounts:
```bash
# Process in chunks
./discover_iam.sh --max-policies 500
./analyze_policies.sh --batch-size 100
```

---

## Advanced Usage

### Custom Analysis

```bash
# Extract just actions from a policy
source utils.sh
extract_actions_from_policy "data/raw/policy.json"

# Compare two policies
compare_policies "policy1.json" "policy2.json"
```

### Export for External Analysis

```bash
# Export to format for Python analysis
./generate_reports.sh --format json

# Export for Terraform
./generate_reports.sh --format terraform
```

---

## Next Steps After Analysis

1. **Review consolidation opportunities** in `output/reports/consolidation_opportunities.csv`
2. **Identify permission set candidates** based on clusters
3. **Design Identity Center permission sets** using the analysis
4. **Create migration plan** with the discovered data

---

## Notes

- All scripts are **read-only** - they don't modify any IAM resources
- Scripts use **jq** for JSON processing (pre-installed in CloudShell)
- Outputs are **human-readable** and **machine-parseable**
- Scripts include **error handling** and **progress indicators**

---

**Last Updated:** 2025-01-27  
**Compatible with:** AWS CloudShell, AWS CLI v2

