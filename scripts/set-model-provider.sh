#!/bin/bash
# Register a model provider with TrueForge, pulling model definitions straight
# from TrueForge's own catalog. Prompts for the key (hidden; never stored on disk).
#
#   bash scripts/set-model-provider.sh anthropic
#   bash scripts/set-model-provider.sh openai
#
set -uo pipefail
TF="${TRUEFORGE_URL:-http://localhost:8790}"
PROVIDER="${1:-}"

if [ -z "$PROVIDER" ]; then
  echo "usage: $0 <provider>"
  echo "available:"
  curl -s "$TF/api/v1/catalogs/model-providers" \
    | python3 -c 'import sys,json
for p in (json.load(sys.stdin).get("data") or []): print("   ",p.get("type"))'
  exit 1
fi

curl -sf --max-time 5 "$TF/healthz" >/dev/null || { echo "TrueForge not reachable at $TF"; exit 1; }

CATALOG=$(curl -s --max-time 10 "$TF/api/v1/catalogs/model-providers")
printf '%s' "$CATALOG" | PROVIDER="$PROVIDER" python3 -c '
import sys,json,os
p=os.environ["PROVIDER"]
d=json.load(sys.stdin).get("data") or []
e=[x for x in d if x.get("type")==p]
if not e: print("unknown provider:",p); sys.exit(1)
print("models that will be registered:")
for m in e[0].get("models",[]): print("   ",m.get("model_id"))
' || exit 1

printf 'Paste your %s API key (input hidden): ' "$PROVIDER"
read -rs KEY; echo
[ -n "$KEY" ] || { echo "No key entered."; exit 1; }

BODY=$(printf '%s' "$CATALOG" | PROVIDER="$PROVIDER" KEY="$KEY" python3 -c '
import sys,json,os
p=os.environ["PROVIDER"]
entry=[x for x in (json.load(sys.stdin).get("data") or []) if x.get("type")==p][0]
manifest={"type":p,"auth":{"api_key":os.environ["KEY"]},"models":entry["models"]}
print(json.dumps({"manifest":manifest}))')

echo "==> registering with TrueForge"
CODE=$(printf '%s' "$BODY" | curl -s -o /tmp/tf-resp.json -w '%{http_code}' \
  -X PUT "$TF/api/v1/settings/model-providers" \
  -H 'content-type: application/json' --data-binary @-)
unset KEY BODY
if [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
  echo "FAILED (HTTP $CODE):"; python3 -m json.tool /tmp/tf-resp.json 2>/dev/null || cat /tmp/tf-resp.json
  rm -f /tmp/tf-resp.json; exit 1
fi
rm -f /tmp/tf-resp.json
echo "==> registered. models now available:"
curl -s "$TF/api/v1/models" | python3 -c '
import sys,json
for m in (json.load(sys.stdin).get("data") or []): print("   ",m.get("name"))'
echo
echo "Now verify with a real turn:"
echo "   bash scripts/verify-trueforge.sh <provider>/<model-name>"
