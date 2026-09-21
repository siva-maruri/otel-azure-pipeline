# 2. Azure Data Explorer for queryable telemetry, not Log Analytics

Status: accepted

## Context

Traces, logs and metrics need to be queryable for a couple of weeks, kept for up to a few
months, and cheap enough that nobody argues for turning tracing off. On Azure the obvious
candidates are Log Analytics / Application Insights and Azure Data Explorer. Both speak KQL.

## Decision

Send the collector's output to ADX through the `azuredataexplorer` exporter, with tables
matching the exporter's schema and per-table retention and hot-cache policies
(`adx/tables.kql`). Keep Log Analytics for what it's good at here: the platform's own audit
and diagnostic logs.

## Consequences

- Retention and caching are per table (traces 90d / 14d hot, logs 30d / 7d, metrics
  180d / 30d), so the expensive table doesn't set the price for everything else.
- We own the schema and the query functions (`adx/functions.kql`). Nothing comes for free
  the way App Insights' portal views do; on-call uses the KQL functions instead.
- Ingestion is queued (batched), so data shows up after a short delay rather than
  immediately. Streaming ingestion is available per table if that ever matters.
- The exporter's column set is fixed. Anything extra has to come from update policies or
  from attributes in the dynamic columns.
