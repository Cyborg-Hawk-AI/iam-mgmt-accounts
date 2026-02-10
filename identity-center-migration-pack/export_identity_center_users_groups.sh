#!/bin/bash
#
# export_identity_center_users_groups.sh - Export Identity Store users and groups (READ-ONLY)
#
# Scope: Identity Center (SSO) only. These are the IdC users/groups that get permission sets
# in member accounts (the reserved SSO roles). Standard IAM users in accounts are NOT in scope.
# Run in the MANAGEMENT ACCOUNT only. Uses list APIs only; no create/update/delete.
#
# Produces: identity_center/users.json + users.csv, groups.json + groups.csv,
#           group_memberships.json + group_memberships.csv
#
# Usage: ./export_identity_center_users_groups.sh [--output-dir DIR]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_DIR="${OUTPUT_DIR:-identity_center}"

while [[ $# -gt 0 ]]; do
  case $1 in
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

CONTEXT="$OUTPUT_DIR/context.json"
if [ ! -f "$CONTEXT" ]; then
  echo "Error: $CONTEXT not found. Run ./export_identity_center_context.sh first."
  exit 1
fi

IDENTITY_STORE_ID=$(jq -r '.IdentityStoreId' "$CONTEXT")
echo "Exporting users and groups from identity store (management account, read-only)..."
echo "  IdentityStoreId: $IDENTITY_STORE_ID"
echo ""

# List users (paginated), then normalize to UserId, UserName, DisplayName, PrimaryEmail
USERS_TMP="$OUTPUT_DIR/users_tmp.json"
echo "[]" > "$USERS_TMP"
NEXT_TOKEN=""
while true; do
  if [ -n "$NEXT_TOKEN" ]; then
    PAGE=$(aws identitystore list-users --identity-store-id "$IDENTITY_STORE_ID" --starting-token "$NEXT_TOKEN" --output json 2>/dev/null)
  else
    PAGE=$(aws identitystore list-users --identity-store-id "$IDENTITY_STORE_ID" --output json 2>/dev/null)
  fi
  [ -z "$PAGE" ] && break
  echo "$PAGE" | jq -r '.Users[]?' 2>/dev/null | while read -r u; do
    [ -z "$u" ] && continue
    echo "$u" | jq -c '{UserId, UserName, DisplayName, PrimaryEmail: ([.Emails[]? | select(.Primary == true) | .Value] | first // (.[0]?.Value // "") | tostring)}' 2>/dev/null >> "$USERS_TMP"
  done
  NEXT_TOKEN=$(echo "$PAGE" | jq -r '.NextToken // empty')
  [ -z "$NEXT_TOKEN" ] && break
done
# Build array from one-json-per-line
USERS=$(jq -n '[inputs] | map(select(.UserId != null))' "$USERS_TMP" 2>/dev/null || echo "[]")
# If empty, try single call (no pagination)
if [ "$USERS" = "[]" ] || [ "$USERS" = "null" ]; then
  USERS=$(aws identitystore list-users --identity-store-id "$IDENTITY_STORE_ID" --output json 2>/dev/null | jq '[.Users[]? | {UserId, UserName, DisplayName, PrimaryEmail: ([.Emails[]? | select(.Primary == true) | .Value] | first // ([.Emails[0]?.Value] | first) // "")}]' 2>/dev/null || echo "[]")
fi
rm -f "$USERS_TMP"
echo "$USERS" > "$OUTPUT_DIR/users.json"
echo "  Users: $(echo "$USERS" | jq -r 'length')"
echo "  JSON: $OUTPUT_DIR/users.json"
echo "UserId,UserName,DisplayName,PrimaryEmail" > "$OUTPUT_DIR/users.csv"
echo "$USERS" | jq -r '.[] | [.UserId, .UserName, .DisplayName, .PrimaryEmail] | @csv' >> "$OUTPUT_DIR/users.csv"
echo "  CSV: $OUTPUT_DIR/users.csv"
echo ""

# List groups (paginated)
GROUPS_TMP="$OUTPUT_DIR/groups_tmp.json"
echo "[]" > "$GROUPS_TMP"
NEXT_TOKEN=""
while true; do
  if [ -n "$NEXT_TOKEN" ]; then
    PAGE=$(aws identitystore list-groups --identity-store-id "$IDENTITY_STORE_ID" --starting-token "$NEXT_TOKEN" --output json 2>/dev/null)
  else
    PAGE=$(aws identitystore list-groups --identity-store-id "$IDENTITY_STORE_ID" --output json 2>/dev/null)
  fi
  [ -z "$PAGE" ] && break
  GROUPS=$(echo "$PAGE" | jq '[.Groups[]? | {GroupId, DisplayName, Description}]' 2>/dev/null)
  CURRENT=$(cat "$GROUPS_TMP")
  echo "$CURRENT" | jq --argjson new "$GROUPS" '. + $new' > "$GROUPS_TMP"
  NEXT_TOKEN=$(echo "$PAGE" | jq -r '.NextToken // empty')
  [ -z "$NEXT_TOKEN" ] && break
done
GROUPS=$(cat "$GROUPS_TMP")
rm -f "$GROUPS_TMP"
if [ "$GROUPS" = "[]" ] || [ -z "$GROUPS" ]; then
  GROUPS=$(aws identitystore list-groups --identity-store-id "$IDENTITY_STORE_ID" --output json 2>/dev/null | jq '[.Groups[]? | {GroupId, DisplayName, Description}]' 2>/dev/null || echo "[]")
fi
echo "$GROUPS" > "$OUTPUT_DIR/groups.json"
echo "  Groups: $(echo "$GROUPS" | jq -r 'length')"
echo "  JSON: $OUTPUT_DIR/groups.json"
echo "GroupId,DisplayName,Description" > "$OUTPUT_DIR/groups.csv"
echo "$GROUPS" | jq -r '.[] | [.GroupId, .DisplayName, (.Description // "")] | @csv' >> "$OUTPUT_DIR/groups.csv"
echo "  CSV: $OUTPUT_DIR/groups.csv"
echo ""

# Group memberships
MEMBERSHIPS="[]"
for GROUP_ID in $(echo "$GROUPS" | jq -r '.[].GroupId'); do
  [ -z "$GROUP_ID" ] && continue
  PAGE=$(aws identitystore list-group-memberships --identity-store-id "$IDENTITY_STORE_ID" --group-id "$GROUP_ID" --output json 2>/dev/null || echo '{"GroupMemberships":[]}')
  echo "$PAGE" | jq -r '.GroupMemberships[]? | select(.MemberId.UserId != null) | [.MemberId.UserId] | @tsv' 2>/dev/null | while read -r uid; do
    [ -z "$uid" ] && continue
    MEMBERSHIPS=$(echo "$MEMBERSHIPS" | jq --arg gid "$GROUP_ID" --arg uid "$uid" '. + [{"GroupId": $gid, "UserId": $uid}]')
  done
done
# Build memberships from temp file (subshell issue)
MM_TMP="$OUTPUT_DIR/mm_tmp.json"
echo "[]" > "$MM_TMP"
for GROUP_ID in $(echo "$GROUPS" | jq -r '.[].GroupId'); do
  [ -z "$GROUP_ID" ] && continue
  MEMBER_TOKEN=""
  while true; do
    if [ -n "$MEMBER_TOKEN" ]; then
      PAGE=$(aws identitystore list-group-memberships --identity-store-id "$IDENTITY_STORE_ID" --group-id "$GROUP_ID" --starting-token "$MEMBER_TOKEN" --output json 2>/dev/null || echo '{"GroupMemberships":[]}')
    else
      PAGE=$(aws identitystore list-group-memberships --identity-store-id "$IDENTITY_STORE_ID" --group-id "$GROUP_ID" --output json 2>/dev/null || echo '{"GroupMemberships":[]}')
    fi
    for ROW in $(echo "$PAGE" | jq -c '.GroupMemberships[]? | select(.MemberId.UserId != null) | {GroupId: "'"$GROUP_ID"'", UserId: .MemberId.UserId}' 2>/dev/null); do
      CURRENT=$(cat "$MM_TMP")
      echo "$CURRENT" | jq --argjson row "$ROW" '. + [$row]' > "$MM_TMP"
    done
    MEMBER_TOKEN=$(echo "$PAGE" | jq -r '.NextToken // empty')
    [ -z "$MEMBER_TOKEN" ] && break
  done
done
MEMBERSHIPS=$(cat "$MM_TMP")
rm -f "$MM_TMP"
echo "$MEMBERSHIPS" > "$OUTPUT_DIR/group_memberships.json"
echo "  Group memberships: $(echo "$MEMBERSHIPS" | jq -r 'length')"
echo "  JSON: $OUTPUT_DIR/group_memberships.json"
echo "GroupId,UserId" > "$OUTPUT_DIR/group_memberships.csv"
echo "$MEMBERSHIPS" | jq -r '.[] | [.GroupId, .UserId] | @csv' >> "$OUTPUT_DIR/group_memberships.csv"
echo "  CSV: $OUTPUT_DIR/group_memberships.csv"
echo ""

echo "Done. All outputs in JSON and CSV. Supply identity_center/*.json and *.csv for deployment."
echo ""
