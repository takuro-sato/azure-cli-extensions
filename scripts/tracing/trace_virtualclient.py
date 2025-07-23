#!/usr/bin/env python3

from common import read_state, KUSTO_TABLE, conn, KustoClient, KUSTO_DATABASE
from argparse import ArgumentParser
import sys
import random
import time
import re

args = ArgumentParser()
args.add_argument("container_log_file", type=str)
args.add_argument("--dry-run", action="store_true")
args = args.parse_args()

state = read_state()
runId = state["run_info"]["UniqueRunId"]

cut_line = "------------[ metrics follow ]------------"
cut_line_2 = "------------[ metrics end ]------------"

metrics_csv = []
with open(args.container_log_file, "rt") as f:
    csv_started = False
    csv_line_count = 0
    for line in f:
        if line.endswith("\n"):
            line = line[:-1]
        if not line:
            continue
        if not csv_started:
            if cut_line in line:
                csv_started = True
        elif cut_line in line:
            # repeated output?
            metrics_csv = []
            csv_line_count = 0
        elif cut_line_2 in line:
            break
        elif csv_line_count == 0:
            csv_line_count += 1
            # do nothing to skip the header
        else:
            csv_line_count += 1
            # Check if output is in azcri format
            # 2025-01-30T12:49:25.7415657Z stdout|stderr F|P|F:P <csv_line>
            azcri_match = re.fullmatch(r"^[0-9\-TZ:.]+ (stdout|stderr) [FP:]+ (.+)$", line)
            if azcri_match:
                csv_line = azcri_match.group(2)
            else:
                csv_line = line.strip()
            metrics_csv.append(f"{runId},{csv_line}")

if not metrics_csv:
    print(f"No valid lines found in {args.container_log_file}", file=sys.stderr, flush=True)
    sys.exit(1)

print(f"Ingesting {len(metrics_csv)} lines from {args.container_log_file} into {KUSTO_TABLE}", file=sys.stderr, flush=True)

query_lines = [
    f".ingest inline into table {KUSTO_TABLE} with (format='csv') <|",
    *metrics_csv,
    ""
]
query_str = "\n".join(query_lines)

if args.dry_run:
    print(query_str)
    sys.exit(0)

nb_attempts = 0
max_attempts = 3
while True:
    try:
        client = KustoClient(conn)
        client.execute(KUSTO_DATABASE, query_str)
        break
    except Exception as e:
        nb_attempts += 1
        if nb_attempts >= max_attempts:
            raise
        else:
            print(f"Failed to ingest VirtualClient result: {e}", file=sys.stderr)
            wait_time = random.randint(10, 30)
            print(f"Retrying in {wait_time} seconds...", file=sys.stderr, flush=True)
            time.sleep(wait_time)
