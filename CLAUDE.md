# CLAUDE.md — project context for any Claude Code session

**Read this first.** It exists so that a fresh session (new account, new machine, lost
conversation) can pick up without re-deriving decisions that were already made and paid for.

---

## ▶ RESUME HERE — state as of 29 Aug 2026, 13:45 PT

**Deadline: Sunday 30 August 2026, 12:00 PM Pacific.**

Pull request #2 is **merged**. `main` has everything — just `git pull` and work on `main`.

### Where it stands

Built, merged and verified: the detector, the positive control, the agent definition with a
real approval gate, the GitHub connector, a stranger-followable README, and a results
dashboard generated from real inspections.

**Not yet done: a full end-to-end agent run.** That is the single most important graded item
("agent runs on TrueForge, with the harness visibly doing the work") and the demo video
depends on it.

### THE ONE BLOCKER — the free tier cannot run this agent

This was misdiagnosed twice before being pinned down. The settled finding:

**It is a token-rate limit, not a request-rate limit.**

| Agent | First-request context | Result |
| --- | --- | --- |
| bare agent, no sandbox, no MCP | ~1,100 tokens | works, repeatedly |
| `customs` (sandbox + GitHub MCP) | **~50,000 tokens** | HTTP 429 instantly, even on "Say OK" |

The proof it is not exhausted quota: a bare `scripts/verify-trueforge.sh` call succeeds
*immediately after* a `customs` call fails. Same key, same minute. The agent's first request
is ~45x larger and blows the free tier's per-minute token allowance before doing any work.

Already tried and **not sufficient** — do not spend time re-trying these:

- `generative_ui: {enabled: false}`
- `dynamic_sub_agents: {enabled: false}`
- `ask_user_questions: {enabled: false}`
- `sandbox.file_downloads: false`
- `enable_tools` narrowed to 3 GitHub tools, `preload_tools` set

Still 429s. The sandbox tooling plus any MCP connector puts the floor above what the free
tier allows per minute.

**The fix — a paid provider. One command:**

```bash
bash scripts/set-model-provider.sh anthropic
```

Then point the agent at it and re-register:

```bash
python3 - <<'EOF'
import json
p="agent/customs.agent.json"; d=json.load(open(p))
d["manifest"]["model"]={"name":"anthropic/claude-sonnet-5"}
json.dump(d,open(p,"w"),indent=2)
EOF
AGENT_ID=$(curl -s http://localhost:8790/api/v1/agents | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["id"])')
python3 -c 'import json;print(json.dumps({"manifest":json.load(open("agent/customs.agent.json"))["manifest"]}))'   | curl -s -X PUT "http://localhost:8790/api/v1/agents/$AGENT_ID"       -H 'content-type: application/json' --data-binary @- >/dev/null
```

Note the update endpoint takes **only** `{"manifest": {...}}` — including `name` returns
`Unrecognized key: "name"`.

Everything else is built and verified. This is the last thing standing between the project
and a complete submission.

### Run the agent

```bash
bash scripts/run-customs.sh 3      # pull request #3 is the demo target
```

Expect it to read the diff, inspect two packages, write a report, then **pause for approval**
before posting. Re-register the agent after editing its definition:

```bash
AGENT_ID=$(curl -s http://localhost:8790/api/v1/agents | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"][0]["id"])')
curl -X PUT "http://localhost:8790/api/v1/agents/$AGENT_ID" \
  -H 'content-type: application/json' --data-binary @agent/customs.agent.json
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
