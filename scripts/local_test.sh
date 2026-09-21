#!/usr/bin/env bash
# Runs the real router and gateway configs on this machine, with the Azure exporters
# swapped for debug output, and checks routing, tail sampling and scrubbing end to end.
#   needs: helm, otelcol-contrib, python3 + pyyaml, curl
set -euo pipefail

cd "$(dirname "$0")/.."
chart_version="${CHART_VERSION:-0.173.1}"
work="$(mktemp -d)"
pids=()
cleanup() { kill "${pids[@]}" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

for release in gateway router; do
  helm template "otel-$release" open-telemetry/opentelemetry-collector --version "$chart_version" \
    -n observability -f "collector/$release-values.yaml" > "$work/$release.yaml"
done

python3 - "$work" << 'PY'
import sys, yaml
work = sys.argv[1]
def config(release):
    docs = [d for d in yaml.safe_load_all(open(f"{work}/{release}.yaml")) if d]
    return yaml.safe_load(next(d for d in docs if d["kind"] == "ConfigMap")["data"]["relay"])

gw = config("gateway")
gw["exporters"] = {"debug/hot": {"verbosity": "detailed"}, "debug/archive": {"verbosity": "basic"}}
gw["service"]["pipelines"]["traces"]["exporters"] = ["debug/hot"]
for p in ("traces/archive", "logs", "metrics"):
    gw["service"]["pipelines"][p]["exporters"] = ["debug/archive"]
gw["receivers"]["otlp"]["protocols"] = {"grpc": {"endpoint": "127.0.0.1:14317"}}
gw["processors"]["tail_sampling"]["decision_wait"] = "2s"
gw["extensions"]["health_check"]["endpoint"] = "127.0.0.1:13134"
gw["service"]["telemetry"] = {"metrics": {"level": "none"}}

rt = config("router")
rt["exporters"]["loadbalancing"]["resolver"] = {"static": {"hostnames": ["127.0.0.1:14317"]}}
rt["exporters"]["otlp_grpc/gateway"]["endpoint"] = "127.0.0.1:14317"
rt["receivers"]["otlp"]["protocols"] = {"http": {"endpoint": "127.0.0.1:24318"}}
rt["extensions"]["health_check"]["endpoint"] = "127.0.0.1:13135"
rt["service"]["telemetry"] = {"metrics": {"level": "none"}}

yaml.safe_dump(gw, open(f"{work}/gw.yaml", "w"))
yaml.safe_dump(rt, open(f"{work}/rt.yaml", "w"))
PY

otelcol-contrib --config="$work/gw.yaml" > "$work/gw.log" 2>&1 & pids+=($!)
otelcol-contrib --config="$work/rt.yaml" > "$work/rt.log" 2>&1 & pids+=($!)
sleep 5

now="$(date +%s%N)"
send() {  # trace_id name duration_ns status_code
  curl -sf -o /dev/null -X POST localhost:24318/v1/traces -H 'Content-Type: application/json' -d "{
    \"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"checkout\"}}]},
    \"scopeSpans\":[{\"spans\":[{\"traceId\":\"$1\",\"spanId\":\"00f067aa0ba902b7\",\"name\":\"$2\",\"kind\":2,
    \"startTimeUnixNano\":\"$now\",\"endTimeUnixNano\":\"$((now + $3))\",
    \"attributes\":[{\"key\":\"url.full\",\"value\":{\"stringValue\":\"https://a.blob.core.windows.net/c?sig=abc123XYZ&se=1\"}},
                    {\"key\":\"http.request.header.authorization\",\"value\":{\"stringValue\":\"Bearer not-a-real-token\"}}],
    \"status\":{\"code\":$4}}]}]}]}"
}

send 11111111111111111111111111111111 error-span 5000000 2
send 22222222222222222222222222222222 slow-span 2000000000 0
for i in $(seq 1 30); do send "$(printf '%032x' $((1000 + i)))" fast-ok-span 1000000 0; done
sleep 8

fail() { echo "FAIL: $1"; exit 1; }
grep -q "Name *: error-span" "$work/gw.log" || fail "error span was not kept by tail sampling"
grep -q "Name *: slow-span" "$work/gw.log" || fail "slow span was not kept by tail sampling"
grep -q "sig=REDACTED" "$work/gw.log" || fail "SAS signature not redacted"
if grep -q "not-a-real-token" "$work/gw.log"; then fail "authorization header reached the gateway output"; fi

archived="$(grep -F '"otelcol.component.id": "debug/archive"' "$work/gw.log" | grep -oE '"spans": [0-9]+' | awk '{s += $2} END {print s + 0}')"
(( archived == 32 )) || fail "archive pipeline got $archived spans, expected 32"

echo "ok: errors and slow traces kept, all 32 spans archived, credentials and SAS signature scrubbed"
