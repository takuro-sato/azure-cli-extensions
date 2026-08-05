---
name: add-region
description: "Add or audit regional C-ACI and C-VN2 test coverage. Use when asked to add a region, add regional workflows, reconcile the region availability matrix, add VN2 cluster inventory rows, or update regional test badges. Covers basic-region, region, attestation, VN2 workflow, aks-instances.csv, and README/MORE-TESTS requirements."
---

# Add regional test coverage

Use the current C-ACI and C-VN2 availability matrix as the source of truth. Region identifiers must be the lowercase ARM region names used in workflow filename suffixes and the VN2 CSV `location` column.

## 1. Determine required coverage

For each region in the matrix:

- C-ACI support requires `.github/workflows/basic-region-<region>.yml`.
- Non-VNet C-ACI support also requires `.github/workflows/region-<region>.yml` and `.github/workflows/attestation-<region>.yml`.
- C-VN2 support requires `.github/workflows/vn2-<region>.yml`, even when the region does not support C-ACI.
- C-VN2 support also requires exactly one row in `workloads/vn2/aks-instances.csv`.

Ignore shared implementations such as `basic-region.yml`, `region.yml`, and `vn2-region.yml`, and ignore C-WCOW-specific wrappers when comparing per-region coverage.

## 2. Add C-ACI wrappers

Copy the closest existing regional wrapper and replace every occurrence of its region. Keep the filename, pull-request path, job ID, `location`, and display name consistent.

- Basic: copy `.github/workflows/basic-region-<nearby-region>.yml`.
- Full non-VNet suite: copy `.github/workflows/region-<nearby-region>.yml`.
- Attestation: copy `.github/workflows/attestation-<nearby-region>.yml`; it should call `workload-attestation.yml` with `policy_type: allow_all` and `test_schedule: gh-hourly`.

Schedules are managed by `scripts/spread_out_schedules.py`. New wrappers may use this placeholder:

```yaml
on:
  schedule:
    - cron: '15 19 * * *'  # managed by scripts/spread_out_schedules.py
```

## 3. Add a VN2 wrapper and cluster

Create `.github/workflows/vn2-<region>.yml` from an existing VN2 regional wrapper. It must call `vn2-region.yml` with:

```yaml
with:
  location: <region>
  resource_group: c-aci-vn2
  aks_cluster_name: vn2-aks-<region>
```

Add the matching cluster to `workloads/vn2/aks-instances.csv`, preserving alphabetical order:

```csv
c-aci-vn2,vn2-aks-<region>,<region>
```

The deployment script creates the cluster later; adding regional coverage does not require deploying it immediately.

## 4. Add test links

- Add `basic-region` and `attestation` workflow badges to `README.md` in their existing sections.
- Add VN2 workflow badges to the `Deployment with VN2` section of `MORE-TESTS.md`.
- Follow the existing badge URL format and keep entries ordered by display name.

## 5. Validate

- Run `python3 scripts/audit_region_coverage.py` to parse the HTML availability tables and compare them with workflows, VN2 clusters, and live GitHub variables. Use `--strict` when differences should fail validation.
- Parse every added workflow as YAML.
- Verify each workflow's filename, pull-request path, job ID, `location`, and cluster name use the same ARM region name.
- Compare C-VN2 workflow suffixes with unique CSV locations in both directions; there must be no supported region missing from either set.
- Check `aks-instances.csv` for duplicate locations and cluster names.
- Verify every new badge target exists under `.github/workflows/`.
- Run `git diff --check` over all changed files.
