#!/usr/bin/env bash
# deploy-resource-stack.sh — Creates the main conditional-resource stack (stack.yaml).
# Run this once per environment. The Lambda stack (deploy-lambda-stack.sh) controls it after that.
#
# Usage: ./deploy-resource-stack.sh [stack-name] [region]
#   stack-name  Name for the CloudFormation stack (default: scheduled-switch-main)
#   region      AWS region (default: eu-central-1)

set -euo pipefail

STACK_NAME="${1:-scheduled-switch-main}"
REGION="${2:-eu-central-1}"

echo "Creating stack '$STACK_NAME' in region '$REGION'..."

aws cloudformation create-stack \
  --stack-name "$STACK_NAME" \
  --template-body file://stack.yaml \
  --parameters ParameterKey=SwitchState,ParameterValue=SwitchedOff \
  --region "$REGION"

echo "Waiting for stack creation to complete..."

aws cloudformation wait stack-create-complete \
  --stack-name "$STACK_NAME" \
  --region "$REGION"

echo ""
echo "Stack '$STACK_NAME' created successfully."
echo "Next: run ./deploy-lambda-stack.sh to deploy the scheduler."
