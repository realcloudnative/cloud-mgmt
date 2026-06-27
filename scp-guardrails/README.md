# scp-guardrails

Deny-Unless Service Control Policies (SCPs) for a home / small-time AWS
Organization, plus a CloudFormation template to roll them out.

Everything here uses the **Deny-Unless** pattern: start from `FullAWSAccess`
and *subtract* with `Deny` statements that are conditioned ("deny everything
**unless** …"). This is the recommended way to build guardrails, because new
services and actions are blocked by default until you explicitly allow them.

## What gets deployed

| # | SCP | What it does |
|---|-----|--------------|
| 01 | `region-lock` | Deny all actions outside the 5 allowed regions; global services exempt. |
| 02 | `service-allowlist` | Deny any service not on the home allowlist. |
| 03 | `ec2-instance-size` | Deny `ec2:RunInstances` for anything larger than `*.small`. |
| 04 | `baseline-security` *(optional)* | Require IMDSv2 (launch + modify); require encrypted EBS volumes; keep EBS default encryption; protect CloudTrail/GuardDuty; protect account-level S3 Block Public Access; block IAM user/access-key creation; block leaving the org. |
| 05 | `cost-control` *(optional)* | Block reserved/capacity commitments and Dedicated tenancy. |

Each SCP is defined **once**, embedded in
[`cloudformation/scp-guardrails.yaml`](./cloudformation/scp-guardrails.yaml),
which is also what deploys them. That template is the single source of truth —
there is no separate copy of the policy JSON to keep in sync.

## The May 2026 SCP quota increase

On **15 May 2026** AWS doubled the two headline SCP limits:

- Max SCPs attached per node (root / OU / account): **5 → 10**
- Max SCP document size: **5,120 → 10,240 characters**

That is why these are kept as **five separate, individually-detachable
policies** rather than being crammed into one. You can attach all of them to a
single OU or root and still have room for five more. The largest policy here
(the service allowlist) is comfortably under the new 10,240-character ceiling.

## Allowed regions

`us-east-1`, `us-west-2`, `eu-central-1`, `eu-north-1`, `ap-southeast-1`.

Region-less / global services are exempted in the region-lock SCP via
`NotAction` so they keep working: IAM, Organizations, Route 53 (+ Domains),
CloudFront, the billing family, Artifact, Health, Trusted Advisor, Support,
STS, and `aws-external-anthropic` (Claude Platform on AWS).

## Service allowlist — mapping and decisions

Your requested services map to these IAM prefixes. A few notes on choices made
during design (all confirmed with you):

- **Secrets Manager: removed.** Use SSM Parameter Store instead (covered by
  `ssm:*`). SecureString parameters still work because `kms:*` is allowed.
- **Glue: reduced to a Data Catalog subset** (not `glue:*`). Only the
  database/table/partition read + CRUD actions Athena needs for queries and
  CTAS/`INSERT INTO`. No crawlers, jobs, connections, or dev endpoints.
- **ECS / EC2 helpers added:** `elasticloadbalancing:*`, `autoscaling:*`,
  `application-autoscaling:*` — without these you cannot put a load balancer in
  front of ECS or scale services/instances.
- **Unavoidable "glue" prefixes kept:** `sts:*` (assume-role — SSO, CFN,
  Lambda, ECS all break without it), `tag:*`, `support:*`, `aws-portal:*`.
- **AWS Global View** is the EC2 console cross-region view; it is read-only
  `ec2:Describe*`, already covered by `ec2:*`. No separate prefix needed.

### EC2 instance size limit

Denies `ec2:RunInstances` unless the type matches `*.nano`, `*.micro`, or
`*.small`. Because the match is on the size suffix, it applies across all
families (e.g. `t3.micro`, `t4g.small`, `c7g.nano` are fine; `t3.medium` and up
are blocked).

> Note: this guards the launch action. Resizing a stopped instance via
> `ec2:ModifyInstanceAttribute` is not covered by this condition key; add a
> separate statement if you want to block that path too.

## Deploy

> Run from the **Organizations management account** (or a delegated SCP admin).
> SCPs must be enabled in Organizations first. The management account is never
> restricted by SCPs — that is your escape hatch.

```bash
# Attach all policies to the org root:
./deploy.sh r-abcd

# …or to a specific OU:
./deploy.sh ou-abcd-11112222

# Skip the optional policies:
STACK_NAME=home-scp-guardrails ./deploy.sh r-abcd   # then set params below
```

To toggle the optional policies, pass parameters to CloudFormation
(`EnableBaselineSecurity` / `EnableCostControl`, both default `true`):

```bash
aws cloudformation deploy \
  --stack-name home-scp-guardrails \
  --template-file cloudformation/scp-guardrails.yaml \
  --region us-east-1 \
  --parameter-overrides TargetIds=r-abcd EnableCostControl=false
```

Keep the default `FullAWSAccess` SCP attached to the same target(s) — these
Deny policies only subtract from it.

## Recommended additional Deny-Unless rules for a home setup

### Now included in `baseline-security` (04)

The following were added after review and ship in policy 04:

- **IMDSv2 on existing instances** — deny `ec2:ModifyInstanceMetadataOptions`
  that would re-enable IMDSv1 (`StringNotEqualsIfExists` so it only fires when a
  caller explicitly sets `HttpTokens=optional`, never on unrelated edits like
  hop limit).
- **Require encrypted EBS** — deny `ec2:CreateVolume` / `ec2:RunInstances` when
  `ec2:Encrypted = false`, on top of keeping EBS default encryption on.
- **Protect account-level S3 Block Public Access** — deny
  `s3:PutAccountPublicAccessBlock` and `s3:DeleteAccountPublicAccessBlock`.
- **Block IAM users / long-lived keys** — deny `iam:CreateUser`,
  `iam:CreateAccessKey`, `iam:CreateLoginProfile` (you use IAM Identity Center).

> **Prerequisite for the S3 rule:** there is no condition key to tell "enable"
> from "disable" on these calls, so the policy blocks the calls outright.
> **Enable account-level S3 Block Public Access (all four settings) *before*
> attaching policy 04** — otherwise this rule will also prevent you from turning
> it on. Account-level BPA overrides per-bucket settings, which is why only the
> account-level actions are blocked (bucket-level `Put` stays available).

### Still optional / not done as SCPs

1. **Remove root credentials from member accounts** (not an SCP). Use
   centralized root access in Organizations — cleaner than any deny-root policy,
   which is why there is no deny-root SCP here.
2. **Protect the guardrails themselves** — deny detaching/deleting these SCPs or
   modifying the CloudFormation execution role from within member accounts.

### CloudWatch Logs retention — why it is *not* an SCP

You asked to deny creating log groups that have **no** retention (infinite).
This **cannot be done with an SCP**: `CreateLogGroup` has no retention
parameter (groups are always created as "never expire"), and there is no
`logs:` condition key for retention days — so there is nothing for a
Deny-Unless rule to match at creation time.

Enforceable alternatives:

- **Auto-remediate (recommended):** an EventBridge rule on the `CreateLogGroup`
  CloudTrail event triggering a small Lambda that calls `PutRetentionPolicy`
  with a default (e.g. 30 days). This is the only way to *guarantee* finite
  retention, and it fits the Lambda pattern already in `scheduled-switch/`.
- **Complementary SCP guard:** deny `logs:DeleteRetentionPolicy` so an existing
  retention can't be reverted back to infinite. (Not added yet — say the word.)

> AWS Config has a managed rule for this (`cw-loggroup-retention-period-check`),
> but Config bills per item and we've deliberately left it out for cost.

## Files

```
scp-guardrails/
├── README.md
├── deploy.sh
└── cloudformation/
    └── scp-guardrails.yaml      # AWS::Organizations::Policy x5 + attachment (single source of truth)
```
