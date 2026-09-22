#!/usr/bin/env bash
# Offline checks for everything in the repo. Used by CI, handy before a deploy.
#   needs: bicep, helm, otelcol-contrib (matching the image tag), promtool, python3
set -euo pipefail

cd "$(dirname "$0")/.."
chart_version="${CHART_VERSION:-0.173.1}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "-- bicep"
bicep build infra/main.bicep --outfile "$work/main.json"
bicep lint infra/main.bicep
bicep build-params infra/main.bicepparam --outfile "$work/main.parameters.json"
bicep build-params infra/prod.bicepparam --outfile "$work/prod.parameters.json"

echo "-- apim policy"
python3 -c "import sys, xml.dom.minidom as m; m.parse(sys.argv[1])" apim/otlp-ingest-policy.xml

echo "-- collector"
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1 || true
helm repo update open-telemetry >/dev/null

for release in gateway router; do
  helm template "otel-$release" open-telemetry/opentelemetry-collector \
    --version "$chart_version" --namespace observability \
    -f "collector/$release-values.yaml" > "$work/$release.yaml"

  # Pull the rendered collector config out of the ConfigMap and validate it with the
  # same collector version the pods run. Env placeholders get dummy values.
  python3 - "$work/$release.yaml" "$work/$release-config.yaml" << 'PY'
import sys, yaml
docs = [d for d in yaml.safe_load_all(open(sys.argv[1])) if d]
cm = next(d for d in docs if d["kind"] == "ConfigMap")
open(sys.argv[2], "w").write(cm["data"]["relay"])
PY

  MY_POD_IP=127.0.0.1 ADX_CLUSTER_URI=https://example.westus2.kusto.windows.net \
  ARCHIVE_BLOB_URL=https://example.blob.core.windows.net/ \
  AZURE_TENANT_ID=00000000-0000-0000-0000-000000000000 AZURE_CLIENT_ID=00000000-0000-0000-0000-000000000000 \
  AZURE_FEDERATED_TOKEN_FILE=/var/run/secrets/azure/tokens/azure-identity-token \
    otelcol-contrib validate --config="$work/$release-config.yaml"
  echo "   $release: ok"
done

echo "-- consistency"
# The router's internal load balancer IP lives in three places (ADR 7); they must agree.
ilb="$(grep -oP "param routerIlbIp string = '\K[0-9.]+" infra/main.bicep)"
if ! grep -q "azure-load-balancer-ipv4: \"$ilb\"" collector/router-values.yaml \
  || ! grep -q -- "- $ilb" collector/certs.yaml; then
  echo "routerIlbIp ($ilb) must match collector/router-values.yaml and collector/certs.yaml"
  exit 1
fi
echo "   router IP $ilb matches in Bicep, Helm values and certificate"

# The NetworkPolicy allows the APIM and AKS subnets by range (ADR 8).
for subnet in apim aks; do
  cidr="$(grep -A3 "name: '$subnet'" infra/modules/network.bicep | grep -oP "addressPrefix: '\K[0-9./]+")"
  if ! grep -q "cidr: $cidr" collector/network-policies.yaml; then
    echo "$subnet subnet ($cidr) must be the range allowed in collector/network-policies.yaml"
    exit 1
  fi
done
echo "   APIM and AKS subnet ranges match the NetworkPolicy"

echo "-- alerts"
promtool check rules alerts/collector-rules.yaml > /dev/null
promtool test rules alerts/collector-rules.test.yaml > /dev/null
echo "   rules valid, unit tests pass"

echo "all checks passed"
