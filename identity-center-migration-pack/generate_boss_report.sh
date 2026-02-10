#!/bin/bash
#
# generate_boss_report.sh - Generate MIGRATION_STATUS.md from real audit/aggregate data
#
# Run after generate_migration_pack.sh (and optionally after aggregate). Produces
# audit/MIGRATION_STATUS.md with counts and lists derived from:
#   - audit/permission_sets_to_create.json
#   - audit/sso_roles_audit.json
#   - audit/customer-policies/manifest.json
#   - aggregated/analysis/summary.json (if provided)
#
# Usage:
#   ./generate_boss_report.sh --audit-dir audit
#   ./generate_boss_report.sh --audit-dir audit --summary aggregated/analysis/summary.json
#
# Output: audit/MIGRATION_STATUS.md (overwritten each run)

set -euo pipefail

AUDIT_DIR="${AUDIT_DIR:-audit}"
SUMMARY_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --audit-dir)
      AUDIT_DIR="$2"
      shift 2
      ;;
    --summary)
      SUMMARY_FILE="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

PERM_SETS_FILE="$AUDIT_DIR/permission_sets_to_create.json"
SSO_AUDIT_FILE="$AUDIT_DIR/sso_roles_audit.json"
MANIFEST_FILE="$AUDIT_DIR/customer-policies/manifest.json"
OUTPUT_FILE="$AUDIT_DIR/MIGRATION_STATUS.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -f "$PERM_SETS_FILE" ]; then
  echo -e "${RED}Error: $PERM_SETS_FILE not found. Run audit_sso_roles.sh and generate_migration_pack.sh first.${NC}"
  exit 1
fi

# Gather data from files (with defaults when missing)
GEN_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

PERM_SET_COUNT=$(jq 'length' "$PERM_SETS_FILE" 2>/dev/null || echo "0")
PERM_SET_NAMES=$(jq -r '.[].permission_set_name' "$PERM_SETS_FILE" 2>/dev/null || true)

SSO_ROLE_COUNT="0"
ACCOUNT_IDS=""
if [ -f "$SSO_AUDIT_FILE" ]; then
  SSO_ROLE_COUNT=$(jq 'length' "$SSO_AUDIT_FILE" 2>/dev/null || echo "0")
  ACCOUNT_IDS=$(jq -r '[.[].account_id] | unique | .[]' "$SSO_AUDIT_FILE" 2>/dev/null || true)
fi

CUSTOM_POLICY_COUNT="0"
CUSTOM_POLICY_LINES=""
if [ -f "$MANIFEST_FILE" ]; then
  CUSTOM_POLICY_COUNT=$(jq 'length' "$MANIFEST_FILE" 2>/dev/null || echo "0")
  CUSTOM_POLICY_LINES=$(jq -r '.[] | "- " + .policy_name + " → " + .file' "$MANIFEST_FILE" 2>/dev/null || true)
fi

# Optional: summary from aggregation
ACCOUNT_COUNT=""
TOTAL_ROLES=""
TOTAL_USERS=""
TOTAL_GROUPS=""
if [ -n "$SUMMARY_FILE" ] && [ -f "$SUMMARY_FILE" ]; then
  ACCOUNT_COUNT=$(jq -r '.account_count // empty' "$SUMMARY_FILE" 2>/dev/null)
  TOTAL_ROLES=$(jq -r '.total_roles // empty' "$SUMMARY_FILE" 2>/dev/null)
  TOTAL_USERS=$(jq -r '.total_users // empty' "$SUMMARY_FILE" 2>/dev/null)
  TOTAL_GROUPS=$(jq -r '.total_groups // empty' "$SUMMARY_FILE" 2>/dev/null)
fi

# If we have audit but no summary, count unique accounts from SSO audit
if [ -z "$ACCOUNT_COUNT" ] && [ -f "$SSO_AUDIT_FILE" ]; then
  ACCOUNT_COUNT=$(jq '[.[].account_id] | unique | length' "$SSO_AUDIT_FILE" 2>/dev/null || echo "0")
fi

# List files actually in audit/
PACK_FILES=""
if [ -d "$AUDIT_DIR" ]; then
  PACK_FILES=$(cd "$AUDIT_DIR" && find . -maxdepth 1 -type f -name '*.md' -o -maxdepth 1 -type f -name '*.json' -o -maxdepth 1 -type f -name '*.csv' 2>/dev/null | sort)
  if [ -d "$AUDIT_DIR/customer-policies" ]; then
    PACK_FILES="$PACK_FILES"
    CP_FILES=$(cd "$AUDIT_DIR/customer-policies" && find . -maxdepth 1 -type f -name '*.json' 2>/dev/null | sort | sed 's|^|  customer-policies/|')
  fi
fi

# Build the report
mkdir -p "$AUDIT_DIR"
{
  echo "# Migration Status — Generated Report"
  echo ""
  echo "**Generated at:** $GEN_TIME"
  echo ""
  echo "---"
  echo ""
  echo "## Summary (from this run)"
  echo ""
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Accounts in pack | ${ACCOUNT_COUNT:-N/A} |"
  echo "| SSO roles audited | $SSO_ROLE_COUNT |"
  echo "| Permission sets to create | $PERM_SET_COUNT |"
  echo "| Custom policies to recreate | $CUSTOM_POLICY_COUNT |"
  if [ -n "$TOTAL_ROLES" ]; then echo "| Total IAM roles (all accounts) | $TOTAL_ROLES |"; fi
  if [ -n "$TOTAL_USERS" ]; then echo "| Total IAM users (all accounts) | $TOTAL_USERS |"; fi
  if [ -n "$TOTAL_GROUPS" ]; then echo "| Total IAM groups (all accounts) | $TOTAL_GROUPS |"; fi
  echo ""
  echo "---"
  echo ""
  echo "## Permission sets to create (in new Identity Center)"
  echo ""
  if [ -n "$PERM_SET_NAMES" ]; then
    echo "$PERM_SET_NAMES" | while read -r name; do
      [ -z "$name" ] && continue
      echo "- $name"
    done
  else
    echo "- (none)"
  fi
  echo ""
  echo "---"
  echo ""
  echo "## Custom policies to recreate (use files in \`customer-policies/\`)"
  echo ""
  if [ -n "$CUSTOM_POLICY_LINES" ]; then
    echo "$CUSTOM_POLICY_LINES"
  else
    echo "- (none)"
  fi
  echo ""
  echo "---"
  echo ""
  echo "## Files in this pack"
  echo ""
  echo "| File | Purpose |"
  echo "|------|---------|"
  echo "| MIGRATION_STATUS.md | This status report (generated) |"
  echo "| MIGRATION_PACK.md | Human-readable migration guide |"
  echo "| permission_sets_to_create.json | Machine-readable permission set definitions |"
  echo "| sso_roles_audit.json | Full SSO role audit |"
  echo "| sso_roles_audit.csv | SSO audit in table form |"
  echo "| customer-policies/manifest.json | Custom policy ARN → filename |"
  echo "| customer-policies/*.json | One policy document per custom policy |"
  echo ""
  echo "---"
  echo ""
  echo "## What's done"
  echo ""
  echo "- Migration pack generated (permission sets and custom policies identified)."
  echo "- Discovery and audit completed for **${ACCOUNT_COUNT:-N/A}** account(s); **$SSO_ROLE_COUNT** SSO roles audited."
  echo "- **$PERM_SET_COUNT** permission set(s) to create; **$CUSTOM_POLICY_COUNT** custom policy/policies to recreate."
  echo ""
  echo "## What's left (manual in new org)"
  echo ""
  echo "1. Create each permission set in the new Identity Center (see MIGRATION_PACK.md) and attach the listed policies."
  echo "2. Recreate each custom policy in the target account(s) using the JSON in \`customer-policies/\`, then attach by ARN."
  echo "3. Create groups in the new Identity Center and assign them to permission sets and accounts."
  echo "4. Add users to those groups."
  echo ""
  echo "---"
  echo ""
  echo "*This file was generated by generate_boss_report.sh. Do not edit by hand; re-run the central workflow to refresh.*"
  echo ""
} > "$OUTPUT_FILE"

echo -e "${GREEN}  $OUTPUT_FILE${NC}"
echo ""
