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
          environmentVariables: [
            {
              name: 'VN2_THIM_ENDPOINT'
              value: '===VIRTUALNODE2.CC.THIM.ENDPOINT==='
            }
          ]
          command: [
            'sh'
            '-c'
            '''
            set +e
            has_error=0
            echo "env:"
            env
            echo "Provided UVM_SECURITY_CONTEXT_DIR=$UVM_SECURITY_CONTEXT_DIR"
            if [ -z "$UVM_SECURITY_CONTEXT_DIR" ]; then
              UVM_SECURITY_CONTEXT_DIR=$(echo /security-context-*)
            fi
            echo ls /security*:
            ls -la / | grep security
            if [ ! -d "$UVM_SECURITY_CONTEXT_DIR" ]; then
              echo "ERROR: Security context directory $UVM_SECURITY_CONTEXT_DIR not found"
              has_error=1
            fi
            ls -la $UVM_SECURITY_CONTEXT_DIR
            for file in host-amd-cert-base64 reference-info-base64 security-policy-base64; do
              if [ ! -f "$UVM_SECURITY_CONTEXT_DIR/$file" ]; then
                echo "ERROR: $UVM_SECURITY_CONTEXT_DIR/$file not found"
                has_error=1
              fi
            done

            usable_certification_url=""

            if [ -z "$Fabric_NodeIPOrFQDN" ]; then
              echo "(no Fabric_NodeIPOrFQDN env)"
            else
              usable_certification_url="http://$Fabric_NodeIPOrFQDN:2377/metadata/THIM/amd/certification"
              echo "THIM certification via Fabric_NodeIPOrFQDN:"
              timeout 10s curl --fail-with-body "$usable_certification_url" -H "Metadata: true"
              status=$?
              echo
              if [ $status -ne 0 ]; then
                echo "ERROR: Failed to fetch certification from THIM via Fabric_NodeIPOrFQDN"
                has_error=1
              fi
            fi

            if [ -z "$VN2_THIM_ENDPOINT" ]; then
              echo "(no VN2_THIM_ENDPOINT env)"
            elif [ "$VN2_THIM_ENDPOINT" = "===VIRTUALNODE2.CC.THIM.ENDPOINT===" ]; then
              echo "(VN2_THIM_ENDPOINT env not replaced)"
            else
              usable_certification_url="$VN2_THIM_ENDPOINT"
              echo "THIM certification via VN2_THIM_ENDPOINT:"
              timeout 10s curl --fail-with-body "$usable_certification_url" -H "Metadata: true"
              status=$?
              echo
              if [ $status -ne 0 ]; then
                echo "ERROR: Failed to fetch certification from THIM via VN2_THIM_ENDPOINT"
                has_error=1
              fi
            fi

            if [ -z "$usable_certification_url" ]; then
              echo "ERROR: No usable environment variable for THIM endpoint"
              has_error=1
            fi

            echo "SNP report:"
            get-snp-report
            status=$?
            echo # the above doesn't print a newline
            if [ $status -ne 0 ]; then
              echo "ERROR: Failed to get SNP report"
              has_error=1
            fi
            if [ $has_error -ne 0 ]; then
              echo "Exiting due to errors"
              exit 1
            fi
            nb_repeat_errors=0
            while :; do
              echo "Doing repeat check: $(date)"
              echo "URL: $usable_certification_url"
              timeout 10s curl --fail "$usable_certification_url" -H "Metadata: true" -v > /dev/null 2>err.log
              if [ $? -ne 0 ]; then
                echo "ERROR: Failed to fetch certification from THIM via $usable_certification_url:"
                cat err.log
                nb_repeat_errors=$((nb_repeat_errors + 1))
                echo "$nb_repeat_errors errors encountered now"
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
