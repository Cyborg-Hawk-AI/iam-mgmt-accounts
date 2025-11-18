#!/bin/bash
#
# discover_iam.sh - Discover all IAM users, roles, groups, and policies
#
# Usage:
#   ./discover_iam.sh [--include-access-advisor] [--output FILE] [--profile PROFILE]
#
# Output: data/raw/iam_discovery.json

set -euo pipefail

# Configuration
OUTPUT_FILE="${OUTPUT_FILE:-data/raw/iam_discovery.json}"
INCLUDE_ACCESS_ADVISOR="${INCLUDE_ACCESS_ADVISOR:-false}"
AWS_PROFILE="${AWS_PROFILE:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --include-access-advisor)
      INCLUDE_ACCESS_ADVISOR=true
      shift
      ;;
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

# Create output directory
mkdir -p "$(dirname "$OUTPUT_FILE")"
mkdir -p data/raw

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting IAM Discovery...${NC}"

# Get account info
echo "Fetching account information..."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
REGION=$(aws configure get region 2>/dev/null || echo "us-east-1")

# Initialize output structure
cat > "$OUTPUT_FILE" <<EOF
{
  "account_id": "$ACCOUNT_ID",
  "region": "$REGION",
  "discovered_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "discovered_by": "$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo 'unknown')",
  "users": [],
  "roles": [],
  "groups": [],
  "summary": {}
}
EOF

# Function to get policy document
get_policy_document() {
  local policy_arn="$1"
  local version_id
  
  # Get default version
  version_id=$(aws iam get-policy --policy-arn "$policy_arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || echo "")
  
  if [ -n "$version_id" ]; then
    aws iam get-policy-version --policy-arn "$policy_arn" --version-id "$version_id" --query 'PolicyVersion.Document' --output json 2>/dev/null || echo "{}"
  else
    echo "{}"
  fi
}

# Function to get inline policy document
get_inline_policy_document() {
  local principal_type="$1"
  local principal_name="$2"
  local policy_name="$3"
  
  case "$principal_type" in
    user)
      aws iam get-user-policy --user-name "$principal_name" --policy-name "$policy_name" --query 'PolicyDocument' --output json 2>/dev/null || echo "{}"
      ;;
    role)
      aws iam get-role-policy --role-name "$principal_name" --policy-name "$policy_name" --query 'PolicyDocument' --output json 2>/dev/null || echo "{}"
      ;;
    group)
      aws iam get-group-policy --group-name "$principal_name" --policy-name "$policy_name" --query 'PolicyDocument' --output json 2>/dev/null || echo "{}"
      ;;
  esac
}

# Function to get access advisor data (if enabled)
get_access_advisor() {
  local principal_type="$1"
  local principal_name="$2"
  
  if [ "$INCLUDE_ACCESS_ADVISOR" != "true" ]; then
    echo "null"
    return
  fi
  
  # Generate job (this is async, so we'll just note it)
  local job_id
  job_id=$(aws iam generate-service-last-accessed-details \
    --arn "arn:aws:iam::${ACCOUNT_ID}:${principal_type}/${principal_name}" \
    --query 'JobId' --output text 2>/dev/null || echo "")
  
  if [ -n "$job_id" ]; then
    # Wait a bit and try to get results
    sleep 2
    aws iam get-service-last-accessed-details \
      --job-id "$job_id" \
      --query 'ServicesLastAccessed' \
      --output json 2>/dev/null || echo "[]"
  else
    echo "[]"
  fi
}

# Discover Users
echo -e "${YELLOW}Discovering IAM Users...${NC}"
USER_NAMES=$(aws iam list-users --query 'Users[*].UserName' --output text 2>/dev/null || echo "")
USER_COUNT=0

for user_name in $USER_NAMES; do
  echo "  Processing user: $user_name"
  
  # Get user details
  USER_ARN=$(aws iam get-user --user-name "$user_name" --query 'User.Arn' --output text 2>/dev/null || echo "")
  CREATE_DATE=$(aws iam get-user --user-name "$user_name" --query 'User.CreateDate' --output text 2>/dev/null || echo "")
  
  # Get attached managed policies
  ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name "$user_name" --query 'AttachedPolicies[*]' --output json 2>/dev/null || echo "[]")
  
  # Get inline policy names
  INLINE_POLICY_NAMES=$(aws iam list-user-policies --user-name "$user_name" --query 'PolicyNames' --output json 2>/dev/null || echo "[]")
  
  # Build user object
  USER_JSON=$(jq -n \
    --arg name "$user_name" \
    --arg arn "$USER_ARN" \
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
  
  # Get inline policy documents
  INLINE_POLICIES_JSON="[]"
  for policy_name in $(echo "$INLINE_POLICY_NAMES" | jq -r '.[]'); do
    POLICY_DOC=$(get_inline_policy_document "user" "$user_name" "$policy_name")
    INLINE_POLICIES_JSON=$(echo "$INLINE_POLICIES_JSON" | jq --arg name "$policy_name" --argjson doc "$POLICY_DOC" '. + [{"name": $name, "document": $doc}]')
  done
  
  USER_JSON=$(echo "$USER_JSON" | jq --argjson inline "$INLINE_POLICIES_JSON" '.inline_policies = $inline')
  
  # Add to output
  jq --argjson user "$USER_JSON" '.users += [$user]' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  
  USER_COUNT=$((USER_COUNT + 1))
done

# Discover Roles
echo -e "${YELLOW}Discovering IAM Roles...${NC}"
ROLE_NAMES=$(aws iam list-roles --query 'Roles[*].RoleName' --output text 2>/dev/null || echo "")
ROLE_COUNT=0

for role_name in $ROLE_NAMES; do
  echo "  Processing role: $role_name"
  
  # Get role details
  ROLE_ARN=$(aws iam get-role --role-name "$role_name" --query 'Role.Arn' --output text 2>/dev/null || echo "")
  CREATE_DATE=$(aws iam get-role --role-name "$role_name" --query 'Role.CreateDate' --output text 2>/dev/null || echo "")
  
  # Get attached managed policies
  ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role_name" --query 'AttachedPolicies[*]' --output json 2>/dev/null || echo "[]")
  
  # Get inline policy names
  INLINE_POLICY_NAMES=$(aws iam list-role-policies --role-name "$role_name" --query 'PolicyNames' --output json 2>/dev/null || echo "[]")
  
  # Build role object
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
  
  # Get inline policy documents
  INLINE_POLICIES_JSON="[]"
  for policy_name in $(echo "$INLINE_POLICY_NAMES" | jq -r '.[]'); do
    POLICY_DOC=$(get_inline_policy_document "role" "$role_name" "$policy_name")
    INLINE_POLICIES_JSON=$(echo "$INLINE_POLICIES_JSON" | jq --arg name "$policy_name" --argjson doc "$POLICY_DOC" '. + [{"name": $name, "document": $doc}]')
  done
  
  ROLE_JSON=$(echo "$ROLE_JSON" | jq --argjson inline "$INLINE_POLICIES_JSON" '.inline_policies = $inline')
  
  # Add to output
  jq --argjson role "$ROLE_JSON" '.roles += [$role]' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  
  ROLE_COUNT=$((ROLE_COUNT + 1))
done

# Discover Groups
echo -e "${YELLOW}Discovering IAM Groups...${NC}"
GROUP_NAMES=$(aws iam list-groups --query 'Groups[*].GroupName' --output text 2>/dev/null || echo "")
GROUP_COUNT=0

for group_name in $GROUP_NAMES; do
  echo "  Processing group: $group_name"
  
  # Get group details
  GROUP_ARN=$(aws iam get-group --group-name "$group_name" --query 'Group.Arn' --output text 2>/dev/null || echo "")
  CREATE_DATE=$(aws iam get-group --group-name "$group_name" --query 'Group.CreateDate' --output text 2>/dev/null || echo "")
  
  # Get attached managed policies
  ATTACHED_POLICIES=$(aws iam list-attached-group-policies --group-name "$group_name" --query 'AttachedPolicies[*]' --output json 2>/dev/null || echo "[]")
  
  # Get inline policy names
  INLINE_POLICY_NAMES=$(aws iam list-group-policies --group-name "$group_name" --query 'PolicyNames' --output json 2>/dev/null || echo "[]")
  
  # Build group object
  GROUP_JSON=$(jq -n \
    --arg name "$group_name" \
    --arg arn "$GROUP_ARN" \
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
  
  # Get inline policy documents
  INLINE_POLICIES_JSON="[]"
  for policy_name in $(echo "$INLINE_POLICY_NAMES" | jq -r '.[]'); do
    POLICY_DOC=$(get_inline_policy_document "group" "$group_name" "$policy_name")
    INLINE_POLICIES_JSON=$(echo "$INLINE_POLICIES_JSON" | jq --arg name "$policy_name" --argjson doc "$POLICY_DOC" '. + [{"name": $name, "document": $doc}]')
  done
  
  GROUP_JSON=$(echo "$GROUP_JSON" | jq --argjson inline "$INLINE_POLICIES_JSON" '.inline_policies = $inline')
  
  # Add to output
  jq --argjson group "$GROUP_JSON" '.groups += [$group]' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"
  
  GROUP_COUNT=$((GROUP_COUNT + 1))
done

# Collect all unique managed policies and fetch their documents
echo -e "${YELLOW}Fetching managed policy documents...${NC}"
ALL_POLICY_ARNS=$(jq -r '[.users[].attached_managed_policies[], .roles[].attached_managed_policies[], .groups[].attached_managed_policies[]] | unique | .[].PolicyArn' "$OUTPUT_FILE" 2>/dev/null || echo "")

POLICIES_JSON="[]"
POLICY_COUNT=0
for policy_arn in $ALL_POLICY_ARNS; do
  echo "  Fetching policy: $policy_arn"
  POLICY_DOC=$(get_policy_document "$policy_arn")
  POLICY_NAME=$(echo "$policy_arn" | awk -F'/' '{print $NF}')
  
  POLICY_JSON=$(jq -n \
    --arg arn "$policy_arn" \
    --arg name "$POLICY_NAME" \
    --argjson doc "$POLICY_DOC" \
    '{
      "arn": $arn,
      "name": $name,
      "document": $doc
    }')
  
  POLICIES_JSON=$(echo "$POLICIES_JSON" | jq --argjson policy "$POLICY_JSON" '. + [$policy]')
  POLICY_COUNT=$((POLICY_COUNT + 1))
done

# Add policies to output
jq --argjson policies "$POLICIES_JSON" '.managed_policies = $policies' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

# Calculate summary
TOTAL_INLINE=$(jq '[.users[].inline_policies | length, .roles[].inline_policies | length, .groups[].inline_policies | length] | add' "$OUTPUT_FILE" 2>/dev/null || echo "0")

# Update summary
jq \
  --argjson users "$USER_COUNT" \
  --argjson roles "$ROLE_COUNT" \
  --argjson groups "$GROUP_COUNT" \
  --argjson policies "$POLICY_COUNT" \
  --argjson inline "$TOTAL_INLINE" \
  '.summary = {
    "total_users": $users,
    "total_roles": $roles,
    "total_groups": $groups,
    "total_managed_policies": $policies,
    "total_inline_policies": $inline
  }' "$OUTPUT_FILE" > "${OUTPUT_FILE}.tmp" && mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

echo -e "${GREEN}Discovery complete!${NC}"
echo "  Users: $USER_COUNT"
echo "  Roles: $ROLE_COUNT"
echo "  Groups: $GROUP_COUNT"
echo "  Managed Policies: $POLICY_COUNT"
echo "  Inline Policies: $TOTAL_INLINE"
echo ""
echo "Output saved to: $OUTPUT_FILE"
echo ""
echo "Summary:"
jq '.summary' "$OUTPUT_FILE"

