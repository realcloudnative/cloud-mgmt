#!/usr/bin/env bash
# apply-account-baseline.sh — Applies home baseline settings that have NO native
# CloudFormation resource. Run ONCE PER ACCOUNT, with that account's credentials.
#
# Applies:
#   1. S3 account-level Block Public Access  (global, per account)
#   2. EBS encryption by default             (per region)
#   3. IMDSv2 as the instance-metadata default (per region)
#
# !! RUN ORDER !!  Run this BEFORE attaching SCP policy 04
# (home-guardrail-baseline-security). That policy denies
# s3:PutAccountPublicAccessBlock, so if you attach it first you can no longer
# turn S3 Block Public Access on. Settings 2 and 3 are order-independent.
#
# Run it in every account you want protected — including the management account
# (SCPs don't touch it, but the settings are still good hygiene there).
#
# All three calls are idempotent; re-running is safe.
#
# Env overrides:
#   REGIONS   Space-separated regions for the per-region settings
#             (default: the 5 allowed home regions)
#
# Usage:
#   ./apply-account-baseline.sh                 # uses current credentials/profile
#   AWS_PROFILE=dev ./apply-account-baseline.sh
#   REGIONS="us-east-1 eu-central-1" AWS_PROFILE=prod ./apply-account-baseline.sh

set -euo pipefail

REGIONS="${REGIONS:-us-east-1 us-west-2 eu-central-1 eu-north-1 ap-southeast-1}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
echo "Applying home baseline to account: $ACCOUNT_ID"
echo "Regions for per-region settings: $REGIONS"
echo ""

echo "[1/3] S3 account-level Block Public Access (global)..."
aws s3control put-public-access-block \
  --account-id "$ACCOUNT_ID" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "      done."

for r in $REGIONS; do
  echo "[2/3] [$r] Enable EBS encryption by default..."
  aws ec2 enable-ebs-encryption-by-default --region "$r" >/dev/null

  echo "[3/3] [$r] Set IMDSv2 (http-tokens=required) as instance-metadata default..."
  aws ec2 modify-instance-metadata-defaults --region "$r" \
    --http-tokens required \
    --http-endpoint enabled >/dev/null
done

echo ""
echo "Baseline applied to $ACCOUNT_ID. You can now attach the SCPs (scp-guardrails)."
