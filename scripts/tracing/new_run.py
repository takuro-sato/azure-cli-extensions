#!/usr/bin/env python3

from common import get_env_or_die, write_state, trace_step, STATUS_STARTED
import uuid
import os

RESOURCE_GROUP = get_env_or_die("RESOURCE_GROUP")
DEPLOYMENT_NAME = get_env_or_die("DEPLOYMENT_NAME")
LOCATION = get_env_or_die("LOCATION")
RUN_LINK = get_env_or_die("RUN_LINK")
TEST_TYPE = get_env_or_die("TEST_TYPE")
TEST_NAME = get_env_or_die("TEST_NAME")
BRANCH = os.getenv("GITHUB_REF_NAME", os.getenv("BRANCH", ""))

unique_run_id = str(uuid.uuid4())

run_info = {
    "UniqueRunId": unique_run_id,
    "ResourceGroup": RESOURCE_GROUP,
    "DeploymentName": DEPLOYMENT_NAME,
    "Location": LOCATION,
    "TestType": TEST_TYPE,
    "TestName": TEST_NAME,
    "RunLink": RUN_LINK,
    "Branch": BRANCH,
}

state = {
    "run_info": run_info,
    "curr_step": None,
}

trace_step(run_info, "Init", STATUS_STARTED)
state["curr_step"] = "Init"

write_state(state)
