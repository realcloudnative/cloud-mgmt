# budget-alarms

Home cost guardrails: AWS Budgets with email alerts. The single most useful
home guardrail — it catches the mistakes SCPs can't (a `t3.micro` left running,
a NAT Gateway, data egress, an experiment you forgot to tear down).

## Where does this run? (management account)

Deploy this **in the Organizations management / payer account**, and run both
the org-wide and per-account budgets from there:

- The payer account is the only place that sees **consolidated** cost data and
  can filter budgets by `LinkedAccount`. So one stack covers the org total
  *and* each account (dev, prod).
- A budget created *inside* a member account only sees that account's own spend
  and can't reference siblings — so per-account-in-each-account means more
  stacks and credentials for zero benefit at home.

## What gets created

| Budget | Scope | Default limit | In free tier? |
|--------|-------|---------------|---------------|
| `home-overall-monthly` | Whole org (consolidated) | $10/mo | yes (1st) |
| `home-dev-monthly` | Dev account only | $5/mo | yes (2nd) |
| `home-prod-monthly` *(opt-in)* | Prod account only | $2/mo | no (3rd) |

Each budget alerts the same email at **80% actual**, **100% actual**, and
**100% forecasted**.

**Cost:** the first **2 budgets per account are free**; each additional is
~$0.02/day (~$0.60/mo). Defaults stay free (overall + dev). The prod budget is
opt-in because it's the 3rd.

These defaults reflect a genuinely small home org: normal spend under ~$10/mo
total, ~$5 dev, ~$2 prod (a small blog). **Expect the overall budget to trip
once a year when your domain renews** (a `.com` renewal is ~$13, more than a
$10 month) — that alert is informational and expected, not a problem to fix.

Why dev gets its own budget and prod is optional: dev is your spend-risk
account (experiments), prod is a small, stable blog. Start with overall + dev;
add prod only if you want the extra signal.

## Deploy

> Run in the management account, with SCPs/Budgets-capable credentials.
> Budgets is a global service; us-east-1 is its endpoint.

```bash
# Overall + dev budgets (free tier):
./deploy.sh you@example.com 111122223333

# Add the prod budget too:
ENABLE_PROD_BUDGET=true PROD_ACCOUNT_ID=444455556666 \
  ./deploy.sh you@example.com 111122223333

# Custom limits:
OVERALL_LIMIT=80 DEV_LIMIT=30 ./deploy.sh you@example.com 111122223333
```

Parameters can also be set directly via `aws cloudformation deploy
--parameter-overrides` (see `cloudformation/budget-alarms.yaml`).

## Notes

- Budgets refresh roughly 3x/day, so alerts are near-real-time but not instant.
- Email subscribers receive a one-time confirmation from AWS Budgets — no
  action needed beyond noting the first message is legitimate.
- To alert more than one address, add more `EMAIL` subscribers in the template
  (up to 10 per notification), or switch a subscriber to an SNS topic.

## Files

```
budget-alarms/
├── README.md
├── deploy.sh
└── cloudformation/
    └── budget-alarms.yaml
```
