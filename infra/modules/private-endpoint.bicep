param name string
param location string
param tags object
param subnetId string
param targetId string
param groupId string
param zoneIds array

resource pe 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: name
        properties: {
          privateLinkServiceId: targetId
          groupIds: [groupId]
        }
      }
    ]
  }
}

resource dns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-09-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      for (zoneId, i) in zoneIds: {
        name: 'zone-${i}'
        properties: {
          privateDnsZoneId: zoneId
        }
      }
    ]
  }
}
