#!/usr/bin/env bash
# Push one failing span through APIM and print the KQL to find it in ADX.
# APIM is internal, so run this from somewhere inside the VNet (jump box, Bastion, CI runner).
#
#   APIM_URL=https://<apim>.azure-api.net AUDIENCE=api://otlp-ingest bash scripts/send_test_span.sh
#
# The caller needs a token with the Telemetry.Write app role, e.g. after
# `az login --identity` on a VM whose identity was granted that role.
set -euo pipefail

apim_url="${APIM_URL:?set APIM_URL}"
audience="${AUDIENCE:-api://otlp-ingest}"
token="$(az account get-access-token --resource "$audience" --query accessToken -o tsv)"

trace_id="$(openssl rand -hex 16)"
span_id="$(openssl rand -hex 8)"
now="$(date +%s%N)"

body=$(cat << JSON
{"resourceSpans":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"pipeline-smoke-test"}}]},
 "scopeSpans":[{"scope":{"name":"send_test_span.sh"},"spans":[{
  "traceId":"$trace_id","spanId":"$span_id","name":"GET /orders/{id}","kind":2,
  "startTimeUnixNano":"$((now - 250000000))","endTimeUnixNano":"$now",
  "attributes":[{"key":"http.route","value":{"stringValue":"/orders/{id}"}},
                {"key":"http.response.status_code","value":{"intValue":"500"}}],
  "status":{"code":2,"message":"smoke test"}}]}]}]}
JSON
)

status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST "$apim_url/otlp/v1/traces" \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' -d "$body")"
echo "APIM responded $status"
[[ "$status" == "200" ]] || exit 1

echo "Error spans are always kept by tail sampling. In ADX, after a minute or two:"
echo "  TraceWaterfall(\"$trace_id\")"
