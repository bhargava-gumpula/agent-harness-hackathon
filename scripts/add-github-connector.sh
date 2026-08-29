#!/bin/bash
# Register the GitHub MCP connector with TrueForge.
#
# The token is read straight from `gh auth token` and piped to the local TrueForge
# API. It is never printed, never written to disk, and never passed as an argument.
set -uo pipefail
TF="${TRUEFORGE_URL:-http://localhost:8790}"

curl -sf --max-time 5 "$TF/healthz" >/dev/null || { echo "TrueForge not reachable at $TF"; exit 1; }
command -v gh >/dev/null || { echo "gh CLI not found"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not authenticated - run: gh auth login"; exit 1; }

echo "==> using the GitHub token from 'gh auth token' (value is never displayed)"
BODY=$(TOKEN="$(gh auth token)" python3 -c '
import json,os
print(json.dumps({"manifest":{
  "type":"remote",
  "name":"github",
  "url":"https://api.githubcopilot.com/mcp/",
  "description":"Work with issues, pull requests, repository files, and CI status.",
  "auth":{"type":"header","headers":{"Authorization":"Bearer "+os.environ["TOKEN"]}}
}}))')

CODE=$(printf '%s' "$BODY" | curl -s -o /tmp/tf-mcp.json -w '%{http_code}' \
  -X PUT "$TF/api/v1/settings/mcp-servers" -H 'content-type: application/json' --data-binary @-)
unset BODY
if [ "$CODE" = "409" ]; then
  echo "    connector already exists - leaving it as is"
elif [ "$CODE" != "200" ] && [ "$CODE" != "201" ]; then
  echo "FAILED (HTTP $CODE):"; python3 -m json.tool /tmp/tf-mcp.json 2>/dev/null || cat /tmp/tf-mcp.json
  rm -f /tmp/tf-mcp.json; exit 1
else
  echo "    registered"
fi
rm -f /tmp/tf-mcp.json

echo "==> configured connectors:"
curl -s "$TF/api/v1/settings/mcp-servers" | python3 -c '
import sys,json
for s in (json.load(sys.stdin).get("data") or []):
    print("   ",s.get("name"),"-",s.get("auth_status"))'
