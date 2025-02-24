#!/usr/bin/env bash

set -ex

if [ ! -d /opt/virtualclient ]; then
  # example: ubuntu
  declare os_distro=$(if command -v lsb_release &> /dev/null; then lsb_release -is | tr '[:upper:]' '[:lower:]' ; else grep -oP '(?<=^ID=).+' /etc/os-release ; fi)
  # example: 20.04
  declare os_version=$(if command -v lsb_release &> /dev/null; then lsb_release -rs; else grep -oP '(?<=^VERSION_ID=).+' /etc/os-release | tr -d '"'; fi)
  # Add Microsoft deb repo
  curl -sSL -O https://packages.microsoft.com/config/$os_distro/$os_version/packages-microsoft-prod.deb
  dpkg -i packages-microsoft-prod.deb
  rm packages-microsoft-prod.deb
  apt-get update
  apt-get install virtualclient
else
  export PATH=$PATH:/opt/virtualclient
fi

. /run_profiles.sh
for profile in "${run_profiles[@]}"; do
  VirtualClient --profile=$profile --profile=MONITORS-NONE.json --dependencies --packages=https://virtualclient.blob.core.windows.net/packages
done
