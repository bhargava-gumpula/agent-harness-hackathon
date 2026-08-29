#!/bin/sh
# Runs INSIDE the disposable container.
#
# Phase 1: resolve the dependency tree with scripts DISABLED (network normal, so npm
#          can reach the registry).
# Phase 2: arm a transparent sinkhole - iptables redirects ALL outbound TCP to a local
#          listener - then run the install scripts and import the package. Anything the
#          package tries to send is captured regardless of whether it honours HTTP_PROXY.
# Phase 3: sweep for planted decoys that moved.
set -u
PKG="$PKG"; CANARY="$CANARY"; LOCAL_TGZ="${LOCAL_TGZ:-}"
FAKE=/sandbox/home; PROJ=/sandbox/proj
mkdir -p "$FAKE/.ssh" "$FAKE/.aws" "$PROJ" /sandbox/local
export HOME="$FAKE"

[ -n "$LOCAL_TGZ" ] && printf '%s' "$LOCAL_TGZ" | base64 -d | tar -xzf - -C /sandbox/local 2>/dev/null

# --- plant decoys ---
printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\n%s\n-----END OPENSSH PRIVATE KEY-----\n' "$CANARY" > "$FAKE/.ssh/id_rsa"
printf '[default]\naws_access_key_id = AKIA%s\naws_secret_access_key = %s\n' "${CANARY#CANARY-}" "$CANARY" > "$FAKE/.aws/credentials"
printf 'API_TOKEN=%s\n' "$CANARY" > "/sandbox/.env"
printf 'API_TOKEN=%s\n' "$CANARY" > "$PROJ/.env"

cd "$PROJ"
echo '{"name":"customs-probe","version":"1.0.0","private":true}' > package.json

# --- PHASE 1: resolve tree, scripts disabled ---
timeout 120 npm install --ignore-scripts --no-audit --no-fund "$PKG" >/sandbox/install1.log 2>&1
P1=$?

# --- arm the sinkhole ---
apk add --no-cache iptables >/dev/null 2>&1
cat > /sandbox/sink.js <<'EOF'
const net=require('net'),fs=require('fs');
const LOG='/sandbox/egress.log';
const rec=s=>{try{fs.appendFileSync(LOG,s+'\n')}catch(e){}};
// Pull the SNI hostname out of a TLS ClientHello so HTTPS destinations are still visible.
function sni(b){try{
  if(b[0]!==0x16)return null; let p=43; p+=1+b[p]; p+=2+b.readUInt16BE(p); p+=1+b[p];
  const extEnd=p+2+b.readUInt16BE(p); p+=2;
  while(p<extEnd){const t=b.readUInt16BE(p),l=b.readUInt16BE(p+2);
    if(t===0)return b.toString('utf8',p+9,p+9+b.readUInt16BE(p+7));
    p+=4+l;}
}catch(e){} return null;}
net.createServer(s=>{
  let buf=Buffer.alloc(0), done=false;
  const finish=()=>{ if(done)return; done=true;
    try{ s.end('HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 2\r\n\r\nok'); }catch(e){}
    setTimeout(()=>{try{s.destroy()}catch(e){}},50); };
  s.setTimeout(3000,finish);
  s.on('data',d=>{ buf=Buffer.concat([buf,d]);
    if(buf.length<16384){
      const h=sni(buf);
      if(h){ rec(`TLS_CONNECT host=${h}`); return finish(); }
      const head=buf.toString('utf8',0,8);
      if(/^[A-Z]{3,7} /.test(head)){
        rec(`PLAINTEXT ${buf.toString('utf8',0,8000)}`);
        // wait briefly for the body, then answer so the client is never left hanging
        setTimeout(finish,300);
      }
    }});
  s.on('error',()=>{}); s.on('end',finish);
}).listen(8899,'0.0.0.0');
EOF
# Answer every DNS query with 127.0.0.1 so a connection is always attempted, even when
# the attacker's host is dead or the name is unregistrable. Without this, an unresolvable
# name means no packet is ever emitted and there is nothing for iptables to redirect.
cat > /sandbox/dns.js <<'EOF'
const dgram=require('dgram'),s=dgram.createSocket('udp4');
s.on('message',(m,r)=>{try{
  const id=m.subarray(0,2);
  let p=12; while(m[p]!==0)p+=m[p]+1; const qEnd=p+5;
  const q=m.subarray(12,qEnd);
  const h=Buffer.concat([id,Buffer.from([0x81,0x80,0,1,0,1,0,0,0,0])]);
  const a=Buffer.concat([Buffer.from([0xc0,0x0c,0,1,0,1,0,0,0,60,0,4]),Buffer.from([127,0,0,1])]);
  s.send(Buffer.concat([h,q,a]),r.port,r.address);
}catch(e){}});
s.bind(53,'127.0.0.1');
EOF
node /sandbox/dns.js & DNS=$!
node /sandbox/sink.js & SINK=$!
sleep 1
echo 'nameserver 127.0.0.1' > /etc/resolv.conf
# Redirect every outbound TCP connection (except to the sinkhole itself) into the sinkhole.
iptables -t nat -A OUTPUT -p tcp --dport 8899 -j RETURN 2>/dev/null
iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-port 8899 2>/dev/null
ARMED=$?

# --- PHASE 2: detonate ---
timeout 90 npm rebuild --foreground-scripts >/sandbox/install2.log 2>&1
P2=$?
BASE=$(basename "$PKG" | sed 's/@[^@]*$//')
timeout 30 node -e "try{require('$BASE')}catch(e){}" >/sandbox/import.log 2>&1
sleep 2
iptables -t nat -F OUTPUT 2>/dev/null
kill $SINK $DNS 2>/dev/null

# --- PHASE 3: sweep ---
CANARY_FILES=$(grep -rl "$CANARY" /sandbox "$FAKE" 2>/dev/null \
  | grep -v "^$FAKE/.ssh/id_rsa$" | grep -v "^$FAKE/.aws/credentials$" \
  | grep -v "^$PROJ/.env$" | grep -v "^/sandbox/.env$" \
  | grep -v '^/sandbox/egress.log$' | head -20)
CANARY_NET=$(grep -c "$CANARY" /sandbox/egress.log 2>/dev/null | head -1); [ -n "$CANARY_NET" ] || CANARY_NET=0
HOSTS=$(grep -oE 'TLS_CONNECT host=[^ ]+|Host: [^ ]+' /sandbox/egress.log 2>/dev/null \
  | sed 's/TLS_CONNECT host=//; s/Host: //' | tr -d '\r' | sort -u | head -20)
OUTSIDE=$(find "$PROJ" "$FAKE" -newer "$PROJ/package.json" -type f 2>/dev/null \
  | grep -v '/node_modules/' | grep -v "$FAKE/.npm" | head -20)

arr() { [ -z "$1" ] && { printf '[]'; return; }; printf '%s' "$1" | awk 'BEGIN{printf"["}{printf"%s\"%s\"",(NR>1?",":""),$0}END{printf"]"}'; }
HIT=false; { [ -n "$CANARY_FILES" ] || [ "$CANARY_NET" -gt 0 ]; } && HIT=true

echo "---CUSTOMS-JSON---"
cat <<JSON
{
  "package": "$PKG",
  "sinkhole_armed": $([ "$ARMED" -eq 0 ] && echo true || echo false),
  "install_exit_ignore_scripts": $P1,
  "script_exec_exit": $P2,
  "canary_hit": $HIT,
  "canary_in_files": $(arr "$CANARY_FILES"),
  "canary_in_network_bytes": $CANARY_NET,
  "hosts_contacted": $(arr "$HOSTS"),
  "files_written_outside_package": $(arr "$OUTSIDE")
}
JSON
