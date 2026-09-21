param prefix string
param location string
param tags object

var addressSpace = '10.20.0.0/16'

// APIM (stv2, internal mode) needs its management port reachable from the ApiManagement
// service tag and the load balancer probe. Everything else stays on NSG defaults.
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${prefix}-apim-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'allow-apim-management'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'ApiManagement'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '3443'
        }
      }
      {
        name: 'allow-lb-probe'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: 'AzureLoadBalancer'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRange: '6390'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${prefix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [addressSpace]
    }
    subnets: [
      {
        name: 'aks'
        properties: {
          addressPrefix: '10.20.0.0/22'
        }
      }
      {
        name: 'apim'
        properties: {
          addressPrefix: '10.20.4.0/27'
          networkSecurityGroup: {
            id: apimNsg.id
          }
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.20.5.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

var zoneNames = {
  blob: 'privatelink.blob.${environment().suffixes.storage}'
  dfs: 'privatelink.dfs.${environment().suffixes.storage}'
  queue: 'privatelink.queue.${environment().suffixes.storage}'
  table: 'privatelink.table.${environment().suffixes.storage}'
  vault: 'privatelink.vaultcore.azure.net'
  kusto: 'privatelink.${location}.kusto.windows.net'
}

resource zones 'Microsoft.Network/privateDnsZones@2020-06-01' = [
  for z in items(zoneNames): {
    name: z.value
    location: 'global'
    tags: tags
  }
]

resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = [
  for (z, i) in items(zoneNames): {
    parent: zones[i]
    name: '${prefix}-link'
    location: 'global'
    properties: {
      registrationEnabled: false
      virtualNetwork: {
        id: vnet.id
      }
    }
  }
]

output vnetId string = vnet.id
output aksSubnetId string = vnet.properties.subnets[0].id
output apimSubnetId string = vnet.properties.subnets[1].id
output endpointSubnetId string = vnet.properties.subnets[2].id
// Built from names rather than the zones loop so callers can pick zones by key.
// Consumers take a dependency on this whole module, so the zones exist before any endpoint.
output zoneIds object = toObject(items(zoneNames), z => z.key, z => resourceId('Microsoft.Network/privateDnsZones', z.value))
