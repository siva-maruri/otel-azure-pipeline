# 3. No Event Hubs between the gateway and ADX, for now

Status: accepted

## Context

A common Azure pattern puts Event Hubs in front of ADX: collectors write to Event Hubs, ADX
pulls through a data connection. It buys a durable buffer, replay, and room for more
consumers.

## Decision

Write straight from the gateway to ADX with queued ingestion, with the exporter's sending
queue and retries in front of it. The unsampled archive in ADLS Gen2 already gives us
something to replay from.

## Consequences

- One less service to size, secure (another private endpoint, another RBAC assignment) and
  pay for.
- If ADX is unavailable for longer than the exporter's retry window (10 minutes), data
  in the hot path is dropped. The archive pipeline is independent, so it's still in ADLS.
- Revisit when a second consumer appears (a SIEM, a streaming job) or when we need replay
  from the hot path rather than from the archive.
