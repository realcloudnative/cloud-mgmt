#!/usr/bin/env bash
# deploy.sh — Deploys the management-operator IdC permission sets (CloudOps +
# IdentityAdmin) and assigns both ONLY to the management account.
#
# IMPORTANT:
#   - Run in the MANAGEMENT account.
#   - Run in the REGION where your Identity Center instance is homed
#     (SSO resources are region-bound). Set REGION to match.
#   - You must create the IdC user first; this only assigns permission sets to it.
#
# Find the inputs:
#   Instance ARN:  aws sso-admin list-instances
#   Principal id:  aws identitystore list-users --identity-store-id <store-id>
#
# Usage: ./deploy.sh <instance-arn> <mgmt-account-id> <principal-id>
#
# Env overrides:
#   STACK_NAME      CloudFormation stack name (default: home-idc-permission-sets)
#   REGION         IdC home region (default: us-east-1 — CHANGE to match your instance)
#   PRINCIPAL_TYPE  USER or GROUP (default: USER)

set -euo pipefail

STACK_NAME="${STACK_NAME:-home-idc-permission-sets}"
REGION="${REGION:-us-east-1}"
PRINCIPAL_TYPE="${PRINCIPAL_TYPE:-USER}"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/cloudformation/idc-permission-sets.yaml"

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <instance-arn> <mgmt-account-id> <principal-id>" >&2
  echo "  Instance ARN:  aws sso-admin list-instances" >&2
  echo "  Principal id:  aws identitystore list-users --identity-store-id <store-id>" >&2
  exit 1
fi

INSTANCE_ARN="$1"
MGMT_ACCOUNT_ID="$2"
PRINCIPAL_ID="$3"

echo "Validating template..."
aws cloudformation validate-template --template-body "file://$TEMPLATE" \
  --region "$REGION" >/dev/null

echo "Deploying stack '$STACK_NAME' in $REGION..."
aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE" \
  --region "$REGION" \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "IdentityCenterInstanceArn=$INSTANCE_ARN" \
    "ManagementAccountId=$MGMT_ACCOUNT_ID" \
    "PrincipalId=$PRINCIPAL_ID" \
    "PrincipalType=$PRINCIPAL_TYPE"

echo ""
echo "Done. Permission sets:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$REGION" \
  --query 'Stacks[0].Outputs[].{Key:OutputKey,Value:OutputValue}' \
  --output table
