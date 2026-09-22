#!/usr/bin/env bash
# Deploy the Azure resources, then install the router and gateway collectors.
#   bash scripts/deploy.sh <resource-group> [location]
# Needs: az (logged in), jq. First run takes a while: APIM in VNet mode is 30-45 minutes.
set -euo pipefail

cd "$(dirname "$0")/.."
rg="${1:?usage: deploy.sh <resource-group> [location]}"
location="${2:-westus2}"
chart_version="${CHART_VERSION:-0.173.1}"
cert_manager_version="${CERT_MANAGER_VERSION:-v1.15.3}"

az group create -n "$rg" -l "$location" -o none

echo "-- infra"
outputs="$(az deployment group create -g "$rg" -n otel-pipeline \
  -f infra/main.bicep -p infra/main.bicepparam \
  --query properties.outputs -o json)"
out() { jq -r ".$1.value" <<< "$outputs"; }

aks="$(out aksName)"
bundle="$(mktemp -d)"
trap 'rm -rf "$bundle"' EXIT

cp collector/gateway-values.yaml collector/router-values.yaml collector/certs.yaml \
  collector/ama-metrics-settings.yaml "$bundle/"
cat > "$bundle/gateway-overrides.yaml" << YAML
serviceAccount:
  annotations:
    azure.workload.identity/client-id: "$(out collectorClientId)"
extraEnvs:
  - name: ADX_CLUSTER_URI
    value: "$(out adxClusterUri)"
  - name: ARCHIVE_BLOB_URL
    value: "$(out archiveBlobUrl)"
YAML

echo "-- collectors"
# The API server is private, so helm runs inside the cluster network via command invoke.
# cert-manager and the router/gateway certificates first (mTLS between the tiers), then the
# gateway, then the router, which resolves the gateway's headless service.
(
  cd "$bundle"
  az aks command invoke -g "$rg" -n "$aks" --file . --command "
    helm repo add jetstack https://charts.jetstack.io &&
    helm upgrade --install cert-manager jetstack/cert-manager --version $cert_manager_version \
      -n cert-manager --create-namespace --set crds.enabled=true --wait &&
    kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f - &&
    kubectl apply -f certs.yaml &&
    kubectl apply -f ama-metrics-settings.yaml &&
    kubectl -n observability wait --for=condition=Ready --timeout=180s \
      certificate/otel-gateway-tls certificate/otel-router-tls &&
    helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts &&
    helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
      --version $chart_version -n observability --create-namespace \
      -f gateway-values.yaml -f gateway-overrides.yaml --wait &&
    helm upgrade --install otel-router open-telemetry/opentelemetry-collector \
      --version $chart_version -n observability \
      -f router-values.yaml --wait"
)

echo
echo "APIM gateway (private): $(out apimGatewayUrl)/otlp/v1/traces"
echo "In-cluster OTLP:        otel-router-opentelemetry-collector.observability:4317"
