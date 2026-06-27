# account-baseline

Turns **on** the security settings that the SCPs in [`../scp-guardrails`](../scp-guardrails)
later *lock*. SCPs are Deny-Unless guardrails — they stop you *disabling* good
settings, but they can't *enable* them. This folder does the enabling.

## Why part CloudFormation, part script

Most of these are account/region-level toggles that AWS never exposed as
CloudFormation resources, so they have to be set via the CLI. CloudFormation is
used wherever a native resource exists.

| Setting | Scope | Mechanism | Why |
|---------|-------|-----------|-----|
| S3 account-level Block Public Access | per account (global) | CLI | no native CFN resource |
| EBS encryption by default | per region | CLI | no native CFN resource |
| IMDSv2 instance-metadata default | per region | CLI | no native CFN resource |
| GuardDuty detector *(optional, OFF by default)* | per region | **CloudFormation** (`AWS::GuardDuty::Detector`) | native resource exists |

GuardDuty is **foundational-only** (CloudTrail mgmt events + VPC flow logs +
DNS). Every usage-billed protection plan — S3 Protection, Malware Protection,
Runtime Monitoring, etc. — is explicitly disabled in the template, and the
deploy script does nothing unless you opt in with `REGIONS=`.

## Run order (important)

```
1. account-baseline  ──►  2. scp-guardrails
   (enable settings)        (lock them)
```

**Run `apply-account-baseline.sh` before attaching SCP policy 04**
(`home-guardrail-baseline-security`). That policy denies
`s3:PutAccountPublicAccessBlock`, so if the SCP is attached first you can no
longer turn account-level S3 Block Public Access on. The EBS and IMDSv2
settings are order-independent.

Run both steps in **each account** (dev, prod, and the management account —
SCPs don't touch management, but the settings are still good hygiene there).

## Usage

Per account, with that account's credentials/profile:

```bash
# 1) Always-on, free preventive settings (S3 BPA + EBS encryption + IMDSv2 defaults):
AWS_PROFILE=dev ./apply-account-baseline.sh

# Narrow the regions for the per-region settings (default: all 5 allowed regions):
REGIONS="us-east-1 eu-central-1" AWS_PROFILE=dev ./apply-account-baseline.sh

# 2) GuardDuty (OPTIONAL, off by default) — only runs if you set REGIONS,
#    and you should pick just the 1-2 regions you actually use:
REGIONS="eu-central-1" AWS_PROFILE=dev ./deploy-guardduty.sh
```

All three CLI settings are idempotent — re-running is safe.

## Notes

- **GuardDuty is optional and off by default.** It's foundational-only (no
  S3 Protection / Malware / Runtime Monitoring), so the main bill-shock vectors
  are disabled. Enable it only in the 1-2 regions you actually use. There's a
  30-day free trial per region; idle regions cost ~nothing.
- **GuardDuty already on:** if a region already has a detector,
  `deploy-guardduty.sh` warns and continues — that region is already covered.
- **S3 account BPA vs bucket BPA:** account-level overrides per-bucket settings,
  which is why the SCP only protects the account-level toggle. This script sets
  all four account-level settings to `true`.
- These actions are all inside the SCP service allowlist and allowed regions,
  so they keep working after the SCPs are attached — except
  `PutAccountPublicAccessBlock`, hence the run order above.

## Files

```
account-baseline/
├── README.md
├── apply-account-baseline.sh          # S3 BPA + EBS default encryption + IMDSv2 defaults (CLI)
├── deploy-guardduty.sh                # deploys the GuardDuty stack per region
└── cloudformation/
    └── guardduty-detector.yaml        # AWS::GuardDuty::Detector
```
