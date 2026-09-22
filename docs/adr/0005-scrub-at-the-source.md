# 5. Full scrubbing happens in the SDK; the gateway is the backstop

Status: accepted

## Context

The gateway's `redaction` and `transform` processors catch known patterns (card numbers,
AWS keys, SAS signatures, credential headers). They can't do entropy checks or keyed
tokenization: OTTL has no notion of a secret key, and a custom collector build just for
this would be ours to maintain forever.

[telemetry-scrubber](https://github.com/siva-maruri/telemetry-scrubber) does both, as
exporter wrappers for spans and log records.

## Decision

Services wrap their OTLP exporters with telemetry-scrubber, so data is scrubbed before it
leaves the process. The HMAC tokenization key lives in this deployment's Key Vault; services
read it with their own managed identity (`Tokenizer.from_key_vault`). The gateway keeps its
pattern rules as a second line for anything that wasn't instrumented that way.

## Consequences

- Secrets never cross the network in the clear, not even inside the cluster.
- Every service gets the same tokens for the same values, because they share one key, so
  tokenized ids still join across services in ADX.
- It depends on teams adopting the wrapper. Services that don't are only covered by the
  gateway's patterns, which miss unknown secret formats. Worth tracking which services
  send spans without it (a resource attribute set by the wrapper would make that visible).
- Rotating the key changes tokens everywhere at once. Plan rotations like a schema change.
