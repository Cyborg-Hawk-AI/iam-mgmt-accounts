#!/bin/bash
#
# generate_sso_per_account_report.sh - From SSO discovery JSON, write human-readable
# report and policies-per-role under data/processed for a single account.
#
# Used when run_migration_workflow.sh --per-account (SSO-only). Produces tangible
# results you can show your boss: which SSO roles exist and what policies are
# attached to each. Policy documents are stored as JSON so you can retrieve them.
#
# Usage:
#   ./generate_sso_per_account_report.sh --input ACCOUNT_DIR/data/raw/iam_discovery.json --output-dir ACCOUNT_DIR/data/processed
#
# Output under output-dir:
#   SSO_ROLES_AND_POLICIES.md  - Human-readable: one section per SSO role, policies listed
#   policies_per_role.json     - Machine-readable: role name -> attached policies
#   customer-policies/*.json   - Policy documents (customer-managed + inline) for retrieval
#

set -euo pipefail

INPUT_FILE=""
OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --input)
      INPUT_FILE="$2"
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

if [ -z "$INPUT_FILE" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "Usage: $0 --input <iam_discovery.json> --output-dir <data/processed>"
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  echo "Error: Input file not found: $INPUT_FILE"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/customer-policies"

# Sanitize for filenames: replace / and space with -
sanitize() { echo "$1" | sed 's/[\/ ]/-/g'; }

ACCOUNT_ID=$(jq -r '.account_id // "unknown"' "$INPUT_FILE")
DISCOVERED_AT=$(jq -r '.discovered_at // ""' "$INPUT_FILE")

# --- 1. Export customer-managed policy documents to customer-policies/ ---
for policy_arn in $(jq -r '.managed_policies[] | select(.arn | test("arn:aws:iam::aws:policy/") | not) | .arn' "$INPUT_FILE" 2>/dev/null); do
  [ -z "$policy_arn" ] && continue
  name=$(jq -r --arg arn "$policy_arn" '.managed_policies[] | select(.arn == $arn) | .name' "$INPUT_FILE")
  [ -z "$name" ] && name=$(echo "$policy_arn" | awk -F'/' '{print $NF}')
  out="$OUTPUT_DIR/customer-policies/$(sanitize "$name").json"
  jq -c --arg arn "$policy_arn" '.managed_policies[] | select(.arn == $arn) | .document' "$INPUT_FILE" > "$out"
done

# --- 2. Export inline policy documents to customer-policies/inline-<Role>-<Name>.json ---
jq -r '.roles[] | .name as $r | .inline_policies[]? | "\($r)|\(.name)"' "$INPUT_FILE" 2>/dev/null | while IFS='|' read -r role_name policy_name; do
  [ -z "$role_name" ] || [ -z "$policy_name" ] && continue
  out="$OUTPUT_DIR/customer-policies/inline-$(sanitize "$role_name")-$(sanitize "$policy_name").json"
  jq -c --arg r "$role_name" --arg p "$policy_name" '.roles[] | select(.name == $r) | .inline_policies[] | select(.name == $p) | .document' "$INPUT_FILE" > "$out"
done

# --- 3. Build policies_per_role.json (machine-readable) ---
jq -c '
  def sanitize: gsub(" "; "-") | gsub("/"; "-");
  [.roles[] | .name as $r | {
    role_name: .name,
    role_arn: .arn,
    aws_managed_policy_arns: [.attached_managed_policies[]?.PolicyArn | select(startswith("arn:aws:iam::aws:policy/"))],
    customer_managed_policy_arns: [.attached_managed_policies[]?.PolicyArn | select(startswith("arn:aws:iam::aws:policy/") | not)],
    inline_policy_names: (.inline_policy_names // []),
    inline_policies: [.inline_policies[]? | { name: .name, document_file: ("customer-policies/inline-" + ($r | sanitize) + "-" + (.name | sanitize) + ".json") } ]
  }]
' "$INPUT_FILE" > "$OUTPUT_DIR/policies_per_role.json"

# --- 4. Build SSO_ROLES_AND_POLICIES.md (human-readable, boss-presentable) ---
MD="$OUTPUT_DIR/SSO_ROLES_AND_POLICIES.md"
{
  echo "# SSO Roles and Attached Policies — Account $ACCOUNT_ID"
  echo ""
  echo "Generated from discovery at **$DISCOVERED_AT**. Use this to replicate permission sets in your target Identity Center."
  echo ""
  echo "---"
  echo ""

  jq -r '.roles[] | .name' "$INPUT_FILE" 2>/dev/null | while read -r role_name; do
    [ -z "$role_name" ] && continue
    echo "## $role_name"
    echo ""
    aws_managed=$(jq -r --arg r "$role_name" '[.roles[] | select(.name == $r) | .attached_managed_policies[]?.PolicyArn | select(startswith("arn:aws:iam::aws:policy/"))] | .[]' "$INPUT_FILE" 2>/dev/null)
    cust_managed=$(jq -r --arg r "$role_name" '[.roles[] | select(.name == $r) | .attached_managed_policies[]?.PolicyArn | select(startswith("arn:aws:iam::aws:policy/") | not)] | .[]' "$INPUT_FILE" 2>/dev/null)
    inline_names=$(jq -r --arg r "$role_name" '.roles[] | select(.name == $r) | .inline_policy_names[]?' "$INPUT_FILE" 2>/dev/null)

    echo "**AWS-managed policies** (attach by ARN in Identity Center):"
    if [ -n "$aws_managed" ]; then
      echo "$aws_managed" | while read -r arn; do echo "  - \`$arn\`"; done
    else
      echo "  - (none)"
    fi
    echo ""

    echo "**Customer-managed policies** (recreate in target from JSON in \`customer-policies/\`, then attach by ARN):"
    if [ -n "$cust_managed" ]; then
      echo "$cust_managed" | while read -r arn; do
        fname=$(echo "$arn" | awk -F'/' '{print $NF}')
        echo "  - \`$arn\` → \`customer-policies/$(sanitize "$fname").json\`"
      done
    else
      echo "  - (none)"
    fi
    echo ""

    echo "**Inline policies**:"
    if [ -n "$inline_names" ]; then
      echo "$inline_names" | while read -r pname; do
        echo "  - \`$pname\` → \`customer-policies/inline-$(sanitize "$role_name")-$(sanitize "$pname").json\`"
      done
    else
      echo "  - (none)"
    fi
    echo ""
    echo "---"
    echo ""
  done

  echo "## File reference"
  echo ""
  echo "| File | Purpose |"
  echo "|------|---------|"
  echo "| \`SSO_ROLES_AND_POLICIES.md\` | This report — policies per SSO role |"
  echo "| \`policies_per_role.json\` | Machine-readable list of policies per role |"
  echo "| \`customer-policies/*.json\` | Policy documents (JSON) for customer-managed and inline policies |"
  echo ""
} > "$MD"

# --- 5. Short README in data/processed so the folder is self-explanatory ---
README="$OUTPUT_DIR/README.md"
{
  echo "# Processed output for account $ACCOUNT_ID"
  echo ""
  echo "**Show your boss:** open **\`SSO_ROLES_AND_POLICIES.md\`** — it lists every SSO role found in this account and the policies attached to each."
  echo ""
  echo "- \`SSO_ROLES_AND_POLICIES.md\` — Human-readable report (policies per role)"
  echo "- \`policies_per_role.json\` — Machine-readable (role → policies)"
  echo "- \`customer-policies/*.json\` — Policy documents in JSON so you can retrieve and reuse them"
  echo ""
} > "$README"

echo "  SSO_ROLES_AND_POLICIES.md (human-readable, policies per role)"
echo "  policies_per_role.json"
echo "  customer-policies/*.json (policy documents)"
echo "  README.md"
