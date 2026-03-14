# scheduled-switch

> [!NOTE]
> **Made with ❤️  by Claude Code**
> This repository was created by an AI coding agent with minimal human oversight. The code examples, documentation, and infrastructure templates were generated to demonstrate switching on/off resources through CloudFormation. While functional and tested, please review thoroughly before real-world use.

A working example of a **Lambda durable function** that toggles a CloudFormation resource on a daily schedule. The pattern: a resource is off by default, switched on at 7 AM UTC, held for a configurable duration (default 8 hours), then switched off automatically — with no compute charges during the wait.

The conditional resource here is represented by an SSM Parameter. Replace it with a NAT Gateway, ALB, RDS instance, or any other resource you want to run only during business hours.

### Why this pattern exists

Cloud resources cost money even when idle. A NAT Gateway charges ~$0.045/hour just for existing, independent of traffic. An ALB is similar. For development and staging environments that are only used during business hours, this adds up to real waste over nights and weekends. This pattern eliminates that by managing the resource lifecycle automatically, without any manual intervention.

The key design choice is to toggle resources via a **CloudFormation parameter update** rather than by creating and deleting the stack. The stack remains intact at all times; only the conditional resource inside it appears and disappears. This preserves stack outputs, avoids re-provisioning dependent infrastructure, and keeps the blast radius small — a failed update rolls back to the previous known-good state rather than leaving you with a partially deleted stack.

---

## Architecture

```
EventBridge (cron 7 AM UTC)
    └── Lambda durable function (scheduled-switch-lambda-switch:live)
            ├── step: UpdateStack SwitchedOn
            ├── wait_for_condition: poll DescribeStacks until UPDATE_COMPLETE (5 min intervals)
            ├── wait: 8 hours (durable suspension — zero compute cost)
            ├── step: UpdateStack SwitchedOff
            └── wait_for_condition: poll DescribeStacks until UPDATE_COMPLETE (5 min intervals)

stack.yaml (scheduled-switch-main)
    ├── DummyParameter  [always present — prevents empty-template error]
    └── ExpensiveParameter  [Condition: IsOn — only exists when SwitchedOn]
```

Two CloudFormation stacks:

| Stack | Template | Purpose |
|---|---|---|
| `scheduled-switch-main` | `stack.yaml` | The conditional resource being toggled |
| `scheduled-switch-lambda` | `lambda-stack.yaml` | The durable function + EventBridge schedule |

---

## Lambda Durable Functions

Lambda durable functions (announced at re:Invent 2025) are a code-first alternative to Step Functions. The key capability used here is **durable suspension**: `context.wait(Duration.from_seconds(N))` pauses the execution for N seconds with no Lambda compute running. For an 8-hour hold this saves the equivalent of 8 hours of Lambda invocation time.

The function uses three durable primitives:

- `context.step(fn(...), name=...)` — executes a retryable, idempotent unit of work; result is memoized so replays skip re-execution
- `context.wait(duration, name=...)` — durable sleep; Lambda is not running during this time
- `context.wait_for_condition(check, config, name=...)` — polls a condition function on a durable timer; Lambda wakes periodically to check, sleeps between checks

### Published version and alias are required

Durable functions cannot be invoked against `$LATEST`. Attempting an async invocation against `$LATEST` fails with `InvalidParameterValueException`. `AutoPublishAlias: live` in the SAM template handles version publishing and alias creation automatically; EventBridge and manual invocations both target the alias ARN.

### `DurableConfig` changes force resource replacement

`DurableConfig` is a property that defines the fundamental execution model of the function. Any change to it — including adjusting `ExecutionTimeout` — triggers replacement of the Lambda resource, which terminates all in-flight durable executions. Set `ExecutionTimeout` generously upfront rather than adjusting it later.

### `wait_for_condition` vs a boto3 waiter

An earlier version of this handler used `cfn.get_waiter("stack_update_complete")` inside the durable step. That works, but the boto3 waiter blocks synchronously — Lambda runs continuously, polling every 15 seconds until the update completes. A typical CloudFormation update takes 30–90 seconds, so the cost is small but real, and it scales badly if the stack update ever stalls.

`wait_for_condition` solves this properly: Lambda wakes every 5 minutes to run the check function, then suspends again. No compute runs between polls.

### Steps must be idempotent

Durable steps are memoized on first execution and skipped on replay. But if a step raises an exception, the runtime will retry it. This means step functions must be safe to call more than once with the same arguments. The `"No updates are to be performed"` exception handling in `set_switch_state` is what provides that guarantee — a replay after a partial failure won't try to re-apply an already-applied parameter change and raise unexpectedly.

### Concurrent executions are safe but additive

Invoking the function while a scheduled execution is already running starts a second independent durable execution. Both handle idempotently — each will hit "No updates are to be performed" on `switch-on` if the stack is already in the target state, and will independently switch off after the hold duration. The daily schedule naturally avoids this since the full cycle completes well within 24 hours, but it is worth knowing if you invoke manually.

---

## Files

```
scheduled-switch/
├── stack.yaml           # Conditional resource stack
├── lambda-stack.yaml    # SAM template: durable function + EventBridge schedule
├── lambda/
│   ├── handler.py       # Durable function implementation
│   └── pyproject.toml   # Python dependencies (uv)
├── deploy-resource-stack.sh         # One-time: creates stack.yaml in AWS
└── deploy-lambda-stack.sh             # sam build + sam deploy
```

---

## Deploy

### Prerequisites

- AWS CLI configured (`aws sso login` or equivalent)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) installed
- [uv](https://docs.astral.sh/uv/) installed

### 1. Create the main stack

```bash
./deploy-resource-stack.sh [stack-name] [region]
# defaults: scheduled-switch-main, eu-central-1
```

### 2. Build and deploy the Lambda stack

```bash
./deploy-lambda-stack.sh [main-stack-name] [region]
# defaults: scheduled-switch-main, eu-central-1
```

`deploy-lambda-stack.sh` runs `sam build` to package the Lambda code and `sam deploy` to deploy the stack. The `--resolve-s3` flag lets SAM manage the S3 bucket for deployment artifacts automatically.

### 3. Test manually

The build script prints the invocation command on completion. To invoke at any time:

```bash
ALIAS_ARN=$(aws cloudformation describe-stacks \
  --stack-name scheduled-switch-lambda --region eu-central-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`FunctionArn`].OutputValue' \
  --output text)

aws lambda invoke \
  --function-name "$ALIAS_ARN" \
  --invocation-type Event \
  --region eu-central-1 \
  --payload '{}' /dev/null
```

`--invocation-type Event` is required — durable functions must be invoked asynchronously.

The response includes a `DurableExecutionArn` you can use to track execution status.

---

## Modifying the schedule

Edit `DailySchedule` under `Events` in `lambda-stack.yaml`:

```yaml
Schedule: "cron(0 7 * * ? *)"  # 7 AM UTC daily
```

Then redeploy with `./deploy-lambda-stack.sh`.

## Modifying the hold duration

Pass `PauseSeconds` as a parameter override:

```bash
./deploy-lambda-stack.sh scheduled-switch-main eu-central-1 --parameter-overrides PauseSeconds=3600
```

Or edit the default in `lambda-stack.yaml` (`Default: 28800`).

## Replacing the SSM placeholder with a real resource

Edit `stack.yaml`. Add your resource under the `IsOn` condition:

```yaml
Conditions:
  IsOn: !Equals [!Ref SwitchState, SwitchedOn]

Resources:
  MyNatGateway:
    Type: AWS::EC2::NatGateway
    Condition: IsOn
    Properties:
      ...
```

Keep `DummyParameter` — CloudFormation rejects templates with zero resources, which would happen when `SwitchedOff` and all real resources are conditional. An SSM parameter is the cheapest possible placeholder: free tier covers it and it creates in seconds.

## Adding failure alerts

Pass an SNS topic ARN when deploying the Lambda stack:

```bash
./deploy-lambda-stack.sh scheduled-switch-main eu-central-1 --parameter-overrides \
  AlertTopicArn=arn:aws:sns:eu-central-1:123456789012:my-alerts
```

This enables `StackFailureRule`, an EventBridge rule that fires on `UPDATE_ROLLBACK_IN_PROGRESS` — the earliest signal of a failed stack update, before CloudFormation has finished rolling back.

---

## IAM: Why the Lambda role needs SSM permissions

CloudFormation supports an explicit service role via the `RoleARN` parameter on `CreateStack`/`UpdateStack`. When provided, CloudFormation assumes that role via `sts:AssumeRole` and all downstream resource API calls happen under that role's identity.

When no `RoleARN` is provided — which is the case here — CloudFormation makes downstream API calls using the credentials of the IAM principal that invoked the stack operation. Here that principal is the Lambda execution role, because the Lambda function is the one calling `cfn.update_stack()`. This is not a named IAM mechanism; it is a CloudFormation-specific default behavior documented in the CloudFormation user guide under *AWS CloudFormation service role*.

The practical consequence: every AWS resource your stack manages must be permitted in the caller's IAM policy. This stack creates and deletes SSM parameters, so the Lambda role needs `ssm:PutParameter` and `ssm:DeleteParameter`.

Without those permissions the stack update fails. The error message CloudFormation surfaces in this case is a generic `GeneralServiceException` rather than `AccessDeniedException` — CloudFormation wraps SSM API errors without preserving the authorization failure detail. The symptom is a stack update that rolls back immediately with no obvious cause.

The permissions are scoped tightly to the path this stack actually uses:

```yaml
Resource:
  - !Sub "arn:${AWS::Partition}:ssm:${AWS::Region}:${AWS::AccountId}:parameter/scheduled-switch/${MainStackName}/*"
```

If you switch from SSM parameters to a different resource type (for example, EC2), add the corresponding permissions to the `Policies` list on `SwitchFunction` in `lambda-stack.yaml`.
