#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

OVERRIDES_DIR="helmfile/overrides"
CHARTS_DIR="helmfile/charts"

echo -e "\n${BOLD}Scanning override files for AWS secret references...${NC}"
echo "  Overrides dir : $OVERRIDES_DIR"
echo -e "  Charts dir    : $CHARTS_DIR\n"

# Temporary files to store unique secrets/parameters
SM_TEMP=$(mktemp)
SSM_TEMP=$(mktemp)
trap "rm -f $SM_TEMP $SSM_TEMP" EXIT

# Pattern 1: Extract MANIFEST_* from environment variable mappings
# e.g., "ADMIN_CLIENT_SECRET: MANIFEST_ADMIN_CLIENT_SECRET"
grep -h "MANIFEST_[A-Z0-9_]*" "$OVERRIDES_DIR"/**/*.gotmpl "$CHARTS_DIR"/*/values.yaml 2>/dev/null | \
    grep -oE 'MANIFEST_[A-Z0-9_]+' | sort -u >> "$SM_TEMP" || true

# Pattern 1b: Extract values from any "*Secrets:" mapping blocks.
# This catches non-MANIFEST names too, e.g. "QA_TEST_MISSING_SECRET".
for file in $(find "$OVERRIDES_DIR" "$CHARTS_DIR" -name "*.gotmpl" -o -name "values.yaml" 2>/dev/null); do
    awk '
        function leading_spaces(s,    n) {
            n = 0
            while (substr(s, n + 1, 1) == " ") n++
            return n
        }

        {
            line = $0
            indent = leading_spaces(line)

            if (line ~ /^[[:space:]]*[A-Za-z0-9_]+Secrets:[[:space:]]*$/) {
                in_secrets = 1
                secrets_indent = indent
                next
            }

            if (in_secrets && line !~ /^[[:space:]]*$/ && indent <= secrets_indent) {
                in_secrets = 0
            }

            if (in_secrets && match(line, /^[[:space:]]*[A-Za-z0-9_]+:[[:space:]]*([A-Za-z0-9_\/.:-]+)[[:space:]]*$/, m)) {
                print m[1]
            }
        }
    ' "$file" >> "$SM_TEMP" 2>/dev/null || true
done

# Pattern 2: Extract objectName with objectType:secretsmanager
# Look for blocks with both objectName and objectType: secretsmanager
for file in $(find "$OVERRIDES_DIR" "$CHARTS_DIR" -name "*.gotmpl" -o -name "values.yaml" 2>/dev/null); do
    # Extract blocks that contain both objectName and objectType: secretsmanager
    awk '/objectName:/{getline; if(/objectType: secretsmanager/) print prev} {prev=$0}' "$file" >> "$SM_TEMP" 2>/dev/null || true
done

# Better approach: look for objectName lines that are followed by objectType: secretsmanager
for file in $(find "$OVERRIDES_DIR" "$CHARTS_DIR" -name "*.gotmpl" -o -name "values.yaml" 2>/dev/null); do
    grep -B1 "objectType: secretsmanager" "$file" 2>/dev/null | grep "objectName:" | \
        grep -oE '[A-Z0-9_]+\s*$' | tr -d ' ' | sort -u >> "$SM_TEMP" || true
done

# Pattern 3: Extract objectName with objectType:ssmparameter
for file in $(find "$OVERRIDES_DIR" "$CHARTS_DIR" -name "*.gotmpl" -o -name "values.yaml" 2>/dev/null); do
    grep -B1 "objectType: ssmparameter" "$file" 2>/dev/null | grep "objectName:" | \
        grep -oE '[a-zA-Z0-9_/]+\s*$' | tr -d ' ' | sort -u >> "$SSM_TEMP" || true
done

# Also check for notify_o11y_google_oauth_client_* pattern directly
grep -h "notify_o11y_google_oauth_client_" "$OVERRIDES_DIR"/**/*.gotmpl "$CHARTS_DIR"/*/values.yaml 2>/dev/null | \
    grep -oE 'notify_o11y_google_oauth_client_[a-z_]+' | sort -u >> "$SSM_TEMP" || true

# Get unique counts
SM_COUNT=$(sort -u "$SM_TEMP" | grep -c . || echo 0)
SSM_COUNT=$(sort -u "$SSM_TEMP" | grep -c . || echo 0)

echo "Found $SM_COUNT Secrets Manager secret(s) to verify."
echo -e "Found $SSM_COUNT SSM parameter(s) to verify.\n"

MISSING_TEMP=$(mktemp)
FAILED=0

# Check Secrets Manager secrets
if [[ $SM_COUNT -gt 0 ]]; then
    echo -e "${BOLD}Checking Secrets Manager secrets...${NC}"
    OK_COUNT=0
    
    while IFS= read -r secret; do
        [[ -z "$secret" ]] && continue
        if aws secretsmanager describe-secret --secret-id "$secret" --region "${AWS_DEFAULT_REGION:-ca-central-1}" >/dev/null 2>&1; then
            OK_COUNT=$((OK_COUNT + 1))
        else
            FAILED=1
            echo "[Secrets Manager] $secret" >> "$MISSING_TEMP"
        fi
    done < <(sort -u "$SM_TEMP" | grep .)
    
    if [[ $FAILED -eq 0 ]]; then
        echo -e "  ${GREEN}[OK]${NC} $OK_COUNT verified"
    else
        echo -e "  ${RED}[FAILED]${NC} See errors below"
    fi
fi

# Check SSM parameters
if [[ $SSM_COUNT -gt 0 ]]; then
    echo -e "${BOLD}Checking SSM parameters...${NC}"
    OK_COUNT=0
    
    while IFS= read -r param; do
        [[ -z "$param" ]] && continue
        if aws ssm get-parameter --name "$param" --region "${AWS_DEFAULT_REGION:-ca-central-1}" >/dev/null 2>&1; then
            OK_COUNT=$((OK_COUNT + 1))
        else
            FAILED=1
            echo "[SSM Parameter] $param" >> "$MISSING_TEMP"
        fi
    done < <(sort -u "$SSM_TEMP" | grep .)
    
    if [[ $FAILED -eq 0 ]]; then
        echo -e "  ${GREEN}[OK]${NC} $OK_COUNT verified"
    fi
fi

echo

if [[ $FAILED -eq 1 ]]; then
    echo -e "${RED}${BOLD}ERROR: The following secrets/parameters do NOT exist in AWS:${NC}\n"
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        echo -e "  ${RED}[MISSING]${NC} $item"
    done < "$MISSING_TEMP"
    echo
    echo -e "${YELLOW}This likely means the Terraform repo has not been released yet.${NC}"
    echo -e "${YELLOW}Please ensure the corresponding Terraform changes are applied before merging.${NC}"
    rm -f "$MISSING_TEMP"
    exit 1
else
    TOTAL=$((SM_COUNT + SSM_COUNT))
    echo -e "${GREEN}${BOLD}All $TOTAL secrets/parameters verified in AWS.${NC}"
    rm -f "$MISSING_TEMP"
    exit 0
fi
