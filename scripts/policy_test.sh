#!/usr/bin/env bash
# Checks collector/network-policies.yaml offline: exactly the intended connections can reach
# the collectors, and nothing else. Renders the real Helm releases (so pod labels are the ones
# the cluster will see), adds test namespaces and pods, and asks np-guard's netpol-analyzer
# for the resulting connectivity.
#   needs: helm, netpolicy (github.com/np-guard/netpol-analyzer), kubeconform
set -euo pipefail

cd "$(dirname "$0")/.."
chart_version="${CHART_VERSION:-0.173.1}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

kubeconform -strict -summary collector/network-policies.yaml

helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts > /dev/null 2>&1 || true
for release in gateway router; do
  helm template "otel-$release" open-telemetry/opentelemetry-collector --version "$chart_version" \
    -n observability -f "collector/$release-values.yaml" > "$work/$release.yaml"
done
cp collector/network-policies.yaml "$work/"

# A namespace that is allowed to send (labelled like deploy.sh does), one that isn't, and the
# managed Prometheus agent in kube-system.
cat > "$work/fixtures.yaml" << 'YAML'
apiVersion: v1
kind: Namespace
metadata: {name: observability, labels: {kubernetes.io/metadata.name: observability}}
---
apiVersion: v1
kind: Namespace
metadata: {name: kube-system, labels: {kubernetes.io/metadata.name: kube-system}}
---
apiVersion: v1
kind: Namespace
metadata: {name: checkout, labels: {kubernetes.io/metadata.name: checkout, otel-client: "true"}}
---
apiVersion: v1
kind: Namespace
metadata: {name: sandbox, labels: {kubernetes.io/metadata.name: sandbox}}
---
apiVersion: v1
kind: Pod
metadata: {name: checkout-api, namespace: checkout, labels: {app: checkout-api}}
spec: {containers: [{name: app, image: app}]}
---
apiVersion: v1
kind: Pod
metadata: {name: stray, namespace: sandbox, labels: {app: stray}}
spec: {containers: [{name: app, image: app}]}
---
apiVersion: v1
kind: Pod
metadata: {name: ama-metrics, namespace: kube-system, labels: {rsName: ama-metrics}}
spec: {containers: [{name: agent, image: agent}]}
YAML

# Everything that may reach a collector. Anything added or missing fails the test.
cat > "$work/expected.txt" << 'TXT'
10.20.0.0-10.20.3.255 => observability/otel-gateway-opentelemetry-collector[Deployment] : TCP 13133
10.20.0.0-10.20.3.255 => observability/otel-router-opentelemetry-collector[Deployment] : TCP 13133
10.20.4.0-10.20.4.31 => observability/otel-router-opentelemetry-collector[Deployment] : TCP 4318
checkout/checkout-api[Pod] => observability/otel-router-opentelemetry-collector[Deployment] : TCP 4317-4318
kube-system/ama-metrics[Pod] => observability/otel-gateway-opentelemetry-collector[Deployment] : TCP 8888
kube-system/ama-metrics[Pod] => observability/otel-router-opentelemetry-collector[Deployment] : TCP 8888
observability/otel-router-opentelemetry-collector[Deployment] => observability/otel-gateway-opentelemetry-collector[Deployment] : TCP 4317
TXT

netpolicy list --dirpath "$work" \
  | grep -E '=> observability/otel-(router|gateway)-' | sort > "$work/actual.txt"

if ! diff -u "$work/expected.txt" "$work/actual.txt"; then
  echo "FAIL: connectivity to the collectors differs from what's intended (- expected, + actual)"
  exit 1
fi
echo "ok: only labelled namespaces, APIM, the metrics agent and kubelet reach the router;" \
  "only the router reaches the gateway"
