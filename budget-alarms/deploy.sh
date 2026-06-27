#!/usr/bin/env bash
# deploy.sh — Deploys home cost budgets with email alerts.
#
# IMPORTANT: Run this in the Organizations MANAGEMENT (payer) account. Only the
# payer account sees consolidated cost data and can filter budgets by linked
# account, so this one stack covers both org-wide and per-account spend.
#
# Usage: ./deploy.sh <email> <dev-account-id>
#   email            Address that receives budget alerts.
#   dev-account-id   12-digit id of your dev account.
#
# Env overrides:
#   STACK_NAME           CloudFormation stack name (default: home-budget-alarms)
#   REGION               Region for the API endpoint (default: us-east-1; Budgets is global)
#   OVERALL_LIMIT        Monthly USD limit for total org spend (default: 10)
#   DEV_LIMIT            Monthly USD limit for dev (default: 5)
#   ENABLE_PROD_BUDGET   "true" to also create a prod budget (default: false; 3rd budget leaves free tier)
#   PROD_ACCOUNT_ID      12-digit id of prod account (required if ENABLE_PROD_BUDGET=true)
#   PROD_LIMIT           Monthly USD limit for prod (default: 2)
#
# Examples:
#   ./deploy.sh you@example.com 111122223333
#   ENABLE_PROD_BUDGET=true PROD_ACCOUNT_ID=444455556666 ./deploy.sh you@example.com 111122223333

set -euo pipefail

STACK_NAME="${STACK_NAME:-home-budget-alarms}"
REGION="${REGION:-us-east-1}"
OVERALL_LIMIT="${OVERALL_LIMIT:-10}"
DEV_LIMIT="${DEV_LIMIT:-5}"
ENABLE_PROD_BUDGET="${ENABLE_PROD_BUDGET:-false}"
PROD_ACCOUNT_ID="${PROD_ACCOUNT_ID:-}"
PROD_LIMIT="${PROD_LIMIT:-2}"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/cloudformation/budget-alarms.yaml"

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <email> <dev-account-id>" >&2
  exit 1
fi

EMAIL="$1"
DEV_ACCOUNT_ID="$2"

PARAMS=(
  "NotificationEmail=$EMAIL"
  "DevAccountId=$DEV_ACCOUNT_ID"
  "OverallMonthlyLimit=$OVERALL_LIMIT"
  "DevMonthlyLimit=$DEV_LIMIT"
  "EnableProdBudget=$ENABLE_PROD_BUDGET"
  "ProdMonthlyLimit=$PROD_LIMIT"
)
if [[ "$ENABLE_PROD_BUDGET" == "true" ]]; then
  if [[ -z "$PROD_ACCOUNT_ID" ]]; then
    echo "ENABLE_PROD_BUDGET=true requires PROD_ACCOUNT_ID to be set." >&2
    exit 1
  fi
  PARAMS+=("ProdAccountId=$PROD_ACCOUNT_ID")
fi

echo "Validating template..."
aws cloudformation validate-template \
  --template-body "file://$TEMPLATE" \
  --region "$REGION" >/dev/null

echo "Deploying stack '$STACK_NAME'..."
aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE" \
  --region "$REGION" \
  --no-fail-on-empty-changeset \
  --parameter-overrides "${PARAMS[@]}"

echo ""
echo "Done. Budgets:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$REGION" \
  --query 'Stacks[0].Outputs[].{Budget:OutputKey,Name:OutputValue}' \
  --output table
