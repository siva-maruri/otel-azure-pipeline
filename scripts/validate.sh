#!/usr/bin/env bash
# Offline checks for everything in the repo. Used by CI, handy before a deploy.
#   needs: bicep, helm, otelcol-contrib (matching the image tag), python3
set -euo pipefail

cd "$(dirname "$0")/.."
chart_version="${CHART_VERSION:-0.173.1}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "-- bicep"
bicep build infra/main.bicep --outfile "$work/main.json"
bicep lint infra/main.bicep
bicep build-params infra/main.bicepparam --outfile "$work/main.parameters.json"

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

echo "all checks passed"
