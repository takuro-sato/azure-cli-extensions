param location string
param tag string
param ccePolicies object

param cpu int = 1
param memoryInGb int = 2

param managedIDGroup string = resourceGroup().name
param managedIDName string = ''

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  identity: !empty(managedIDName)
    ? {
        type: 'UserAssigned'
        userAssignedIdentities: {
          '${resourceId(managedIDGroup, 'Microsoft.ManagedIdentity/userAssignedIdentities', managedIDName)}': {}
        }
      }
    : {
        type: 'None'
      }
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.thim
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: 'mcr.microsoft.com/aci/skr:${empty(tag) ? 'latest': tag}'
          resources: {
            requests: {
              memoryInGB: memoryInGb
              cpu: cpu
            }
          }
          command: [
            'sh'
            '-c'
            '''
            set -e
            echo "Provided UVM_SECURITY_CONTEXT_DIR=$UVM_SECURITY_CONTEXT_DIR"
            if [ -z "$UVM_SECURITY_CONTEXT_DIR" ]; then
              UVM_SECURITY_CONTEXT_DIR=$(echo /security-context-*)
            fi
            echo ls /security*:
            ls -la / | grep security
            if [ ! -d "$UVM_SECURITY_CONTEXT_DIR" ]; then
              echo "ERROR: Security context directory $UVM_SECURITY_CONTEXT_DIR not found"
              exit 1
            fi
            ls -la $UVM_SECURITY_CONTEXT_DIR
            for file in host-amd-cert-base64 reference-info-base64 security-policy-base64; do
              if [ ! -f "$UVM_SECURITY_CONTEXT_DIR/$file" ]; then
                echo "ERROR: $UVM_SECURITY_CONTEXT_DIR/$file not found"
                exit 1
              fi
            done
            echo "THIM certification via Fabric_NodeIPOrFQDN:"
            timeout 10s curl --fail-with-body "http://$Fabric_NodeIPOrFQDN:2377/metadata/THIM/amd/certification" -H "Metadata: true"
            status=$?
            echo
            if [ $status -ne 0 ]; then
              echo "ERROR: Failed to fetch certification from THIM via Fabric_NodeIPOrFQDN"
              exit 1
            fi
            while :; do
              echo "Doing repeat check: $(date)"
              timeout 10s curl --fail "http://$Fabric_NodeIPOrFQDN:2377/metadata/THIM/amd/certification" -H "Metadata: true" -v > /dev/null 2>err.log
              if [ $? -ne 0 ]; then
                echo "ERROR: Failed to fetch certification from THIM via Fabric_NodeIPOrFQDN:"
                cat err.log
                exit 1
              fi
              sleep 5
            done
            '''
          ]
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
