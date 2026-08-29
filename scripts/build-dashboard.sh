#!/bin/bash
# Run Customs over a set of packages and bake the real results into a self-contained
# dashboard at web/dashboard.html. No mock data: every row is an actual inspection.
#
#   bash scripts/build-dashboard.sh [package ...]
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
OUT=web/results.json
TARGETS=("$@")
if [ ${#TARGETS[@]} -eq 0 ]; then
  TARGETS=(fixtures/customs-demo-exfil esbuild sharp bcrypt)
fi

echo "[" > "$OUT"
first=1
for t in "${TARGETS[@]}"; do
  printf 'inspecting %-38s' "$t"
  started=$(date +%s)
  r=$(bash customs/customs.sh inspect "$t" 2>/dev/null)
  elapsed=$(( $(date +%s) - started ))
  if ! printf '%s' "$r" | python3 -c 'import sys,json;json.load(sys.stdin)' 2>/dev/null; then
    r=$(printf '{"package":"%s","error":"inspection failed"}' "$t")
  fi
  hit=$(printf '%s' "$r" | python3 -c 'import sys,json
try: print(str(json.load(sys.stdin).get("canary_hit")).lower())
except Exception: print("error")' 2>/dev/null)
  echo "$hit  (${elapsed}s)"
  [ $first -eq 0 ] && echo "," >> "$OUT"
  printf '%s' "$r" | TGT="$t" EL="$elapsed" python3 -c '
import sys,json,os
d=json.load(sys.stdin); d["target"]=os.environ["TGT"]; d["seconds"]=int(os.environ["EL"])
print(json.dumps(d))' >> "$OUT"
  first=0
done
echo "]" >> "$OUT"

python3 scripts/render_dashboard.py "$OUT" web/dashboard.html
echo "wrote web/dashboard.html"
