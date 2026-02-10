#!/bin/bash
#
# generate_migration_pack.sh - Produce human-readable migration pack and export customer policies
#
# Run after audit_sso_roles.sh. Reads audit output and:
# 1. Exports each customer-managed policy document to audit/customer-policies/<Name>.json (for recreation).
# 2. Writes audit/customer-policies/manifest.json (ARN -> file reference).
# 3. Writes audit/MIGRATION_PACK.md (human-readable: permission sets, custom policies, groups).
#
# Usage:
#   ./generate_migration_pack.sh --audit-dir audit
#   ./generate_migration_pack.sh --audit-dir audit --discovery path/to/iam_discovery.json
#   ./generate_migration_pack.sh --audit-dir audit --aggregated path/to/aggregated/discovery/all_accounts.json
#   ./generate_migration_pack.sh --audit-dir audit --live
#
# To export customer policy documents you must provide --discovery, --aggregated, or --live.
# Without one of those, MIGRATION_PACK.md and manifest are still generated but customer policy
# JSON files will be missing (you'll need to export them separately).
#
# Requires: jq. For --live: AWS CLI.

set -euo pipefail

AUDIT_DIR="${AUDIT_DIR:-audit}"
DISCOVERY_FILE=""
AGGREGATED_FILE=""
LIVE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --audit-dir)
      AUDIT_DIR="$2"
      shift 2
      ;;
    --discovery)
      DISCOVERY_FILE="$2"
      shift 2
      ;;
    --aggregated)
      AGGREGATED_FILE="$2"
      shift 2
      ;;
    --live)
      LIVE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

PERM_SETS_FILE="$AUDIT_DIR/permission_sets_to_create.json"
CUSTOMER_POLICIES_DIR="$AUDIT_DIR/customer-policies"
PACK_MD="$AUDIT_DIR/MIGRATION_PACK.md"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ ! -f "$PERM_SETS_FILE" ]; then
  echo -e "${RED}Error: $PERM_SETS_FILE not found. Run audit_sso_roles.sh first.${NC}"
  exit 1
fi

mkdir -p "$CUSTOMER_POLICIES_DIR"

# Collect unique customer-managed policy ARNs
CUSTOMER_ARNS=$(jq -r '
  [.[].customer_managed_policy_arns[]?] | unique[]
' "$PERM_SETS_FILE" 2>/dev/null || true)

# Export customer policy documents
MANIFEST_JSON="[]"
if [ -n "$DISCOVERY_FILE" ] && [ -f "$DISCOVERY_FILE" ]; then
  echo -e "${YELLOW}Exporting customer policy documents from discovery...${NC}"
  for arn in $CUSTOMER_ARNS; do
    [ -z "$arn" ] && continue
    name=$(echo "$arn" | awk -F'/' '{print $NF}')
    safe_name=$(echo "$name" | tr '/' '-')
    doc=$(jq -c --arg arn "$arn" '.managed_policies[]? | select(.arn == $arn) | .document' "$DISCOVERY_FILE" 2>/dev/null)
    if [ -n "$doc" ] && [ "$doc" != "null" ]; then
      echo "$doc" | jq '.' > "$CUSTOMER_POLICIES_DIR/${safe_name}.json"
      MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq --arg arn "$arn" --arg name "$name" --arg file "${safe_name}.json" '. + [{arn: $arn, policy_name: $name, file: $file}]')
    fi
  done
fi

if [ -n "$AGGREGATED_FILE" ] && [ -f "$AGGREGATED_FILE" ]; then
  echo -e "${YELLOW}Exporting customer policy documents from aggregated discovery...${NC}"
  for arn in $CUSTOMER_ARNS; do
    [ -z "$arn" ] && continue
    name=$(echo "$arn" | awk -F'/' '{print $NF}')
    safe_name=$(echo "$name" | tr '/' '-')
    [ -f "$CUSTOMER_POLICIES_DIR/${safe_name}.json" ] && continue
    doc=$(jq -c --arg arn "$arn" '[.accounts[]?.managed_policies[]? | select(.arn == $arn) | .document] | first // empty' "$AGGREGATED_FILE" 2>/dev/null)
    if [ -n "$doc" ] && [ "$doc" != "null" ]; then
      echo "$doc" | jq '.' > "$CUSTOMER_POLICIES_DIR/${safe_name}.json"
      MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq --arg arn "$arn" --arg name "$name" --arg file "${safe_name}.json" '. + [{arn: $arn, policy_name: $name, file: $file}]')
    fi
  done
fi

if [ "$LIVE" = true ]; then
  echo -e "${YELLOW}Exporting customer policy documents from AWS (live)...${NC}"
  for arn in $CUSTOMER_ARNS; do
    [ -z "$arn" ] && continue
    name=$(echo "$arn" | awk -F'/' '{print $NF}')
    safe_name=$(echo "$name" | tr '/' '-')
    [ -f "$CUSTOMER_POLICIES_DIR/${safe_name}.json" ] && continue
    version_id=$(aws iam get-policy --policy-arn "$arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || true)
    if [ -n "$version_id" ]; then
      aws iam get-policy-version --policy-arn "$arn" --version-id "$version_id" --query 'PolicyVersion.Document' --output json 2>/dev/null | jq '.' > "$CUSTOMER_POLICIES_DIR/${safe_name}.json"
      MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq --arg arn "$arn" --arg name "$name" --arg file "${safe_name}.json" '. + [{arn: $arn, policy_name: $name, file: $file}]')
    fi
  done
fi

# Dedupe manifest by file
MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq 'unique_by(.file)')
echo "$MANIFEST_JSON" | jq '.' > "$CUSTOMER_POLICIES_DIR/manifest.json"
echo -e "${GREEN}  $CUSTOMER_POLICIES_DIR/manifest.json${NC}"
echo -e "${GREEN}  $CUSTOMER_POLICIES_DIR/*.json (policy documents)${NC}"

# Human-readable migration pack
echo -e "${YELLOW}Writing $PACK_MD${NC}"
{
  echo "# Identity Center Migration Pack"
  echo ""
  echo "Use this pack to **pre-create permission sets and groups** in the destination org, then assign users to groups. Custom (customer-managed) policies are stored under \`customer-policies/\` so you can recreate them if needed."
  echo ""
  echo "---"
  echo ""

  echo "## 1. Permission sets to create"
  echo ""
  echo "Create each permission set in the destination Identity Center, then attach the listed policies."
  echo ""
  jq -r '.[] | "
### \(.permission_set_name)

- **AWS-managed policies** (attach by ARN in Identity Center):"
    + (if (.aws_managed_policy_arns | length) > 0 then "\n" + ([.aws_managed_policy_arns[]] | map("  - " + .) | join("\n")) else "\n  (none)" end)
    + "
- **Customer-managed policies** (recreate in target account from customer-policies/<file>, then attach by ARN):"
    + (if (.customer_managed_policy_arns | length) > 0 then "\n" + ([.customer_managed_policy_arns[]] | map("  - " + . + " → document: customer-policies/" + (split("/") | last) + ".json") | join("\n")) else "\n  (none)" end)
    + "
- **Inline policy**: " + (if (.inline_policies | length) > 0 then "Yes – copy from permission_sets_to_create.json (key: inline_policies)" else "None" end)
    + "
"
  ' "$PERM_SETS_FILE" 2>/dev/null

  echo "---"
  echo ""
  echo "## 2. Custom (customer-managed) policies to recreate"
  echo ""
  echo "These policies are **not** AWS-managed; create them in the destination account(s) and attach to the permission sets above. Policy documents are stored in \`customer-policies/\` for reference."
  echo ""
  echo "| Policy name | ARN | Document file |"
  echo "|-------------|-----|---------------|"
  jq -r '.[] | "| " + .policy_name + " | " + .arn + " | " + .file + " |"' "$CUSTOMER_POLICIES_DIR/manifest.json" 2>/dev/null || echo "| (none) | | |"
  echo ""
  echo "To recreate: create an IAM policy in the target account using the JSON in \`customer-policies/<file>\`, then use the new policy ARN when creating the permission set."
  echo ""
  echo "---"
  echo ""
  echo "## 3. Groups (you create these manually)"
  echo ""
  echo "In the destination Identity Center (identity store), create groups that match your intended access (e.g. by role or team). Then:"
  echo "- Assign each **group** to the **permission set(s)** and **accounts** that group should have access to."
  echo "- Copy or sync **users** into those groups (manually or via your IdP)."
  echo ""
  echo "Groups do not store policies; they define *who* gets which permission set in which account."
  echo ""
  echo "---"
  echo ""
  echo "## 4. File reference"
  echo ""
  echo "| File | Purpose |"
  echo "|------|---------|"
  echo "| \`MIGRATION_PACK.md\` | This human-readable guide |"
  echo "| \`permission_sets_to_create.json\` | Machine-readable permission set definitions (AWS + customer ARNs, inline policy docs) |"
  echo "| \`sso_roles_audit.json\` | Full audit of each SSO role and attached policies |"
  echo "| \`sso_roles_audit.csv\` | Same audit in table form |"
  echo "| \`customer-policies/manifest.json\` | ARN → filename for custom policies |"
  echo "| \`customer-policies/<name>.json\` | Policy document for each customer-managed policy (recreate in target account) |"
  echo ""

} > "$PACK_MD"

echo -e "${GREEN}  $PACK_MD${NC}"
echo ""
echo -e "${BLUE}Done. Open $PACK_MD for the human-readable migration guide.${NC}"
echo "  Customer policy documents (if exported): $CUSTOMER_POLICIES_DIR/"
echo ""
