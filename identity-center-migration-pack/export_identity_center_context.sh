#!/bin/bash
#
# export_identity_center_context.sh - Export Identity Center instance and permission sets (READ-ONLY)
#
# Scope: Identity Center (SSO) only. Standard IAM users in member accounts are NOT in scope.
# Run in the MANAGEMENT ACCOUNT only. Uses list/describe APIs only; no create/update/delete.
#
# Produces: identity_center/context.json, identity_center/context_permission_sets.csv
#
# Usage: ./export_identity_center_context.sh [--output-dir DIR]
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

mkdir -p "$OUTPUT_DIR"

echo "Exporting Identity Center context (management account, read-only)..."
echo "  Output: $OUTPUT_DIR/context.json, $OUTPUT_DIR/context_permission_sets.csv"

INSTANCES=$(aws sso-admin list-instances --output json 2>/dev/null || true)
if [ -z "$INSTANCES" ] || [ "$(echo "$INSTANCES" | jq -r '.Instances | length')" -eq 0 ]; then
  echo "Error: No Identity Center instance found. Run this in the management account with sso-admin permissions."
  exit 1
fi

INSTANCE_ARN=$(echo "$INSTANCES" | jq -r '.Instances[0].InstanceArn')
IDENTITY_STORE_ID=$(echo "$INSTANCES" | jq -r '.Instances[0].IdentityStoreId')
echo "  InstanceArn: $INSTANCE_ARN"
echo "  IdentityStoreId: $IDENTITY_STORE_ID"

PS_ARNS=""
NEXT_TOKEN=""
while true; do
  if [ -n "$NEXT_TOKEN" ]; then
    PAGE=$(aws sso-admin list-permission-sets --instance-arn "$INSTANCE_ARN" --starting-token "$NEXT_TOKEN" --output json 2>/dev/null)
  else
    PAGE=$(aws sso-admin list-permission-sets --instance-arn "$INSTANCE_ARN" --output json 2>/dev/null)
  fi
  PS_ARNS="$PS_ARNS $(echo "$PAGE" | jq -r '.PermissionSets[]?' 2>/dev/null)"
  NEXT_TOKEN=$(echo "$PAGE" | jq -r '.NextToken // empty')
  [ -z "$NEXT_TOKEN" ] && break
done

PERMISSION_SETS="[]"
for ARN in $PS_ARNS; do
  [ -z "$ARN" ] && continue
  DESC=$(aws sso-admin describe-permission-set --instance-arn "$INSTANCE_ARN" --permission-set-arn "$ARN" --output json 2>/dev/null || echo "{}")
  NAME=$(echo "$DESC" | jq -r '.PermissionSet.Name // "unknown"')
  PERMISSION_SETS=$(echo "$PERMISSION_SETS" | jq --arg arn "$ARN" --arg name "$NAME" '. + [{"PermissionSetArn": $arn, "Name": $name}]')
done

echo "  Permission sets: $(echo "$PERMISSION_SETS" | jq -r 'length')"

EXPORTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -n \
  --arg instance "$INSTANCE_ARN" \
  --arg store "$IDENTITY_STORE_ID" \
  --argjson permission_sets "$PERMISSION_SETS" \
  --arg exported "$EXPORTED_AT" \
  '{ InstanceArn: $instance, IdentityStoreId: $store, PermissionSets: $permission_sets, ExportedAt: $exported }' \
  > "$OUTPUT_DIR/context.json"

# CSV: permission sets
echo "PermissionSetArn,Name" > "$OUTPUT_DIR/context_permission_sets.csv"
echo "$PERMISSION_SETS" | jq -r '.[] | [.PermissionSetArn, .Name] | @csv' >> "$OUTPUT_DIR/context_permission_sets.csv"
echo "  CSV: $OUTPUT_DIR/context_permission_sets.csv"

# CSV: instance summary (one row)
echo "InstanceArn,IdentityStoreId,ExportedAt" > "$OUTPUT_DIR/context_instance.csv"
echo "\"$INSTANCE_ARN\",\"$IDENTITY_STORE_ID\",\"$EXPORTED_AT\"" >> "$OUTPUT_DIR/context_instance.csv"
echo "  CSV: $OUTPUT_DIR/context_instance.csv"

echo "Done. Next: ./export_identity_center_assignments.sh and ./export_identity_center_users_groups.sh"
echo ""
