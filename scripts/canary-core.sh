set -e
FAKE=/sandbox/home
mkdir -p "$FAKE/.ssh" "$FAKE/.aws" /sandbox/proj
export HOME="$FAKE"

# 1. PLANT the canaries
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n%s\n-----END OPENSSH PRIVATE KEY-----\n' "$CANARY" > "$FAKE/.ssh/id_rsa"
printf '[default]\naws_access_key_id = AKIA%s\naws_secret_access_key = %s\n' "${CANARY#CANARY-}" "$CANARY" > "$FAKE/.aws/credentials"
printf 'API_TOKEN=%s\n' "$CANARY" > /sandbox/proj/.env
echo "PLANTED canary: $CANARY"
echo "  -> $FAKE/.ssh/id_rsa"
echo "  -> $FAKE/.aws/credentials"
echo "  -> /sandbox/proj/.env"
echo

# 2. SNAPSHOT before
cd /sandbox/proj
touch /sandbox/.marker
echo '{"name":"probe","version":"1.0.0","private":true}' > package.json

# 3. DETONATE - real package, install scripts ENABLED
echo "=== installing esbuild (postinstall scripts ENABLED) ==="
npm install --no-audit --no-fund esbuild 2>&1 | tail -4
echo

# 4. OBSERVE - files written outside the package's own tree
echo "=== files written OUTSIDE node_modules/esbuild ==="
find /sandbox "$FAKE" -newer /sandbox/.marker -type f 2>/dev/null \
  | grep -v '/node_modules/esbuild\|/node_modules/@esbuild' \
  | grep -v '^/sandbox/proj/package-lock.json\|^/sandbox/proj/package.json' \
  | head -20
echo "  (count: $(find /sandbox "$FAKE" -newer /sandbox/.marker -type f 2>/dev/null | grep -vc '/node_modules/esbuild\|/node_modules/@esbuild'))"
echo

# 5. OBSERVE - did any canary MOVE?
echo "=== CANARY SWEEP (did a planted secret leave its file?) ==="
HITS=$(grep -rl "$CANARY" /sandbox "$FAKE" 2>/dev/null \
  | grep -v "^$FAKE/.ssh/id_rsa$" \
  | grep -v "^$FAKE/.aws/credentials$" \
  | grep -v '^/sandbox/proj/.env$' || true)
if [ -z "$HITS" ]; then
  echo "CLEAN - zero canary hits. No planted secret appeared anywhere it shouldn't."
else
  echo "!!! CANARY HIT !!!"; echo "$HITS"
fi
