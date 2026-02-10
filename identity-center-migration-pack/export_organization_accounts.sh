#!/bin/bash
#
# export_organization_accounts.sh - List AWS Organization accounts (READ-ONLY, optional)
#
# Scope: Identity Center migration — account list only. Run in the MANAGEMENT ACCOUNT.
# Produces identity_center/org_accounts.json and org_accounts.csv.
#
# Usage: ./export_organization_accounts.sh [--output-dir DIR]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_DIR="${OUTPUT_DIR:-identity_center}"
mkdir -p "$OUTPUT_DIR"

echo "Listing AWS Organization accounts (management account)..."
ACC_TMP="$OUTPUT_DIR/org_accounts_tmp.json"
echo "[]" > "$ACC_TMP"
NEXT_TOKEN=""
while true; do
  if [ -n "$NEXT_TOKEN" ]; then
    PAGE=$(aws organizations list-accounts --starting-token "$NEXT_TOKEN" --output json 2>/dev/null || echo '{"Accounts":[]}')
  else
    PAGE=$(aws organizations list-accounts --output json 2>/dev/null || echo '{"Accounts":[]}')
  fi
  CURRENT=$(cat "$ACC_TMP")
  NEW=$(echo "$PAGE" | jq '[.Accounts[]? | {Id, Name, Email, Status}]' 2>/dev/null || echo "[]")
  echo "$CURRENT" | jq --argjson new "$NEW" '. + $new' > "$ACC_TMP"
  NEXT_TOKEN=$(echo "$PAGE" | jq -r '.NextToken // empty')
  [ -z "$NEXT_TOKEN" ] && break
done
ACCOUNTS=$(cat "$ACC_TMP")
rm -f "$ACC_TMP"
if [ "$ACCOUNTS" = "[]" ] || [ -z "$ACCOUNTS" ]; then
  echo "  No accounts returned. Ensure you are in the management account with organizations:ListAccounts."
  echo "[]" > "$OUTPUT_DIR/org_accounts.json"
  exit 0
fi
echo "$ACCOUNTS" > "$OUTPUT_DIR/org_accounts.json"
echo "Id,Name,Email,Status" > "$OUTPUT_DIR/org_accounts.csv"
echo "$ACCOUNTS" | jq -r '.[] | [.Id, .Name, .Email, .Status] | @csv' >> "$OUTPUT_DIR/org_accounts.csv"
echo "  Accounts: $(echo "$ACCOUNTS" | jq -r 'length')"
echo "  JSON: $OUTPUT_DIR/org_accounts.json"
echo "  CSV: $OUTPUT_DIR/org_accounts.csv"
echo "  Use this to build accounts.txt (one Id per line for accounts you want to migrate)."
echo ""
