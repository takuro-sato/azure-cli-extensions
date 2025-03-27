#!/usr/bin/python3

import os
import subprocess
import os.path
import csv

aks_csv_path = os.path.join(os.path.dirname(__file__), 'aks-instances.csv')
script_path = os.path.join(os.path.dirname(__file__), 'upgrade-aks.sh')
aks_deployments = []
with open(aks_csv_path, 'rt') as f:
    dict_reader = csv.DictReader(f)
    for row in dict_reader:
        aks_deployments.append(row)

for aks in aks_deployments:
    resource_group = aks['resource_group']
    cluster_name = aks['aks_cluster_name']
    _location = aks['location']

    cmd = [
        script_path,
        resource_group,
        cluster_name
    ]
    print(f"Running command: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)
