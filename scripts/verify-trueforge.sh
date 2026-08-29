#!/bin/bash
# Proves the whole path works: TrueForge -> provider -> Gemini -> a real answer.
set -uo pipefail
TF="${TRUEFORGE_URL:-http://localhost:8790}"
MODEL="${1:-google-gemini/gemini-3-6-flash}"

echo "==> model: $MODEL"
SID=$(curl -s --max-time 15 -X POST "$TF/api/v1/sessions" -H 'content-type: application/json' \
  -d "{\"agent\":{\"spec\":{\"model\":{\"name\":\"$MODEL\"}}}}" \
  | python3 -c 'import sys,json;print((json.load(sys.stdin).get("data") or {}).get("id",""))' 2>/dev/null)
[ -n "$SID" ] || { echo "FAILED to create session"; exit 1; }
echo "==> session: $SID"

curl -s --max-time 30 -o /dev/null -X POST "$TF/api/v1/sessions/$SID/turns" \
  -H 'content-type: application/json' \
  -d '{"stream":false,"input":[{"type":"user.message","content":"Reply with exactly: TRUEFORGE OK"}]}'
echo "==> turn dispatched, waiting..."

R=""; i=0
until [ $i -ge 45 ]; do
  R=$(curl -s "$TF/api/v1/sessions/$SID/turns")
  ST=$(printf '%s' "$R" | python3 -c 'import sys,json
try: print(json.load(sys.stdin)["data"][-1].get("state",{}).get("status",""))
except Exception: print("")' 2>/dev/null)
  [ -n "$ST" ] && [ "$ST" != "running" ] && break
  i=$((i+1)); sleep 2
done

printf '%s' "$R" | python3 -c '
import sys,json
t=json.load(sys.stdin)["data"][-1]; st=t.get("state",{})
status=st.get("status")
if status!="done":
    print("\n  RESULT: FAILED  (status: %s)"%status)
    print("  ", st.get("message"))
    if "API key not valid" in str(st.get("message","")):
        print("\n  -> Key stored in TrueForge is wrong or missing.")
        print("     Fix: http://localhost:8790 -> Settings -> Models -> Google Gemini")
    sys.exit(1)
out=st.get("output") or {}
c=out.get("content")
if isinstance(c,list):
    c=" ".join(p.get("text","") for p in c if isinstance(p,dict))
m=st.get("metrics") or {}
print("\n  RESULT: OK")
print("  model said:", c)
print("  tokens: in=%s out=%s total=%s"%(m.get("total_input_tokens"),
      m.get("total_output_tokens"),m.get("total_tokens")))
print("\n  TrueForge -> Gemini is working end to end.")'
