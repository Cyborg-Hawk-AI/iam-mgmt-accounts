#!/bin/bash
#
# run_migration_workflow.sh - Single entry point for the full IAM migration workflow
#
# Usage:
#   In each account (Phase 1):
#     ./run_migration_workflow.sh --per-account
#   In central, after you have all account tarballs (Phase 2):
#     ./run_migration_workflow.sh --central
#
# Options:
#   --per-account   Run discovery in this account and create a bundle (tarball) to download.
#   --central       Unpack any *-iam-discovery.tar.gz, then aggregate → audit → migration pack.
#   --central-only  Same as --central but skip unpacking (account dirs already present).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
  echo ""
  echo -e "${BLUE}IAM Migration Workflow — single entry point${NC}"
  echo ""
  echo "  Phase 1 (in each of your AWS accounts, e.g. CloudShell):"
  echo "    ./run_migration_workflow.sh --per-account"
  echo "    → Discovers IAM, creates {account_id}-iam-discovery.tar.gz. Download it."
  echo ""
  echo "  Phase 2 (in one central place, with all tarballs in this directory):"
  echo "    ./run_migration_workflow.sh --central"
  echo "    → Unpacks tarballs, aggregates, audits SSO roles, generates migration pack."
  echo ""
  echo "  If account dirs are already unpacked:"
  echo "    ./run_migration_workflow.sh --central-only"
  echo ""
  echo "  After a successful run you get: audit/MIGRATION_PACK.md, audit/MIGRATION_STATUS.md,"
  echo "  audit/permission_sets_to_create.json, audit/customer-policies/*.json"
  echo ""
}

MODE=""
CENTRAL_SKIP_UNPACK=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --per-account)
      MODE="per-account"
      shift
      ;;
    --central)
      MODE="central"
      shift
      ;;
    --central-only)
      MODE="central"
      CENTRAL_SKIP_UNPACK=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $1${NC}"
      usage
      exit 1
      ;;
  esac
done

if [ -z "$MODE" ]; then
  echo -e "${RED}No mode specified. You must run with either --per-account or --central.${NC}"
  echo ""
  echo "  In each account (Phase 1):  ./run_migration_workflow.sh --per-account"
  echo "  In central (Phase 2):       ./run_migration_workflow.sh --central"
  echo ""
  usage
  exit 1
fi

# --- Phase 1: Per-account discovery and bundle ---
if [ "$MODE" = "per-account" ]; then
  echo -e "${BLUE}Phase 1: SSO-only discovery (Identity Center roles) + bundle${NC}"
  echo "  IAM users, service roles, and non-SSO roles are not collected."
  echo ""
  exec ./discover_and_upload.sh --bundle --sso-only
fi

# --- Phase 2: Central aggregate → audit → migration pack ---
if [ "$MODE" = "central" ]; then
  echo -e "${BLUE}Phase 2: Central aggregation and migration pack${NC}"
  echo ""

  if [ "$CENTRAL_SKIP_UNPACK" != true ]; then
    echo -e "${YELLOW}Unpacking account tarballs...${NC}"
    unpacked=0
    for f in *-iam-discovery.tar.gz; do
      [ -f "$f" ] || continue
      tar xzf "$f"
      unpacked=$((unpacked + 1))
      echo "  Unpacked: $f"
    done
    if [ "$unpacked" -eq 0 ]; then
      echo -e "${YELLOW}  No *-iam-discovery.tar.gz found. If account dirs are already here, use --central-only.${NC}"
    fi
    echo ""
  fi

  echo -e "${YELLOW}Aggregating discovery from all account dirs...${NC}"
  ./aggregate_all_accounts.sh
  echo ""

  AGGREGATED="aggregated/discovery/all_accounts.json"
  if [ ! -f "$AGGREGATED" ]; then
    echo -e "${RED}Error: $AGGREGATED not found. Run Phase 1 in each account and add tarballs, or unpack them here.${NC}"
    exit 1
  fi

  echo -e "${YELLOW}Auditing SSO roles...${NC}"
  ./audit_sso_roles.sh --aggregated "$AGGREGATED" --output-dir audit
  echo ""

  echo -e "${YELLOW}Generating migration pack...${NC}"
  ./generate_migration_pack.sh --audit-dir audit --aggregated "$AGGREGATED"
  echo ""

  echo -e "${YELLOW}Generating status report (for your boss)...${NC}"
  if [ -f "aggregated/analysis/summary.json" ]; then
    ./generate_boss_report.sh --audit-dir audit --summary aggregated/analysis/summary.json
  else
    ./generate_boss_report.sh --audit-dir audit
  fi
  echo ""

  echo -e "${GREEN}Workflow complete.${NC}"
  echo ""
  echo "  Open for your boss / team:"
  echo "    - audit/MIGRATION_PACK.md     (what to create in the new Identity Center)"
  echo "    - audit/MIGRATION_STATUS.md   (generated status — what’s left)"
  echo ""
  echo "  Machine-readable: audit/permission_sets_to_create.json, audit/customer-policies/"
  echo ""
  exit 0
fi

usage
exit 1
