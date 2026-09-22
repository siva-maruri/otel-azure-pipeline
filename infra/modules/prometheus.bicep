// Azure Monitor managed Prometheus for the collectors' own metrics, and the alert rules in
// alerts/collector-rules.yaml (the same file promtool tests in CI).
param prefix string
param location string
param tags object
param aksName string
param alertEmail string
param endpointSubnetId string
@description('Private DNS zones for the Azure Monitor Private Link Scope endpoint.')
param amplsZoneIds array

resource aks 'Microsoft.ContainerService/managedClusters@2024-05-01' existing = {
  name: aksName
}

resource workspace 'Microsoft.Monitor/accounts@2023-04-03' = {
  name: '${prefix}-amw'
  location: location
  tags: tags
}

resource dce 'Microsoft.Insights/dataCollectionEndpoints@2023-03-11' = {
  name: '${prefix}-prom-dce'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Disabled'
    }
  }
}

resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: '${prefix}-prom-dcr'
  location: location
  tags: tags
  kind: 'Linux'
  properties: {
    dataCollectionEndpointId: dce.id
    dataSources: {
      prometheusForwarder: [
        {
          name: 'PrometheusDataSource'
          streams: ['Microsoft-PrometheusMetrics']
          labelIncludeFilter: {}
        }
      ]
    }
    destinations: {
      monitoringAccounts: [
        {
          name: 'MonitoringAccount1'
          accountResourceId: workspace.id
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-PrometheusMetrics']
        destinations: ['MonitoringAccount1']
      }
    ]
  }
}

resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'MSProm-${location}-${aksName}'
  scope: aks
  properties: {
    dataCollectionRuleId: dcr.id
  }
}

resource dceAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'configurationAccessEndpoint'
  scope: aks
  properties: {
    dataCollectionEndpointId: dce.id
  }
}

// Private ingestion: the metrics agents in the VNet reach both endpoints (the cluster's
// configuration endpoint and the workspace's ingestion endpoint) through a private endpoint.
// PrivateOnly ingestion means agents in the VNet can't fall back to public endpoints. Query
// stays open so the portal and Grafana still work from outside.
resource ampls 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' = {
  name: '${prefix}-ampls'
  location: 'global'
  tags: tags
  properties: {
    accessModeSettings: {
      ingestionAccessMode: 'PrivateOnly'
      queryAccessMode: 'Open'
    }
  }
}

resource amplsConfigEndpoint 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'prometheus-config'
  properties: {
    linkedResourceId: dce.id
  }
}

resource amplsIngestionEndpoint 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: ampls
  name: 'prometheus-ingestion'
  properties: {
    linkedResourceId: workspace.properties.defaultIngestionSettings.dataCollectionEndpointResourceId
  }
}

module amplsPrivateEndpoint 'private-endpoint.bicep' = {
  name: 'ampls-pe'
  params: {
    name: '${prefix}-ampls-pe'
    location: location
    tags: tags
    subnetId: endpointSubnetId
    targetId: ampls.id
    groupId: 'azuremonitor'
    zoneIds: amplsZoneIds
  }
  dependsOn: [amplsConfigEndpoint, amplsIngestionEndpoint]
}

resource oncall 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${prefix}-otel-oncall'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'otel-oncall'
    enabled: true
    emailReceivers: [
      {
        name: 'oncall'
        emailAddress: alertEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

var alertFile = loadYamlContent('../../alerts/collector-rules.yaml')
var severity = {
  critical: 1
  warning: 2
}

// Prometheus writes `for: 10m`; Azure wants ISO 8601 (PT10M).
resource ruleGroups 'Microsoft.AlertsManagement/prometheusRuleGroups@2023-03-01' = [
  for group in alertFile.groups: {
    name: '${prefix}-${group.name}'
    location: location
    tags: tags
    properties: {
      scopes: [workspace.id, aks.id]
      clusterName: aksName
      enabled: true
      interval: 'PT1M'
      rules: [
        for rule in group.rules: {
          alert: rule.alert
          expression: rule.expr
          for: 'PT${toUpper(rule.for)}'
          severity: severity[rule.labels.severity]
          labels: rule.labels
          annotations: rule.annotations
          enabled: true
          resolveConfiguration: {
            autoResolved: true
            timeToResolve: 'PT10M'
          }
          actions: [
            {
              actionGroupId: oncall.id
            }
          ]
        }
      ]
    }
  }
]

output workspaceId string = workspace.id
