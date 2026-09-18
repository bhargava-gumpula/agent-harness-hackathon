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
# Each entry wraps the real event under "event", and the list arrives newest-first.
# Tool calls live on model.message under tool_calls[].function, and tool_info says
# whether a call went to an MCP server, the sandbox, or the harness itself.
curl -s "$TF/api/v1/sessions/$SID/events" | python3 -c '
import sys,json
d=json.load(sys.stdin).get("data") or []
for e in reversed(d):
    ev=e.get("event") or {}
    t=ev.get("type","")
    if t=="sandbox.created":
        print("  [sandbox] created")
    elif t=="tool.approval_required":
        print("  *** PAUSED FOR HUMAN APPROVAL ***")
    elif t=="model.message":
        for tc in ev.get("tool_calls") or []:
            fn=tc.get("function") or {}
            name=fn.get("name","")
            info=tc.get("tool_info") or {}
            kind=info.get("type","")
            server=info.get("server_name","")
            try: args=json.loads(fn.get("arguments") or "{}")
            except Exception: args={}
            if kind=="mcp":
                print("  [mcp:"+str(server)+"] "+name+" "+json.dumps(args)[:120])
            elif name=="exec":
                print("  [sandbox] exec - "+str(args.get("intent",""))[:90])
            elif name=="call_tool":
                # Code Mode routes an MCP call through the sandbox. This is the call
                # being MADE - whether it was held is the tool.approval_required event.
                inp=args.get("input") or {}
                detail=inp.get("package") or inp.get("pullNumber") or ""
                print("  [mcp:"+str(args.get("mcp_server"))+"] "+str(args.get("tool_name"))+(" "+str(detail) if detail else "")+"  (via code mode)")
            elif kind=="truefoundry-system":
                print("  [harness] "+name)
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
