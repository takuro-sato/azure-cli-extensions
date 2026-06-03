#!/usr/bin/env python3
import glob
import os.path
import yaml
import re
import sys

from dataclasses import dataclass

workflows_dir = os.path.join(os.path.dirname(__file__), "..", ".github/workflows")
workflows = sorted(glob.glob("*.yml", root_dir=workflows_dir))


@dataclass
class TestType:
    ty: str
    rough_time_mins: int
    max_concurrency: int
    shift: int
    priority: int


test_types = [
    # For VM tests, once they're deployed, they can run concurrently with the
    # ACI tests without hitting max deployment counts.  However, VM tests deploy
    # a few VMs in parallel at the start, so we reduce the max concurrency
    TestType("vm", 10, 8, 1, 1),
    TestType("perf", 10, 8, 1, 2),

    TestType("region", 110, 4, 1, 3),
    TestType("vn2", 20, 20, 1, 4),
    TestType("uptime", 5, 20, 1, 5),
    TestType("high-spec", 5, 10, 1, 6),
]

# These tests are special - it runs every hour for continuous monitoring
continuous_test_types = [
    TestType("basic-region", 5, 50, 1, 0),
    TestType("attestation-", 3, 50, 1, 1),
]

tests = []
continuous_tests = {}

ignore_list = ["vn2-australiacentral2.yml", "region-australiacentral2.yml", "vn2-eastus2euap.yml"]

# Don't run on 0:00-0:59 UTC as that's when cleanup would be happening.
CONTINUOUS_TEST_HOURS = "1-23"

def find_test_type(workflow_name: str) -> TestType:
    for test_type in test_types:
        if workflow_name.startswith(test_type.ty):
            return test_type
    return None

for wf in workflows:
    if wf in ignore_list:
        continue

    with open(os.path.join(workflows_dir, wf), "rt") as f:
        doc = yaml.safe_load(f)

    add_to_list = tests

    t = find_test_type(wf)
    if not t:
        for ct in continuous_test_types:
            if wf.startswith(ct.ty):
                t = ct
                if ct.ty not in continuous_tests:
                    continuous_tests[ct.ty] = []
                add_to_list = continuous_tests[t.ty]
                break
    if not t:
        print(f"Skipping {wf}")
        continue

    # "on" is interpreted as a boolean in YAML :)
    on = doc.get("on", doc.get(True, {}))
    schedules = on.get("schedule", [])
    if len(schedules) != 1:
        continue
    cron = schedules[0].get("cron")
    if not cron:
        raise ValueError(f"Workflow {wf} has no existing cron schedule. Please add one arbitrarily first.")
    add_to_list.append((wf, t))

last_t = None
curr_concurrency = 0
accumulated_time = 0

def minutes_to_cron(minutes: int) -> str:
    hours = minutes // 60
    minutes = minutes % 60
    hours += 1
    return f"{minutes} {hours} * * *"

CRON_RE = re.compile(
    r"""^on:
(\s+pull_request:
\s+paths:
(\s+- .+)+
)?\s+schedule:
\s+- cron: '(?P<cron>.+?)'(?P<comment>\s*(\#.+)?$)""",
    re.MULTILINE
)

def write_cron(workflow: str, cron: str):
    # Use regex replace to preserve comments etc
    with open(os.path.join(workflows_dir, workflow), "rt") as f:
        content = f.read()
    found_cron = CRON_RE.search(content)
    if not found_cron:
        print(f"Failed to replace cron in {workflow}")
        sys.exit(1)
    str_span = found_cron.span("cron")
    orig_len = str_span[1] - str_span[0]
    comment_span = found_cron.span("comment")
    content = content[:str_span[0]] + cron + content[str_span[1]:]
    comment_span = (comment_span[0] - orig_len + len(cron), comment_span[1] - orig_len + len(cron))
    content = content[:comment_span[0]] + "  # managed by scripts/spread_out_schedules.py" + content[comment_span[1]:]
    with open(os.path.join(workflows_dir, workflow), "wt") as f:
        f.write(content)

for wf, t in sorted(tests, key=lambda x: (x[1].priority, x[0])):
    if last_t and t.ty != last_t.ty and curr_concurrency > 0:
        # wait for last test type to finish
        accumulated_time += last_t.rough_time_mins
        curr_concurrency = 0
        last_t = None
    if curr_concurrency >= t.max_concurrency:
        accumulated_time += t.rough_time_mins
        curr_concurrency = 0
    else:
        accumulated_time += t.shift
    curr_concurrency += 1
    last_t = t
    cron = minutes_to_cron(accumulated_time)
    print(f"Setting {wf} to {cron}")
    write_cron(wf, cron)

if curr_concurrency > 0:
    accumulated_time += last_t.rough_time_mins

# schedule the continuous tests

cont_start_min = 0
for ty in continuous_test_types:
    tests = continuous_tests[ty.ty]
    accu_minutes = cont_start_min % 60
    cont_start_min += continuous_test_types[0].rough_time_mins
    for wf, t in sorted(tests, key=lambda x: x[0]):
        cron = f"{accu_minutes} {CONTINUOUS_TEST_HOURS} * * *"
        print(f"Setting {wf} to {cron}")
        write_cron(wf, cron)
        accu_minutes = (accu_minutes + t.shift) % 60

print(f"Tests expected to finish around {accumulated_time // 60 + 1}:{accumulated_time % 60} UTC")
