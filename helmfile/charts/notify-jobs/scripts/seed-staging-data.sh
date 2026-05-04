#!/bin/bash
# seed-staging-data.sh
#
# Seeds the staging database with non-PII, production-like data for performance
# testing, using the tests-simulate-prod-data script that ships with the
# notification-api image at /app/tests-simulate-prod-data.
#
# SQLALCHEMY_DATABASE_URI is injected at runtime from the notify-api Kubernetes
# Secret via the CronJob spec — it must not be hardcoded here.
#
# To tune volumes, adjust NUM_EMAILS_TOTAL / NUM_SMS_TOTAL.
# To change the target service, update the SERVICE_ID below.

set -euo pipefail

# tests-simulate-prod-data lives in the API image at this well-known path.
SCRIPT_DIR="/app/tests-simulate-prod-data"

echo "==> Installing / verifying Python dependencies..."
# requirements.txt may declare versions different from the main API — run pip
# so any delta is satisfied. Already-installed packages are a fast no-op.
cd "$SCRIPT_DIR"
poetry run pip install -q -r requirements.txt

echo "==> Running seeding script..."
# --live-only-service-id inserts rows only into the live notifications table
# (not the 14M-row notification_history) for the given service UUID.
# NUM_EMAILS_TOTAL / NUM_SMS_TOTAL cap the volume for a manageable daily run.
NUM_EMAILS_TOTAL=900000 \
NUM_SMS_TOTAL=600000 \
  poetry run python generate.py \
    --live-only-service-id "8dad0c16-6952-4424-be2a-d98b8bfc3c2d"
