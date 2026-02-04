#!/usr/bin/env python3

import os
from os.path import join

regions = \
"""
australiacentral
australiacentral2
australiaeast
austriaeast
belgiumcentral
brazilsouth
brazilsoutheast
centralindia
centralus
centraluseuap
chilecentral
canadacentral
eastasia
eastus
eastus2
eastus2euap
francecentral
francesouth
germanywestcentral
indonesiacentral
israelcentral
italynorth
japaneast
japanwest
koreacentral
koreasouth
malaysiawest
newzealandnorth
northeurope
norwayeast
norwaywest
polandcentral
southafricanorth
southafricawest
southcentralus
southeastasia
southindia
swedencentral
switzerlandnorth
taiwannorth
uaenorth
uksouth
westeurope
westus
westus2
westus3
"""

regions = [r for r in regions.splitlines() if r]

for r in regions:
    path = f".github/workflows/basic-region-{r}.yml"
    if not os.path.exists(path):
        print(r)
