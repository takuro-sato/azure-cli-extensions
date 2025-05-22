param vnetName string
param location string = resourceGroup().location

resource wafNsg 'Microsoft.Network/networkSecurityGroups@2019-11-01' = {
  name: '${vnetName}-waf-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'appgwrequired'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '60000-65535'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1000
          direction: 'Inbound'
        }
      }
      {
        name: 'anyout'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '*'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1001
          direction: 'Outbound'
        }
      }
      {
        name: 'httpin'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 1002
          direction: 'Inbound'
        }
      }
    ]
  }
}
