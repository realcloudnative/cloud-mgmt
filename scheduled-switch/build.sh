#!/usr/bin/env bash
# build.sh — Packages and deploys the Lambda durable function stack.
#
# Uses `aws cloudformation package` to zip and upload the Lambda code automatically —
# no manual S3 management required.
#
# NOTE: Lambda durable functions are available in us-east-2 (Ohio) and eu-central-1 (Frankfurt).
#
# Usage: ./build.sh [main-stack-name] [region]
#   main-stack-name  Name of the main conditional-resource stack (default: scheduled-switch-main)
#   region           AWS region (default: eu-central-1)

set -euo pipefail

MAIN_STACK="${1:-scheduled-switch-main}"
REGION="${2:-eu-central-1}"
LAMBDA_STACK="scheduled-switch-lambda"
S3_BUCKET="demo-adriaan"
PACKAGED="lambda-stack-packaged.yaml"

echo "Packaging (uploading Lambda code to S3)..."
aws cloudformation package \
  --template-file lambda-stack.yaml \
  --s3-bucket "$S3_BUCKET" \
  --s3-prefix scheduled-switch \
  --output-template-file "$PACKAGED" \
  --region "$REGION"

echo "Deploying..."
aws cloudformation deploy \
  --template-file "$PACKAGED" \
  --stack-name "$LAMBDA_STACK" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION" \
  --parameter-overrides \
    MainStackName="$MAIN_STACK"

echo ""
echo "Deployed. To test manually:"
echo "  ALIAS_ARN=\$(aws cloudformation describe-stacks \\"
echo "    --stack-name $LAMBDA_STACK --region $REGION \\"
echo "    --query 'Stacks[0].Outputs[?OutputKey==\`FunctionArn\`].OutputValue' \\"
echo "    --output text)"
echo "  aws lambda invoke --function-name \"\$ALIAS_ARN\" \\"
echo "    --invocation-type Event --region $REGION --payload '{}' /dev/null"
