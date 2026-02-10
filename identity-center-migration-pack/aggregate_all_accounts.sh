#!/bin/bash
#
# aggregate_all_accounts.sh - Aggregate discovery results from all account subdirectories
#
# Usage:
#   ./aggregate_all_accounts.sh [--parent-dir DIR]
#
# Aggregates IAM discovery results from all account subdirectories
# Creates aggregated analysis for designing shared permission sets

set -euo pipefail

# Configuration
PARENT_DIR="${PARENT_DIR:-.}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --parent-dir)
      PARENT_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Aggregating IAM Discovery Results from All Accounts${NC}"
echo -e "${GREEN}⚠️  READ-ONLY OPERATION - Only processes local files${NC}"
echo ""

# Create aggregated output directory
AGGREGATED_DIR="$PARENT_DIR/aggregated"
mkdir -p "$AGGREGATED_DIR"/{discovery,analysis,permission-sets,groups}

# Find all account directories (numeric directories)
ACCOUNT_DIRS=$(find "$PARENT_DIR" -maxdepth 1 -type d -regex '.*/[0-9][0-9]*' | sort)

if [ -z "$ACCOUNT_DIRS" ]; then
  echo -e "${YELLOW}No account directories found. Looking for numeric subdirectories...${NC}"
  exit 1
fi

echo -e "${YELLOW}Found account directories:${NC}"
echo "$ACCOUNT_DIRS" | sed 's|.*/||' | while read -r account; do
  echo "  - $account"
done
echo ""

# Aggregate discovery files
AGGREGATED_DISCOVERY="$AGGREGATED_DIR/discovery/all_accounts.json"
cat > "$AGGREGATED_DISCOVERY" <<EOF
{
  "aggregated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "accounts": []
}
EOF

ACCOUNT_COUNT=0
while IFS= read -r account_dir; do
  account_id=$(basename "$account_dir")
  discovery_file="$account_dir/data/raw/iam_discovery.json"
  
  if [ -f "$discovery_file" ]; then
    echo -e "${YELLOW}Processing account: $account_id${NC}"
    
    # Extract account data
    account_data=$(jq -c --arg account "$account_id" '{
      account_id: $account,
      discovered_at: .discovered_at,
      users: .users,
      roles: .roles,
      groups: .groups,
      managed_policies: .managed_policies
    }' "$discovery_file" 2>/dev/null)
    
    if [ -n "$account_data" ]; then
      # Add to aggregated file
      jq --argjson account "$account_data" '.accounts += [$account]' \
        "$AGGREGATED_DISCOVERY" > "${AGGREGATED_DISCOVERY}.tmp" && \
        mv "${AGGREGATED_DISCOVERY}.tmp" "$AGGREGATED_DISCOVERY"
      ACCOUNT_COUNT=$((ACCOUNT_COUNT + 1))
    fi
  else
    echo -e "${YELLOW}  Warning: Discovery file not found: $discovery_file${NC}"
  fi
done <<< "$ACCOUNT_DIRS"

# Aggregate policy actions across all accounts
echo ""
echo -e "${YELLOW}Aggregating policy actions across all accounts...${NC}"

POLICY_ACTIONS_FILE="$AGGREGATED_DIR/analysis/all_policy_actions.json"
cat > "$POLICY_ACTIONS_FILE" <<EOF
{
  "aggregated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "account_count": $ACCOUNT_COUNT,
  "all_actions": {},
  "per_account_actions": {}
}
EOF

# Extract all unique actions from all accounts (Action can be string or array)
ALL_ACTIONS=$(jq -r '
  .accounts[].managed_policies[]?.document.Statement[]? |
  (.Action | if type == "array" then .[] else . end) |
  select(type == "string")
' "$AGGREGATED_DISCOVERY" 2>/dev/null | grep -v '^null$' | sort -u)

# Count action usage across accounts (|| true so empty ALL_ACTIONS doesn't trigger set -e)
while IFS= read -r action; do
  [ -z "$action" ] && continue

  # Count how many accounts use this action
  account_count=$(jq -r --arg action "$action" '
    .accounts[] | select(
      [.managed_policies[]?.document.Statement[]? |
       (.Action | if type == "array" then .[] else . end) |
       select(. == $action)] | length > 0
    ) | .account_id
  ' "$AGGREGATED_DISCOVERY" 2>/dev/null | sort -u | wc -l | tr -d ' ')

  jq --arg action "$action" --argjson count "$account_count" \
    '.all_actions[$action] = $count' \
    "$POLICY_ACTIONS_FILE" > "${POLICY_ACTIONS_FILE}.tmp" && \
    mv "${POLICY_ACTIONS_FILE}.tmp" "$POLICY_ACTIONS_FILE"
done <<< "$ALL_ACTIONS" || true

# Generate summary
SUMMARY_FILE="$AGGREGATED_DIR/analysis/summary.json"
cat > "$SUMMARY_FILE" <<EOF
{
  "aggregated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "account_count": $ACCOUNT_COUNT,
  "total_users": $(jq '[.accounts[].users[]?] | length' "$AGGREGATED_DISCOVERY" 2>/dev/null || echo "0"),
  "total_roles": $(jq '[.accounts[].roles[]?] | length' "$AGGREGATED_DISCOVERY" 2>/dev/null || echo "0"),
  "total_groups": $(jq '[.accounts[].groups[]?] | length' "$AGGREGATED_DISCOVERY" 2>/dev/null || echo "0"),
  "total_managed_policies": $(jq '[.accounts[].managed_policies[]?] | length' "$AGGREGATED_DISCOVERY" 2>/dev/null || echo "0"),
  "unique_actions_count": $(jq '.all_actions | length' "$POLICY_ACTIONS_FILE" 2>/dev/null || echo "0")
}
EOF

echo ""
echo -e "${GREEN}Aggregation complete!${NC}"
echo ""
echo "Summary:"
jq '.' "$SUMMARY_FILE" 2>/dev/null || cat "$SUMMARY_FILE"
echo ""
echo "Aggregated files:"
echo "  - Discovery: $AGGREGATED_DIR/discovery/all_accounts.json"
echo "  - Policy Actions: $AGGREGATED_DIR/analysis/all_policy_actions.json"
echo "  - Summary: $AGGREGATED_DIR/analysis/summary.json"
