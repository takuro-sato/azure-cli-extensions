#!/usr/bin/env python3

"""
Extract lines containing "ERROR:" and "OUTPUT:" from the a container log file,
and trace appropriately.
"""

import subprocess
import os
import sys
import json
from argparse import ArgumentParser, FileType
from typing import TextIO

args = ArgumentParser(prog=sys.argv[0])
args.add_argument("container_log_file", type=FileType("rt"), help="File containing container output to parse")
args.add_argument(
    "--must-have-output", action="store_true", help="Fail if no OUTPUT found"
)
args.add_argument(
    "--fail-on-error", action="store_true", help="Exit with non-zero code if any ERROR found"
)
args.add_argument(
    "--error-count-threshold", type=int, default=1, help="At least this many errors must be found in output for the step to trace as failed"
)
args.add_argument(
    "--write-output-to", type=FileType("wt"), required=False, default=None, help="Extract output to file"
)
args = args.parse_args()

out_file: TextIO = args.container_log_file
write_output_to: TextIO = args.write_output_to
must_have_output = args.must_have_output
fail_on_error = args.fail_on_error
error_count_threshold = args.error_count_threshold
if error_count_threshold <= 0:
    raise ValueError("error-count-threshold must be at least 1")

trace_step_py = os.path.join(os.path.dirname(__file__), "tracing", "trace_step.py")

subprocess.run([trace_step_py, "--start", "Parse container output"], check=True)

err_msgs = []
output = {}
output_seen = False


def fail(msg: str):
    print(f"Error: {msg}", flush=True)
    subprocess.run(
        [
            trace_step_py,
            "--complete",
            "--strict",
            "--err",
            msg,
        ]
    )
    sys.exit(1)


for line in out_file:
    error_prefix = "ERROR:"
    err_idx = line.find(error_prefix)
    if err_idx >= 0:
        err_msg = line[err_idx + len(error_prefix) :].strip()
        err_msgs.append(err_msg)
        print(f"\x1b[31;1mError found: {err_msg}\x1b[0m", flush=True)
    output_prefix = "OUTPUT:"
    output_idx = line.find(output_prefix)
    if output_idx >= 0:
        output_msg = line[output_idx + len(output_prefix) :].strip()
        print(f"Output found: {output_msg}", flush=True)
        try:
            this_output = json.loads(output_msg)
            if not isinstance(this_output, dict):
                fail(f"OUTPUT is not a JSON object: {output_msg}")
            output.update(this_output)
            output_seen = True
        except json.JSONDecodeError as e:
            fail(f"Failed to decode JSON in OUTPUT: {output_msg}")

out_file.close()

output["error_count"] = len(err_msgs)
output["errors"] = err_msgs
args = [trace_step_py, "--complete", "--strict", "--output-from-stdin"]
if len(err_msgs) >= error_count_threshold:
    args.append("--err")
    args.append("\n".join(err_msgs))
elif not output_seen and must_have_output:
    fail("No OUTPUT or ERROR found in container output.\nContainer execution failed?")

if write_output_to and output_seen:
    write_output_to.write(json.dumps(output, indent=2))
    write_output_to.close()

output_str = json.dumps(output, indent=2)
subprocess.run(args, input=output_str.encode(), check=True)

if fail_on_error and len(err_msgs) >= error_count_threshold:
    print("Exiting with failure due to ERRORs in container output", flush=True)
    sys.exit(1)
