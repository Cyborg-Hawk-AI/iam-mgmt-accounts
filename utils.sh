#!/bin/bash
#
# utils.sh - Helper functions for IAM analysis scripts
#
# Source this file in other scripts:
#   source utils.sh

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to check AWS CLI availability
check_aws_cli() {
  if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found${NC}"
    exit 1
  fi
  
  # Check version
  AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}' | cut -d'/' -f2)
  echo -e "${BLUE}AWS CLI version: $AWS_VERSION${NC}"
}

# Function to verify IAM permissions
check_iam_permissions() {
  echo -e "${YELLOW}Checking IAM permissions...${NC}"
  
  local required_permissions=(
    "iam:ListUsers"
    "iam:ListRoles"
    "iam:ListGroups"
    "iam:GetPolicy"
  )
  
  local failed=0
  
  # Test basic list operations
  if ! aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}  ✗ Missing: iam:ListUsers${NC}"
    failed=1
  else
    echo -e "${GREEN}  ✓ iam:ListUsers${NC}"
  fi
  
  if ! aws iam list-roles --max-items 1 &> /dev/null; then
    echo -e "${RED}  ✗ Missing: iam:ListRoles${NC}"
    failed=1
  else
    echo -e "${GREEN}  ✓ iam:ListRoles${NC}"
  fi
  
  if ! aws iam list-groups --max-items 1 &> /dev/null; then
    echo -e "${RED}  ✗ Missing: iam:ListGroups${NC}"
    failed=1
  else
    echo -e "${GREEN}  ✓ iam:ListGroups${NC}"
  fi
  
  if [ $failed -eq 1 ]; then
    echo -e "${RED}Some required permissions are missing. Please check your IAM permissions.${NC}"
    return 1
  fi
  
  echo -e "${GREEN}All basic permissions verified.${NC}"
  return 0
}

# Function to get account information
get_account_info() {
  local account_id=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
  local account_arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "unknown")
  local user_id=$(aws sts get-caller-identity --query UserId --output text 2>/dev/null || echo "unknown")
  
  echo "Account ID: $account_id"
  echo "ARN: $account_arn"
  echo "User ID: $user_id"
}

# Function to extract actions from a policy document
extract_actions_from_policy() {
  local policy_file="$1"
  
  if [ ! -f "$policy_file" ]; then
    echo "Error: Policy file not found: $policy_file" >&2
    return 1
  fi
  
  jq -r '
    if type == "object" then
      (.Statement // []) | 
      if type == "array" then .[] else . end |
      if type == "object" then
        (.Action // []) |
        if type == "array" then .[] else . end |
        if type == "string" then . else empty end
      else empty end
    else empty end
  ' "$policy_file" | sort -u
}

# Function to compare two policies
compare_policies() {
  local policy1="$1"
  local policy2="$2"
  
  if [ ! -f "$policy1" ] || [ ! -f "$policy2" ]; then
    echo "Error: One or both policy files not found" >&2
    return 1
  fi
  
  local actions1=$(extract_actions_from_policy "$policy1")
  local actions2=$(extract_actions_from_policy "$policy2")
  
  echo "Policy 1 actions: $(echo "$actions1" | wc -l | tr -d ' ')"
  echo "Policy 2 actions: $(echo "$actions2" | wc -l | tr -d ' ')"
  
  echo ""
  echo "Actions only in Policy 1:"
  comm -23 <(echo "$actions1" | sort) <(echo "$actions2" | sort)
  
  echo ""
  echo "Actions only in Policy 2:"
  comm -13 <(echo "$actions1" | sort) <(echo "$actions2" | sort)
  
  echo ""
  echo "Common actions:"
  comm -12 <(echo "$actions1" | sort) <(echo "$actions2" | sort)
}

# Function to retry AWS CLI commands with exponential backoff
aws_retry() {
  local max_attempts=5
  local attempt=1
  local delay=1
  
  while [ $attempt -le $max_attempts ]; do
    if aws "$@"; then
      return 0
    fi
    
    local exit_code=$?
    
    # Check if it's a rate limit error
    if [ $exit_code -eq 254 ] || aws "$@" 2>&1 | grep -q "Throttling\|Rate exceeded"; then
      echo -e "${YELLOW}Rate limit hit, waiting ${delay}s before retry (attempt $attempt/$max_attempts)...${NC}" >&2
      sleep $delay
      delay=$((delay * 2))
      attempt=$((attempt + 1))
    else
      # Not a rate limit error, return immediately
      return $exit_code
    fi
  done
  
  echo -e "${RED}Max retry attempts reached${NC}" >&2
  return 1
}

# Function to create required directories
setup_directories() {
  mkdir -p data/raw
  mkdir -p data/processed
  mkdir -p output/reports
  mkdir -p output/proposals
  
  echo -e "${GREEN}Directories created${NC}"
}

# Function to display progress
show_progress() {
  local current=$1
  local total=$2
  local item="$3"
  
  local percent=$((current * 100 / total))
  local filled=$((percent / 2))
  local empty=$((50 - filled))
  
  printf "\r${BLUE}[%s%s] %d%% - %s${NC}" \
    "$(printf '#%.0s' $(seq 1 $filled))" \
    "$(printf ' %.0s' $(seq 1 $empty))" \
    "$percent" \
    "$item"
  
  if [ $current -eq $total ]; then
    echo ""
  fi
}

# Function to validate JSON file
validate_json() {
  local json_file="$1"
  
  if [ ! -f "$json_file" ]; then
    echo "Error: File not found: $json_file" >&2
    return 1
  fi
  
  if jq empty "$json_file" 2>/dev/null; then
    echo -e "${GREEN}✓ Valid JSON: $json_file${NC}"
    return 0
  else
    echo -e "${RED}✗ Invalid JSON: $json_file${NC}" >&2
    return 1
  fi
}

# Function to get policy document from ARN
get_policy_doc_from_arn() {
  local policy_arn="$1"
  
  local version_id=$(aws iam get-policy --policy-arn "$policy_arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || echo "")
  
  if [ -n "$version_id" ]; then
    aws iam get-policy-version --policy-arn "$policy_arn" --version-id "$version_id" --query 'PolicyVersion.Document' --output json 2>/dev/null
  else
    echo "{}"
  fi
}

# Export functions for use in other scripts
export -f check_aws_cli
export -f check_iam_permissions
export -f get_account_info
export -f extract_actions_from_policy
export -f compare_policies
export -f aws_retry
export -f setup_directories
export -f show_progress
export -f validate_json
export -f get_policy_doc_from_arn

