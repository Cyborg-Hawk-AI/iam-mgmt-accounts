#!/bin/bash
#
# validate_setup.sh - Validate that all scripts are ready to run
#
# Usage: ./validate_setup.sh

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}Validating CloudShell IAM Analysis Setup...${NC}"
echo ""

ERRORS=0

# Check required scripts exist
echo -e "${YELLOW}Checking scripts...${NC}"
REQUIRED_SCRIPTS=("discover_iam.sh" "analyze_policies.sh" "generate_reports.sh" "utils.sh")

for script in "${REQUIRED_SCRIPTS[@]}"; do
  if [ -f "$script" ]; then
    if [ -x "$script" ]; then
      echo -e "${GREEN}  ✓ $script (executable)${NC}"
    else
      echo -e "${YELLOW}  ⚠ $script (not executable - run: chmod +x $script)${NC}"
    fi
  else
    echo -e "${RED}  ✗ $script (missing)${NC}"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check AWS CLI
echo ""
echo -e "${YELLOW}Checking AWS CLI...${NC}"
if command -v aws &> /dev/null; then
  AWS_VERSION=$(aws --version 2>&1 | head -1)
  echo -e "${GREEN}  ✓ AWS CLI installed: $AWS_VERSION${NC}"
  
  # Test AWS access
  if aws sts get-caller-identity &> /dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    echo -e "${GREEN}  ✓ AWS access verified (Account: $ACCOUNT_ID)${NC}"
  else
    echo -e "${RED}  ✗ AWS access failed - check credentials${NC}"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo -e "${RED}  ✗ AWS CLI not found${NC}"
  ERRORS=$((ERRORS + 1))
fi

# Check required commands
echo ""
echo -e "${YELLOW}Checking required commands...${NC}"
REQUIRED_CMDS=("jq" "bc" "date")

for cmd in "${REQUIRED_CMDS[@]}"; do
  if command -v "$cmd" &> /dev/null; then
    echo -e "${GREEN}  ✓ $cmd${NC}"
  else
    echo -e "${RED}  ✗ $cmd (missing)${NC}"
    echo -e "${YELLOW}    Install with: sudo yum install $cmd (Amazon Linux)${NC}"
    echo -e "${YELLOW}    Or: sudo apt-get install $cmd (Ubuntu)${NC}"
    ERRORS=$((ERRORS + 1))
  fi
done

# Check IAM permissions
echo ""
echo -e "${YELLOW}Checking IAM permissions...${NC}"
if aws iam list-users --max-items 1 &> /dev/null; then
  echo -e "${GREEN}  ✓ iam:ListUsers${NC}"
else
  echo -e "${RED}  ✗ iam:ListUsers (missing permission)${NC}"
  ERRORS=$((ERRORS + 1))
fi

if aws iam list-roles --max-items 1 &> /dev/null; then
  echo -e "${GREEN}  ✓ iam:ListRoles${NC}"
else
  echo -e "${RED}  ✗ iam:ListRoles (missing permission)${NC}"
  ERRORS=$((ERRORS + 1))
fi

if aws iam list-groups --max-items 1 &> /dev/null; then
  echo -e "${GREEN}  ✓ iam:ListGroups${NC}"
else
  echo -e "${RED}  ✗ iam:ListGroups (missing permission)${NC}"
  ERRORS=$((ERRORS + 1))
fi

# Check/create directories
echo ""
echo -e "${YELLOW}Checking directories...${NC}"
REQUIRED_DIRS=("data/raw" "data/processed" "output/reports" "output/proposals")

for dir in "${REQUIRED_DIRS[@]}"; do
  if [ -d "$dir" ]; then
    echo -e "${GREEN}  ✓ $dir${NC}"
  else
    echo -e "${YELLOW}  ⚠ $dir (will be created automatically)${NC}"
    mkdir -p "$dir"
  fi
done

# Summary
echo ""
echo "================================"
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}✓ Setup validation passed!${NC}"
  echo ""
  echo "You're ready to run:"
  echo "  1. ./discover_iam.sh"
  echo "  2. ./analyze_policies.sh"
  echo "  3. ./generate_reports.sh"
  exit 0
else
  echo -e "${RED}✗ Setup validation failed with $ERRORS error(s)${NC}"
  echo ""
  echo "Please fix the errors above before proceeding."
  exit 1
fi

