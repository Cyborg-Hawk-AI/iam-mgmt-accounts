# Quick Start Guide - CloudShell IAM Analysis

**Get started in 5 minutes!**

---

## Step 1: Upload Scripts to CloudShell

### Option A: Clone from Git (if repo is available)
```bash
git clone <your-repo-url>
cd iam-mgmt-accounts
```

### Option B: Upload Files Manually
1. In CloudShell, create the directory:
   ```bash
   mkdir -p ~/iam-analysis
   cd ~/iam-analysis
   ```
2. Upload these files using CloudShell's upload feature:
   - `discover_iam.sh`
   - `analyze_policies.sh`
   - `generate_reports.sh`
   - `utils.sh`
   - `CLOUDSHELL_SCRIPTS_README.md`

### Option C: Copy-Paste Scripts
Copy the script contents directly into CloudShell editor and save.

---

## Step 2: Make Scripts Executable

```bash
chmod +x discover_iam.sh analyze_policies.sh generate_reports.sh utils.sh
```

---

## Step 3: Verify AWS Access

```bash
# Check you're in the right account
aws sts get-caller-identity

# Test IAM access
aws iam list-users --max-items 1
```

---

## Step 4: Run Discovery

```bash
# Basic discovery (2-5 minutes)
./discover_iam.sh

# With Access Advisor (slower, but shows usage)
./discover_iam.sh --include-access-advisor
```

**Output:** `data/raw/iam_discovery.json`

---

## Step 5: Analyze Policies

```bash
./analyze_policies.sh
```

**Output:** 
- `data/processed/policy_analysis.json`
- `data/processed/consolidation_candidates.json`

---

## Step 6: Generate Reports

```bash
./generate_reports.sh
```

**Output:** `output/reports/*.csv`

---

## Step 7: Review Results

```bash
# View summary
cat output/reports/summary_statistics.txt

# View consolidation opportunities
cat output/reports/consolidation_opportunities.csv | column -t -s,

# View policy overlaps
cat output/reports/policy_overlaps.csv | head -20
```

---

## Download Results from CloudShell

CloudShell has a download feature. Use it to download:
- `output/reports/*.csv` - All your reports
- `data/processed/consolidation_candidates.json` - Detailed analysis

Or use AWS CLI to copy to S3:
```bash
aws s3 cp output/reports/ s3://your-bucket/iam-analysis/ --recursive
```

---

## Common Issues

### "Permission Denied"
- Check your IAM permissions
- Verify you can list IAM resources

### "jq: command not found"
- CloudShell should have jq pre-installed
- If not: `sudo yum install jq` (Amazon Linux) or `sudo apt-get install jq` (Ubuntu)

### "bc: command not found"
- Install: `sudo yum install bc` or `sudo apt-get install bc`

### Scripts are slow
- Normal for large accounts (100+ users/roles)
- Access Advisor adds significant time
- Be patient, scripts show progress

---

## Next Steps

1. **Review consolidation opportunities** - See what can be merged
2. **Identify permission set candidates** - Based on clusters
3. **Design Identity Center permission sets** - Using the analysis
4. **Plan migration** - With discovered data

---

## Example Workflow

```bash
# 1. Setup
cd ~/iam-analysis
chmod +x *.sh

# 2. Discover
./discover_iam.sh

# 3. Analyze
./analyze_policies.sh

# 4. Report
./generate_reports.sh

# 5. Review
cat output/reports/consolidation_opportunities.csv | column -t -s,
```

---

**That's it!** You now have a complete analysis of your IAM permissions and consolidation opportunities.

