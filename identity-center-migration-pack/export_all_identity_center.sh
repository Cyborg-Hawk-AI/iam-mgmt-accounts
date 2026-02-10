#!/bin/bash
#
# export_all_identity_center.sh - Run all Identity Center exports (READ-ONLY)
#
# Scope: Identity Center (SSO) only. Reserved SSO roles in member accounts are the
# only things migrating. Standard IAM users in accounts are NOT in scope.
# Run in the MANAGEMENT ACCOUNT only. All operations are list/describe; no writes.
#
# Produces under identity_center/:
#   JSON: context.json, assignments.json, users.json, groups.json, group_memberships.json
#   CSV:  context_instance.csv, context_permission_sets.csv, assignments.csv,
#         users.csv, groups.csv, group_memberships.csv
# Optional (if accounts.txt exists): org_accounts.json, org_accounts.csv
#
# After running, zip identity_center/ or copy its contents to supply in another session.
#
# Usage: ./export_all_identity_center.sh [--output-dir DIR]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_DIR="identity_center"
while [[ $# -gt 0 ]]; do
  case $1 in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

export OUTPUT_DIR

echo "=== Identity Center export (read-only, management account) ==="
echo "  Output dir: $OUTPUT_DIR"
echo ""

./export_identity_center_context.sh --output-dir "$OUTPUT_DIR"
./export_identity_center_assignments.sh --output-dir "$OUTPUT_DIR" 2>/dev/null || {
  echo "  (assignments skipped: need accounts.txt; copy accounts.txt.example to accounts.txt)"
}
./export_identity_center_users_groups.sh --output-dir "$OUTPUT_DIR"
[ -f "accounts.txt" ] && ./export_organization_accounts.sh --output-dir "$OUTPUT_DIR" 2>/dev/null || true

echo "=== All Identity Center exports finished ==="
echo ""
echo "JSON and CSV files in $OUTPUT_DIR/:"
ls -la "$OUTPUT_DIR"/*.json "$OUTPUT_DIR"/*.csv 2>/dev/null || ls -la "$OUTPUT_DIR/"
echo ""
echo "Supply the contents of $OUTPUT_DIR/ (JSON + CSV) in your next session for deployment."
echo ""
