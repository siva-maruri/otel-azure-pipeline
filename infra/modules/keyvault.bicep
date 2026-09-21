param prefix string
param location string
param tags object
param endpointSubnetId string
param vaultZoneId string
param collectorPrincipalId string
param workspaceId string

// Key Vault Secrets User
var secretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take('${prefix}-kv-${uniqueString(resourceGroup().id)}', 24)
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// Holds the HMAC key telemetry-scrubber uses for tokenization.
resource collectorCanRead 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: vault
  name: guid(vault.id, collectorPrincipalId, secretsUserRoleId)
  properties: {
    principalId: collectorPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', secretsUserRoleId)
  }
}

resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: vault
  name: 'audit'
  properties: {
    workspaceId: workspaceId
    logs: [
      {
        category: 'AuditEvent'
        enabled: true
      }
    ]
  }
}

module endpoint 'private-endpoint.bicep' = {
  name: 'pe-vault'
  params: {
    name: '${vault.name}-pe'
    location: location
    tags: tags
    subnetId: endpointSubnetId
    targetId: vault.id
    groupId: 'vault'
    zoneIds: [vaultZoneId]
  }
}

output name string = vault.name
