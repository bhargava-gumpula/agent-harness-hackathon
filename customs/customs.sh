#!/bin/bash
# customs — inspect a package before it enters your dependency tree.
#
#   customs inspect <package[@version]>
#
# Detonates the package inside a disposable Docker container seeded with decoy
# credentials, then reports whether any decoy moved. Emits JSON on stdout.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${CUSTOMS_IMAGE:-node:22-alpine}"
TIMEOUT_S="${CUSTOMS_TIMEOUT:-240}"

# Colima's socket is not at /var/run/docker.sock. Resolve it, or trust an override.
if [ -z "${DOCKER_HOST:-}" ]; then
  for s in "$HOME/.colima/default/docker.sock" /var/run/docker.sock; do
    [ -S "$s" ] && { export DOCKER_HOST="unix://$s"; break; }
  done
fi
DOCKER="${DOCKER_BIN:-$(command -v docker || echo /opt/homebrew/bin/docker)}"

die() { printf '{"error":%s}\n' "\"$1\""; exit 1; }

cmd="${1:-}"; shift || true
[ "$cmd" = "inspect" ] || { echo "usage: customs inspect <package[@version]>" >&2; exit 1; }
PKG="${1:-}"; [ -n "$PKG" ] || { echo "usage: customs inspect <package[@version]>" >&2; exit 1; }

"$DOCKER" info >/dev/null 2>&1 || die "docker unreachable (DOCKER_HOST=${DOCKER_HOST:-unset}) - is colima running?"

# A local directory is shipped in as a base64 tarball: the VM has no host mounts
# (colima --mount none), so bind-mounting is deliberately unavailable.
LOCAL_TGZ=""
if [ -d "$PKG" ]; then
  LOCAL_TGZ=$(tar -czf - -C "$(dirname "$PKG")" "$(basename "$PKG")" 2>/dev/null | base64 | tr -d '\n')
  PKG="/sandbox/local/$(basename "$PKG")"
fi

CANARY="CANARY-$( (uuidgen 2>/dev/null || head -c16 /dev/urandom | od -An -tx1) | tr -d ' -' | tr 'a-z' 'A-Z' | head -c 24)"

RAW=$("$DOCKER" run --rm -i \
  --stop-timeout 10 --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -e PKG="$PKG" -e CANARY="$CANARY" -e LOCAL_TGZ="$LOCAL_TGZ" \
  "$IMAGE" sh -s < "$HERE/inspect-in-container.sh" 2>/dev/null)
RC=$?

JSON=$(printf '%s' "$RAW" | awk '/^---CUSTOMS-JSON---$/{f=1;next} f')
[ -n "$JSON" ] || die "inspection produced no result (exit $RC)"
printf '%s' "$JSON" | python3 -c '
import sys,json
try:
    d=json.load(sys.stdin)
except Exception as e:
    print(json.dumps({"error":"unparseable result: %s"%e})); sys.exit(1)
hit=d.get("canary_hit")
d["verdict"]="CANARY HIT - a planted credential left its file" if hit else "clean - no planted credential moved"
print(json.dumps(d,indent=2))'
