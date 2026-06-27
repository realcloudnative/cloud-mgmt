#!/usr/bin/env bash
# deploy.sh — Deploys the automatic cost-overrun quarantine.
#
# IMPORTANT: Run in the Organizations MANAGEMENT (payer) account. It creates a
# detached quarantine SCP plus an AWS Budgets action that AUTOMATICALLY attaches
# that SCP to the dev account when ACTUAL spend crosses the threshold.
#
# Prereqs:
#   - SCPs enabled in AWS Organizations.
#   - aws CLI configured for the management account.
#
# Usage: ./deploy.sh <dev-account-id> <email>
#   dev-account-id  12-digit id of the dev account to monitor/quarantine.
#   email           Address notified when quarantine fires.
#
# Env overrides:
#   STACK_NAME            CloudFormation stack name (default: home-cost-quarantine)
#   REGION               API endpoint region (default: us-east-1)
#   QUARANTINE_THRESHOLD  ACTUAL monthly USD that triggers quarantine (default: 15)

set -euo pipefail

STACK_NAME="${STACK_NAME:-home-cost-quarantine}"
REGION="${REGION:-us-east-1}"
QUARANTINE_THRESHOLD="${QUARANTINE_THRESHOLD:-15}"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/cloudformation/cost-quarantine.yaml"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <dev-account-id> <email>" >&2
  exit 1
fi

DEV_ACCOUNT_ID="$1"
EMAIL="$2"

echo "Validating template..."
aws cloudformation validate-template --template-body "file://$TEMPLATE" \
  --region "$REGION" >/dev/null

echo "Deploying stack '$STACK_NAME' (dev=$DEV_ACCOUNT_ID, threshold=\$$QUARANTINE_THRESHOLD)..."
aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE" \
  --region "$REGION" \
  --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "DevAccountId=$DEV_ACCOUNT_ID" \
    "NotificationEmail=$EMAIL" \
    "QuarantineThreshold=$QUARANTINE_THRESHOLD"

echo ""
echo "Done. Outputs (note the ManualLiftCommand for recovery):"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$REGION" \
  --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' \
  --output table
