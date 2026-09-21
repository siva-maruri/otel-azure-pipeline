param prefix string
param location string
param tags object
param endpointSubnetId string
param blobZoneId string
param dfsZoneId string
param collectorPrincipalId string
param workspaceId string

// Storage Blob Data Contributor
var blobContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource account 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take('${replace(prefix, '-', '')}archive${uniqueString(resourceGroup().id)}', 24)
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_ZRS'
  }
  properties: {
    isHnsEnabled: true
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: account
  name: 'default'
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [
  for c in ['raw-traces', 'raw-logs', 'raw-metrics']: {
    parent: blobService
    name: c
  }
]

// Raw OTLP is only read for replays and investigations, so it moves to cheaper tiers fast.
resource lifecycle 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: account
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'tier-raw-telemetry'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['raw-traces/', 'raw-logs/', 'raw-metrics/']
            }
            actions: {
              baseBlob: {
                tierToCool: {
                  daysAfterModificationGreaterThan: 30
                }
                tierToArchive: {
                  daysAfterModificationGreaterThan: 180
                }
                delete: {
                  daysAfterModificationGreaterThan: 365
                }
              }
            }
          }
        }
      ]
    }
  }
}

resource collectorCanWrite 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: account
  name: guid(account.id, collectorPrincipalId, blobContributorRoleId)
  properties: {
    principalId: collectorPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributorRoleId)
  }
}

resource blobDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: blobService
  name: 'audit'
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'StorageRead'
        enabled: true
      }
      {
        category: 'StorageWrite'
        enabled: true
      }
      {
        category: 'StorageDelete'
        enabled: true
      }
    ]
  }
}

module blobEndpoint 'private-endpoint.bicep' = {
  name: 'pe-archive-blob'
  params: {
    name: '${account.name}-blob-pe'
    location: location
    tags: tags
    subnetId: endpointSubnetId
    targetId: account.id
    groupId: 'blob'
    zoneIds: [blobZoneId]
  }
}

module dfsEndpoint 'private-endpoint.bicep' = {
  name: 'pe-archive-dfs'
  params: {
    name: '${account.name}-dfs-pe'
    location: location
    tags: tags
    subnetId: endpointSubnetId
    targetId: account.id
    groupId: 'dfs'
    zoneIds: [dfsZoneId]
  }
}

output blobUrl string = account.properties.primaryEndpoints.blob
