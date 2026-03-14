#!/usr/bin/env bash
# deploy-lambda-stack.sh — Builds and deploys the Lambda durable function stack using AWS SAM.
#
# Usage: ./deploy-lambda-stack.sh [main-stack-name] [region]
#   main-stack-name  Name of the main conditional-resource stack (default: scheduled-switch-main)
#   region           AWS region (default: eu-central-1)

set -euo pipefail

MAIN_STACK="${1:-scheduled-switch-main}"
REGION="${2:-eu-central-1}"
LAMBDA_STACK="scheduled-switch-lambda"

echo "Building..."
sam build --template lambda-stack.yaml

echo "Deploying..."
sam deploy \
  --stack-name "$LAMBDA_STACK" \
  --region "$REGION" \
  --capabilities CAPABILITY_NAMED_IAM \
  --resolve-s3 \
  --parameter-overrides \
    MainStackName="$MAIN_STACK"

echo ""
echo "Deployed. To test manually:"
ALIAS_ARN=$(aws cloudformation describe-stacks \
  --stack-name "$LAMBDA_STACK" --region "$REGION" \
  --query 'Stacks[0].Outputs[?OutputKey==`FunctionArn`].OutputValue' \
  --output text)
echo "  aws lambda invoke --function-name \"$ALIAS_ARN\" \\"
echo "    --invocation-type Event --region $REGION --payload '{}' /dev/null"
