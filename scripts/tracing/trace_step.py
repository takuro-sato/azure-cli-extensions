#!/usr/bin/env python3

import os
import sys
if not os.environ.get("KUSTO_CONNECTION_STRING"):
    print("No KUSTO_CONNECTION_STRING set, skipping tracing", file=sys.stderr, flush=True)
    sys.exit(0)

from argparse import ArgumentParser
from common import read_state, write_state, trace_step, STATUS_STARTED, STATUS_COMPLETED
import json


args = ArgumentParser()
args.add_argument("--start", type=str, nargs='?', help='Start a step, pass in step name')
args.add_argument("--complete", action="store_true")
args.add_argument(
    "--output", type=str, nargs="*", help="Output in the format key1=value1 ..."
)
args.add_argument(
    "--output-from-stdin",
    action="store_true",
)
args.add_argument("--err", type=str, required=False, help="Error message")
args.add_argument("--strict", action="store_true", help="Fail \"--complete\" if no current step open")
args = args.parse_args()


def get_output():
    if args.output_from_stdin:
        parsed = json.loads(sys.stdin.read())
        return parsed
    elif isinstance(args.output, list):
        obj = {}
        for item in args.output:
            if "=" not in item:
                raise ValueError(
                    f"Output argument {item} must be in the format key=value"
                )
            key, value = item.split("=", 1)
            obj[key] = value
        return obj
    elif args.output is None:
        return None
    else:
        raise AssertionError(f"wrong type?")


state = read_state()
step_name_to_complete = state["curr_step"]

if step_name_to_complete:
    trace_step(state["run_info"], step_name_to_complete, STATUS_COMPLETED, args.err, get_output())
    state["curr_step"] = None
    write_state(state)

if not step_name_to_complete and args.complete:
    if not args.strict:
        print("Warning: No step to mark as complete", file=sys.stderr, flush=True)
    else:
        raise RuntimeError("No step to mark as complete")

if args.start:
    step_name = args.start
    state["curr_step"] = step_name
    trace_step(state["run_info"], step_name, STATUS_STARTED)
    write_state(state)
