#!/usr/bin/env python3

from argparse import ArgumentParser
import sys
from common import read_state, write_state, trace_step, STATUS_STARTED, STATUS_COMPLETED


args = ArgumentParser()
args.add_argument("--start", type=str, nargs='?', help='Start a step, pass in step name')
args.add_argument("--complete", action="store_true")
args.add_argument(
    "--output", type=str, nargs="*", help="Output in the format key=value"
)
args.add_argument("--err", type=str, required=False, help="Error message")
args = args.parse_args()


def get_output():
    obj = {}
    if isinstance(args.output, list):
        for item in args.output:
            if "=" not in item:
                raise ValueError(
                    f"Output argument {item} must be in the format key=value"
                )
            key, value = item.split("=")
            obj[key] = value
    elif args.output is None:
        return None
    else:
        raise AssertionError(f"wrong type?")
    return obj


state = read_state()

if args.complete or (args.start and state["curr_step"]):
    step_name = state["curr_step"]
    if not step_name:
        sys.stderr.write("No current step to complete\n")
        sys.stderr.flush()
        sys.exit(1)
    trace_step(state["run_info"], step_name, STATUS_COMPLETED, args.err, get_output())
    state["curr_step"] = None
    write_state(state)

if args.start:
    step_name = args.start
    state["curr_step"] = step_name
    trace_step(state["run_info"], step_name, STATUS_STARTED)
    write_state(state)
