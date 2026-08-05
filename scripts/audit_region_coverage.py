#!/usr/bin/env python3

import argparse
import csv
import subprocess
from html.parser import HTMLParser
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORKFLOWS = ROOT / ".github" / "workflows"
WIKI_EXTRACT = ROOT / "extract-from-wiki.txt"
VN2_CLUSTERS = ROOT / "workloads" / "vn2" / "aks-instances.csv"


class AvailabilityParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.section = None
        self.in_heading = False
        self.in_cell = False
        self.heading = ""
        self.cell = ""
        self.row = []
        self.rows = {"caci": [], "vn2": [], "big": []}

    def handle_starttag(self, tag, attrs):
        if tag == "h1":
            self.in_heading = True
            self.heading = ""
        elif tag == "tr":
            self.row = []
        elif tag == "td":
            self.in_cell = True
            self.cell = ""

    def handle_data(self, data):
        if self.in_heading:
            self.heading += data
        if self.in_cell:
            self.cell += data

    def handle_endtag(self, tag):
        if tag == "h1":
            self.in_heading = False
            if "C-ACI Region Availability" in self.heading:
                self.section = "caci"
            elif "Confidential-VN2" in self.heading:
                self.section = "vn2"
            elif "Confidential BigContainers" in self.heading:
                self.section = "big"
            else:
                self.section = None
        elif tag == "td":
            self.in_cell = False
            self.row.append(self.cell.strip())
        elif tag == "tr" and self.section and self.row:
            self.rows[self.section].append(self.row)


def parse_availability():
    parser = AvailabilityParser()
    parser.feed(WIKI_EXTRACT.read_text(encoding="utf-8"))

    expected_widths = {"caci": 10, "vn2": 6, "big": 14}
    for section, width in expected_widths.items():
        invalid = [row for row in parser.rows[section] if len(row) != width]
        if invalid:
            raise ValueError(f"Unexpected {section} row widths: {invalid}")

    caci = {row[0]: row[2:] for row in parser.rows["caci"]}
    caci["westcentralus"] = ["yes", "", "", "", "", "", "", ""]
    for region in ("eastus2euap", "germanynorth"):
        caci[region] = ["yes", "", "", "", "yes", "", "", ""]
    vn2 = {row[0]: row[2:] for row in parser.rows["vn2"]}
    big = {row[0]: row[2:] for row in parser.rows["big"]}
    return caci, vn2, big


def workflow_regions(prefix):
    regions = set()
    for path in WORKFLOWS.glob(f"{prefix}-*.yml"):
        region = path.stem.removeprefix(f"{prefix}-")
        if region not in {"region", "cwcow"} and not region.startswith("cwcow-"):
            regions.add(region)
    return regions


def variable_regions(name):
    result = subprocess.run(
        ["gh", "variable", "get", name],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return {region for region in result.stdout.strip().strip(",").split(",") if region}


def csv_regions():
    with VN2_CLUSTERS.open(newline="", encoding="utf-8") as stream:
        rows = list(csv.DictReader(stream))
    locations = [row["location"] for row in rows]
    clusters = [row["aks_cluster_name"] for row in rows]
    return set(locations), duplicates(locations), duplicates(clusters)


def duplicates(values):
    return sorted({value for value in values if values.count(value) > 1})


def report_difference(label, expected, actual):
    missing = sorted(expected - actual)
    extra = sorted(actual - expected)
    status = "OK" if not missing and not extra else "CHANGE"
    print(f"{label}: {status}")
    print(f"  expected: ,{','.join(sorted(expected))},")
    print(f"  add: {','.join(missing) or '<none>'}")
    print(f"  remove: {','.join(extra) or '<none>'}")
    return bool(missing or extra)


def main():
    argument_parser = argparse.ArgumentParser()
    argument_parser.add_argument(
        "--strict", action="store_true", help="Exit nonzero when differences are found"
    )
    args = argument_parser.parse_args()

    caci, vn2, big = parse_availability()
    caci_regions = set(caci)
    non_vnet_regions = {region for region, cells in caci.items() if any(cells[4:8])}
    only_zonal_vnet_regions = {
        region for region, cells in caci.items() if not cells[0] and any(cells[1:4])
    }
    vnet_only_regions = {
        region
        for region, cells in caci.items()
        if cells[0] and not any(cells[4:8])
    }
    zoned_regions = {
        region for region, cells in caci.items() if all(cells[1:4])
    }
    zone_1_2_regions = {
        region
        for region, cells in caci.items()
        if cells[1] and cells[2] and not cells[3]
    }
    vn2_regions = set(vn2)
    big_aci_regions = {
        region for region, cells in big.items() if cells[4]
    }
    big_vn2_regions = {
        region for region, cells in big.items() if cells[8]
    }

    differences = []
    print("Workflow and cluster coverage")
    differences.append(
        report_difference("basic-region workflows", caci_regions, workflow_regions("basic-region"))
    )
    differences.append(
        report_difference("region workflows", non_vnet_regions, workflow_regions("region"))
    )
    differences.append(
        report_difference(
            "attestation workflows", non_vnet_regions, workflow_regions("attestation")
        )
    )
    differences.append(
        report_difference("vn2 workflows", vn2_regions, workflow_regions("vn2"))
    )
    locations, duplicate_locations, duplicate_clusters = csv_regions()
    differences.append(report_difference("VN2 CSV locations", vn2_regions, locations))
    print(f"VN2 CSV duplicate locations: {','.join(duplicate_locations) or '<none>'}")
    print(f"VN2 CSV duplicate clusters: {','.join(duplicate_clusters) or '<none>'}")
    differences.extend([bool(duplicate_locations), bool(duplicate_clusters)])

    print("\nGitHub variables")
    expected_variables = {
        "ACI_ONLY_ZONAL_VNET_REGIONS": only_zonal_vnet_regions,
        "ACI_VNET_ONLY_REGIONS": vnet_only_regions,
        "ACI_ZONED_REGIONS": zoned_regions,
        "ACI_ZONE_1_2_REGIONS": zone_1_2_regions,
        "ACI_BIG_CONTAINERS_REGION": big_aci_regions,
        "VN2_BIG_CONTAINERS_REGIONS": big_vn2_regions,
    }
    for name, expected in expected_variables.items():
        differences.append(report_difference(name, expected, variable_regions(name)))

    print(
        "ACI_BIG_CONTAINERS_REGION_8CPU_ONLY: NOT DERIVABLE "
        "(the source has no 8-CPU-only marker)"
    )
    print(
        "REGIONS_WITH_PROBLEMATIC_PUBLIC_IP: NOT DERIVABLE "
        "(the source has no public-IP health data)"
    )

    if args.strict and any(differences):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
