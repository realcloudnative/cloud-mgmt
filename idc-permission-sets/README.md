# idc-permission-sets

Two IAM Identity Center permission sets for a single management-account operator.
One human, one IdC user, **two deliberately-assumed hats** — so management work
is always intentional and nothing happens by accident.

| Permission set | When you use it | Can do | Cannot do |
|----------------|-----------------|--------|-----------|
| **CloudOpsManagement** | Everyday | Organizations/SCPs, Budgets, CloudFormation, account-baseline settings; read-only everything | Run workloads; administer Identity Center |
| **IdentityAdmin** | Rarely | Administer IdC permission sets + assignments (incl. dev/prod) | Run workloads (from management) |

Both are assigned **only to the management account**, so this login never has
direct access to dev/prod.

## How the isolation works

- **"Only management, not dev/prod"** comes from the **assignment target** — both
  permission sets are assigned to the management account id only. Account scope
  is never enforced by the policy; it's enforced by *where you assign*.
- **"Never run workloads"** comes from the inline `NeverRunWorkloads` **Deny** in
  each set. Since SCPs don't apply to the management account, this Deny is the
  guardrail that plays the SCP's role here.
- **CloudOps can't escalate** — it carries a `NoSelfEscalationViaIdentityCenter`
  Deny, so the everyday hat can't grant itself dev/prod access. Only the
  IdentityAdmin hat can touch Identity Center, and you assume it on purpose.

## Why two hats instead of one

Identity Center administration *is* a privilege-escalation primitive: anyone who
can edit assignments can grant any access to anyone. So "administers dev/prod
permission sets" and "can never reach dev/prod" can't both live in one role.
Splitting them lets your **everyday** role be safe-by-construction, while the
**power** to change access requires a deliberate switch into a separate, short-
session hat.

## Honest residual risk (called out, not stifled)

- **IdentityAdmin is effectively org-admin while assumed** — a mistake in that
  session can grant broad access. Mitigation is behavioral: use it rarely, and
  its session is short (`PT1H`).
- **One human identity backs both hats** — the real single point of failure is
  that IdC user's credentials. **Put strong MFA (hardware/passkey) on it.**
- **CloudOps grants `iam:CreateRole`** (needed to deploy the cost-quarantine
  stack). That's a *deliberate* escalation path, not an accidental one. Close it
  later with a permissions boundary if you want.

This is still a clear improvement over using root in management, or over one
user that accesses both dev and management.

## Prerequisites & inputs

Create the IdC user first (console or `identitystore`), then gather:

```bash
# Identity Center instance ARN + identity store id:
aws sso-admin list-instances

# The user's principal id:
aws identitystore list-users --identity-store-id <identity-store-id>
```

## Deploy

> Run in the **management account**, in the **region where Identity Center is
> homed** (SSO resources are region-bound — set `REGION` to match).

```bash
REGION=<idc-region> ./deploy.sh <instance-arn> <mgmt-account-id> <principal-id>
```

Session durations and principal type are adjustable via parameters / env
(`CloudOpsSessionDuration` default `PT4H`, `IdentityAdminSessionDuration`
default `PT1H`, `PRINCIPAL_TYPE` default `USER`).

## Files

```
idc-permission-sets/
├── README.md
├── deploy.sh
└── cloudformation/
    └── idc-permission-sets.yaml
```
