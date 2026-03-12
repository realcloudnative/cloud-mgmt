import os
import boto3
from botocore.exceptions import ClientError
from aws_durable_execution_sdk_python import (
    DurableContext,
    StepContext,
    durable_execution,
    durable_step,
)
from aws_durable_execution_sdk_python.config import Duration

STACK_NAME = os.environ["STACK_NAME"]
PAUSE_SECONDS = int(os.environ.get("PAUSE_SECONDS", "28800"))  # 8 hours default


@durable_step
def switch_on(step_ctx: StepContext) -> str:
    cfn = boto3.client("cloudformation")
    try:
        cfn.update_stack(
            StackName=STACK_NAME,
            UsePreviousTemplate=True,
            Parameters=[{"ParameterKey": "SwitchState", "ParameterValue": "SwitchedOn"}],
        )
    except ClientError as e:
        if "No updates are to be performed" not in str(e):
            raise
    return "on"


@durable_step
def switch_off(step_ctx: StepContext) -> str:
    cfn = boto3.client("cloudformation")
    try:
        cfn.update_stack(
            StackName=STACK_NAME,
            UsePreviousTemplate=True,
            Parameters=[{"ParameterKey": "SwitchState", "ParameterValue": "SwitchedOff"}],
        )
    except ClientError as e:
        if "No updates are to be performed" not in str(e):
            raise
    return "off"


@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    # Step 1: Switch on the expensive resource
    context.step(switch_on(), name="switch-on")

    # Step 2: Wait with no compute charges during the pause
    context.wait(duration=Duration.from_seconds(PAUSE_SECONDS), name="timed-pause")

    # Step 3: Switch off the expensive resource
    context.step(switch_off(), name="switch-off")

    return {"status": "complete", "stack": STACK_NAME}
