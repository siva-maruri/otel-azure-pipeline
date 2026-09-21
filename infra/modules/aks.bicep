param prefix string
param location string
param tags object
param subnetId string
param nodeCount int
param nodeVmSize string
param collectorIdentityName string

@description('Namespace and service account the gateway collector runs as. Must match collector/gateway-values.yaml.')
param collectorNamespace string = 'observability'
param collectorServiceAccount string = 'otel-gateway'

resource aks 'Microsoft.ContainerService/managedClusters@2024-02-01' = {
  name: '${prefix}-aks'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    dnsPrefix: '${prefix}-aks'
    disableLocalAccounts: true
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    apiServerAccessProfile: {
      enablePrivateCluster: true
    }
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        osType: 'Linux'
        type: 'VirtualMachineScaleSets'
        count: nodeCount
        vmSize: nodeVmSize
        vnetSubnetID: subnetId
        availabilityZones: ['1', '2', '3']
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      networkPolicy: 'cilium'
      podCidr: '192.168.0.0/16'
      serviceCidr: '10.100.0.0/16'
      dnsServiceIP: '10.100.0.10'
    }
    addonProfiles: {
      azureKeyvaultSecretsProvider: {
        enabled: true
      }
    }
  }
}

resource collectorIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: collectorIdentityName
}

// Lets the gateway pods exchange their service account token for an Entra token.
// No client secret anywhere in the cluster.
resource federation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: collectorIdentity
  name: 'aks-${collectorServiceAccount}'
  properties: {
    issuer: aks.properties.oidcIssuerProfile.issuerURL
    subject: 'system:serviceaccount:${collectorNamespace}:${collectorServiceAccount}'
    audiences: ['api://AzureADTokenExchange']
  }
}

output name string = aks.name
