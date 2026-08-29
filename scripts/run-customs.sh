#!/bin/bash
# Run the Customs agent against a pull request. Shows the tool calls it makes and
# stops when a tool call pauses for human approval.
set -uo pipefail
TF="${TRUEFORGE_URL:-http://localhost:8790}"
PR="${1:?usage: run-customs.sh <pr-number>}"
REPO="${2:-bhargava-gumpula/agent-harness-hackathon}"

SID=$(curl -s -X POST "$TF/api/v1/sessions" -H 'content-type: application/json' \
  -d '{"agent":{"name":"customs"}}' \
  | python3 -c 'import sys,json;print((json.load(sys.stdin).get("data") or {}).get("id",""))')
[ -n "$SID" ] || { echo "failed to create session"; exit 1; }
echo "session: $SID"; echo "$SID" > /tmp/customs-session

MSG="Inspect pull request #$PR in the repository $REPO."
curl -s --max-time 30 -o /dev/null -X POST "$TF/api/v1/sessions/$SID/turns" \
  -H 'content-type: application/json' \
  -d "$(M="$MSG" python3 -c 'import json,os;print(json.dumps({"stream":False,"input":[{"type":"user.message","content":os.environ["M"]}]}))')"

echo "==> running (free-tier rate limits make this slow)"
i=0
while [ $i -lt 200 ]; do
  R=$(curl -s "$TF/api/v1/sessions/$SID/turns")
  ST=$(printf '%s' "$R" | python3 -c 'import sys,json
try: print(json.load(sys.stdin)["data"][-1].get("state",{}).get("status",""))
except Exception: print("")' 2>/dev/null)
  [ -n "$ST" ] && [ "$ST" != "running" ] && break
  i=$((i+1)); sleep 4
done
echo "status: $ST"

echo; echo "==== what the agent did ===="
curl -s "$TF/api/v1/sessions/$SID/events" | python3 -c '
import sys,json
for e in (json.load(sys.stdin).get("data") or []):
    t=e.get("type","")
    if t=="tool.call":
        print("  call:",e.get("name"),str(e.get("arguments"))[:150])
    elif t=="tool.approval_required":
        print("  *** APPROVAL REQUIRED ***")
        for tc in e.get("tool_calls",[]): print("      ",json.dumps(tc)[:300])
    elif t in ("sandbox.created",): print("  sandbox created:",e.get("sandbox_id"))
' 2>/dev/null | head -40

echo; echo "==== result ===="
printf '%s' "$R" | python3 -c '
import sys,json
t=json.load(sys.stdin)["data"][-1]; st=t.get("state",{})
if st.get("message"): print("message:",st["message"][:400])
ra=st.get("required_actions") or []
if ra:
    print(">>> PAUSED FOR HUMAN APPROVAL <<<")
    print(json.dumps(ra,indent=1)[:1000])
o=st.get("output") or {}
c=o.get("content")
if isinstance(c,list): c=" ".join(p.get("text","") for p in c if isinstance(p,dict))
if c: print(); print(c)
m=st.get("metrics") or {}
print("\ntokens:",m.get("total_tokens"))'
