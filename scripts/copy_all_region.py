"""
Stashed one-off script - change before use!
"""

import glob
import os.path

regions = glob.glob('.github/workflows/region-*.yml')
for rf in regions:
  region_name = os.path.basename(rf).replace('region-', '').replace('.yml', '')
  old_path = f".github/workflows/region-{region_name}.yml"
  new_path = f".github/workflows/basic-region-{region_name}.yml"
  with open(old_path, 'rt') as f:
    content = f.read()
  content = content.replace("Region", "Region (Basic)")
  content = content.replace(old_path, new_path)
  content = content.replace(f"jobs:\n  {region_name}", f"jobs:\n  basic-{region_name}")
  content = content.replace("uses: ./.github/workflows/region.yml", "uses: ./.github/workflows/basic-region.yml")
  with open(new_path, 'wt') as f:
    f.write(content)
