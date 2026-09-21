param prefix string
param location string
param tags object
param endpointSubnetId string
param zoneIds array
param collectorClientId string
param workspaceId string

@description('Dev SKU is fine for a demo. Use a Standard SKU with 2+ instances for anything real.')
param skuName string = 'Dev(No SLA)_Standard_E2a_v4'
param skuTier string = 'Basic'
param capacity int = 1

@description('Optional Entra group that gets read access (Viewer) to the telemetry database.')
param viewerGroupObjectId string = ''

resource cluster 'Microsoft.Kusto/clusters@2023-08-15' = {
  name: take('${replace(prefix, '-', '')}adx${uniqueString(resourceGroup().id)}', 22)
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuTier
    capacity: capacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publicNetworkAccess: 'Disabled'
    enableDiskEncryption: true
  }
}

resource db 'Microsoft.Kusto/clusters/databases@2023-08-15' = {
  parent: cluster
  name: 'telemetry'
  location: location
  kind: 'ReadWrite'
  properties: {
    hotCachePeriod: 'P14D'
    softDeletePeriod: 'P90D'
  }
}

resource tables 'Microsoft.Kusto/clusters/databases/scripts@2023-08-15' = {
  parent: db
  name: 'tables'
  properties: {
    #disable-next-line use-secure-value-for-secure-inputs // table DDL, nothing sensitive
    scriptContent: loadTextContent('../../adx/tables.kql')
    continueOnErrors: false
  }
}

resource functions 'Microsoft.Kusto/clusters/databases/scripts@2023-08-15' = {
  parent: db
  name: 'functions'
  properties: {
    #disable-next-line use-secure-value-for-secure-inputs // query functions, nothing sensitive
    scriptContent: loadTextContent('../../adx/functions.kql')
    continueOnErrors: false
  }
  dependsOn: [tables]
}

// The collector authenticates as the managed identity (App principal by client id).
resource ingestor 'Microsoft.Kusto/clusters/databases/principalAssignments@2023-08-15' = {
  parent: db
  name: 'collector-ingestor'
  properties: {
    principalId: collectorClientId
    principalType: 'App'
    role: 'Ingestor'
    tenantId: subscription().tenantId
  }
}

resource viewers 'Microsoft.Kusto/clusters/databases/principalAssignments@2023-08-15' = if (!empty(viewerGroupObjectId)) {
  parent: db
  name: 'sre-viewers'
  properties: {
    principalId: viewerGroupObjectId
    principalType: 'Group'
    role: 'Viewer'
    tenantId: subscription().tenantId
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: cluster
  name: 'audit'
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        categoryGroup: 'audit'
        enabled: true
      }
    ]
  }
}

module endpoint 'private-endpoint.bicep' = {
  name: 'pe-adx'
  params: {
    name: '${cluster.name}-pe'
    location: location
    tags: tags
    subnetId: endpointSubnetId
    targetId: cluster.id
    groupId: 'cluster'
    zoneIds: zoneIds
  }
}

output clusterUri string = cluster.properties.uri
