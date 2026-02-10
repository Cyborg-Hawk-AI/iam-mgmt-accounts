#!/bin/bash
#
# export_identity_center_assignments.sh - Export account assignments (READ-ONLY)
#
# Scope: Identity Center (SSO) only. Who (user/group) is assigned which permission set in which account.
# Run in the MANAGEMENT ACCOUNT only. Uses list APIs only; no create/update/delete.
# Requires identity_center/context.json and accounts.txt.
#
# Produces: identity_center/assignments.json, identity_center/assignments.csv
#
# Usage: ./export_identity_center_assignments.sh [--output-dir DIR] [--accounts-file FILE]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_DIR="identity_center"
ACCOUNTS_FILE="accounts.txt"
while [[ $# -gt 0 ]]; do
  case $1 in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --accounts-file) ACCOUNTS_FILE="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

CONTEXT="$OUTPUT_DIR/context.json"
if [ ! -f "$CONTEXT" ]; then
  echo "Error: $CONTEXT not found. Run ./export_identity_center_context.sh first."
  exit 1
fi

if [ ! -f "$ACCOUNTS_FILE" ]; then
  echo "Error: Accounts file not found: $ACCOUNTS_FILE"
  echo "Copy accounts.txt.example to accounts.txt and edit, or create with one account ID per line."
  exit 1
fi

INSTANCE_ARN=$(jq -r '.InstanceArn' "$CONTEXT")
PS_ARNS=$(jq -r '.PermissionSets[].PermissionSetArn' "$CONTEXT")
ACCOUNT_IDS=$(grep -E '^[0-9]{12}$' "$ACCOUNTS_FILE" | tr -d '\r' || true)

echo "Exporting account assignments (management account, read-only)..."
echo "  Accounts: $(echo "$ACCOUNT_IDS" | wc -l | tr -d ' ')"
echo "  Output: $OUTPUT_DIR/assignments.json, $OUTPUT_DIR/assignments.csv"

TMP_ASSIGN="$OUTPUT_DIR/assignments.tmp.json"
echo "{}" > "$TMP_ASSIGN"

for ACC in $ACCOUNT_IDS; do
  [ -z "$ACC" ] && continue
  echo "  Account $ACC..."
  ACC_LIST="$OUTPUT_DIR/acc_${ACC}.tmp.json"
  echo "[]" > "$ACC_LIST"
  for PS_ARN in $PS_ARNS; do
    [ -z "$PS_ARN" ] && continue
    ASSIGN_TOKEN=""
    while true; do
      if [ -n "$ASSIGN_TOKEN" ]; then
        ASSIGNMENTS=$(aws sso-admin list-account-assignments \
          --instance-arn "$INSTANCE_ARN" \
          --account-id "$ACC" \
          --permission-set-arn "$PS_ARN" \
          --starting-token "$ASSIGN_TOKEN" \
          --output json 2>/dev/null || echo '{"AccountAssignments":[]}')
      else
        ASSIGNMENTS=$(aws sso-admin list-account-assignments \
          --instance-arn "$INSTANCE_ARN" \
          --account-id "$ACC" \
          --permission-set-arn "$PS_ARN" \
          --output json 2>/dev/null || echo '{"AccountAssignments":[]}')
      fi
      echo "$ASSIGNMENTS" | jq -r '.AccountAssignments[]? | [.PrincipalId, .PrincipalType, .PermissionSetArn] | @tsv' 2>/dev/null | while read -r pid ptype arn; do
        [ -z "$pid" ] && continue
        CURRENT=$(cat "$ACC_LIST")
        echo "$CURRENT" | jq --arg pid "$pid" --arg ptype "$ptype" --arg arn "$arn" '. + [{"PrincipalId": $pid, "PrincipalType": $ptype, "PermissionSetArn": $arn}]' > "$ACC_LIST"
      done
      ASSIGN_TOKEN=$(echo "$ASSIGNMENTS" | jq -r '.NextToken // empty')
      [ -z "$ASSIGN_TOKEN" ] && break
    done
  done
  ACC_JSON=$(cat "$ACC_LIST")
  rm -f "$ACC_LIST"
  CURRENT=$(cat "$TMP_ASSIGN")
  echo "$CURRENT" | jq --arg acc "$ACC" --argjson list "$ACC_JSON" '. + {($acc): $list}' > "$TMP_ASSIGN"
done

EXPORTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -n \
  --argjson by_account "$(cat "$TMP_ASSIGN")" \
  --arg exported "$EXPORTED_AT" \
  '{ AssignmentsByAccount: $by_account, ExportedAt: $exported }' \
  > "$OUTPUT_DIR/assignments.json"
rm -f "$TMP_ASSIGN"

# CSV: one row per assignment — AccountId, PermissionSetArn, PrincipalType, PrincipalId
echo "AccountId,PermissionSetArn,PrincipalType,PrincipalId" > "$OUTPUT_DIR/assignments.csv"
jq -r '
  .AssignmentsByAccount | to_entries[] | .key as $acc | .value[] | [$acc, .PermissionSetArn, .PrincipalType, .PrincipalId] | @csv
' "$OUTPUT_DIR/assignments.json" >> "$OUTPUT_DIR/assignments.csv" 2>/dev/null || true
echo "  CSV: $OUTPUT_DIR/assignments.csv"

echo "Done."
echo ""
