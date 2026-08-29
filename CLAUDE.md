# CLAUDE.md — project context for any Claude Code session

**Read this first.** It exists so that a fresh session (new account, new machine, lost
conversation) can pick up without re-deriving decisions that were already made and paid for.

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

- Model provider: **google-gemini**, models `gemini-3-1-pro-preview` and `gemini-3-6-flash`
- Default for this project: **`google-gemini/gemini-3-6-flash`** (tool-calling loop, not a
  reasoning-heavy task — flash is faster and cheaper)
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
CANARY="CANARY-$(uuidgen | tr -d '-' | head -c 24)"
docker run --rm -i -e CANARY="$CANARY" node:22-alpine sh -s < scripts/canary-core.sh
docker run --rm -i -e CANARY="$CANARY" node:22-alpine sh -s < scripts/positive-control.sh
```

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

## What is left

- [ ] Sandbox provider registered in TrueForge, pointed at Colima
- [ ] GitHub MCP connector (read pull request diff, post findings)
- [ ] The Customs agent definition
- [ ] A test pull request that adds a dependency, to run against
- [ ] README rewritten for a stranger
- [ ] Demo video (~3 min, recorded not live — a live `npm install` can fail on stage)
- [ ] Qodo Code Review Evidence section with a merged pull request
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

- `main` is branch-protected and requires a pull request review. Qodo reviews every PR.
  (`enforce_admins` is off, so a manual merge is possible in an emergency — last resort only.)
- Never commit the Gemini key, any `.env`, or personal data (hackathon rule 7).
- Test the full flow after each phase; do not auto-advance to the next phase without
  explicit permission.
