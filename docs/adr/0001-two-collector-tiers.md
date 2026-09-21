# 1. Two collector tiers so tail sampling can scale out

Status: accepted

## Context

We want to keep every error trace and every slow trace, and only a sample of the rest.
That decision can only be made once a trace is complete, which means tail sampling, and
tail sampling needs every span of a trace in the same collector process. Behind a normal
Kubernetes service, spans of one trace land on whichever gateway pod the connection hits.

Running a single gateway replica would work until it doesn't: no headroom, and a restart
drops every trace in flight.

## Decision

Split the collectors in two:

- A **router** tier that receives everything (apps in the cluster, APIM from outside) and
  uses the `loadbalancing` exporter with `routing_key: traceID`, resolving gateway pods
  through a headless service.
- A **gateway** tier that does the expensive work: scrubbing, tail sampling, export to ADX
  and ADLS Gen2.

Logs and metrics don't need affinity and go straight to the gateway's normal service.

## Consequences

- The gateway can scale horizontally. When it scales, the hash ring changes and traces in
  flight during the change can be split across two gateways; those are sampled on partial
  data. Acceptable for our use; worth knowing when reading a trace from a deploy window.
- One more hop and one more thing to run. The router is cheap (no processing beyond
  `memory_limiter`) and has its own queue in front of each gateway endpoint.
- DNS-based resolution lags pod changes by the resolver interval (5s default). The `k8s`
  resolver reacts faster but needs RBAC to watch endpoints; not worth it yet.
