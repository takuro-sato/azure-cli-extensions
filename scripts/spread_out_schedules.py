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
    TestType("region", 60, 4, 1, 2),
    TestType("uptime", 5, 20, 1, 3),
    TestType("high-spec", 5, 10, 1, 4),
    TestType("vn2", 20, 20, 1, 5),

    # For VM tests, once they're deployed, they can run concurrently with the
    # ACI tests without hitting max deployment counts.  However, VM tests deploy
    # a few VMs in parallel at the start, so we reduce the max concurrency
    TestType("vm", 10, 8, 1, 6),

    TestType("perf", 120, 20, 1, 10),
]

# This test is special - it runs every hour for continuous monitoring
basic_test = TestType("basic-region", 20, 50, 1, 0)

tests = []
basic_tests = []

# Don't run on 0:00-0:59 UTC as that's when cleanup would be happening.
BASIC_TEST_HOURS = "1-23"

def find_test_type(workflow_name: str) -> TestType:
    for test_type in test_types:
        if workflow_name.startswith(test_type.ty):
            return test_type
    return None

for wf in workflows:
    with open(os.path.join(workflows_dir, wf), "rt") as f:
        doc = yaml.safe_load(f)

    add_to_list = tests

    t = find_test_type(wf)
    if not t and wf.startswith(basic_test.ty):
        t = basic_test
        add_to_list = basic_tests
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
    hours += 2
    return f"{minutes} {hours} * * *"

CRON_RE = re.compile(r"""^on:
\s+schedule:
\s+- cron: '(.+?)'(\s*(\#.+)?$)""", re.MULTILINE)

def write_cron(workflow: str, cron: str):
    # Use regex replace to preserve comments etc
    with open(os.path.join(workflows_dir, workflow), "rt") as f:
        content = f.read()
    found_cron = CRON_RE.search(content)
    if not found_cron:
        print(f"Failed to replace cron in {workflow}")
        sys.exit(1)
    str_span = found_cron.span(1)
    orig_len = str_span[1] - str_span[0]
    comment_span = found_cron.span(2)
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

# schedule the basic tests
basic_test_minute = 0
for wf, t in sorted(basic_tests, key=lambda x: x[0]):
    cron = f"{basic_test_minute} {BASIC_TEST_HOURS} * * *"
    print(f"Setting {wf} to {cron}")
    write_cron(wf, cron)
    basic_test_minute = (basic_test_minute + t.shift) % 60

print(f"Tests expected to finish around {accumulated_time // 60 + 2}:{accumulated_time % 60} UTC")
