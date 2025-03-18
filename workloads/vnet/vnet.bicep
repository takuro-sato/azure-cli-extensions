param location string
param ccePolicies object
param cpu int = 1
param memoryInGb int = 2

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    subnetIds: [{id: subnet.id}]
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.vnet
    }
    containers: [
      {
        name: 'ubuntu'
        properties: {
          image: 'quay.io/curl/curl:8.11.0'
          command: [
            'sh'
            '-c'
            '''
            ATTEMPTS=0
            TIMEOUT=200
            START_TS=$(date +%s)
            SECS_SINCE_START=0
            while [ $SECS_SINCE_START -lt $TIMEOUT ]; do
              ATTEMPTS=$((ATTEMPTS+1))
              SECS_SINCE_START=$(( $(date +%s) - $START_TS ))
              echo "Attempt $ATTEMPTS: $SECS_SINCE_START seconds since start"
              timeout -s INT 20s curl -sv http://example.com
              if [ $? -eq 0 ]; then
                SECS_SINCE_START=$(( $(date +%s) - $START_TS ))
                echo "It worked"
                echo "OUTPUT: {\"attempts\": $ATTEMPTS, \"first_success_exit_time\": $SECS_SINCE_START}"
                exit 0
              fi
              echo "Didn't work, trying without dependency on DNS"
              timeout -s INT 20s curl -sv http://1.1.1.1
              if [ $? -eq 0 ]; then
                echo "Hmm... that worked. DNS broken?"
                echo "Retrying..."
                continue
              fi
              echo "That still didn't work - outbound networking is broken."
              echo "Retrying in 5 seconds..."
              sleep 5
            done
            echo "ERROR: curl failed after $ATTEMPTS attempts, $TIMEOUT seconds"
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

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: '${deployment().name}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2021-02-01' = {
  parent: virtualNetwork
  name: '${deployment().name}-subnet'
  properties: {
    addressPrefix: '10.0.0.0/24'
    delegations: [
      {
        name: 'aciDelegation'
        properties: {
          serviceName: 'Microsoft.ContainerInstance/containerGroups'
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
