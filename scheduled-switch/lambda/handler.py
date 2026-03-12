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
from aws_durable_execution_sdk_python.types import WaitForConditionCheckContext
from aws_durable_execution_sdk_python.waits import (
    WaitForConditionConfig,
    WaitForConditionDecision,
)

STACK_NAME = os.environ["STACK_NAME"]
PAUSE_SECONDS = int(os.environ.get("PAUSE_SECONDS", "28800"))  # 8 hours default
CONDITION_POLL_SECONDS = 300  # 5 minutes between stack status checks

CFN_SUCCESS = {
    "UPDATE_COMPLETE",
    "UPDATE_COMPLETE_CLEANUP_IN_PROGRESS",
}
CFN_FAILURES = {
    "UPDATE_FAILED",
    "UPDATE_ROLLBACK_IN_PROGRESS",
    "UPDATE_ROLLBACK_COMPLETE",
    "UPDATE_ROLLBACK_COMPLETE_CLEANUP_IN_PROGRESS",
    "UPDATE_ROLLBACK_FAILED",
    "ROLLBACK_IN_PROGRESS",
    "ROLLBACK_COMPLETE",
    "ROLLBACK_FAILED",
}

@durable_step
def set_switch_state(step_ctx: StepContext, state: str) -> str:
    cfn = boto3.client("cloudformation")
    try:
        cfn.update_stack(
            StackName=STACK_NAME,
            UsePreviousTemplate=True,
            Parameters=[{"ParameterKey": "SwitchState", "ParameterValue": state}],
        )
    except ClientError as e:
        if "No updates are to be performed" not in str(e):
            raise
    return state


def _check_stack_status(_: str, ctx: WaitForConditionCheckContext) -> str:
    status = boto3.client("cloudformation").describe_stacks(
        StackName=STACK_NAME
    )["Stacks"][0]["StackStatus"]
    if status in CFN_FAILURES:
        raise RuntimeError(f"Stack update failed: {status}")
    return status


def _wait_for_stack() -> WaitForConditionConfig:
    def wait_strategy(status: str, attempt: int) -> WaitForConditionDecision:
        if status in CFN_SUCCESS:
            return WaitForConditionDecision.stop_polling()
        return WaitForConditionDecision.continue_waiting(
            delay=Duration.from_seconds(CONDITION_POLL_SECONDS)
        )

    return WaitForConditionConfig(wait_strategy=wait_strategy, initial_state="")


@durable_execution
def handler(event: dict, context: DurableContext) -> dict:
    context.step(set_switch_state("SwitchedOn"), name="switch-on")
    context.wait_for_condition(check=_check_stack_status, config=_wait_for_stack(), name="wait-for-on")

    context.wait(duration=Duration.from_seconds(PAUSE_SECONDS), name="timed-pause")

    context.step(set_switch_state("SwitchedOff"), name="switch-off")
    context.wait_for_condition(check=_check_stack_status, config=_wait_for_stack(), name="wait-for-off")

    return {"status": "complete", "stack": STACK_NAME}
