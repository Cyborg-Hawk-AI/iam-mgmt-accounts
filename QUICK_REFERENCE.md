# Quick Reference Guide

**Last Updated:** 2025-01-27

---

## Project Status

| Component | Status | Location |
|-----------|--------|----------|
| README | ✅ Complete | `README.md` |
| Codebase Index | ✅ Complete | `CODEBASE_INDEX.md` |
| Architecture Docs | ✅ Complete | `ARCHITECTURE.md` |
| Project Structure | ⏳ Planned | See README |
| Discovery Scripts | ⏳ Planned | `scripts/discover_iam.py` |
| Analysis Scripts | ⏳ Planned | `scripts/analyze_policies.py` |
| Reporting Scripts | ⏳ Planned | `scripts/generate_reports.py` |
| AWS Utilities | ⏳ Planned | `scripts/utils_aws.py` |
| Configuration | ⏳ Planned | `config/accounts.yaml` |

---

## File Index

### Documentation
- `README.md` - Main project documentation
- `CODEBASE_INDEX.md` - Comprehensive codebase index and analysis
- `ARCHITECTURE.md` - System architecture documentation
- `QUICK_REFERENCE.md` - This file

### Planned Scripts
- `scripts/discover_iam.py` - IAM resource discovery
- `scripts/analyze_policies.py` - Policy analysis and clustering
- `scripts/generate_reports.py` - Report generation
- `scripts/utils_aws.py` - AWS session management

### Planned Configuration
- `config/accounts.yaml` - Account/profiles/roles configuration

### Planned Data Directories
- `data/raw/` - Raw JSON dumps per account
- `data/processed/` - Normalized and analyzed data
- `output/reports/` - CSV/HTML reports
- `output/proposals/` - Permission set proposals

---

## Key Concepts

### Discovery Phase
- **Read-only** enumeration of IAM resources
- Collects: users, roles, groups, policies, access advisor data
- Outputs: Raw JSON in `data/raw/{account_id}/`

### Analysis Phase
- Normalizes policy documents
- Computes overlaps between policies
- Clusters similar permissions
- Identifies unused permissions
- Outputs: Processed data in `data/processed/`

### Reporting Phase
- Generates CSV reports
- Creates summary statistics
- Proposes permission sets
- Outputs: Reports in `output/reports/` and `output/proposals/`

---

## Common Tasks

### Adding a New Account
1. Edit `config/accounts.yaml`
2. Add account ID, profile, and optional role ARN
3. Run discovery script

### Running Discovery
```bash
python scripts/discover_iam.py --config config/accounts.yaml
```

### Running Analysis
```bash
python scripts/analyze_policies.py --input data/raw/ --output data/processed/
```

### Generating Reports
```bash
python scripts/generate_reports.py --input data/processed/ --output output/reports/
```

---

## Important Constraints

1. **Read-only** - No modifications in initial phase
2. **Multi-account** - Must support multiple AWS accounts
3. **Auditable** - All decisions must be traceable
4. **Safe** - Question dangerous assumptions
5. **No outages** - Discover → Analyze → Propose → Dry-run → Implement

---

## AWS Permissions Required

Minimum IAM permissions needed:
- `iam:List*`
- `iam:Get*`
- `iam:GenerateServiceLastAccessedDetails`
- `iam:GetServiceLastAccessedDetails`

**Note:** All operations are read-only.

---

## Next Steps

1. Review documentation (README, INDEX, ARCHITECTURE)
2. Create directory structure
3. Set up `requirements.txt`
4. Implement `utils_aws.py`
5. Implement `discover_iam.py`

---

**Quick Reference Version:** 1.0  
**Last Updated:** 2025-01-27T00:00:00Z

