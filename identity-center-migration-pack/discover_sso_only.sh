#!/bin/bash
#
# discover_sso_only.sh - Discover only Identity Center (SSO) roles and their policies
#
# Use this for Identity Center user-access migration. It does NOT discover IAM users,
# IAM groups, or non-SSO roles (e.g. service roles). Only roles named AWSReservedSSO_*
# are collected, plus the managed and inline policies attached to them. Customer-managed
# policy documents are fetched so you can recreate them in the new org.
#
# IAM users, service roles, and other IAM resources stay unchanged; we only need to
# recreate permission sets (and their policies) for human user access in the new IdC.
#
# Usage:
#   ./discover_sso_only.sh [--output FILE] [--profile PROFILE]
#
# Output: same shape as discover_iam.sh (roles, managed_policies; users/groups empty)
# so aggregate_all_accounts.sh and audit_sso_roles.sh work unchanged.

set -euo pipefail

OUTPUT_FILE="${OUTPUT_FILE:-data/raw/iam_discovery.json}"
AWS_PROFILE="${AWS_PROFILE:-}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    --profile)
      AWS_PROFILE="$2"
      export AWS_PROFILE
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

mkdir -p "$(dirname "$OUTPUT_FILE")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}SSO-only discovery (Identity Center roles and their policies)${NC}"
echo "  IAM users, service roles, and other IAM are not collected."
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

# Initialize: users and groups empty; we only fill roles and managed_policies
cat > "$OUTPUT_FILE" <<EOF
{
  "account_id": "$ACCOUNT_ID",
  "region": "$REGION",
  "discovered_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "discovered_by": "$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo 'unknown')",
  "users": [],
  "roles": [],
  "groups": [],
  "managed_policies": [],
  "summary": {}
}
EOF

get_policy_document() {
  local policy_arn="$1"
  local version_id
  version_id=$(aws iam get-policy --policy-arn "$policy_arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || echo "")
  if [ -n "$version_id" ]; then
    aws iam get-policy-version --policy-arn "$policy_arn" --version-id "$version_id" --query 'PolicyVersion.Document' --output json 2>/dev/null || echo "{}"
  else
    echo "{}"
  fi
}

# List only SSO roles (Identity Center–created)
echo -e "${YELLOW}Discovering SSO roles (AWSReservedSSO_*)...${NC}"
ROLE_NAMES=$(aws iam list-roles --output json 2>/dev/null | jq -r '.Roles[] | select(.RoleName | startswith("AWSReservedSSO_")) | .RoleName' 2>/dev/null || echo "")
ROLE_COUNT=0

for role_name in $ROLE_NAMES; do
  [ -z "$role_name" ] && continue
  echo "  Processing SSO role: $role_name"

  ROLE_ARN=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null || echo "")
  CREATE_DATE=$(aws iam get-role --role-name "$role_name" --query 'Role.CreateDate' --output text 2>/dev/null || echo "")
  ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[*]' --output json 2>/dev/null || echo "[]")
  INLINE_POLICY_NAMES=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output json 2>/dev/null || echo "[]")

  ROLE_JSON=$(jq -n \
    --arg name "$role_name" \
    --arg arn "$ROLE_ARN" \
    --arg created "$CREATE_DATE" \
    --argjson attached "$ATTACHED_POLICIES" \
    --argjson inline_names "$INLINE_POLICY_NAMES" \
    '{
      "name": $name,
      "arn": $arn,
      "created_date": $created,
      "attached_managed_policies": $attached,
      "inline_policy_names": $inline_names,
      "inline_policies": []
    }')

  INLINE_POLICIES_JSON="[]"
  for policy_name in $(echo "$INLINE_POLICY_NAMES" | jq -r '.[]'); do
    POLICY_DOC=$(aws iam get-role-policy --role-name "$role_name" --policy-name "$policy_name" --query 'PolicyDocument' --output json 2>/dev/null || echo "{}")
    INLINE_POLICIES_JSON=$(echo "$INLINE_POLICIES_JSON" | jq --arg name "$policy_name" --argjson doc "$POLICY_DOC" '. + [{"name": $name, "document": $doc}]')
  done
  ROLE_JSON=$(echo "$ROLE_JSON" | jq --argjson inline "$INLINE_POLICIES_JSON" '.inline_policies = $inline')

  jq --argjson role "$ROLE_JSON" '.roles += [$role]' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  ROLE_COUNT=$((ROLE_COUNT + 1))
done

# Collect unique managed policy ARNs from SSO roles and fetch documents (customer-managed only need document for recreation)
echo -e "${YELLOW}Fetching policy documents (for policies attached to SSO roles)...${NC}"
ALL_POLICY_ARNS=$(jq -r '[.roles[].attached_managed_policies[].PolicyArn] | unique | .[]' "$OUTPUT_FILE" 2>/dev/null || true)
POLICY_COUNT=0

for policy_arn in $ALL_POLICY_ARNS; do
  [ -z "$policy_arn" ] && continue
  echo "  Policy: $policy_arn"
  POLICY_DOC=$(get_policy_document "$policy_arn")
  POLICY_NAME=$(echo "$policy_arn" | awk -F'/' '{print $NF}')
  POLICY_JSON=$(jq -n \
    --arg arn "$policy_arn" \
    --arg name "$POLICY_NAME" \
    --argjson doc "$POLICY_DOC" \
    '{ "arn": $arn, "name": $name, "document": $doc }')
  jq --argjson policy "$POLICY_JSON" '.managed_policies += [$policy]' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  POLICY_COUNT=$((POLICY_COUNT + 1))
done

# Summary
jq --argjson roles "$ROLE_COUNT" --argjson policies "$POLICY_COUNT" \
  '.summary = { "total_sso_roles": $roles, "total_managed_policies": $policies }' \
  "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

echo -e "${GREEN}SSO-only discovery complete.${NC}"
echo "  SSO roles: $ROLE_COUNT"
echo "  Managed policies (attached to those roles): $POLICY_COUNT"
echo "  Output: $OUTPUT_FILE"
echo ""
