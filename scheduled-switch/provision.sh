#!/usr/bin/env bash
# provision.sh — Creates the main conditional-resource stack (stack.yaml)
#
# NOTE: Lambda durable functions are available in eu-central-1 (Ohio) and eu-central-1 (Frankfurt).
#       The default region is hardcoded to eu-central-1 (Frankfurt).
#
# Usage: ./provision.sh [stack-name] [region]
#   stack-name  Name for the CloudFormation stack (default: scheduled-switch-main)
#   region      AWS region (default: eu-central-1)

set -euo pipefail

STACK_NAME="${1:-scheduled-switch-main}"
REGION="${2:-eu-central-1}"

echo "Provisioning stack '$STACK_NAME' in region '$REGION'..."

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
echo ""
echo "Next steps:"
echo "  1. Build the Lambda deployment package:"
echo "       cd lambda && uv sync  # generates uv.lock if not present"
echo "       cd .. && ./build.sh"
echo ""
echo "  2. Upload function.zip to S3:"
echo "       aws s3 cp function.zip s3://<your-bucket>/scheduled-switch/function.zip"
echo ""
echo "  3. Deploy the Lambda stack:"
echo "       aws cloudformation deploy \\"
echo "         --template-file lambda-stack.yaml \\"
echo "         --stack-name scheduled-switch-lambda \\"
echo "         --capabilities CAPABILITY_NAMED_IAM \\"
echo "         --region $REGION \\"
echo "         --parameter-overrides \\"
echo "           MainStackName=$STACK_NAME \\"
echo "           DeploymentBucket=<your-bucket> \\"
echo "           DeploymentKey=scheduled-switch/function.zip"
echo ""
echo "  4. Test manually:"
echo "       ALIAS_ARN=\$(aws cloudformation describe-stacks \\"
echo "         --stack-name scheduled-switch-lambda --region $REGION \\"
echo "         --query 'Stacks[0].Outputs[?OutputKey==\`FunctionArn\`].OutputValue' \\"
echo "         --output text)"
echo "       aws lambda invoke --function-name \"\$ALIAS_ARN\" \\"
echo "         --region $REGION --payload '{}' response.json"
