param location string
param tag string
param ccePolicies object

param cpu int = 1
param memoryInGb int = 4

resource containerGroup 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: deployment().name
  location: location
  properties: {
    osType: 'Linux'
    sku: 'Confidential'
    restartPolicy: 'Never'
    confidentialComputeProperties: {
      ccePolicy: ccePolicies.attestation
    }
    containers: [
      {
        name: 'primary'
        properties: {
          image: 'quay.io/curl/curl:8.11.0'
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
            timeout 30 sh -c 'until curl -s http://localhost:8080/status > /dev/null 2>&1; do sleep 1; done'
            curl "http://localhost:8080/attest/maa" \
              -s \
              -X POST \
              -H "Content-Type: application/json" \
              -d '{
                "maa_endpoint": "cacidashboard.weu.attest.azure.net",
                "runtime_data": "'$(echo '{
                  "keys": [
                    {
                      "key_ops": ["encrypt"],
                      "kid": "example-key",
                      "kty": "oct-HSM",
                      "k": "example"
                    }
                  ]
                }' | base64 -w 0)'"
              }'
            '''
          ]
        }
      }
      {
        name: 'attestation'
        properties: {
          image: 'mcr.microsoft.com/aci/skr:${empty(tag) ? 'latest': tag}'
          ports: [
            {
              protocol: 'TCP'
              port: 8080
            }
          ]
          resources: {
            requests: {
              memoryInGB: 4
              cpu: 1
            }
          }
        }
      }
    ]
  }
}

output ids array = [containerGroup.id]
