#!/usr/bin/python3

from typing import List

import os
import subprocess
from subprocess import Popen
import os.path
import csv
import sys

cmd_args = sys.argv[1:]

# resource_group,aks_cluster_name,location
RESOURCE_GROUP_PLACEHOLDER = "resource_group"
AKS_CLUSTER_NAME_PLACEHOLDER = "aks_cluster_name"
LOCATION_PLACEHOLDER = "location"

if AKS_CLUSTER_NAME_PLACEHOLDER not in cmd_args:
    print(
        f"Usage: {sys.argv[0]} anything ... {AKS_CLUSTER_NAME_PLACEHOLDER} [ {RESOURCE_GROUP_PLACEHOLDER} ] [ {LOCATION_PLACEHOLDER} ] (in any order)"
    )
    sys.exit(1)


def sub_cmd_args(resource_group, aks_cluster_name, location):
    res = []
    for arg in cmd_args:
        if arg == AKS_CLUSTER_NAME_PLACEHOLDER:
            res.append(aks_cluster_name)
        elif arg == RESOURCE_GROUP_PLACEHOLDER:
            res.append(resource_group)
        elif arg == LOCATION_PLACEHOLDER:
            res.append(location)
        else:
            res.append(arg)
    return res


aks_csv_path = os.path.join(os.path.dirname(__file__), "aks-instances.csv")
aks_deployments = []
with open(aks_csv_path, "rt") as f:
    dict_reader = csv.DictReader(f)
    for row in dict_reader:
        aks_deployments.append(row)

cmds_to_run = []
print("Commands to run (all in parallel):")

for aks in aks_deployments:
    resource_group = aks["resource_group"]
    cluster_name = aks["aks_cluster_name"]
    location = aks["location"]

    cmd = sub_cmd_args(resource_group, cluster_name, location)
    cmds_to_run.append(cmd)
    print(f" {' '.join(cmd)}")

print("Confirm? y/n >", end="", flush=True)
confirm = input().strip()
if confirm != "y":
    print("Aborting")
    sys.exit(1)

processes: List[Popen] = []
for cmd in cmds_to_run:
    process = subprocess.Popen(cmd, stdin=subprocess.DEVNULL)
    processes.append(process)

has_fail = False

for process in processes:
    process.wait()
    if process.returncode != 0:
        arg_joined = " ".join(process.args)
        print(f"{arg_joined}: failed with code {process.returncode}")
        has_fail = True

if has_fail:
    sys.exit(1)

print("All commands completed successfully.")
