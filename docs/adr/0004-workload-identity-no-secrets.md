# 4. Workload identity for the collectors, no secrets in the cluster

Status: accepted

## Context

The gateway writes to ADX and blob storage and will read a tokenization key from Key Vault.
The usual shortcuts are a service principal secret or a storage connection string in a
Kubernetes secret. Both have to be rotated, both leak into places they shouldn't (Helm
values, CI logs), and a telemetry pipeline is exactly where leaked credentials end up
being ingested.

## Decision

One user-assigned managed identity for the gateway, federated to the `otel-gateway`
service account through AKS workload identity. Storage has shared key access disabled, so
there is no connection string to leak even by accident. Role assignments are scoped to the
single resource each one is for.

## Consequences

- Nothing to rotate. The federated token is short-lived and issued per pod.
- The federated credential's subject is `system:serviceaccount:observability:otel-gateway`.
  Renaming the namespace or service account breaks auth until the Bicep is updated; the
  names are parameters in `infra/modules/aks.bicep` for that reason.
- New role assignments can take a few minutes to apply. A first deploy can show 403s from
  the blob exporter for a short while; they clear on their own.
