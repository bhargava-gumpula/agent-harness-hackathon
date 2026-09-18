# CLAUDE.md — project context for any Claude Code session

**Read this first.** It exists so that a fresh session (new account, new machine, lost
conversation) can pick up without re-deriving decisions that were already made and paid for.

---

## ▶ RESUME HERE — state as of 29 Aug 2026, 14:45 PT

**Deadline: Sunday 30 August 2026, 12:00 PM Pacific** (= 8 PM London, confirmed on the
wemakedevs page). The Luma page shows an `18:00` "project submission deadline" — that is the
**in-person SF day only**, not the online track. Online submission is Sunday noon PT.

**Submission form: https://forms.gle/7DWiH2SDCJioWtdeA**

Pull requests #2 and #4 are **merged**.

### Where it stands — THE AGENT RUNS END TO END

`bash scripts/run-customs.sh 3` now completes the full loop and stops at the approval gate.
Verified trace from a real run:

```
[mcp:github]  pull_request_read          <- real tool through MCP
[mcp:customs] customs_inspect esbuild     <- canary_hit false (clean)
[mcp:customs] customs_inspect fixtures/customs-demo-exfil  <- canary_hit TRUE
[sandbox]     exec - aggregate results into a computed markdown table
[mcp:github]  add_issue_comment
*** PAUSED FOR HUMAN APPROVAL ***
```

One run demonstrates both directions, because PR #3 adds `esbuild` **and** the local
positive control. Cost about **$0.13 per run** on `anthropic/claude-sonnet-5`.

### CORRECTION — the earlier Gemini diagnosis was wrong

A previous session recorded "it is a token-rate limit, not a request-rate limit." **That is
not what the API says.** The actual 429 body is:

```
Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests, limit: 20
```

That is a **requests** metric. A minimal sandbox-only agent with no MCP — first request
~1k tokens — also 429s at `tokens: 0`, four times, spaced 70s apart. A per-minute *token*
ceiling cannot explain that; an exhausted request quota can. Do not repeat the token-rate
claim on camera (hackathon rule 13: you must be able to explain every decision).

Config knobs already tried and insufficient on the free tier — do not re-try:
`generative_ui`, `dynamic_sub_agents`, `ask_user_questions`, `sandbox.file_downloads`,
narrowed `enable_tools`/`preload_tools`.

### The Anthropic key must be WORKSPACE-SCOPED

An unscoped (identity-linked) key returns HTTP 400:

```
anthropic-workspace-id is required when authenticating with an identity-linked API key
```

TrueForge **cannot** send that header: `ModelProviderAuthSchema` is `.strict()` and accepts
only `api_key`. There is no custom-header field. So the key itself must be scoped: in the
Console, Create key → set **Workspace** to a specific workspace (Default is fine). Personal
vs service account does not matter; scope does. Then `bash scripts/set-model-provider.sh
anthropic` to rotate it in place.

### CONFIRMED — the sandbox cannot run `customs.sh`, and no model provider fixes that

This was the real blocker behind the missing E2E run, and it is *provider-independent*.
TrueForge has no sandbox provider configured, so it falls back to `local` —
`@anthropic-ai/sandbox-runtime`, a host process under a macOS seatbelt profile. Measured
from inside that sandbox:

| Check | Result |
| --- | --- |
| `ls` the repo | `Operation not permitted` |
| `docker ps` | `permission denied` on the docker socket |
| `curl registry.npmjs.org` | `000` (blocked) |
| `curl api.github.com` | `200` (allowed) |
| `pwd` | `~/Library/Application Support/trueforge/sandboxes/<id>/<id>` |

The allow-read list is **hardcoded** in the shipped code (`ALLOW_READ_BY_PLATFORM`), the
network allowlist is hardcoded to pypi + github, and `allowRead` is assembled as
`[sandboxRootPath, codeModeSocketParent, ...platformAllowRead]` with **no config hook**.
Copying `customs.sh` into the sandbox root would not help — it still needs the Docker socket
and the npm registry, both outside the policy.

**The fix, now built: `customs/mcp-server.js`.** A zero-dependency local HTTP MCP server that
exposes one tool, `customs_inspect(package)`, and shells out to `customs.sh` **on the host**,
where Docker and npm work. TrueForge's MCP schema is `type: z.enum(["remote"])` + `url`, so a
localhost URL is how a local tool gets in — stdio servers are not supported.

Start it before any agent run (nothing else depends on it):

```bash
node customs/mcp-server.js          # http://127.0.0.1:8791/mcp
curl -s http://127.0.0.1:8791/health
```

This made the submission **stronger**, not weaker: two real MCP servers instead of one, and
the sandbox now does genuine work (aggregating the JSON into the report table) rather than
being the thing that was broken.

### Run the agent

```bash
bash scripts/run-customs.sh 3      # pull request #3 is the demo target
```

Expect it to read the diff, inspect two packages, write a report, then **pause for approval**
before posting. Start `customs/mcp-server.js` first or the inspections have no tool to call.

Re-register the agent after editing its definition. Select the agent **by name** — an earlier
version of this snippet used `data[0]`, which silently overwrites the wrong agent the moment a
second one is registered. The endpoint takes **only** `{"manifest": {...}}`; including `name`
returns `Unrecognized key: "name"`.

```bash
AGENT_ID=$(curl -s http://localhost:8790/api/v1/agents \
  | python3 -c 'import sys,json;print([a for a in json.load(sys.stdin)["data"] if a["name"]=="customs"][0]["id"])')
python3 -c 'import json;print(json.dumps({"manifest":json.load(open("agent/customs.agent.json"))["manifest"]}))' \
  | curl -s -X PUT "http://localhost:8790/api/v1/agents/$AGENT_ID" \
      -H 'content-type: application/json' --data-binary @-
```

### Restore the environment on any machine

```bash
brew install colima docker
colima start --cpu 2 --memory 4 --disk 20 --mount none   # --mount none is load-bearing
npx @truefoundry/trueforge                                # http://localhost:8790
bash scripts/set-model-provider.sh anthropic              # or google-gemini
bash scripts/add-github-connector.sh
curl -X POST http://localhost:8790/api/v1/agents \
  -H 'content-type: application/json' --data-binary @agent/customs.agent.json
```

### Confirm it all still works

```bash
bash scripts/verify-trueforge.sh   # harness -> model, asserts the answer
bash scripts/prove.sh              # detector fires on theft, quiet otherwise; exits non-zero on failure
bash scripts/build-dashboard.sh    # real inspections -> web/dashboard.html
```

### Pull requests

- **#2** — merged. Qodo reviewed it; findings addressed. This is the Qodo evidence link.
- **#3** `demo/add-dependencies` — **leave open**. It is what the agent inspects in the demo.

---

## What this is

A submission for **The Agent Harness Hackathon** (WeMakeDevs x TrueFoundry).
Deadline: **Sunday 30 August 2026, 12:00 PM Pacific**.

The agent must run on **TrueForge** (TrueFoundry's open-source agent harness), and the
graded checklist is:

- agent runs on TrueForge, with the harness visibly doing the work
- a real tool reached through MCP
- code executed in the sandbox
- a human approval gate before anything irreversible
- public repo with a README a stranger can follow
- demo video, ~3 minutes, on YouTube
- `## Qodo Code Review Evidence` section with a merged pull request link
- no keys, credentials or personal data in the repo or the video (rule 7)
- the author must be able to explain every technical decision (rule 13)

## The project: Customs

**An agent that inspects an npm package before it enters your dependency tree.**

Installing a package runs arbitrary code on your machine via `postinstall`, before any of
your own code runs. Reading the source does not reliably tell you what it does — payloads
are obfuscated or fetched remotely at install time. The only way to know is to run it
somewhere disposable and watch.

Flow:

1. Triggered by a pull request that adds or bumps a dependency
2. For each package: a disposable Docker container
3. Seed it with **decoy credentials** containing unique, unguessable marker strings
   (fake `~/.ssh/id_rsa`, `~/.aws/credentials`, `.env`)
4. `npm install` with install scripts **enabled**, then `require()` the package
5. Observe: **canary hits** (did a planted marker leave its file?), filesystem diff,
   network egress
6. Report, then **stop at an approval gate** before doing anything irreversible

### Why this idea, and not another one

Three earlier ideas were rejected against one standing test:

> **Does the sandbox PRODUCE the finding, or does it merely produce input for a model to
> have an opinion about?**

- *Flaky-test hunter* — rejected, "a wrapper around Claude itself"
- *Subscription audit agent* — rejected, the author would write both the data and the
  answer key, so the agent "discovers" a planted number
- *Time-travel breakage agent* — rejected, the sandbox produces a failure but a model still
  has to judge whether it is a real bug

Customs passes because a canary hit is an **observation**: a unique string either appeared
somewhere it should not, or it did not. No model sits between the observation and the verdict.

**Do not re-litigate this.** It was decided by a 5-advisor council with peer review; the full
reasoning is in `docs/council-verdict.md`.

### Prior art — be honest about this

The detonation mechanism is **not novel**, and the README/video should say so:

- **OpenSSF Package Analysis** (Google-backed) already does sandboxed detonation with gVisor
  and syscall tracing. But it is a scheduled registry-wide pipeline that produces **data only**
  — it does not decide or act.
- **SafeDep** — commercial, eBPF tracing, also a scanner rather than an actor.
- **Socket.dev** (market leader) — **static analysis only**, explicitly does not execute
  install scripts.

The contribution is **placement** (an agent inside the pull request loop that decides, gates
and acts) and **technique** (canary tokens instead of heavyweight syscall surveillance).
Framing: the safety catch between an AI coding assistant and your machine, since Codex/Cursor/
Copilot now auto-install dependencies without verification.

---

## Environment — already set up and verified

### TrueForge
Running via `npx @truefoundry/trueforge` on **http://localhost:8790**.
State lives in `~/Library/Application Support/trueforge/db/db.sqlite`.

- Model provider: **google-gemini** (current), `gemini-3-6-flash`.
- Default for this project: **`google-gemini/gemini-3-6-flash`**
- **Planned:** switch to `anthropic/claude-sonnet-5` once a key is added. The setup script
  is ready — `bash scripts/set-model-provider.sh anthropic` — and registering a new provider
  adds alongside Gemini rather than replacing it.

### Gemini free tier limits — measured, not guessed

| Model | Free tier limit |
| --- | --- |
| `gemini-3.6-flash` | usable for bare calls; **cannot carry an agent with a sandbox + MCP** |
| `gemini-3.1-pro-preview` | **`limit: 0` — unavailable entirely** |

The binding constraint is tokens per minute, not requests per minute. See "THE ONE BLOCKER"
at the top. Gemini is fine for `scripts/verify-trueforge.sh`; it is not fine for the agent.

Register or rotate any provider with:

```bash
bash scripts/set-model-provider.sh anthropic
```
- **The API key lives only in TrueForge's local database. It is NOT in this repo and must
  never be.**

Verify the whole path works:

```bash
bash scripts/verify-trueforge.sh
```

Expect `RESULT: OK` and `model said: TRUEFORGE OK`.

### Sandbox — Colima + Docker (NOT Docker Desktop)

Docker Desktop was deliberately avoided: it needs an administrator password and a large
install. Colima gives a real Linux VM with no GUI and no password prompt.

```bash
colima start --cpu 2 --memory 4 --disk 20 --mount none
```

**`--mount none` is load-bearing, do not drop it.** By default Colima mounts the host home
directory into the VM, which would let a detonated package read the real `~/.ssh/id_rsa`.
With no mounts, the host home directory does not exist inside the VM at all.

Verified: `/Users` does not exist inside the VM or inside a container, and none of
`~/.ssh`, `~/.aws`, `~/.npmrc`, `~/.config/gh`, `~/.claude` are reachable.

---

## What is already proven

| Thing | Status |
| --- | --- |
| TrueForge -> Gemini, end to end | working (`scripts/verify-trueforge.sh`) |
| Docker sandbox containment | verified — host credentials unreachable |
| Git push to GitHub | working |
| Canary mechanism, true negative | `esbuild` detonated, zero canary hits |
| Canary mechanism, true positive | authored control package caught exfiltrating |

Reproduce the two canary proofs:

```bash
bash scripts/prove.sh
```

It asserts both directions and **exits non-zero** if either fails. Every `customs inspect`
call mints its own fresh marker internally, so no canary is ever reused between detonations
— reuse would let one run's marker contaminate another's verdict.

---

## Landmines already hit — do not repeat

1. **`python3 - <<'EOF'` in a shell pipeline does not work.** The heredoc becomes stdin, so
   piped data never reaches Python. Use `python3 -c '...'` instead. This cost three
   debugging rounds.
2. **TrueForge's model-provider API wraps the body in `manifest`:**
   `PUT /api/v1/settings/model-providers` with `{"manifest": {...}}`. Sending the manifest
   unwrapped returns an error and registers nothing.
3. **TrueForge does not validate an API key on save.** It will happily store a garbage key
   and only fail later at turn time with `API key not valid`. Always verify with a real turn.
4. **A turn's result is at `state.status` and `state.output.content`**, not at the top level.
5. **Filesystem diff is mostly noise.** A single `esbuild` install wrote 121 files outside
   its own tree, nearly all npm cache. Build around the **canary** signal; treat filesystem
   diff as secondary or filter `~/.npm/_cacache` aggressively.
6. **Never detonate packages outside the container.** A fake `$HOME` in a temp directory is
   not containment — absolute paths defeat it.
7. **Session events are nested and newest-first.** Each entry is `{turn_id, event}` — the real
   payload is under `event`, not at the top level. Reading `e["type"]` yields `None` for every
   entry and prints an empty trace, which is what made an early run look like it did nothing.
   Tool calls live on `model.message` at `tool_calls[].function`, with `tool_info.type`
   distinguishing `mcp` / `truefoundry-system`.
8. **`call_tool` is Code Mode, not an approval hold.** TrueForge routes MCP calls through the
   sandbox as `call_tool`. Do not label those "held for approval" in demo output — the only
   real hold is a `tool.approval_required` event. Mislabelling it overstates the safety story
   on the exact item being graded.
9. **"Offer to post" makes the model ask in prose instead of calling the tool**, so the harness
   gate never fires and there is nothing to film. The instruction must say to CALL
   `add_issue_comment` directly, because the held call *is* how the human gets asked.
10. **An unannotated MCP tool defaults to `destructiveHint: true`**, so TrueForge auto-assigns
    `require_approval_for_tools: ["@write","@destructive"]` and gates every inspection.
    `customs_inspect` declares `annotations.destructiveHint: false` and the agent pins
    `require_approval_for_tools: []`, leaving exactly one gate on the irreversible action.

---

## The `customs` CLI — built and working

`customs/customs.sh inspect <package|local-dir>` emits JSON. The agent calls this **once per
package**, which matters: one tool call per package keeps the loop short.

Architecture, and why:

1. **Phase 1** — `npm install --ignore-scripts` with normal network, so npm can reach the
   registry and resolve the tree. Nothing untrusted has run yet.
2. **Arm the traps** — a DNS responder answering every query with `127.0.0.1`, plus
   `iptables -t nat -A OUTPUT -p tcp -j REDIRECT --to-port 8899` sending *all* outbound TCP
   into a local sinkhole. Requires `--cap-add=NET_ADMIN`.
3. **Phase 2** — `npm rebuild` runs the install scripts, then the package is `require()`d.
   Anything it sends is captured.
4. **Phase 3** — sweep for planted decoys in files and in captured network bytes.

### Four bugs found by building the positive control — do not reintroduce

1. **Node's `http` module ignores `HTTP_PROXY`.** An `HTTP_PROXY`-based proxy catches npm
   and nothing else. Real malware sails past it. Hence the iptables sinkhole.
2. **An unresolvable hostname emits no packet.** Without the DNS sinkhole, malware pointed
   at a dead or unregistrable host is invisible — iptables has nothing to redirect.
3. **A sinkhole that never replies hangs the victim forever.** Node keeps the event loop
   alive waiting for a response, so `npm rebuild` never returns. The sinkhole must answer
   and close.
4. **`grep -c` prints `0` AND exits non-zero** on no match, so `$(grep -c x f || echo 0)`
   yields `0\n0` and corrupts the JSON.

Every phase has a hard `timeout`, so a hostile package cannot stall an inspection.

### Verified results

| Target | Verdict |
| --- | --- |
| `fixtures/customs-demo-exfil` (positive control) | **CANARY HIT**, destination reported |
| `esbuild` (real, has postinstall) | clean |
| `sharp` (real, has postinstall) | clean |

### Known limitation — state it honestly in the README and video

The sinkhole records **plaintext bodies** and **TLS SNI hostnames**. It does not decrypt
TLS, so a payload sent over HTTPS shows the destination but not the contents. OpenSSF uses
syscall tracing to close that gap. Do not overclaim.

## What is built

- `customs/customs.sh` + `customs/inspect-in-container.sh` — the detector (working, proven)
- `fixtures/customs-demo-exfil` — positive control (never published)
- `agent/customs.agent.json` — the agent; `add_issue_comment` sits behind
  `require_approval_for_tools`, which is the approval gate
- `scripts/` — provider setup, GitHub connector, proof, agent runner, dashboard builder
- `web/dashboard.html` — generated from real inspections, no mock data
- `README.md` — complete, stranger-followable

## What is left

- [ ] **Run the agent end to end** and capture it pausing at the approval gate
- [ ] Demo video, ~3 minutes, recorded not live (a live `npm install` can fail on camera)
- [ ] Submission form

### Demo structure (three frames, in this order)

1. **Positive control** — the authored fixture package. Planted key at address A, same
   string in an outbound request to address B. Ten seconds.
2. **Real known-bad** — a sample from OpenSSF's `malicious-packages` corpus, in the container.
3. **Real benign contrast** — `esbuild`, `sharp`, `bcrypt`: genuine postinstall scripts,
   legitimate network fetches, **zero canary hits**. This frame is what stops a judge saying
   "you wrote both the question and the answer."

### Answer this on camera before a judge asks

*"Why not just `npm install --ignore-scripts`?"* — because the code gets `require()`d
eventually, which executes it anyway, and the flag breaks a large fraction of npm.

---

## Working agreements

- `main` is branch-protected and requires a pull request review; Qodo reviews every PR.
  GitHub does not let an author approve their own pull request, so a solo merge needs
  `gh pr merge <n> --merge --admin`. That is how #2 was merged.
- Never commit the Gemini key, any `.env`, or personal data (hackathon rule 7).
- Test the full flow after each phase; do not auto-advance to the next phase without
  explicit permission.
