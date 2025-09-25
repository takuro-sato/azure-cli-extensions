#!/usr/bin/env python3

import os
import csv
import yaml

os.chdir(os.path.dirname(__file__))

def yaml_template(region: str, region_friendly: str, resource_group: str, aks_cluster_name: str) -> str:
  return f"""\
name: VN2 - {region_friendly}

permissions:
   id-token: write
   contents: read

on:
  schedule:
    - cron: '0 8 * * *'
  workflow_dispatch:

jobs:
  vn2-{region}:
    secrets: inherit
    uses: ./.github/workflows/vn2-region.yml
    with:
      location: {region}
      resource_group: {resource_group}
      aks_cluster_name: {aks_cluster_name}
"""

with open("aks-instances.csv", "rt") as f:
  reader = csv.DictReader(f)
  instances = list(reader)

for inst in instances:
  region = inst["location"]
  region_friendly = region
  resource_group = inst["resource_group"]
  aks_cluster_name = inst["aks_cluster_name"]
  file_path = f"../../.github/workflows/vn2-{region}.yml"

  if os.path.exists(file_path):
    with open(file_path, 'rt') as f:
      existing_content = f.read()
      yaml_parsed = yaml.safe_load(existing_content)
      name = yaml_parsed.get('name')
      if name and name.startswith("VN2 - "):
        region_friendly = name[6:]

  with open(file_path, 'wt') as f:
    content = yaml_template(region, region_friendly, resource_group, aks_cluster_name)
    f.write(content)
