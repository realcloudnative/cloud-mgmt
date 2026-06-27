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
| 04 | `baseline-security` *(optional)* | Require IMDSv2; protect CloudTrail/GuardDuty; block leaving the org; keep EBS default encryption. |
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

Beyond the five included policies, these are worth considering. None are
enabled unless you add them.

1. **Remove root credentials from member accounts** (not an SCP). Use
   centralized root access in Organizations to remove root sign-in from member
   accounts entirely. This is why there is **no deny-root SCP here** — the
   feature covers it more cleanly than a policy ever could.
2. **Enforce IMDSv2 on existing instances**, not just launches — add a deny on
   `ec2:ModifyInstanceMetadataOptions` that would re-enable IMDSv1.
3. **Require encrypted EBS volumes** at create time
   (`ec2:CreateVolume` / `RunInstances` unless `ec2:Encrypted = true`), in
   addition to keeping default encryption on.
4. **Block public S3** — deny `s3:PutAccountPublicAccessBlock` /
   `s3:PutBucketPublicAccessBlock` calls that *disable* Block Public Access.
5. **Protect the guardrails themselves** — deny detaching/deleting these SCPs
   or modifying the CloudFormation execution role from within member accounts.
6. **Deny IAM user / long-lived access key creation** to push everything
   through IAM Identity Center and roles (`iam:CreateUser`,
   `iam:CreateAccessKey`). Strong for home use, but confirm you have SSO set up
   first.
7. **Cap log/data retention churn** or deny deleting CloudWatch log groups, if
   you rely on them for after-the-fact debugging.

## Files

```
scp-guardrails/
├── README.md
├── deploy.sh
└── cloudformation/
    └── scp-guardrails.yaml      # AWS::Organizations::Policy x5 + attachment (single source of truth)
```
