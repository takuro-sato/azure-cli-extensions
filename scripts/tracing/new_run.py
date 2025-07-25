#!/usr/bin/env python3

from common import get_env_or_die, write_state, trace_step, STATUS_STARTED
import uuid
import os
import re

RESOURCE_GROUP = get_env_or_die("RESOURCE_GROUP")
DEPLOYMENT_NAME = os.getenv("DEPLOYMENT_NAME", os.getenv("DEPLOYMENT_NAME_BASE", ""))
if not DEPLOYMENT_NAME:
    raise ValueError("DEPLOYMENT_NAME or DEPLOYMENT_NAME_BASE must be set")
LOCATION = get_env_or_die("LOCATION")
RUN_LINK = get_env_or_die("RUN_LINK")
TEST_TYPE = get_env_or_die("TEST_TYPE")
TEST_NAME = get_env_or_die("TEST_NAME")
BRANCH = os.getenv("GITHUB_REF_NAME", os.getenv("BRANCH", ""))
ZONE = os.getenv("ZONE", "")
VALID_ZONE_RE = re.compile(r"^[0-9]$")
if ZONE and not VALID_ZONE_RE.fullmatch(ZONE):
    raise ValueError(f"ZONE must be a single digit, got {ZONE}")

unique_run_id = str(uuid.uuid4())

run_info = {
    "UniqueRunId": unique_run_id,
    "ResourceGroup": RESOURCE_GROUP,
    "DeploymentName": DEPLOYMENT_NAME,
    "Location": LOCATION,
    "AvailabilityZone": ZONE,
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
