#!/usr/bin/env bash
# Delete everything deploy.sh created. APIM, ADX and AKS bill by the hour, so tear a test
# deployment down the same day.
#   bash scripts/teardown.sh <resource-group>
# Key Vault has purge protection on, so its name stays reserved for the soft-delete period
# (90 days). Pick a different prefix if you redeploy before then.
set -euo pipefail

rg="${1:?usage: teardown.sh <resource-group>}"
read -r -p "Delete resource group $rg and everything in it? [y/N] " answer
[[ "$answer" == "y" ]] || { echo "aborted"; exit 1; }
az group delete -n "$rg" --yes --no-wait
echo "deletion started; check with: az group show -n $rg"
