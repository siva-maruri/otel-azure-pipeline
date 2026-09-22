using './main.bicep'

// Production sizing. Same template, SLA-backed SKUs.
param prefix = 'otelprd'
param otlpAudience = 'api://otlp-ingest'
param apimPublisherEmail = 'platform-team@example.com'
param alertEmail = 'platform-oncall@example.com'

param aksNodeCount = 3
param aksNodeMaxCount = 12
param aksNodeVmSize = 'Standard_D8ds_v5'

param adxSkuName = 'Standard_E8ads_v5'
param adxSkuTier = 'Standard'
param adxCapacity = 2

param apimSkuName = 'Premium'
param apimCapacity = 1
