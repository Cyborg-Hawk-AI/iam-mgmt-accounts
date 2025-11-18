#!/bin/bash
#
# analyze_policies.sh - Analyze IAM policies for overlaps and consolidation opportunities
#
# Usage:
#   ./analyze_policies.sh [--input FILE] [--output DIR] [--similarity-threshold FLOAT]
#
# Output: data/processed/policy_analysis.json

set -euo pipefail

# Configuration
INPUT_FILE="${INPUT_FILE:-data/raw/iam_discovery.json}"
OUTPUT_DIR="${OUTPUT_DIR:-data/processed}"
SIMILARITY_THRESHOLD="${SIMILARITY_THRESHOLD:-0.8}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --input)
      INPUT_FILE="$2"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --similarity-threshold)
      SIMILARITY_THRESHOLD="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Starting Policy Analysis...${NC}"

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file not found: $INPUT_FILE"
  echo "Run discover_iam.sh first"
  exit 1
fi

# Extract all actions from a policy document
extract_actions() {
  local policy_doc="$1"
  echo "$policy_doc" | jq -r '
    if type == "object" then
      (.Statement // []) | 
      if type == "array" then .[] else . end |
      if type == "object" then
        (.Action // []) |
        if type == "array" then .[] else . end |
        if type == "string" then . else empty end
      else empty end
    else empty end
  ' | sort -u
}

# Normalize action format (handle wildcards, service prefixes)
normalize_action() {
  local action="$1"
  # Convert to lowercase, handle wildcards
  echo "$action" | tr '[:upper:]' '[:lower:]' | sed 's/\*$//'
}

# Calculate Jaccard similarity between two action sets
calculate_similarity() {
  local actions1="$1"
  local actions2="$2"
  
  if [ -z "$actions1" ] && [ -z "$actions2" ]; then
    echo "1.0"
    return
  fi
  
  if [ -z "$actions1" ] || [ -z "$actions2" ]; then
    echo "0.0"
    return
  fi
  
  # Count intersection and union
  local intersection=$(comm -12 <(echo "$actions1" | sort) <(echo "$actions2" | sort) | wc -l | tr -d ' ')
  local union=$(comm -3 <(echo "$actions1" | sort) <(echo "$actions2" | sort) | wc -l | tr -d ' ')
  union=$((union + intersection))
  
  if [ "$union" -eq 0 ]; then
    echo "0.0"
  else
    echo "scale=4; $intersection / $union" | bc
  fi
}

echo -e "${YELLOW}Extracting policy actions...${NC}"

# Build policy action map
POLICY_ACTIONS_FILE="${OUTPUT_DIR}/policy_actions.json"
cat > "$POLICY_ACTIONS_FILE" <<EOF
{
  "managed_policies": {},
  "inline_policies": []
}
EOF

# Process managed policies
echo "  Processing managed policies..."
MANAGED_POLICIES=$(jq -r '.managed_policies[]? | @json' "$INPUT_FILE" 2>/dev/null || echo "")

while IFS= read -r policy_json; do
  [ -z "$policy_json" ] && continue
  
  POLICY_ARN=$(echo "$policy_json" | jq -r '.arn')
  POLICY_NAME=$(echo "$policy_json" | jq -r '.name')
  POLICY_DOC=$(echo "$policy_json" | jq -c '.document')
  
  ACTIONS=$(extract_actions "$POLICY_DOC" | sort -u)
  ACTION_COUNT=$(echo "$ACTIONS" | grep -c . || echo "0")
  
  POLICY_DATA=$(jq -n \
    --arg arn "$POLICY_ARN" \
    --arg name "$POLICY_NAME" \
    --arg actions "$ACTIONS" \
    --argjson count "$ACTION_COUNT" \
    '{
      "arn": $arn,
      "name": $name,
      "actions": ($actions | split("\n") | map(select(. != ""))),
      "action_count": $count
    }')
  
  jq --arg name "$POLICY_NAME" --argjson data "$POLICY_DATA" '.managed_policies[$name] = $data' "$POLICY_ACTIONS_FILE" > "${POLICY_ACTIONS_FILE}.tmp" && mv "${POLICY_ACTIONS_FILE}.tmp" "$POLICY_ACTIONS_FILE"
done <<< "$MANAGED_POLICIES"

# Process inline policies from users, roles, groups
echo "  Processing inline policies..."
INLINE_POLICIES=$(jq -c '
  [
    (.users[]? | {principal_type: "user", principal_name: .name, policies: .inline_policies}),
    (.roles[]? | {principal_type: "role", principal_name: .name, policies: .inline_policies}),
    (.groups[]? | {principal_type: "group", principal_name: .name, policies: .inline_policies})
  ] | .[]
' "$INPUT_FILE" 2>/dev/null || echo "")

while IFS= read -r principal_data; do
  [ -z "$principal_data" ] && continue
  
  PRINCIPAL_TYPE=$(echo "$principal_data" | jq -r '.principal_type')
  PRINCIPAL_NAME=$(echo "$principal_data" | jq -r '.principal_name')
  POLICIES=$(echo "$principal_data" | jq -c '.policies[]?')
  
  while IFS= read -r policy_json; do
    [ -z "$policy_json" ] && continue
    
    POLICY_NAME=$(echo "$policy_json" | jq -r '.name')
    POLICY_DOC=$(echo "$policy_json" | jq -c '.document')
    
    ACTIONS=$(extract_actions "$POLICY_DOC" | sort -u)
    ACTION_COUNT=$(echo "$ACTIONS" | grep -c . || echo "0")
    
    POLICY_DATA=$(jq -n \
      --arg type "$PRINCIPAL_TYPE" \
      --arg principal "$PRINCIPAL_NAME" \
      --arg name "$POLICY_NAME" \
      --arg actions "$ACTIONS" \
      --argjson count "$ACTION_COUNT" \
      '{
        "principal_type": $type,
        "principal_name": $principal,
        "policy_name": $name,
        "actions": ($actions | split("\n") | map(select(. != ""))),
        "action_count": $count
      }')
    
    jq --argjson data "$POLICY_DATA" '.inline_policies += [$data]' "$POLICY_ACTIONS_FILE" > "${POLICY_ACTIONS_FILE}.tmp" && mv "${POLICY_ACTIONS_FILE}.tmp" "$POLICY_ACTIONS_FILE"
  done <<< "$POLICIES"
done <<< "$INLINE_POLICIES"

echo -e "${YELLOW}Computing policy overlaps...${NC}"

# Compute overlaps between managed policies
OVERLAPS_FILE="${OUTPUT_DIR}/policy_overlaps.json"
cat > "$OVERLAPS_FILE" <<EOF
{
  "managed_policy_overlaps": [],
  "inline_policy_overlaps": [],
  "cross_type_overlaps": []
}
EOF

# Compare managed policies
MANAGED_POLICY_NAMES=$(jq -r '.managed_policies | keys[]' "$POLICY_ACTIONS_FILE" 2>/dev/null || echo "")
POLICY_ARRAY=($MANAGED_POLICY_NAMES)

for i in "${!POLICY_ARRAY[@]}"; do
  for j in "${!POLICY_ARRAY[@]}"; do
    if [ "$i" -lt "$j" ]; then
      POLICY_A="${POLICY_ARRAY[$i]}"
      POLICY_B="${POLICY_ARRAY[$j]}"
      
      ACTIONS_A=$(jq -r ".managed_policies[\"$POLICY_A\"].actions[]" "$POLICY_ACTIONS_FILE" 2>/dev/null | sort -u)
      ACTIONS_B=$(jq -r ".managed_policies[\"$POLICY_B\"].actions[]" "$POLICY_ACTIONS_FILE" 2>/dev/null | sort -u)
      
      SIMILARITY=$(calculate_similarity "$ACTIONS_A" "$ACTIONS_B")
      
      if (( $(echo "$SIMILARITY >= $SIMILARITY_THRESHOLD" | bc -l) )); then
        UNIQUE_A=$(comm -23 <(echo "$ACTIONS_A" | sort) <(echo "$ACTIONS_B" | sort) | wc -l | tr -d ' ')
        UNIQUE_B=$(comm -13 <(echo "$ACTIONS_A" | sort) <(echo "$ACTIONS_B" | sort) | wc -l | tr -d ' ')
        
        OVERLAP=$(jq -n \
          --arg a "$POLICY_A" \
          --arg b "$POLICY_B" \
          --argjson sim "$SIMILARITY" \
          --argjson unique_a "$UNIQUE_A" \
          --argjson unique_b "$UNIQUE_B" \
          '{
            "policy_a": $a,
            "policy_b": $b,
            "similarity": ($sim | tonumber),
            "unique_actions_a": $unique_a,
            "unique_actions_b": $unique_b
          }')
        
        jq --argjson overlap "$OVERLAP" '.managed_policy_overlaps += [$overlap]' "$OVERLAPS_FILE" > "${OVERLAPS_FILE}.tmp" && mv "${OVERLAPS_FILE}.tmp" "$OVERLAPS_FILE"
      fi
    fi
  done
done

echo -e "${YELLOW}Identifying consolidation opportunities...${NC}"

# Generate consolidation candidates
CONSOLIDATION_FILE="${OUTPUT_DIR}/consolidation_candidates.json"

# Sort overlaps by similarity
TOP_OVERLAPS=$(jq -c ".managed_policy_overlaps | sort_by(-.similarity) | .[0:10]" "$OVERLAPS_FILE" 2>/dev/null || echo "[]")

# Build consolidation recommendations
RECOMMENDATIONS=$(jq -c '.managed_policy_overlaps[] | select(.similarity >= 0.8) | {
  policy_a: .policy_a,
  policy_b: .policy_b,
  overlap_percent: (.similarity * 100),
  recommendation: (if .unique_actions_a == 0 then "REPLACE_A_WITH_B" elif .unique_actions_b == 0 then "REPLACE_B_WITH_A" else "CONSOLIDATE" end)
}' "$OVERLAPS_FILE" 2>/dev/null || echo "[]")

cat > "$CONSOLIDATION_FILE" <<EOF
{
  "analysis_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "similarity_threshold": $SIMILARITY_THRESHOLD,
  "top_overlaps": $TOP_OVERLAPS,
  "consolidation_opportunities": $RECOMMENDATIONS,
  "summary": {
    "total_managed_policies": $(jq '.managed_policies | length' "$POLICY_ACTIONS_FILE" 2>/dev/null || echo "0"),
    "total_inline_policies": $(jq '.inline_policies | length' "$POLICY_ACTIONS_FILE" 2>/dev/null || echo "0"),
    "high_similarity_pairs": $(jq "[.managed_policy_overlaps[] | select(.similarity >= 0.8)] | length" "$OVERLAPS_FILE" 2>/dev/null || echo "0")
  }
}
EOF

# Create final analysis file
ANALYSIS_FILE="${OUTPUT_DIR}/policy_analysis.json"
cat > "$ANALYSIS_FILE" <<EOF
{
  "input_file": "$INPUT_FILE",
  "analysis_date": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "policy_actions": $(cat "$POLICY_ACTIONS_FILE"),
  "overlaps": $(cat "$OVERLAPS_FILE"),
  "consolidation_candidates": $(cat "$CONSOLIDATION_FILE")
}
EOF

echo -e "${GREEN}Analysis complete!${NC}"
echo ""
echo "Output files:"
echo "  - $ANALYSIS_FILE"
echo "  - $OVERLAPS_FILE"
echo "  - $CONSOLIDATION_FILE"
echo ""
echo "Top consolidation opportunities:"
jq -r '.consolidation_candidates.consolidation_opportunities[0:5] | .[] | "\(.policy_a) <-> \(.policy_b): \(.overlap_percent)% overlap - \(.recommendation)"' "$ANALYSIS_FILE" 2>/dev/null || echo "None found"

