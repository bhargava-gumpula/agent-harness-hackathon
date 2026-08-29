# Customs

**An agent that inspects an npm package before it enters your dependency tree — by
detonating it in a disposable container seeded with decoy credentials, and reporting
whether any decoy moved.**

Built on [TrueForge](https://github.com/truefoundry/trueforge) for the
[Agent Harness Hackathon](https://www.wemakedevs.org/hackathons/trueforge)
(WeMakeDevs × TrueFoundry).

---

## The problem

`npm install` executes a package's `postinstall` script on your machine **before a single
line of your own code runs**. Reading the source does not settle whether that is safe —
payloads are obfuscated, or fetched from elsewhere at install time.

The only way to know what a package does is to run it somewhere disposable and watch.

That is a thing an AI assistant structurally cannot do for you. It can read the source and
give you an opinion; it must refuse to actually execute an unknown stranger's install script
on your laptop. The one action that would answer the question is the one it cannot take.

## What Customs does

On a pull request that adds or bumps a dependency, for each package:

1. Opens a **disposable Docker container** with no access to your filesystem.
2. Plants **decoy credentials** — a fake `~/.ssh/id_rsa`, `~/.aws/credentials` and `.env`,
   each containing a unique, unguessable marker string.
3. Runs `npm install` with install scripts **enabled**, then `require()`s the package.
4. Captures every outbound TCP connection and every file written.
5. Reports whether any planted marker **left its file**.
6. **Stops and asks a human** before posting anything publicly.

A canary hit is an observation, not a judgement: a unique string either turned up somewhere
it should not have, or it did not. No model sits between the evidence and the verdict.

## Prior art — this technique is not new

The contribution here is **placement and cost**, and it would be dishonest to imply otherwise:

- **[OpenSSF Package Analysis](https://github.com/ossf/package-analysis)** already detonates
  packages in gVisor sandboxes with syscall tracing, and has found 200+ malicious packages.
  But it is a scheduled registry-wide pipeline that emits data to BigQuery — by its own
  documentation it does not make decisions or take actions.
- **SafeDep** does eBPF-based dynamic analysis commercially — also a scanner, not an actor.
- **[Socket.dev](https://docs.socket.dev/docs/faq)**, the market leader, is **static only**
  and explicitly does not execute install scripts.

What is missing is an agent that sits *in the pull request loop*, decides, pauses for a
human, and acts. And decoy credentials turn out to be a far cheaper signal than syscall
tracing: no gVisor, no eBPF, no data warehouse — it runs on a laptop.

---

## How it uses TrueForge

| Harness capability | Used | How |
| --- | --- | --- |
| MCP connectors | ☑ | GitHub connector reads the pull request diff and posts the finding |
| Sandbox | ☑ | The agent's orchestration runs in the TrueForge sandbox; detonation happens one layer deeper, in Docker |
| Human approval checkpoint | ☑ | `add_issue_comment` is behind `require_approval_for_tools` — nothing is ever posted publicly without a person saying yes |
| Persistent sessions | ☑ | Session state survives across the approval pause |

### Architecture — and where the real boundary is

```text
  pull request
      │
      ▼
  ┌─────────────────────────────────┐        ┌──────────────────────────────┐
  │  YOUR MAC · runs as you         │        │  COLIMA VM · --mount none    │
  │                                 │        │                              │
  │   TrueForge agent               │        │   disposable container       │
  │        │                        │        │     · decoys planted         │
  │        ▼                        │        │     · package detonates      │
  │   TrueForge sandbox ────────────┼───────▶│     · sinkhole listening     │
  │   (whoami → your user)          │ docker │     · /Users does not exist  │
  │                                 │  run   │                              │
  │   ~/.ssh  ~/.aws  ~/.npmrc      │   ✕────┼─── no route back             │
  └─────────────────────────────────┘        └──────────────────────────────┘
                                        ▲
                              the only real boundary
```

**TrueForge's local sandbox is not isolation.** Ask an agent to run `whoami` inside it and
it answers with your own username on your own kernel. It shares a disk with your real SSH
key. Containment comes only from crossing into the Colima VM, which is started with
`--mount none` so the host filesystem is not hidden but *absent*.

Untrusted code only ever executes on the right-hand side of that line.

### How detection works — ordering is the trick

```text
 PHASE 1                    ARM                        PHASE 2
 resolve the tree           DNS + iptables             detonate
 npm install                every name → 127.0.0.1     npm rebuild → scripts run
   --ignore-scripts         REDIRECT → sinkhole        require(pkg)
 network normal             (needs NET_ADMIN)          everything sent is captured
 nothing untrusted ran
                                    ─────────────────────────────────▶
                                              traps armed

 PHASE 3 · sweep files and captured bytes for the planted marker
```

npm needs the real registry, so the tree resolves **first**, with scripts disabled — nothing
untrusted has run yet. Only then are the traps armed, so every packet the package itself
emits is captured.

Capturing at the network layer rather than via `HTTP_PROXY` matters: **Node's `http` module
ignores proxy variables entirely**, so a proxy-based design catches npm and misses the
malware.

---

## Getting started

Requires **Node.js 22+**, **Docker** (via Colima), and a **GitHub CLI** login.

```bash
git clone https://github.com/bhargava-gumpula/agent-harness-hackathon.git
cd agent-harness-hackathon
```

### 1. Start the container runtime

```bash
brew install colima docker
colima start --cpu 2 --memory 4 --disk 20 --mount none
```

`--mount none` is **load-bearing**. Colima mounts your home directory into the VM by
default, which would let a detonated package read your real `~/.ssh/id_rsa`. Do not drop it.

Verify containment:

```bash
docker run --rm alpine:latest ls -d /Users    # must fail: no such file or directory
```

### 2. Start the harness

```bash
npx @truefoundry/trueforge          # opens on http://localhost:8790
```

### 3. Add a model

In the TrueForge UI: **Settings → Models**, or:

```bash
bash scripts/set-model-provider.sh anthropic     # or openai, google-gemini, ...
```

The key is prompted for with hidden input and never written to disk.

> **Note on Gemini's free tier:** `gemini-3.6-flash` is capped at **5 requests per minute**
> and `gemini-3.1-pro-preview` is unavailable entirely. An agent loop spends one request per
> tool call, so the free tier will stall a run mid-flight. Use a paid provider.

### 4. Add the GitHub connector

```bash
bash scripts/add-github-connector.sh
```

Reads your token from `gh auth token` and pipes it straight to the local API — never
printed, never stored, never passed as an argument.

### 5. Register the agent

```bash
curl -X POST http://localhost:8790/api/v1/agents \
  -H 'content-type: application/json' \
  --data-binary @agent/customs.agent.json
```

---

## Using it

Inspect a single package directly:

```bash
bash customs/customs.sh inspect esbuild
```

```json
{
  "package": "esbuild",
  "sinkhole_armed": true,
  "canary_hit": false,
  "canary_in_network_bytes": 0,
  "hosts_contacted": [],
  "files_written_outside_package": [],
  "verdict": "clean - no planted credential moved"
}
```

Run the agent over a pull request:

```bash
bash scripts/run-customs.sh 3
```

It reads the diff, inspects each added dependency, writes a report — and then **pauses**,
waiting for you to approve posting it.

## Proving the detector actually works

**A detector that never fires looks exactly like a detector that is broken.**

```bash
bash scripts/prove.sh
```

```
positive control (must fire)              PASS  (canary_hit=true)
esbuild (real, must stay clean)           PASS  (canary_hit=false)
sharp (real, must stay clean)             PASS  (canary_hit=false)

ALL PROOFS PASSED
```

It asserts and **exits non-zero** on failure. `fixtures/customs-demo-exfil` is a positive
control — a package that deliberately steals a planted decoy — and it is never published.

Building that control found **four bugs that each made the detector silently report
*clean* on input that was actively stealing credentials**:

1. **Node's `http` ignores `HTTP_PROXY`** — a proxy-based design catches npm and nothing else.
2. **An unresolvable hostname emits no packet** — with the attacker's host dead, DNS fails
   first and there is nothing to redirect. Hence the DNS responder.
3. **A sinkhole that never replies hangs the victim** — Node keeps its event loop alive
   waiting, so `npm rebuild` never returns.
4. **`grep -c` prints `0` *and* exits non-zero** — so `$(grep -c x f || echo 0)` yields
   `0\n0` and corrupts the JSON.

None were findable without a known-positive to test against.

## Known limitation

The sinkhole records **plaintext request bodies** and **TLS SNI hostnames**. It does **not**
decrypt TLS — a payload sent over HTTPS reveals its destination but not its contents.
OpenSSF closes that gap with syscall tracing. Customs does not, and says so.

---

## Qodo Code Review Evidence

Every change goes through a pull request reviewed by [Qodo](https://www.qodo.ai/) before
merge. `main` is branch-protected, so direct pushes are not possible.

- **Reviewed pull request:** [#2 — project context, environment and verified proofs](https://github.com/bhargava-gumpula/agent-harness-hackathon/pull/2)
- **What Qodo surfaced, and what changed:** Qodo found that `positive-control.sh` printed
  `clean` and **exited 0 when the canary was absent** — meaning a broken detector would pass
  as a verified true positive. It also flagged that `verify-trueforge.sh` accepted any
  completed turn without asserting the model's answer, and that the reproduction commands
  reused a single canary marker across two detonations.

  All three were fixed: the prototypes were replaced by `scripts/prove.sh`, which drives the
  real CLI, asserts both directions and exits non-zero; `verify-trueforge.sh` now asserts its
  expected answer; each `customs inspect` mints its own marker. Three further findings
  (missing `require()`, unfiltered npm cache noise, npm exit status masked by a pipeline)
  were artefacts of the superseded prototype scripts — the real implementation already
  handled all three, which is why the prototypes were removed rather than patched.
- **Full history:** https://github.com/bhargava-gumpula/agent-harness-hackathon/pulls?q=is%3Apr

## AI assistance disclosure

Per hackathon rule 12: Claude Code was used for implementation, debugging and documentation.
Project selection was pressure-tested through a multi-advisor review recorded in
[`docs/council-verdict.md`](docs/council-verdict.md). All architecture and technical
decisions are understood by the author and can be explained (rule 13) — the reasoning behind
each is written up in [`CLAUDE.md`](CLAUDE.md).

## License

[MIT](./LICENSE)
