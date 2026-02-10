#!/bin/bash
#
# discover_and_upload.sh - Run IAM discovery in this account and optionally upload to S3
#
# For CloudShell: run this in each of the 6 accounts. Discovery runs in the current
# account; output is written to {account_id}/ and optionally uploaded to S3 for
# later aggregation (e.g. from management account).
#
# Usage:
#   ./discover_and_upload.sh
#   ./discover_and_upload.sh --s3-bucket BUCKET [--s3-prefix PREFIX] [--no-upload]
#   ./discover_and_upload.sh --discover-only    # no analyze, no reports, no upload
#
# Options:
#   --s3-bucket BUCKET   Upload discovery (and reports) to s3://BUCKET/PREFIX/{account_id}/
#   --s3-prefix PREFIX   Default: iam-migration/discovery
#   --discover-only      Only run discover_iam.sh; skip analyze, reports, upload
#   --skip-upload        Run discover + analyze + reports but do not upload (for local use)
#   --bundle             Create {account_id}-iam-discovery.tar.gz for easy download to central
#   --sso-only           Identity Center migration only: discover only SSO roles (AWSReservedSSO_*)
#                        and their policies. Skip IAM users, groups, and non-SSO roles. (Default for
#                        run_migration_workflow.sh --per-account.)
#
# Requires: discover_iam.sh or discover_sso_only.sh (when --sso-only), analyze_policies.sh, generate_reports.sh in same directory.
# For upload: AWS credentials with s3:PutObject on the bucket.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

S3_BUCKET=""
S3_PREFIX="iam-migration/discovery"
DISCOVER_ONLY=false
SKIP_UPLOAD=false
BUNDLE=false
SSO_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --sso-only)
      SSO_ONLY=true
      shift
      ;;
    --s3-bucket)
      S3_BUCKET="$2"
      shift 2
      ;;
    --s3-prefix)
      S3_PREFIX="$2"
      shift 2
      ;;
    --discover-only)
      DISCOVER_ONLY=true
      shift
      ;;
    --skip-upload)
      SKIP_UPLOAD=true
      shift
      ;;
    --bundle)
      BUNDLE=true
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}IAM Discovery (CloudShell-per-account)${NC}"
echo ""

# Resolve account ID (current credentials)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)
if [ -z "$ACCOUNT_ID" ]; then
  echo -e "${RED}Error: Could not get account ID. Configure AWS credentials (e.g. in CloudShell you are already in an account).${NC}"
  exit 1
fi

ACCOUNT_DIR="$ACCOUNT_ID"
mkdir -p "$ACCOUNT_DIR"/{data/raw,data/processed,output/reports}

echo -e "${GREEN}Account ID: $ACCOUNT_ID${NC}"
echo -e "${GREEN}Output dir: $ACCOUNT_DIR/${NC}"
echo ""

# 1. Discover (SSO-only for IdC migration, or full IAM)
if [ "$SSO_ONLY" = true ]; then
  echo -e "${YELLOW}Step 1: Discovering SSO roles only (Identity Center user access)...${NC}"
  OUTPUT_FILE="$ACCOUNT_DIR/data/raw/iam_discovery.json" \
    ./discover_sso_only.sh --output "$ACCOUNT_DIR/data/raw/iam_discovery.json"
else
  echo -e "${YELLOW}Step 1: Discovering IAM resources (full)...${NC}"
  OUTPUT_FILE="$ACCOUNT_DIR/data/raw/iam_discovery.json" \
    ./discover_iam.sh --output "$ACCOUNT_DIR/data/raw/iam_discovery.json"
fi

if [ ! -f "$ACCOUNT_DIR/data/raw/iam_discovery.json" ]; then
  echo -e "${RED}Discovery failed (no output file).${NC}"
  exit 1
fi

echo -e "${GREEN}Discovery saved to $ACCOUNT_DIR/data/raw/iam_discovery.json${NC}"
echo ""

if [ "$DISCOVER_ONLY" = true ]; then
  echo -e "${BLUE}Discover-only: skipping analyze, reports, and upload.${NC}"
  if [ -n "$S3_BUCKET" ] && [ "$SKIP_UPLOAD" != true ]; then
    echo -e "${YELLOW}Uploading discovery only to S3...${NC}"
    aws s3 cp "$ACCOUNT_DIR/data/raw/iam_discovery.json" \
      "s3://${S3_BUCKET}/${S3_PREFIX}/${ACCOUNT_ID}/iam_discovery.json"
    echo -e "${GREEN}Uploaded to s3://${S3_BUCKET}/${S3_PREFIX}/${ACCOUNT_ID}/iam_discovery.json${NC}"
  fi
  exit 0
fi

# 2. Analyze and 3. Reports (skip for SSO-only; we only need the discovery for migration pack)
if [ "$SSO_ONLY" != true ]; then
  echo -e "${YELLOW}Step 2: Analyzing policies...${NC}"
  ./analyze_policies.sh \
    --input "$ACCOUNT_DIR/data/raw/iam_discovery.json" \
    --output "$ACCOUNT_DIR/data/processed"

  echo -e "${YELLOW}Step 3: Generating reports...${NC}"
  INPUT_DIR="$ACCOUNT_DIR/data/processed" \
  OUTPUT_DIR="$ACCOUNT_DIR/output/reports" \
  DISCOVERY_FILE="$ACCOUNT_DIR/data/raw/iam_discovery.json" \
    ./generate_reports.sh

  echo ""
  echo -e "${GREEN}Reports in $ACCOUNT_DIR/output/reports/${NC}"
  ls -la "$ACCOUNT_DIR/output/reports/" 2>/dev/null || true
  echo ""
fi

# 4. Upload to S3 (optional)
if [ -n "$S3_BUCKET" ] && [ "$SKIP_UPLOAD" != true ]; then
  echo -e "${YELLOW}Step 4: Uploading to S3...${NC}"
  S3_BASE="s3://${S3_BUCKET}/${S3_PREFIX}/${ACCOUNT_ID}"
  aws s3 cp "$ACCOUNT_DIR/data/raw/iam_discovery.json" "${S3_BASE}/data/raw/iam_discovery.json"
  if [ "$SSO_ONLY" != true ] && [ -d "$ACCOUNT_DIR/data/processed" ]; then
    aws s3 cp "$ACCOUNT_DIR/data/processed/" "${S3_BASE}/data/processed/" --recursive
    aws s3 cp "$ACCOUNT_DIR/output/reports/" "${S3_BASE}/output/reports/" --recursive
  fi
  echo -e "${GREEN}Uploaded to ${S3_BASE}/${NC}"
else
  if [ -z "$S3_BUCKET" ]; then
    echo -e "${BLUE}No S3 bucket specified. To aggregate later, copy $ACCOUNT_DIR/ to a shared location or run aggregate_all_accounts.sh where all account dirs exist.${NC}"
  fi
fi

# 5. Bundle for transfer to central (optional)
if [ "$BUNDLE" = true ]; then
  echo -e "${YELLOW}Step 5: Creating bundle for central analysis...${NC}"
  BUNDLE_NAME="${ACCOUNT_ID}-iam-discovery.tar.gz"
  if tar czf "$BUNDLE_NAME" "$ACCOUNT_DIR" 2>/dev/null; then
    echo -e "${GREEN}Bundle: $BUNDLE_NAME ($(du -h "$BUNDLE_NAME" | cut -f1))${NC}"
    echo -e "${BLUE}Download this file from CloudShell and add it to your central folder.${NC}"
  else
    echo -e "${YELLOW}Could not create tarball (tar not found?). Copy the $ACCOUNT_DIR/ folder instead.${NC}"
  fi
  echo ""
fi

echo ""
echo -e "${GREEN}Done. Account $ACCOUNT_ID: discovery, analysis, and reports in $ACCOUNT_DIR/${NC}"
echo ""
echo -e "${BLUE}To analyze in a central terminal:${NC}"
echo "  1. Copy each account's folder ($ACCOUNT_DIR/) or bundle (--bundle) into one directory."
echo "  2. In that directory run: ./aggregate_all_accounts.sh"
echo "  3. Then: ./generate_shared_permission_sets.sh or ./generate_all_migration_artifacts.sh"
echo ""
