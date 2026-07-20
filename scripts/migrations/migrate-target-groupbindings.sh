#!/bin/bash
set -euo pipefail

ENVIRONMENT="${1:?Usage: $0 <environment> [--revert]}"
MODE="${2:-}"

[[ "${ENVIRONMENT}" == "production" ]] && export PROD_LOCAL=true
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_REPO="${HOME}/projects/notification-terraform"
HELMFILE_DIR="${SCRIPT_DIR}/../../helmfile"
TERRAFORM_EKS_DIR="${TERRAFORM_REPO}/env/${ENVIRONMENT}/eks"

###############################################################################
# Shared helper: helmfile sync (used by both main flow and revert)
###############################################################################
run_helmfile_sync() {
  cd "${HELMFILE_DIR}"
  set +u
  source getContext.sh
  set -u
  kubectl delete targetgroupbindings $(kubectl get targetgroupbindings -n notification-canada-ca --no-headers | awk '{print $1}') -n notification-canada-ca || true
  helmfile -e "${ENVIRONMENT}" -l category=deliverable sync
}

###############################################################################
# Revert mode
###############################################################################
if [[ "${MODE}" == "--revert" ]]; then
  echo "==> [Revert Step 1] Checking out admin-tt-revert-step-1 and running terragrunt apply"
  cd "${TERRAFORM_REPO}"
  git checkout admin-tt-revert-step-1
  cd "${TERRAFORM_EKS_DIR}"
  terragrunt apply -auto-approve

  echo "==> [Revert Step 2] Running helmfile operations"
  run_helmfile_sync

  echo "==> [Revert Step 3] Checking out admin-tt-revert-step-2 and running terragrunt apply"
  cd "${TERRAFORM_REPO}"
  git checkout admin-tt-revert-step-2
  cd "${TERRAFORM_EKS_DIR}"
  terragrunt apply -auto-approve

  echo "==> Revert complete"
  exit 0
fi

###############################################################################
# Step 1: admin-tt-step-1 — terragrunt apply (auto-approve)
###############################################################################
echo "==> [Step 1] Checking out admin-tt-step-1 and running terragrunt apply"
cd "${TERRAFORM_REPO}"
git checkout admin-tt-step-1
cd "${TERRAFORM_EKS_DIR}"
terragrunt apply -auto-approve

###############################################################################
# Step 2: admin-tt-step-3 — start terragrunt apply and run helmfile in parallel
#
# The write end of the named pipe is pre-opened on fd 3 so that terragrunt's
# background process can open the read end immediately (without blocking on the
# FIFO open call). Terragrunt then plans in parallel with the helmfile sync.
# Once helmfile finishes we write "yes" via fd 3 to confirm the apply.
###############################################################################
echo "==> [Step 2] Checking out admin-tt-step-3 and starting terragrunt apply"
cd "${TERRAFORM_REPO}"
git checkout admin-tt-step-3
cd "${TERRAFORM_EKS_DIR}"

PIPE="$(mktemp -u /tmp/tg_pipe_XXXXXX)"
mkfifo "${PIPE}"
trap 'exec 3>&- 2>/dev/null; rm -f "${PIPE}"' EXIT

# Start terragrunt in the background first — the child process will block trying
# to open the FIFO for reading, which allows the parent's exec 3> below to
# complete without deadlocking (both opens unblock each other).
terragrunt apply < "${PIPE}" &
TG_PID=$!

# Now open the write end — the child is already waiting on the read end so
# this returns immediately and terragrunt starts planning right away.
exec 3>"${PIPE}"

echo "==> [Step 2] Running helmfile operations in parallel with terragrunt plan"
run_helmfile_sync

echo "==> [Step 2] Helmfile sync complete — sending 'yes' to terragrunt apply"
echo "yes" >&3
exec 3>&-

wait "${TG_PID}"

###############################################################################
# Step 3: Wait 60 seconds
###############################################################################
echo "==> [Step 3] Waiting 60 seconds before next apply"
sleep 60

###############################################################################
# Step 4: admin-tt-step-4 — terragrunt apply (auto-approve)
###############################################################################
echo "==> [Step 4] Checking out admin-tt-step-4 and running terragrunt apply"
cd "${TERRAFORM_REPO}"
git checkout admin-tt-step-4
cd "${TERRAFORM_EKS_DIR}"
terragrunt apply -auto-approve

echo "==> Migration complete"
