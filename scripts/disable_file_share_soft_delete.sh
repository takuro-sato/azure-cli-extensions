#!/usr/bin/env bash
# One-time script: disable Azure Files share soft delete on all storage
# accounts in the c-aci-dashboard resource group and in the MC_ resource
# groups for every AKS cluster listed in workloads/vn2/aks-instances.csv.
#
# Requires: az CLI, logged in, with the right subscription selected.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="${CSV_FILE:-$SCRIPT_DIR/../workloads/vn2/aks-instances.csv}"

disable_in_rg() {
    local rg="$1"
    if ! az group show --name "$rg" >/dev/null 2>&1; then
        echo "  [skip] resource group $rg does not exist"
        return
    fi
    mapfile -t accounts < <(az storage account list \
        --resource-group "$rg" \
        --query "[].name" -o tsv)
    if [[ ${#accounts[@]} -eq 0 ]]; then
        echo "  (no storage accounts)"
        return
    fi
    for acct in "${accounts[@]}"; do
        echo "  - $acct"
        az storage account file-service-properties update \
            --account-name "$acct" \
            --resource-group "$rg" \
            --enable-delete-retention false \
            --output none
    done
}

# Build the list of resource groups to process.
rgs=("c-aci-dashboard")

# Parse the CSV (skip header, dedupe).
mapfile -t aks_rows < <(tail -n +2 "$CSV_FILE" | awk -F, 'NF>=3 {print $1","$2}' | sort -u)

for row in "${aks_rows[@]}"; do
    rg="${row%%,*}"
    cluster="${row##*,}"
    # MC_ resource group naming: MC_<rg>_<cluster>_<location>
    location="$(az aks show --resource-group "$rg" --name "$cluster" \
        --query location -o tsv 2>/dev/null || true)"
    if [[ -z "$location" ]]; then
        echo "[warn] could not find AKS $cluster in $rg, skipping"
        continue
    fi
    rgs+=("MC_${rg}_${cluster}_${location}")
done

for rg in "${rgs[@]}"; do
    echo "== Resource group: $rg =="
    disable_in_rg "$rg"
done

echo "Done."
