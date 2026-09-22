# 7. TLS into the router, with APIM trusting the cluster CA through a second deployment pass

Status: accepted

## Context

After ADR 6 the router-to-gateway hop was mutual TLS, but everything arriving at the router
was plaintext: APIM forwarding external traffic over the internal load balancer, and apps
inside the cluster. That traffic hasn't been through the gateway's scrubbing yet.

Giving the router a certificate is easy with cert-manager. The hard part is APIM: to verify
the router it has to trust the CA that signed it, and that CA is created inside the cluster
by cert-manager, after the Bicep deployment that creates APIM has already run.

Options considered:

- **Skip certificate validation in APIM.** Encrypted, but anything that can answer on the
  router's IP could impersonate it. Rejected.
- **Create the CA in Key Vault first** and have both APIM and cert-manager use it. Cleanest
  on paper, but ARM can't create Key Vault certificates, so it still needs a data-plane step,
  plus syncing the CA's private key into the cluster.
- **Deploy twice.** First pass as before; deploy.sh then reads the CA's public certificate
  from the cluster and redeploys with it, which adds it to APIM's trusted roots and switches
  the backend URL to HTTPS.

## Decision

Deploy twice. The router's OTLP listeners (gRPC and HTTP) serve a cert-manager certificate
valid for the service name and the internal load balancer IP. `main.bicep` takes an optional
`routerCaCertificate`; when set, APIM trusts it and talks HTTPS to the router. In-cluster apps
verify the router with an `otel-ca-bundle` ConfigMap that deploy.sh publishes to the sending
namespaces.

## Consequences

- Every hop is encrypted, and APIM verifies who it's talking to.
- A first deployment is two Bicep runs, and the second one updates APIM, which is slow. On
  later runs deploy.sh passes the CA from the previous run into the first pass, so APIM never
  drops back to plain HTTP in between.
- The CA's private key never leaves the cluster; only its public certificate goes to APIM.
- Rotating the CA (yearly) means rerunning deploy.sh so APIM learns the new one. Leaf
  certificates renew on their own and the router reloads them without a restart
  (`reload_interval`).
- The router's certificate includes the internal load balancer IP. Changing `routerIlbIp`
  means changing it in `collector/certs.yaml` and `collector/router-values.yaml` too.
