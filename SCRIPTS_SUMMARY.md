# CloudShell Scripts Summary

**Complete set of AWS CLI-based scripts for IAM permission analysis and consolidation**

---

## 📁 Files Created

### Core Scripts (Executable)

| File | Purpose | Usage |
|------|---------|-------|
| `discover_iam.sh` | Discover all IAM users, roles, groups, and policies | `./discover_iam.sh [--include-access-advisor]` |
| `analyze_policies.sh` | Analyze policy overlaps and find consolidation opportunities | `./analyze_policies.sh [--input FILE]` |
| `generate_reports.sh` | Generate CSV reports from analysis | `./generate_reports.sh [--report-type TYPE]` |
| `utils.sh` | Helper functions library | `source utils.sh` |
| `validate_setup.sh` | Validate environment and permissions | `./validate_setup.sh` |

### Documentation

| File | Purpose |
|------|---------|
| `CLOUDSHELL_SCRIPTS_README.md` | Comprehensive usage guide |
| `QUICKSTART.md` | 5-minute quick start guide |
| `SCRIPTS_SUMMARY.md` | This file - overview of all scripts |

---

## 🚀 Quick Workflow

```bash
# 1. Validate setup
./validate_setup.sh

# 2. Discover IAM resources
./discover_iam.sh

# 3. Analyze policies
./analyze_policies.sh

# 4. Generate reports
./generate_reports.sh

# 5. Review results
cat output/reports/consolidation_opportunities.csv
```

---

## 📊 What Each Script Does

### 1. discover_iam.sh

**Input:** None (queries AWS directly)  
**Output:** `data/raw/iam_discovery.json`

**Discovers:**
- All IAM users with attached/inline policies
- All IAM roles with attached/inline policies
- All IAM groups with attached/inline policies
- All managed policy documents
- Optional: Access Advisor data (last-used info)

**Time:** 2-5 minutes per account (longer with Access Advisor)

---

### 2. analyze_policies.sh

**Input:** `data/raw/iam_discovery.json`  
**Output:** 
- `data/processed/policy_analysis.json`
- `data/processed/policy_overlaps.json`
- `data/processed/consolidation_candidates.json`

**Analyzes:**
- Extracts all IAM actions from policies
- Computes Jaccard similarity between policies
- Identifies high-overlap pairs (>=80% by default)
- Suggests consolidation opportunities

**Time:** 1-3 minutes depending on policy count

---

### 3. generate_reports.sh

**Input:** `data/processed/policy_analysis.json`  
**Output:** `output/reports/*.csv`

**Generates:**
- `principal_permissions.csv` - Who has what permissions
- `policy_overlaps.csv` - Policy overlap analysis
- `consolidation_opportunities.csv` - What can be consolidated
- `summary_statistics.txt` - High-level summary

**Time:** ~30 seconds

---

## 📋 Key Outputs

### Consolidation Opportunities Report

Shows which policies can be merged:
```csv
policy_a,policy_b,overlap_percent,recommendation,unique_actions_a,unique_actions_b
ReadOnlyAccess,ViewOnlyAccess,95.2,CONSOLIDATE,2,1
DeveloperPolicy,DevAccessPolicy,87.5,CONSOLIDATE,5,8
```

**Recommendations:**
- `CONSOLIDATE` - Merge both policies
- `REPLACE_A_WITH_B` - Policy A is subset of B
- `REPLACE_B_WITH_A` - Policy B is subset of A

### Policy Overlaps Report

Detailed overlap analysis:
```csv
policy_a,policy_b,overlap_percent,unique_actions_a,unique_actions_b,recommendation
```

### Principal Permissions Report

Who has what:
```csv
account_id,principal_type,principal_name,policy_name,policy_type,policy_arn,action_count,actions
```

---

## 🔧 Requirements

### AWS Permissions
- `iam:List*` - List all IAM resources
- `iam:Get*` - Get policy documents
- `iam:GenerateServiceLastAccessedDetails` - Access Advisor (optional)
- `sts:GetCallerIdentity` - Account info

### System Requirements
- AWS CLI v2 (pre-installed in CloudShell)
- `jq` - JSON processor (pre-installed in CloudShell)
- `bc` - Calculator (may need: `sudo yum install bc`)
- Bash 4+

---

## 🎯 Use Cases

### 1. Find Redundant Policies
```bash
./discover_iam.sh
./analyze_policies.sh
cat output/reports/consolidation_opportunities.csv | grep "CONSOLIDATE"
```

### 2. Identify Permission Sets for Identity Center
```bash
# Run full analysis
./discover_iam.sh && ./analyze_policies.sh && ./generate_reports.sh

# Review clusters
cat data/processed/consolidation_candidates.json | jq '.top_overlaps[]'
```

### 3. Audit Who Has What Permissions
```bash
./discover_iam.sh
./generate_reports.sh --report-type principal
cat output/reports/principal_permissions.csv
```

### 4. Multi-Account Analysis
```bash
# Account 1
AWS_PROFILE=account1 ./discover_iam.sh --output data/raw/account1.json

# Account 2
AWS_PROFILE=account2 ./discover_iam.sh --output data/raw/account2.json

# Analyze both (manual merge or separate analysis)
```

---

## 🔍 Understanding the Results

### Similarity Score
- **0.0** = No overlap (completely different)
- **0.5** = 50% overlap (some common actions)
- **0.8+** = High overlap (good consolidation candidate)
- **1.0** = Identical (perfect consolidation candidate)

### Consolidation Recommendations

**CONSOLIDATE**
- Both policies have unique actions
- Merge into single policy with union of actions
- Best for: Similar policies with slight differences

**REPLACE_A_WITH_B**
- Policy A is subset of Policy B
- Remove A, use B instead
- Best for: Redundant policies

**REPLACE_B_WITH_A**
- Policy B is subset of Policy A
- Remove B, use A instead
- Best for: Redundant policies

---

## 📝 Notes

- **Read-only operations** - Scripts never modify IAM resources
- **Safe to run** - No risk of breaking access
- **Progress indicators** - Scripts show what they're doing
- **Error handling** - Graceful failures with helpful messages
- **CloudShell optimized** - Uses native AWS CLI, minimal dependencies

---

## 🐛 Troubleshooting

### Script fails with "command not found"
- Check scripts are executable: `chmod +x *.sh`
- Verify AWS CLI: `aws --version`
- Install missing tools: `sudo yum install jq bc`

### "Access Denied" errors
- Run `./validate_setup.sh` to check permissions
- Verify IAM permissions in your account
- Check you're using the right AWS profile

### Scripts are very slow
- Normal for large accounts (100+ users/roles)
- Access Advisor adds significant time
- Consider running without `--include-access-advisor` first

### Empty or incomplete results
- Check input file exists: `ls -la data/raw/`
- Verify JSON is valid: `jq . data/raw/iam_discovery.json`
- Re-run discovery if needed

---

## 📚 Next Steps

After running the scripts:

1. **Review consolidation opportunities**
   - Open `output/reports/consolidation_opportunities.csv`
   - Identify high-value consolidations

2. **Design permission sets**
   - Use clusters from analysis
   - Map to job functions/environments

3. **Plan migration**
   - Document current state
   - Design target state
   - Create migration plan

4. **Generate Identity Center configs**
   - Use analysis data
   - Create permission set definitions
   - Prepare Terraform/CloudFormation

---

## 📞 Support

- See `CLOUDSHELL_SCRIPTS_README.md` for detailed documentation
- See `QUICKSTART.md` for quick start guide
- Run `./validate_setup.sh` to diagnose issues

---

**Last Updated:** 2025-01-27  
**Version:** 1.0

