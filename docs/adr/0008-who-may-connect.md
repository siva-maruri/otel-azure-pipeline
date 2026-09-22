# 8. NetworkPolicies decide who may connect, with the router keeping source addresses

Status: accepted

## Context

After ADR 7 every hop is encrypted, but encryption says nothing about who is sending. Any
pod in the cluster could reach the router and push telemetry in, and anything that got a
foothold in the pod network could try the gateway.

The router has two kinds of legitimate caller: apps inside the cluster, and APIM, which
forwards external traffic through the router's internal load balancer. A NetworkPolicy can
match the first by namespace. The second is the problem: with the default
`externalTrafficPolicy: Cluster`, load-balanced traffic is rewritten to a node's address on
the way in, so a policy can't tell APIM from anything else on the node subnet.

## Decision

- The router Service uses `externalTrafficPolicy: Local`, so APIM's traffic keeps its source
  address and can be allowed by the APIM subnet range.
- The router accepts OTLP from namespaces labelled `otel-client=true` (deploy.sh labels the
  ones in `OTEL_CLIENT_NAMESPACES`) and OTLP/HTTP from the APIM subnet.
- The gateway accepts OTLP only from router pods.
- Both allow the metrics agent (kube-system) on 8888 and the node subnet on the health port.
- `scripts/policy_test.sh` renders the real releases and checks the analyzed connectivity
  against an exact list in CI.

## Consequences

- A new sending namespace needs the label, or its connections time out. The runbook covers
  the symptom.
- With `externalTrafficPolicy: Local` the load balancer only sends to nodes running a router
  pod, and spreads by node rather than by pod. With a few router replicas that's fine; with
  very uneven placement, a topology spread constraint would even it out.
- The policy test uses standard Kubernetes NetworkPolicy semantics (np-guard's analyzer).
  Cilium enforces the same semantics, and additionally always allows node-to-pod traffic,
  which only matters for the health port, already allowed. What the test can't show is AKS
  preserving APIM's address in practice; that's the first thing to check on a live cluster.
- The subnet ranges are written into the policy. Changing them in network.bicep means
  changing them here too; validate.sh fails if the two drift apart.
