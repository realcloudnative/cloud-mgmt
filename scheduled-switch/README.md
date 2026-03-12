# scheduled-switch

A working example of a **Lambda durable function** that toggles a CloudFormation resource on a daily schedule. The pattern: a resource is off by default, switched on at 7 AM UTC, held for a configurable duration (default 8 hours), then switched off automatically — with no compute charges during the wait.

The conditional resource here is represented by an SSM Parameter. Replace it with a NAT Gateway, ALB, RDS instance, or any other resource you want to run only during business hours.

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

**Regional availability**: us-east-2 (Ohio) and eu-central-1 (Frankfurt).

The function uses three durable primitives:

- `context.step(fn(...), name=...)` — executes a retryable, idempotent unit of work; result is memoized so replays skip re-execution
- `context.wait(duration, name=...)` — durable sleep; Lambda is not running during this time
- `context.wait_for_condition(check, config, name=...)` — polls a condition function on a durable timer; Lambda wakes periodically to check, sleeps between checks

---

## Files

```
scheduled-switch/
├── stack.yaml           # Conditional resource stack
├── lambda-stack.yaml    # Durable function + EventBridge schedule
├── lambda/
│   ├── handler.py       # Durable function implementation
│   └── pyproject.toml   # Python dependencies (uv)
├── provision.sh         # One-time: creates stack.yaml in AWS
└── build.sh             # Packages and deploys lambda-stack.yaml
```

---

## Deploy

### Prerequisites

- AWS CLI configured (`aws sso login` or equivalent)
- [uv](https://docs.astral.sh/uv/) installed
- An S3 bucket in the target region (the `build.sh` script uses `demo-adriaan` — update it for your account)

### 1. Create the main stack

```bash
./provision.sh [stack-name] [region]
# defaults: scheduled-switch-main, eu-central-1
```

### 2. Build and deploy the Lambda stack

```bash
./build.sh [main-stack-name] [region]
# defaults: scheduled-switch-main, eu-central-1
```

`build.sh` uses `aws cloudformation package` to zip and upload the Lambda code to S3 automatically, then deploys the Lambda stack via `aws cloudformation deploy`.

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

Edit `DailyScheduleRule` in `lambda-stack.yaml`:

```yaml
ScheduleExpression: "cron(0 7 * * ? *)"  # 7 AM UTC daily
```

Then redeploy with `./build.sh`.

## Modifying the hold duration

Pass `PauseSeconds` as a parameter override:

```bash
./build.sh scheduled-switch-main eu-central-1 --parameter-overrides PauseSeconds=3600
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

Keep `DummyParameter` — CloudFormation rejects templates with zero resources, which would happen when `SwitchedOff` and all real resources are conditional.

## Adding failure alerts

Pass an SNS topic ARN when deploying the Lambda stack:

```bash
aws cloudformation deploy \
  --template-file lambda-stack-packaged.yaml \
  --stack-name scheduled-switch-lambda \
  --capabilities CAPABILITY_NAMED_IAM \
  --region eu-central-1 \
  --parameter-overrides \
    MainStackName=scheduled-switch-main \
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

If you switch from SSM parameters to a different resource type (e.g., EC2), add the corresponding permissions to `LambdaExecutionRole` in `lambda-stack.yaml`.
