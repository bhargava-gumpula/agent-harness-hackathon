#!/usr/bin/env node
// customs-mcp — exposes `customs.sh inspect` to an agent as an MCP tool.
//
//   node customs/mcp-server.js            # listens on http://127.0.0.1:8791/mcp
//
// Why this exists: TrueForge's local sandbox runs under a macOS seatbelt profile
// whose allow-read list is hardcoded. It cannot read this repo, cannot reach the
// Docker socket, and cannot reach registry.npmjs.org — so the detonation cannot
// run there. It has to run on the host, and MCP is how the agent reaches the host.
//
// Zero dependencies on purpose: MCP over HTTP is JSON-RPC on a POST endpoint, and
// a demo should not acquire a dependency tree hours before it is filmed.

const http = require("http");
const { execFile } = require("child_process");
const path = require("path");

const PORT = Number(process.env.CUSTOMS_MCP_PORT || 8791);
const HOST = "127.0.0.1"; // loopback only — never expose a shell-adjacent tool on 0.0.0.0
const CUSTOMS_SH = path.join(__dirname, "customs.sh");
const PROTOCOL_VERSION = "2025-06-18";
const EXEC_TIMEOUT_MS = 300_000; // customs.sh self-limits to 240s; leave headroom

// A package name reaches a subprocess argument. execFile never invokes a shell, so
// there is no metacharacter to escape — but validate anyway rather than rely on one
// layer. npm names are [@scope/]name, optionally @version.
const SAFE_PKG = /^[@a-zA-Z0-9][@a-zA-Z0-9._/-]{0,213}$/;

// A local `file:` dependency is inspected by path, so slashes are legitimate — but a
// `..` segment would let a caller tar up any directory on the host and ship it into a
// container. Names are checked for shape AND for traversal.
function acceptablePackage(pkg) {
  if (typeof pkg !== "string" || !SAFE_PKG.test(pkg)) return false;
  return !pkg.split("/").includes("..");
}

const TOOL = {
  name: "customs_inspect",
  description:
    "Detonate one npm package inside a disposable Docker container seeded with decoy " +
    "credentials, and report whether any decoy left its file. Returns JSON with " +
    "canary_hit (the observation that matters), verdict, hosts_contacted, and " +
    "files_written_outside_package. Call this at most once per package. Takes up to " +
    "four minutes — that is the container doing real work, not a hang.",
  inputSchema: {
    type: "object",
    properties: {
      package: {
        type: "string",
        description: "npm package name, optionally with a version, e.g. 'esbuild' or 'left-pad@1.3.0'.",
      },
    },
    required: ["package"],
    additionalProperties: false,
  },
  // MCP defaults destructiveHint to true for an unannotated tool, which makes a
  // harness gate this behind human approval. Inspecting is not destructive: the
  // container is disposable and nothing outside it is touched. The approval gate
  // belongs on posting a public comment, not on looking.
  annotations: {
    title: "Inspect an npm package",
    readOnlyHint: false,
    destructiveHint: false,
    idempotentHint: false,
    openWorldHint: true,
  },
};

function runInspect(pkg) {
  return new Promise((resolve) => {
    execFile(
      "/bin/bash",
      [CUSTOMS_SH, "inspect", pkg],
      { timeout: EXEC_TIMEOUT_MS, maxBuffer: 8 * 1024 * 1024 },
      (err, stdout, stderr) => {
        const out = (stdout || "").trim();
        if (out) return resolve(out); // customs.sh reports its own failures as JSON
        resolve(
          JSON.stringify({
            error: err ? `inspection failed: ${err.message}` : "inspection produced no output",
            stderr: (stderr || "").trim().slice(0, 2000),
          })
        );
      }
    );
  });
}

async function handle(msg) {
  const { id, method, params } = msg;
  const reply = (result) => ({ jsonrpc: "2.0", id, result });
  const fail = (code, message) => ({ jsonrpc: "2.0", id, error: { code, message } });

  switch (method) {
    case "initialize":
      return reply({
        // Echo the client's version when we recognise it; otherwise state ours.
        protocolVersion: params?.protocolVersion || PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "customs", version: "1.0.0" },
      });

    case "ping":
      return reply({});

    case "tools/list":
      return reply({ tools: [TOOL] });

    case "tools/call": {
      if (params?.name !== TOOL.name) return fail(-32602, `unknown tool: ${params?.name}`);
      const pkg = params?.arguments?.package;
      if (!acceptablePackage(pkg)) {
        return reply({
          content: [{ type: "text", text: JSON.stringify({ error: "invalid package name" }) }],
          isError: true,
        });
      }
      console.error(`[customs-mcp] inspecting ${pkg}`);
      const text = await runInspect(pkg);
      console.error(`[customs-mcp] done ${pkg}`);
      // A failed inspection is a reportable result, not a protocol error — the agent
      // must be able to say "this could not be inspected" rather than crash the turn.
      return reply({ content: [{ type: "text", text }], isError: false });
    }

    default:
      return fail(-32601, `method not found: ${method}`);
  }
}

const server = http.createServer((req, res) => {
  if (req.method === "GET" && req.url.startsWith("/health")) {
    res.writeHead(200, { "content-type": "application/json" });
    return res.end(JSON.stringify({ ok: true, tool: TOOL.name }));
  }
  // No server-initiated messages, so there is no SSE stream to open.
  if (req.method === "GET") return res.writeHead(405).end();
  if (req.method !== "POST") return res.writeHead(405).end();

  let body = "";
  req.on("data", (c) => {
    body += c;
    if (body.length > 1e6) req.destroy();
  });
  req.on("end", async () => {
    let msg;
    try {
      msg = JSON.parse(body);
    } catch {
      res.writeHead(400, { "content-type": "application/json" });
      return res.end(JSON.stringify({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "parse error" } }));
    }
    // Notifications have no id and take no response.
    if (msg.id === undefined || msg.id === null) return res.writeHead(202).end();

    let out;
    try {
      out = await handle(msg);
    } catch (e) {
      out = { jsonrpc: "2.0", id: msg.id, error: { code: -32603, message: String(e && e.message) } };
    }
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify(out));
  });
});

server.listen(PORT, HOST, () => {
  console.error(`[customs-mcp] listening on http://${HOST}:${PORT}/mcp`);
});
