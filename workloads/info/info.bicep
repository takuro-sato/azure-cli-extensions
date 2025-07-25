param location string
param ccePolicies object

param zone string
param useVnet bool

param cpu int = 1
param memoryInGb int = 2

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = {
  name: 'aci-long-lived-vnet-${location}'
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' existing = {
  parent: virtualNetwork
  name: 'acisubnet'
}

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  zones: empty(zone)
    ? null
    : [
        // Despite this being a "zones" property, ACI only supports one availability zone for a container group resource.
        zone
      ]
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    subnetIds: useVnet ? [{ id: subnet.id }] : []
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.info
    }
    containers: [
      {
        name: 'ubuntu'
        properties: {
          image: 'mcr.microsoft.com/mirror/docker/library/ubuntu:24.04'
          command: [
            'bash'
            '-c'
            '''
            set -e
            uname -a
            dmesg | grep "Kernel command line"
            dmesg | grep "Hyper-V: Host Build"
            echo Reference info SHA256SUM: $(base64 -d < /security-context-*/reference-info-base64 | sha256sum)
            cat /proc/cpuinfo
            echo Building snp-report binary...
            set +e
            ( apt-get update -y && \
              apt-get install -y git make gcc libc-dev ) > apt.log 2>&1
            if [ $? -ne 0 ]; then
              cat apt.log
              exit 1
            fi
            set -e
            git clone -q --branch main --depth 1 --single-branch 'https://github.com/microsoft/confidential-sidecar-containers.git' skr
            cd skr/tools/get-snp-report
            make
            cp ./bin/* /usr/local/bin/
            echo "raw report:"
            get-snp-report
            echo
            echo "snp-report:"
            verbose-report
            '''
          ]
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
