targetScope = 'resourceGroup'

@description('Short prefix for resource names, e.g. "otelp".')
@minLength(3)
@maxLength(10)
param prefix string

param location string = resourceGroup().location

@description('Application ID URI OTLP senders request tokens for, e.g. api://otlp-ingest.')
param otlpAudience string

param apimPublisherEmail string
param apimPublisherName string = 'Telemetry platform'

@description('Where collector alerts are emailed.')
param alertEmail string

param aksNodeCount int = 3
@description('Upper bound for node autoscaling.')
param aksNodeMaxCount int = 6
param aksNodeVmSize string = 'Standard_D4ds_v5'

@description('Static internal IP for the router service. Must sit inside the AKS subnet (10.20.0.0/22).')
param routerIlbIp string = '10.20.3.250'

@description('Optional Entra group object id given read access to the ADX database.')
param adxViewerGroupObjectId string = ''

// Defaults keep a demo affordable. For production, e.g.:
//   adxSkuName = 'Standard_E8ads_v5', adxSkuTier = 'Standard', adxCapacity = 2
//   apimSkuName = 'Premium', apimCapacity = 1 (add zones for an SLA)
param adxSkuName string = 'Dev(No SLA)_Standard_E2a_v4'
param adxSkuTier string = 'Basic'
param adxCapacity int = 1

@allowed(['Developer', 'Premium'])
param apimSkuName string = 'Developer'
param apimCapacity int = 1

var tags = {
  workload: 'otel-pipeline'
}

module network 'modules/network.bicep' = {
  name: 'network'
  params: {
    prefix: prefix
    location: location
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    prefix: prefix
    location: location
    tags: tags
  }
}

resource collectorIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${prefix}-otel-gateway'
  location: location
  tags: tags
}

module aks 'modules/aks.bicep' = {
  name: 'aks'
  params: {
    prefix: prefix
    location: location
    tags: tags
    subnetId: network.outputs.aksSubnetId
    nodeCount: aksNodeCount
    nodeMaxCount: aksNodeMaxCount
    nodeVmSize: aksNodeVmSize
    collectorIdentityName: collectorIdentity.name
  }
}

module prometheus 'modules/prometheus.bicep' = {
  name: 'prometheus'
  params: {
    prefix: prefix
    location: location
    tags: tags
    aksName: aks.outputs.name
    alertEmail: alertEmail
  }
}

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    prefix: prefix
    location: location
    tags: tags
    endpointSubnetId: network.outputs.endpointSubnetId
    blobZoneId: network.outputs.zoneIds.blob
    dfsZoneId: network.outputs.zoneIds.dfs
    collectorPrincipalId: collectorIdentity.properties.principalId
    workspaceId: monitoring.outputs.workspaceId
  }
}

module keyvault 'modules/keyvault.bicep' = {
  name: 'keyvault'
  params: {
    prefix: prefix
    location: location
    tags: tags
    endpointSubnetId: network.outputs.endpointSubnetId
    vaultZoneId: network.outputs.zoneIds.vault
    collectorPrincipalId: collectorIdentity.properties.principalId
    workspaceId: monitoring.outputs.workspaceId
  }
}

module adx 'modules/adx.bicep' = {
  name: 'adx'
  params: {
    prefix: prefix
    location: location
    tags: tags
    endpointSubnetId: network.outputs.endpointSubnetId
    zoneIds: [
      network.outputs.zoneIds.kusto
      network.outputs.zoneIds.blob
      network.outputs.zoneIds.queue
      network.outputs.zoneIds.table
    ]
    collectorClientId: collectorIdentity.properties.clientId
    workspaceId: monitoring.outputs.workspaceId
    viewerGroupObjectId: adxViewerGroupObjectId
    skuName: adxSkuName
    skuTier: adxSkuTier
    capacity: adxCapacity
  }
}

module apim 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    prefix: prefix
    location: location
    tags: tags
    subnetId: network.outputs.apimSubnetId
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    tenantId: subscription().tenantId
    otlpAudience: otlpAudience
    routerUrl: 'http://${routerIlbIp}:4318'
    workspaceId: monitoring.outputs.workspaceId
    skuName: apimSkuName
    skuCapacity: apimCapacity
  }
}

output aksName string = aks.outputs.name
output collectorClientId string = collectorIdentity.properties.clientId
output adxClusterUri string = adx.outputs.clusterUri
output archiveBlobUrl string = storage.outputs.blobUrl
output keyVaultName string = keyvault.outputs.name
output apimGatewayUrl string = apim.outputs.gatewayUrl
output routerIlbIp string = routerIlbIp
