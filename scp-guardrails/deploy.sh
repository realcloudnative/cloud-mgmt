#!/usr/bin/env bash
# deploy.sh — Deploys the home SCP guardrails to your AWS Organization.
#
# IMPORTANT: Run this with credentials for the Organizations MANAGEMENT account
# (or a delegated SCP administrator). The management account is never affected
# by SCPs — it is your escape hatch if a policy is too tight.
#
# Prereqs:
#   - Service control policies are enabled in AWS Organizations
#     (Organizations console > Policies > Service control policies > Enable).
#   - The default FullAWSAccess SCP stays attached to the target(s).
#   - aws CLI configured for the management account.
#
# Usage: ./deploy.sh <target-id> [target-id ...]
#   target-id   Root id (r-xxxx) or OU id (ou-xxxx-xxxxxxxx) to attach the SCPs to.
#               Pass several to attach all policies to all targets.
#
# Env overrides:
#   STACK_NAME  CloudFormation stack name (default: home-scp-guardrails)
#   REGION      Region for the CFN/Organizations endpoint (default: us-east-1)
#
# Examples:
#   ./deploy.sh r-abcd                 # attach to the org root
#   ./deploy.sh ou-abcd-11112222       # attach to a single OU
#   ./deploy.sh ou-abcd-11112222 ou-abcd-33334444

set -euo pipefail

STACK_NAME="${STACK_NAME:-home-scp-guardrails}"
REGION="${REGION:-us-east-1}"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/cloudformation/scp-guardrails.yaml"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <target-id> [target-id ...]" >&2
  echo "  target-id: root (r-xxxx) or OU (ou-xxxx-xxxxxxxx) to attach the SCPs to." >&2
  exit 1
fi

# Join args into a comma-separated list for the CommaDelimitedList parameter.
TARGET_IDS="$(IFS=,; echo "$*")"

echo "Validating template..."
aws cloudformation validate-template \
  --template-body "file://$TEMPLATE" \
  --region "$REGION" >/dev/null

echo "Deploying stack '$STACK_NAME' (targets: $TARGET_IDS)..."
aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file "$TEMPLATE" \
  --region "$REGION" \
  --no-fail-on-empty-changeset \
  --parameter-overrides "TargetIds=$TARGET_IDS"

echo ""
echo "Done. Attached SCPs:"
aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" --region "$REGION" \
  --query 'Stacks[0].Outputs[].{Policy:OutputKey,Id:OutputValue}' \
  --output table
