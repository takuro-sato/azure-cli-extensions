#!/usr/bin/env python3

import os
import csv
import subprocess
import json

os.chdir(os.path.dirname(__file__))

try:
    with open("MAA-endpoints-raw.tsv", "rt") as f:
        reader = csv.DictReader(f, delimiter="\t")
        maa_data = [row for row in reader]
except FileNotFoundError:
    print("Go to MAA Info then copy the table to MAA-endpoints-raw.tsv")
    exit(1)

az_locations = subprocess.run(
    ["az", "account", "list-locations"],
    stdout=subprocess.PIPE,
    text=True,
    check=True,
).stdout
az_locations = json.loads(az_locations)
location_map = {loc["displayName"]: loc["name"] for loc in az_locations}

filtered = []

for d in maa_data:
    if d["Env"] in ["TEST", "PERF"]:
        continue
    if d["Region"] in location_map:
        d["Region"] = location_map[d["Region"]]
        filtered.append(d)
    else:
        fuzzy = d["Region"].lower().replace(" ", "")
        for display_name, loc_name in location_map.items():
            if fuzzy == display_name.lower().replace(" ", ""):
                print(f"Warning: fuzzy match {d['Region']} -> {loc_name}")
                d["Region"] = loc_name
                filtered.append(d)
                break
        else:
            fuzzy = set(d["Region"].lower().split(" "))
            for display_name, loc_name in location_map.items():
                if fuzzy == set(display_name.lower().split(" ")):
                    print(f"Warning: fuzzy match {d['Region']} -> {loc_name}")
                    d["Region"] = loc_name
                    filtered.append(d)
                    break
            else:
                print(f"Unknown region: {d['Region']} ({d['Env']} {d['DNS Name']})")
                filtered.append(d)

with open("MAA-endpoints.csv", "wt", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=maa_data[0].keys())
    writer.writeheader()
    writer.writerows(sorted(filtered, key=lambda x: (x['Region'].lower(), x['Env'] != 'PROD', x['Env'])))
