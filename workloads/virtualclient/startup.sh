#!/usr/bin/env bash

if [[ "$PROFILE_NAME" == "-" || "$PROFILE_NAME" == "*" ]]; then
  export PROFILE_NAME=""
fi

if [ -z "$PROFILE_NAME" ]; then
  . /run_profiles.sh
  if ! [[ ${#run_profiles[@]} -gt 0 ]]; then
    echo "ERROR: No profiles selected by run_profiles.sh"
    exit 1
  fi
else
  run_profiles=($PROFILE_NAME)
fi

export PATH=$PATH:/opt/virtualclient

RUN_LOG=/run.log
echo > $RUN_LOG

has_error=0
for profile in "${run_profiles[@]}"; do
  VirtualClient --profile=$profile --profile=MONITORS-NONE.json --packages=https://virtualclient.blob.core.windows.net/packages --iterations=1 --ltf --log-level=Trace 2>&1 | tee -a $RUN_LOG
  status=$?
  if [ $status -ne 0 ]; then
    echo "ERROR: $profile exited with code $status" | tee -a $RUN_LOG
    has_error=1
  fi
done

echo "------------[ metrics follow ]------------" | tee -a $RUN_LOG
cat /opt/virtualclient/logs/metrics.csv | tee -a $RUN_LOG
if [ $? -ne 0 ]; then
  echo "ERROR: metrics.csv not found" | tee -a $RUN_LOG
  has_error=1
fi
echo | tee -a $RUN_LOG
echo "------------[ metrics end ]------------" | tee -a $RUN_LOG
echo | tee -a $RUN_LOG

sleep 20

exit $has_error
