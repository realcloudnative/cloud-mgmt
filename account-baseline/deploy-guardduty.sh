#!/usr/bin/env bash
# deploy-guardduty.sh — OPTIONAL. Enables GuardDuty (foundational-only) via
# CloudFormation in the region(s) you choose, for the current account.
#
# GuardDuty is OFF by default: this script does nothing unless you explicitly
# set REGIONS. For a home setup, enable only the 1-2 regions you actually use —
# not all five. GuardDuty is regional, so this deploys one stack per region.
#
# Env overrides:
#   STACK_NAME   CloudFormation stack name (default: home-guardduty)
#   REGIONS      Space-separated regions to enable (REQUIRED; no default)
#
# Usage:
#   REGIONS="eu-central-1" ./deploy-guardduty.sh
#   REGIONS="eu-central-1 us-east-1" AWS_PROFILE=dev ./deploy-guardduty.sh
#
# Note: if GuardDuty is already enabled in a region, CreateDetector fails with
# "detector already exists" — that region is already covered, so it's safe to
# skip; this script continues to the next region.

set -euo pipefail

STACK_NAME="${STACK_NAME:-home-guardduty}"
REGIONS="${REGIONS:-}"
TEMPLATE="$(cd "$(dirname "$0")" && pwd)/cloudformation/guardduty-detector.yaml"

if [[ -z "$REGIONS" ]]; then
  echo "GuardDuty is optional and OFF by default — nothing to do." >&2
  echo "To enable it, set REGIONS to the 1-2 regions you actually use:" >&2
  echo "  REGIONS=\"eu-central-1\" $0" >&2
  echo "(Enabling all five regions is discouraged for a home setup.)" >&2
  exit 1
fi

echo "Validating template..."
aws cloudformation validate-template --template-body "file://$TEMPLATE" \
  --region us-east-1 >/dev/null

for r in $REGIONS; do
  echo "Deploying GuardDuty in $r..."
  if ! aws cloudformation deploy \
        --stack-name "$STACK_NAME" \
        --template-file "$TEMPLATE" \
        --region "$r" \
        --no-fail-on-empty-changeset; then
    echo "  WARNING: deploy in $r failed (often: GuardDuty already enabled there). Continuing."
  fi
done

echo ""
echo "GuardDuty deployment pass complete."
