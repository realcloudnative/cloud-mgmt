# cloud-mgmt — a lightweight home AWS landing zone

A small, cost-conscious set of building blocks that turn a personal AWS
Organization into a sane, guard-railed "landing zone" — without the weight of
Control Tower or per-item-billed services like AWS Config.

It is built around **Deny-Unless guardrails** (start from full access, subtract
with conditional denies), a **single human operator** who deliberately switches
between a safe everyday role and a rare powerful one, and **cost controls** that
both alert and, as a last resort, automatically quarantine runaway spend.

## Target shape

Three accounts in one AWS Organization, plus IAM Identity Center for human
access:

```
Organization (management / payer account)
├── management   ← billing, Organizations/SCPs, identity. NEVER runs workloads.
├── dev          ← main workload + experimentation account (spend-risk)
└── prod         ← small, stable workloads (e.g. a blog + its domain)
```

- **Allowed regions:** `us-east-1`, `us-west-2`, `eu-central-1`, `eu-north-1`,
  `ap-southeast-1` (plus unavoidable global services).
- The **management account is never bound by SCPs** — that is the built-in
  escape hatch, and the reason management has its own no-workloads guardrails.

## Components

| Folder | Purpose | Mechanism | Deployed in |
|--------|---------|-----------|-------------|
| [`idc-permission-sets`](./idc-permission-sets) | Two-hats operator: a safe everyday `CloudOps` set + a rare `IdentityAdmin` set, assigned only to management | CloudFormation (`AWS::SSO::*`) | management (IdC home region) |
| [`account-baseline`](./account-baseline) | Turns **on** the settings the SCPs later lock: S3 account Block Public Access, EBS default encryption, IMDSv2 defaults; optional foundational-only GuardDuty | CLI + CloudFormation | each account |
| [`scp-guardrails`](./scp-guardrails) | Deny-Unless SCPs: region lock, service allowlist, EC2 size cap, baseline-security, cost-control | CloudFormation (`AWS::Organizations::Policy`) | management |
| [`budget-alarms`](./budget-alarms) | Email budget alerts (org-wide + per-account), tuned for a ~$10/mo home org | CloudFormation (`AWS::Budgets::Budget`) | management |
| [`cost-quarantine`](./cost-quarantine) | Automatic failsafe: at 3× actual spend, auto-attaches a quarantine SCP to dev | CloudFormation (Budgets action → SCP) | management |
| [`scheduled-switch`](./scheduled-switch) | Schedules expensive resources (NAT Gateway, ALB, …) off when not needed | AWS SAM / Lambda | workload account(s) |

Each folder has its own README with full detail; this file is the map and the
order.

## Prerequisites (assumed, not created here)

These are taken as given before applying anything below:

1. **An AWS Organization with all features enabled**, with the **management
   (payer)** account plus **dev** and **prod** member accounts.
2. **Service control policy type enabled** in Organizations (Policies → SCPs →
   Enable). The default **`FullAWSAccess` SCP stays attached** — the guardrails
   subtract from it.
3. **IAM Identity Center enabled**, with your human **user created**, and its
   **home region** known (SSO resources are region-bound).
4. **Root secured**: strong password + MFA on the management account root; plan
   to stop using root for daily work (and ideally remove root credentials from
   member accounts via centralized root access).
5. **Local tooling**: AWS CLI v2, and (for validation) `cfn-lint`.
6. **Bootstrap access** to the management account to apply the first step —
   initially your existing admin/root; you move to the `CloudOps` role right
   after step 1.
7. You know your **account IDs** (management, dev, prod).

## Order of application

The order matters in two places (flagged below). Everything is deployed from the
**management account** unless noted; per-account steps use that account's
credentials/profile.

**1 — Identity first ([`idc-permission-sets`](./idc-permission-sets))**
Establish the two operator hats so you can stop using root/over-broad access for
the remaining steps. Bootstrap this once with your existing admin, then switch
into the `CloudOps` role for everything else.

**2 — Account baseline ([`account-baseline`](./account-baseline))** — run in
**each** account (management, dev, prod).
⚠️ **Must run before step 3.** Policy 04 denies `s3:PutAccountPublicAccessBlock`,
so account-level S3 Block Public Access has to be switched **on here first** or
you lock yourself out of enabling it. EBS encryption and IMDSv2 defaults are
order-independent. GuardDuty is optional and off by default.

**3 — Guardrails ([`scp-guardrails`](./scp-guardrails))**
Attach the Deny-Unless SCPs to the org root and/or OUs. Region lock + service
allowlist suit the whole org; the EC2 size cap and cost-control earn their keep
on dev. Keep prod's guardrails light so an SCP can't break the blog.

**4 — Budget alerts ([`budget-alarms`](./budget-alarms))**
Create the org-wide and per-account budgets (defaults: $10 overall, $5 dev,
$2 prod). This is the highest-value, lowest-effort control.

**5 — Cost failsafe ([`cost-quarantine`](./cost-quarantine))**
Add the automatic quarantine that attaches a deny-new-spend SCP to dev at 3×
actual spend. Reluctant by design; recovery is a manual detach from management.

**6 — Ongoing operations ([`scheduled-switch`](./scheduled-switch))** — optional.
Schedule expensive resources off when idle to keep the bill near zero.

```
1 idc-permission-sets ─► 2 account-baseline ─►(⚠ before)─► 3 scp-guardrails
        │                                                        │
        └──────────────► 4 budget-alarms ─► 5 cost-quarantine ◄──┘
                                            6 scheduled-switch (anytime, optional)
```

## Cross-cutting principles

- **Deny-Unless everywhere** — new services/actions are blocked by default until
  explicitly allowed.
- **Management is the escape hatch** — never bound by SCPs, so it can always
  detach a too-tight policy or lift a quarantine. In return it carries its own
  no-workloads guardrails (it can't run anything, even by accident).
- **Deliberate, not accidental** — one human, one IdC user, two hats; power
  requires a conscious role switch.
- **Cost is the universal backstop** — when a guardrail can't prevent something
  (e.g. a leaked long-lived Bedrock API key, which can bypass SCPs), the budget
  alert still catches the spend.

## Residual risks (acknowledged, not over-engineered)

- The `IdentityAdmin` hat is effectively org-admin while assumed; one human
  identity backs both hats — so **strong MFA on that IdC user is the key
  mitigation**.
- `CloudOps` can create IAM roles (needed to deploy `cost-quarantine`), a
  *deliberate* (not accidental) escalation path; close it with a permissions
  boundary if desired.
- Quarantine and budget actions are **not real-time** (cost data lags hours), so
  they limit damage rather than cap it precisely.
- Long-lived **Bedrock API keys** are service-specific credentials that can
  evade SCP enforcement; prefer not minting them and rely on cost alerts.

This is a deliberately small landing zone for a single operator. It is a clear
step up from using root in management or sharing one identity across dev and
management — without taking on enterprise cost or complexity.
