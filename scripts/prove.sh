#!/bin/bash
# Proves the Customs detector works in BOTH directions, and FAILS LOUDLY if it does not.
#
# A detector that never fires looks exactly like a detector that is broken. This script
# exists to tell those apart, so it asserts and exits non-zero rather than reporting.
#
#   bash scripts/prove.sh
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
FAILED=0

# Each invocation of customs generates its own fresh, unguessable canary internally,
# so no marker is ever reused between detonations.
assert() {                       # assert <label> <target> <expected true|false>
  local label="$1" target="$2" want="$3"
  printf '%-42s' "$label"
  local out got
  out=$(bash customs/customs.sh inspect "$target" 2>/dev/null)
  got=$(printf '%s' "$out" | python3 -c 'import sys,json
try: print(str(json.load(sys.stdin).get("canary_hit")).lower())
except Exception: print("error")' 2>/dev/null)
  if [ "$got" = "$want" ]; then
    echo "PASS  (canary_hit=$got)"
  else
    echo "FAIL  (canary_hit=$got, expected $want)"
    printf '%s\n' "$out" | sed 's/^/      /'
    FAILED=1
  fi
}

echo "=== Customs detector proof ==="
echo
# Positive control: MUST fire. If this passes silently, the detector is broken.
assert "positive control (must fire)" "fixtures/customs-demo-exfil" true
# Real packages with genuine postinstall scripts: must NOT fire.
assert "esbuild (real, must stay clean)" "esbuild" false
assert "sharp (real, must stay clean)"   "sharp"   false

echo
if [ "$FAILED" -eq 0 ]; then
  echo "ALL PROOFS PASSED - the detector fires on theft and stays quiet otherwise."
else
  echo "PROOF FAILED - do not trust any Customs result until this passes."
fi
exit "$FAILED"
