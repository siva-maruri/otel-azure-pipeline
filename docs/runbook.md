# Runbook

The API server is private, so cluster commands go through `az aks command invoke`:

```bash
k() { az aks command invoke -g "$RG" -n "$AKS" --command "kubectl -n observability $*"; }
k get pods -o wide
k top pods
k logs deploy/otel-gateway-opentelemetry-collector --tail=200
```

## Symptoms

### Traces stop showing up in ADX

1. Gateway logs, look for exporter errors: `k logs deploy/otel-gateway-opentelemetry-collector --tail=500`
2. 401/403 from the ADX exporter means identity. Check the pod has the
   `azure.workload.identity/use: "true"` label and the service account annotation holds
   the collector identity's client id. Then check the federated credential subject matches
   the namespace and service account.
3. Nothing wrong in the logs: ask ADX what it rejected.

   ```kusto
   .show ingestion failures
   | where FailedOn > ago(1h)
   | summarize count() by Table, ErrorCode, Details
   ```

   Schema mismatches after an exporter upgrade show up here first.

### Gateway memory climbing, spans refused

The collector publishes its own metrics on port 8888 (counters carry a `_total` suffix in
Prometheus). The ones that matter:

| Metric | Meaning |
|---|---|
| `otelcol_exporter_queue_size` vs `otelcol_exporter_queue_capacity` | Exporter backlog. Near capacity means the backend is slow or down. |
| `otelcol_exporter_send_failed_spans` | Spans the exporter gave up on. |
| `otelcol_receiver_refused_spans` | Spans turned away, usually `memory_limiter` pushing back. |
| `otelcol_processor_incoming_items` / `outgoing_items` | Per processor; the gap across `tail_sampling` is what sampling dropped. |

A full ADX exporter queue with refused spans upstream is ADX being slow or unreachable, not
a gateway problem. Scaling the gateway won't help; check ADX ingestion and the private
endpoint first.

### Traces look broken (orphan spans, missing children)

Spans of one trace were sampled on different gateways. Normal for a short window while the
gateway scales or rolls (see ADR 1). Outside of that, check the router can resolve the
headless service. The collector image is distroless, so there's no shell for `nslookup`;
compare `k get endpoints otel-gateway-headless` with the gateway pod IPs instead.

### Router can't reach the gateway (TLS errors in router logs)

Usually an expired or not-yet-issued certificate, or a gateway pod that started before a
renewal and still serves the old one.

```bash
k get certificate                      # all should be READY=True
k describe certificate otel-gateway-tls
k rollout restart deploy/otel-gateway-opentelemetry-collector   # picks up renewed files
```

### External senders get 401 / 429 from APIM

```kusto
ApiManagementGatewayLogs
| where TimeGenerated > ago(1h) and ApiId == "otlp"
| summarize count() by ResponseCode, CallerIpAddress
```

- 401: token audience isn't `otlpAudience`, or the caller lacks the `Telemetry.Write` role.
- 429: the caller hit the per-app rate limit (3000/min) or daily quota. Limits are per
  calling app (`azp`), so one noisy sender can't starve the others.
- 413: payload over 4 MB. Senders should batch smaller.

### Who read the tokenization key

```kusto
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT" and OperationName == "SecretGet"
| project TimeGenerated, CallerIPAddress, identity_claim_oid_g, ResultType, id_s
```
