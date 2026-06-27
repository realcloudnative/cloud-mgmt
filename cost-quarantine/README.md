# cost-quarantine

An **automatic** failsafe for runaway cost. Watches the dev account's **actual**
spend and, at a deliberately high threshold, auto-attaches a **quarantine SCP**
that stops new cost-generating actions — without you having to be watching.

Deploy in the Organizations **management (payer) account**.

## How it works

```
ACTUAL dev spend ≥ threshold
        │
        ▼
AWS Budgets assumes the execution role
        │
        ▼
organizations:AttachPolicy  →  quarantine SCP attached to dev account
        │
        ▼
new cost-generating actions denied (existing ones keep running)
```

Built entirely in CloudFormation:

| Resource | Role |
|----------|------|
| `AWS::Organizations::Policy` | the quarantine SCP — created **detached**, does nothing until attached |
| `AWS::IAM::Role` | role AWS Budgets assumes (trusts `budgets.amazonaws.com`, can `organizations:AttachPolicy`/`DetachPolicy`) |
| `AWS::Budgets::Budget` | monthly **cost** budget filtered to the **dev `LinkedAccount`** |
| `AWS::Budgets::BudgetsAction` | `APPLY_SCP_POLICY`, `ApprovalModel: AUTOMATIC`, `NotificationType: ACTUAL` |

## Design choices (per the requirements)

- **Automatic** — `ApprovalModel: AUTOMATIC`. No human approval needed; fires on its own.
- **Reluctant** — single trigger at **3×** (`QuarantineThreshold`, default **$15** = 3 × the $5 dev budget), on **ACTUAL** spend only. No forecast trigger, so a jumpy early-month projection can't set it off.
- **Excludes the annual Route 53 renewal** — the budget is scoped to the **dev** account; the domain lives on prod, so its renewal never counts toward this trigger.
- **Stops the bleeding, not your hands** — the SCP denies *new* compute/AI/job actions (`ec2:RunInstances`, `bedrock:Invoke*`, `aws-external-anthropic:*`, `lambda:InvokeFunction`, `ecs:RunTask`, `athena:StartQueryExecution`, media jobs, etc.) but leaves **read, stop, delete, billing, and support** available so you can investigate and tear resources down.

## Recovery — how to lift a quarantine

The action is **one-way**: it does **not** auto-undo when spend drops. To lift it,
detach the SCP from the **management account** (which is never bound by SCPs, so
this always works). The exact command is in the stack's `ManualLiftCommand`
output:

```bash
aws organizations detach-policy --policy-id <quarantine-scp-id> --target-id <dev-account-id>
```

## Honest limitations

1. **Not real-time / not a hard cap.** Budgets refresh cost data only a few
   times a day, so the trigger lags hours. It limits damage to roughly
   "threshold + a few hours of accrual," not a precise ceiling.
2. **Leaked Bedrock API keys may bypass it.** Long-lived Bedrock API keys are
   IAM *service-specific credentials*, and there is published research showing
   they can evade SCP enforcement. If a runaway is driven by such a key, the
   quarantine SCP may not stop it — your budget **alert** remains the reliable
   signal there. Best prevention: don't mint long-lived Bedrock keys (deny
   `iam:CreateServiceSpecificCredential`).

## Deploy

```bash
# From the management account:
./deploy.sh <dev-account-id> you@example.com

# Custom threshold:
QUARANTINE_THRESHOLD=30 ./deploy.sh <dev-account-id> you@example.com
```

## Files

```
cost-quarantine/
├── README.md
├── deploy.sh
└── cloudformation/
    └── cost-quarantine.yaml
```
