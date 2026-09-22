using './main.bicep'

// Sized for an Azure free account: one 2-vCPU node, the cheapest SKUs that still support
// what the design needs (APIM Developer is the cheapest tier that can run inside a VNet).
// Pair it with the collector/trial overlays: DEPLOY_PROFILE=trial bash scripts/deploy.sh <rg>
// Tear it down the same day: bash scripts/teardown.sh <rg>
param prefix = 'oteltrial'
param otlpAudience = 'api://otlp-ingest'
param apimPublisherEmail = 'you@example.com'
param alertEmail = 'you@example.com'

param aksNodeCount = 1
param aksNodeMaxCount = 2
param aksNodeVmSize = 'Standard_D2ds_v5'

param adxSkuName = 'Dev(No SLA)_Standard_E2a_v4'
param adxSkuTier = 'Basic'
param adxCapacity = 1

param apimSkuName = 'Developer'
param apimCapacity = 1
