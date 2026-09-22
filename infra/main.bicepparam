using './main.bicep'

param prefix = 'otelp'
param otlpAudience = 'api://otlp-ingest'
param apimPublisherEmail = 'platform-team@example.com'
param alertEmail = 'platform-oncall@example.com'
