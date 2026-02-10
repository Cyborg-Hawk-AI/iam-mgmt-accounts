#!/bin/bash
#
# audit_sso_roles.sh - Audit IAM SSO roles in each account and list policies attached to each
#
# Identity Center provisions roles named AWSReservedSSO_<PermissionSetName>_<suffix> in each
# account. This script finds those roles and reports the managed + inline policies attached
# so you know exactly what permission set to create in the destination Identity Center for
# each role/group. You will manually copy users to groups; this gives you the permission sets.
#
# Usage:
#   Live (current account):
#     ./audit_sso_roles.sh
#   From discovery JSON (single account):
#     ./audit_sso_roles.sh --input path/to/iam_discovery.json
#   From aggregated discovery (all accounts):
#     ./audit_sso_roles.sh --aggregated path/to/aggregated/discovery/all_accounts.json
#
# Output (in audit/ by default):
#   sso_roles_audit.json     - Full detail per role
#   sso_roles_audit.csv      - Simple table: permission_set_name, account_id, role_name, policy_type, policy_arn_or_name
#   permission_sets_to_create.json - One definition per permission set (for creating in new Identity Center)
#
# Requires: jq, AWS CLI (for live mode).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${OUTPUT_DIR:-audit}"
INPUT_FILE=""
AGGREGATED_FILE=""
LIVE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --input)
      INPUT_FILE="$2"
      shift 2
      ;;
    --aggregated)
      AGGREGATED_FILE="$2"
      shift 2
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [ -z "$INPUT_FILE" ] && [ -z "$AGGREGATED_FILE" ]; then
  LIVE=true
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse permission set name from role name: AWSReservedSSO_<Name>_<suffix>
# Only roles created by Identity Center use this prefix; all other IAM roles are ignored.
permission_set_name_from_role() {
  local name="$1"
  if [[ "$name" != AWSReservedSSO_* ]]; then
    echo ""
    return
  fi
  local rest="${name#AWSReservedSSO_}"
  if [[ "$rest" == *_* ]]; then
    # Everything before the last underscore (suffix is last segment)
    echo "${rest%_*}"
  else
    echo "$rest"
  fi
}

# Classify managed policy as AWS-managed vs customer-managed from ARN.
# AWS-managed: arn:aws:iam::aws:policy/Name  (no account ID)
# Customer-managed: arn:aws:iam::ACCOUNT_ID:policy/Name
classify_managed_policy() {
  local arn="$1"
  if [[ "$arn" == arn:aws:iam::aws:policy/* ]]; then
    echo "aws"
  else
    echo "customer"
  fi
}

mkdir -p "$OUTPUT_DIR"

if [ "$LIVE" = true ]; then
  echo -e "${BLUE}Auditing SSO roles in current account (live)${NC}"
  ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
  ROLES_JSON=$(aws iam list-roles --output json 2>/dev/null)
  # Build a minimal discovery-like structure for the rest of the script
  INPUT_FILE=""
  # We'll output single-account format and then optionally merge
  SINGLE_ACCOUNT_JSON=$(mktemp)
  echo "{\"account_id\": \"$ACCOUNT_ID\", \"roles\": []}" > "$SINGLE_ACCOUNT_JSON"
  ROLE_NAMES=$(echo "$ROLES_JSON" | jq -r '.Roles[] | select(.RoleName | startswith("AWSReservedSSO_")) | .RoleName')
  for role_name in $ROLE_NAMES; do
    ATTACHED=$(aws iam list-attached-role-policies --role-name "$role_name" --output json 2>/dev/null | jq -c '.AttachedPolicies')
    INLINE_NAMES=$(aws iam list-role-policies --role-name "$role_name" --output json 2>/dev/null | jq -c '.PolicyNames')
    INLINE_POLICIES="[]"
    for pname in $(echo "$INLINE_NAMES" | jq -r '.[]'); do
      DOC=$(aws iam get-role-policy --role-name "$role_name" --policy-name "$pname" --query 'PolicyDocument' --output json 2>/dev/null)
      INLINE_POLICIES=$(echo "$INLINE_POLICIES" | jq --arg n "$pname" --argjson d "$DOC" '. + [{"name": $n, "document": $d}]')
    done
    ROLE_J=$(jq -n --arg name "$role_name" --argjson attached "$ATTACHED" --argjson inline "$INLINE_POLICIES" \
      '{name: $name, attached_managed_policies: $attached, inline_policies: $inline}')
    echo "$(jq --argjson r "$ROLE_J" '.roles += [$r]' "$SINGLE_ACCOUNT_JSON")" > "$SINGLE_ACCOUNT_JSON"
  done
  AGGREGATED_FILE=""
  INPUT_FILE="$SINGLE_ACCOUNT_JSON"
  # Treat as single-account input (one account, roles only)
fi

# Validate input
if [ -z "$INPUT_FILE" ] && [ -z "$AGGREGATED_FILE" ]; then
  echo -e "${RED}No input (--input or --aggregated) and not in live mode.${NC}"
  [ -n "${SINGLE_ACCOUNT_JSON:-}" ] && [ -f "${SINGLE_ACCOUNT_JSON:-}" ] && rm -f "$SINGLE_ACCOUNT_JSON"
  exit 1
fi
if [ -n "$AGGREGATED_FILE" ] && [ ! -f "$AGGREGATED_FILE" ]; then
  echo -e "${RED}Aggregated file not found: $AGGREGATED_FILE${NC}"
  exit 1
fi
if [ -n "$INPUT_FILE" ] && [ ! -f "$INPUT_FILE" ]; then
  echo -e "${RED}Input file not found: $INPUT_FILE${NC}"
  exit 1
fi
if [ -n "$AGGREGATED_FILE" ]; then
  echo -e "${YELLOW}Reading aggregated discovery: $AGGREGATED_FILE${NC}"
fi
if [ -n "$INPUT_FILE" ] && [ "$LIVE" != true ]; then
  echo -e "${YELLOW}Reading discovery: $INPUT_FILE${NC}"
fi

SSO_AUDIT_JSON="[]"
if [ -n "$AGGREGATED_FILE" ]; then
  for acct_id in $(jq -r '.accounts[]?.account_id' "$AGGREGATED_FILE"); do
    roles=$(jq -c --arg id "$acct_id" '.accounts[] | select(.account_id == $id) | .roles' "$AGGREGATED_FILE")
    while IFS= read -r role; do
      name=$(echo "$role" | jq -r '.name')
      [[ "$name" != AWSReservedSSO_* ]] && continue
      ps_name=$(permission_set_name_from_role "$name")
      [ -z "$ps_name" ] && continue
      attached=$(echo "$role" | jq -c '.attached_managed_policies // .AttachedPolicies // []')
      attached_enriched=$(echo "$attached" | jq -c '
        [.[] | . + {managed_type: (if (.PolicyArn // "") | test("^arn:aws:iam::aws:policy/") then "aws" else "customer" end)}]
      ')
      inline=$(echo "$role" | jq -c '.inline_policies // []')
      line=$(jq -n --arg acct "$acct_id" --arg rn "$name" --arg ps "$ps_name" --argjson att "$attached_enriched" --argjson inl "$inline" \
        '{account_id: $acct, role_name: $rn, permission_set_name: $ps, managed_policies: $att, inline_policies: $inl}')
      SSO_AUDIT_JSON=$(echo "$SSO_AUDIT_JSON" | jq --argjson r "$line" '. + [$r]')
    done < <(echo "$roles" | jq -c '.[]?')
  done
else
  acct_id=$(jq -r '.account_id // "unknown"' "$INPUT_FILE")
  roles=$(jq -c '.roles' "$INPUT_FILE")
  while IFS= read -r role; do
    name=$(echo "$role" | jq -r '.name')
    [[ "$name" != AWSReservedSSO_* ]] && continue
    ps_name=$(permission_set_name_from_role "$name")
    [ -z "$ps_name" ] && continue
    attached=$(echo "$role" | jq -c '.attached_managed_policies // .AttachedPolicies // []')
    # Enrich each managed policy with managed_type: "aws" or "customer" from ARN
    attached_enriched=$(echo "$attached" | jq -c '
      [.[] | . + {managed_type: (if (.PolicyArn // "") | test("^arn:aws:iam::aws:policy/") then "aws" else "customer" end)}]
    ')
    inline=$(echo "$role" | jq -c '.inline_policies // []')
    line=$(jq -n --arg acct "$acct_id" --arg rn "$name" --arg ps "$ps_name" --argjson att "$attached_enriched" --argjson inl "$inline" \
      '{account_id: $acct, role_name: $rn, permission_set_name: $ps, managed_policies: $att, inline_policies: $inl}')
    SSO_AUDIT_JSON=$(echo "$SSO_AUDIT_JSON" | jq --argjson r "$line" '. + [$r]')
  done < <(echo "$roles" | jq -c '.[]?')
fi

# Generate CSV from SSO_AUDIT_JSON (managed_scope = aws_managed | customer_managed for managed policies)
CSV_LINES="permission_set_name,account_id,role_name,policy_type,managed_scope,policy_identifier"
while IFS= read -r row; do
  ps_name=$(echo "$row" | jq -r '.permission_set_name')
  acct_id=$(echo "$row" | jq -r '.account_id')
  role_name=$(echo "$row" | jq -r '.role_name')
  for pol in $(echo "$row" | jq -c '.managed_policies[]?'); do
    arn=$(echo "$pol" | jq -r '.PolicyArn // .PolicyName // empty')
    scope=$(echo "$pol" | jq -r '.managed_type // (if (.PolicyArn // "") | test("^arn:aws:iam::aws:policy/") then "aws_managed" else "customer_managed" end)')
    [ -n "$arn" ] && CSV_LINES="$CSV_LINES"$'\n'"${ps_name},${acct_id},${role_name},managed,${scope},${arn}"
  done
  for pol in $(echo "$row" | jq -c '.inline_policies[]?'); do
    pname=$(echo "$pol" | jq -r '.name')
    [ -n "$pname" ] && CSV_LINES="$CSV_LINES"$'\n'"${ps_name},${acct_id},${role_name},inline,,${pname}"
  done
done < <(echo "$SSO_AUDIT_JSON" | jq -c '.[]?')

echo "$SSO_AUDIT_JSON" | jq '.' > "$OUTPUT_DIR/sso_roles_audit.json"
echo "$CSV_LINES" > "$OUTPUT_DIR/sso_roles_audit.csv"
echo -e "${GREEN}  $OUTPUT_DIR/sso_roles_audit.json${NC}"
echo -e "${GREEN}  $OUTPUT_DIR/sso_roles_audit.csv${NC}"

# Build permission_sets_to_create.json: one entry per permission_set_name with merged managed ARNs (split AWS vs customer) + inline docs
PERM_SETS_TO_CREATE=$(echo "$SSO_AUDIT_JSON" | jq '
  group_by(.permission_set_name) | map(
    . as $group
    | $group[0].permission_set_name as $psname
    | ([$group[].managed_policies[]? | select(.PolicyArn != null)] | unique_by(.PolicyArn)) as $all
    | {
        permission_set_name: $psname,
        aws_managed_policy_arns: ([$all[] | select(.PolicyArn | test("^arn:aws:iam::aws:policy/")) | .PolicyArn] | unique),
        customer_managed_policy_arns: ([$all[] | select((.PolicyArn | test("^arn:aws:iam::aws:policy/")) | not)] | map(.PolicyArn) | unique),
        managed_policy_arns: ([$all[].PolicyArn] | unique),
        inline_policies: ([$group[].inline_policies[]?] | unique_by(.name) | map({name: .name, document: .document}))
      }
  )
')
echo "$PERM_SETS_TO_CREATE" | jq '.' > "$OUTPUT_DIR/permission_sets_to_create.json"
echo -e "${GREEN}  $OUTPUT_DIR/permission_sets_to_create.json${NC}"

[ -n "${SINGLE_ACCOUNT_JSON:-}" ] && [ -f "$SINGLE_ACCOUNT_JSON" ] && rm -f "$SINGLE_ACCOUNT_JSON"

echo ""
echo -e "${BLUE}Summary${NC}"
echo "  SSO roles audited: $(echo "$SSO_AUDIT_JSON" | jq length)"
echo "  Permission sets to create: $(echo "$PERM_SETS_TO_CREATE" | jq length)"
echo ""
echo -e "${GREEN}Use permission_sets_to_create.json to create each permission set in the destination Identity Center.${NC}"
echo "  Then assign your groups (with users copied manually) to these permission sets per account."
echo ""
