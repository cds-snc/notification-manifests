#!/usr/bin/env python3
"""
Check that all AWS Secrets Manager secrets and SSM parameters referenced in
helmfile override files actually exist in AWS.

Exits with code 1 if any referenced secrets/parameters are missing.

Usage: python3 scripts/check-aws-secrets.py [overrides_dir] [charts_dir]

Note: This script only verifies the existence of secret/parameter identifiers
(their names), never accessing the actual secret values.
"""

import re
import sys
import glob
import json
import subprocess
from pathlib import Path

OVERRIDES_DIR = sys.argv[1] if len(sys.argv) > 1 else "helmfile/overrides"
CHARTS_DIR = sys.argv[2] if len(sys.argv) > 2 else "helmfile/charts"

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[1;33m"
BOLD = "\033[1m"
NC = "\033[0m"


def extract_secrets_from_file(filepath):
    """
    Extract AWS secret names and SSM parameter names from a gotmpl/yaml file.

    Three patterns are supported:
      1. secrets: map values  →  "  ENV_VAR: MANIFEST_SECRET_NAME"
         The VALUE (right-hand side) is the Secrets Manager secret ID.

      2. objectName + objectType: "secretsmanager"
         The objectName value is the Secrets Manager secret ID.

      3. objectName + objectType: "ssmparameter"
         The objectName value is the SSM Parameter Store parameter name.
    """
    sm_secrets = set()
    ssm_params = set()

    with open(filepath) as f:
        content = f.read()

    # Pattern 1: "  KEY: MANIFEST_VALUE" lines (secrets map)
    # Matches lines like:  ADMIN_CLIENT_SECRET: MANIFEST_ADMIN_CLIENT_SECRET
    for match in re.finditer(r"^\s+\w+:\s+(MANIFEST_\w+)\s*$", content, re.MULTILINE):
        sm_secrets.add(match.group(1))

    # Patterns 2 & 3: objectName followed closely by objectType
    # The objects are inside a YAML multi-line string (objects: |), so
    # objectName and objectType appear on consecutive indented lines.
    for match in re.finditer(
        r"objectName:\s+(\S+)\s*\n\s+objectType:\s+\"(secretsmanager|ssmparameter)\"",
        content,
    ):
        name = match.group(1)
        obj_type = match.group(2)
        if obj_type == "secretsmanager":
            sm_secrets.add(name)
        elif obj_type == "ssmparameter":
            ssm_params.add(name)

    return sm_secrets, ssm_params


def collect_all_references():
    """Collect all secret/parameter references from overrides and chart values."""
    sm_names = set()
    ssm_names = set()

    patterns = [
        f"{OVERRIDES_DIR}/**/*.gotmpl",
        f"{CHARTS_DIR}/**/values.yaml",
    ]

    for pattern in patterns:
        for filepath in sorted(glob.glob(pattern, recursive=True)):
            sm, ssm = extract_secrets_from_file(filepath)
            sm_names.update(sm)
            ssm_names.update(ssm)

    return sm_names, ssm_names


def check_secret_exists(secret_name):
    """Returns True if the Secrets Manager secret exists, False otherwise."""
    result = subprocess.run(
        ["aws", "secretsmanager", "describe-secret", "--secret-id", secret_name],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def check_ssm_parameter_exists(param_name):
    """Returns True if the SSM parameter exists, False otherwise."""
    result = subprocess.run(
        ["aws", "ssm", "get-parameter", "--name", param_name],
        capture_output=True,
        text=True,
    )
    return result.returncode == 0


def main():
    print(f"\n{BOLD}Scanning override files for AWS secret references...{NC}")
    print(f"  Overrides dir : {OVERRIDES_DIR}")
    print(f"  Charts dir    : {CHARTS_DIR}\n")

    sm_names, ssm_names = collect_all_references()

    print(f"Found {len(sm_names)} Secrets Manager secret(s) to verify.")
    print(f"Found {len(ssm_names)} SSM parameter(s) to verify.\n")

    error_found = False

    if sm_names:
        print(f"{BOLD}Checking Secrets Manager secrets...{NC}")
        ok_count = 0
        fail_count = 0
        for secret_id in sorted(sm_names):
            if check_secret_exists(secret_id):
                ok_count += 1
            else:
                fail_count += 1
                if fail_count == 1:
                    print(f"\n{RED}{BOLD}ERROR: The following secrets/parameters do NOT exist in AWS:{NC}\n")
                    error_found = True
                print(f"  {RED}[Secrets Manager]{NC} {secret_id}")
        
        if fail_count == 0:
            print(f"  {GREEN}[OK]{NC} {ok_count} verified")
        else:
            print(f"  {RED}[FAILED]{NC} {fail_count} of {len(sm_names)} secrets")

    if ssm_names:
        print(f"{BOLD}Checking SSM parameters...{NC}")
        ok_count = 0
        fail_count = 0
        for param_id in sorted(ssm_names):
            if check_ssm_parameter_exists(param_id):
                ok_count += 1
            else:
                fail_count += 1
                if fail_count == 1:
                    print(f"\n{RED}{BOLD}ERROR: The following secrets/parameters do NOT exist in AWS:{NC}\n")
                    error_found = True
                print(f"  {RED}[SSM Parameter]  {NC} {param_id}")
        
        if fail_count == 0:
            print(f"  {GREEN}[OK]{NC} {ok_count} verified")
        else:
            print(f"  {RED}[FAILED]{NC} {fail_count} of {len(ssm_names)} parameters")

    print()

    if error_found:
        print(
            f"{YELLOW}This likely means the Terraform repo has not been released yet.{NC}"
        )
        print(
            f"{YELLOW}Please ensure the corresponding Terraform changes are applied before merging.{NC}"
        )
        sys.exit(1)
    else:
        total = len(sm_names) + len(ssm_names)
        print(f"{GREEN}{BOLD}All {total} secrets/parameters verified in AWS.{NC}")
        sys.exit(0)


if __name__ == "__main__":
    main()
