# 6. mTLS between collector tiers with cert-manager, not a service mesh

Status: accepted

## Context

The router forwards everything to the gateway, including data that hasn't been through the
gateway's scrubbing yet. That hop was plaintext inside the cluster. Anything with access to
the pod network could read it, and anything that could reach the gateway's port could write
to it.

The two usual fixes are a service mesh (Istio, Linkerd) that encrypts pod-to-pod traffic
transparently, or certificates configured in the collectors themselves.

## Decision

cert-manager with a namespace-scoped private CA. The gateway gets a server certificate, the
router a client certificate, and the gateway requires a client certificate signed by that CA
(`client_ca_file`) with TLS 1.3 minimum. The gateway's plaintext HTTP listener is removed.

## Consequences

- One small operator instead of a mesh's sidecars or node agents, for the only hop that needs
  it. If other workloads later need mTLS too, a mesh becomes worth it and these certificates
  can go.
- Certificates are 90 days and renewed automatically. The collectors pick up renewed files on
  restart, so a rolling restart within the renewal window is part of routine operation (the
  certificate's `renewBefore` leaves a month of margin).
- The router connects to pod IPs from the headless service, which no certificate names, so
  it verifies against the service name with `server_name_override`. A misconfigured override
  fails closed: the handshake is refused rather than falling back to plaintext.
- `scripts/local_test.sh` exercises the same setup with throwaway certificates and asserts that
  plaintext and certificate-less connections are refused.
