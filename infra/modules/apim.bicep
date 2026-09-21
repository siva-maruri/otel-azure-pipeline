param prefix string
param location string
param tags object
param subnetId string
param publisherEmail string
param publisherName string
param tenantId string
param otlpAudience string
param routerUrl string
param workspaceId string

@allowed(['Developer', 'Premium'])
@description('Only Developer and Premium support VNet injection in internal mode.')
param skuName string = 'Developer'
param skuCapacity int = 1

// stv2 VNet injection needs a Standard public IP for the management plane, even in internal mode.
resource managementIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${prefix}-apim-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${prefix}-apim-${uniqueString(resourceGroup().id)}'
    }
  }
}

resource apim 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: '${prefix}-apim-${uniqueString(resourceGroup().id)}'
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: subnetId
    }
    publicIpAddressId: managementIp.id
  }
}

resource tenantValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'tenant-id'
  properties: {
    displayName: 'tenant-id'
    value: tenantId
  }
}

resource audienceValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'otlp-ingest-audience'
  properties: {
    displayName: 'otlp-ingest-audience'
    value: otlpAudience
  }
}

resource routerValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apim
  name: 'otlp-router-url'
  properties: {
    displayName: 'otlp-router-url'
    value: routerUrl
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apim
  name: 'otlp'
  properties: {
    displayName: 'OTLP ingest'
    path: 'otlp'
    protocols: ['https']
    subscriptionRequired: false
    serviceUrl: routerUrl
  }
}

resource operations 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = [
  for signal in ['traces', 'logs', 'metrics']: {
    parent: api
    name: 'post-${signal}'
    properties: {
      displayName: 'Export ${signal}'
      method: 'POST'
      urlTemplate: '/v1/${signal}'
    }
  }
]

resource policy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/otlp-ingest-policy.xml')
  }
  dependsOn: [tenantValue, audienceValue, routerValue]
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: apim
  name: 'audit'
  properties: {
    workspaceId: workspaceId
    // Resource-specific tables (ApiManagementGatewayLogs) instead of AzureDiagnostics.
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
  }
}

output gatewayUrl string = apim.properties.gatewayUrl
