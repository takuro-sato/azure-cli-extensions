#!/usr/bin/env bash
set -e

./scripts/tracing/trace_step.py --start 'Print info'
c-aci-testing vm exec --deployment-name $DEPLOYMENT_NAME '
  Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" > C:\info.txt
  echo "" >> C:\info.txt
  echo "CPU model name from host:" >> C:\info.txt
  (Get-ItemProperty -Path "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0" -Name ProcessorNameString).ProcessorNameString >> C:\info.txt
  Set-Alias -Name shimdiag -Value C:\ContainerPlat\shimdiag.exe
  echo "uname:" >> C:\info.txt
  shimdiag exec (shimdiag list)[0] uname -a >> C:\info.txt
  echo "cpuinfo:" >> C:\info.txt
  shimdiag exec (shimdiag list)[0] cat /proc/cpuinfo >> C:\info.txt
  echo "snp-report:" >> C:\info.txt
  shimdiag exec (shimdiag list)[0] snp-report -verbose >> C:\info.txt
'
c-aci-testing vm cat --deployment-name $DEPLOYMENT_NAME 'C:\info.txt' | tee info.txt
cat info.txt | jq -R -s '{info: .}' | ./scripts/tracing/trace_step.py --complete --strict --output-from-stdin
