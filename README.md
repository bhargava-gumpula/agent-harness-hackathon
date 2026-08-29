# agent-harness-hackathon

> **Status: work in progress.** Built for [The Agent Harness Hackathon](https://www.wemakedevs.org/hackathons/trueforge)
> (WeMakeDevs x TrueFoundry, 24-30 August 2026). Submissions close 30 Aug 2026, 8:00 PM London.

<!-- TODO: replace with a one-line description of what the agent actually does. -->
An AI agent built on [TrueForge](https://github.com/truefoundry/trueforge), TrueFoundry's
open-source agent harness.

---

## The problem

<!-- TODO: what job is being handed to the agent, and who currently does it by hand? -->

## What the agent does

<!-- TODO: describe the job end to end. A chatbot answers questions; this agent acts. -->

---

## How it uses TrueForge

TrueForge runs the agent loop: tool calls, sandboxed execution, approvals, subagents and
session state. This project uses the harness as follows.

| Harness capability | Used? | How this project uses it |
| --- | --- | --- |
| MCP connectors (real tools) | ☐ | <!-- TODO: which MCP servers, reaching what --> |
| Sandbox as a tool (Daytona) | ☐ | <!-- TODO: what code executes in isolation, and why it must --> |
| Human approval checkpoint | ☐ | <!-- TODO: which irreversible action pauses for a person --> |
| Subagents | ☐ | <!-- TODO: what work is delegated and parallelised --> |
| Skills (`SKILL.md` packs) | ☐ | <!-- TODO: reusable instruction packs loaded on demand --> |
| Persistent sessions | ☐ | <!-- TODO: what survives a refresh/reconnect --> |
| Generative UI | ☐ | <!-- TODO: tables/cards rendered in chat --> |

### Architecture

```text
TODO: diagram or short walkthrough of the flow, e.g.

  user request
      -> TrueForge session
          -> MCP tool (read-only discovery)
          -> subagents (parallel work)
          -> sandbox (generated code executes safely)
      -> APPROVAL GATE  <-- nothing irreversible happens before this
      -> action taken, result logged
```

---

## Getting started

Requires **Node.js 22+**.

```bash
# 1. start the harness
npx @truefoundry/trueforge
# opens on http://localhost:8790

# 2. clone this project
git clone https://github.com/bhargava-gumpula/agent-harness-hackathon.git
cd agent-harness-hackathon

# 3. configure credentials
cp .env.example .env
# then fill in .env  (never commit it)
```

Then, in the TrueForge UI:

1. **Settings > Models** - add a model provider and API key. Any OpenAI-compatible
   endpoint works (OpenAI, Anthropic, Gemini, DeepSeek, or a local model).
2. **Settings > Connectors** - add the MCP servers this agent needs.
   <!-- TODO: list them -->
3. **Settings > Skills** - add any `SKILL.md` packs used. <!-- TODO -->
4. **Settings > Sandbox providers** - select Daytona and add your API key.
5. Load the agent definition: <!-- TODO: path to agent.json + how to import -->

---

## Demo

<!-- TODO: YouTube link, max 3 minutes. Must show: what it does, tech stack and
     architecture, the agent working, and the approval gate firing. -->

---

## Qodo Code Review Evidence

Every substantive change in this repository goes through a GitHub pull request reviewed by
[Qodo](https://www.qodo.ai/) before it is merged. `main` is branch-protected, so direct
pushes are not possible.

- **Representative merged PR:** <!-- TODO: link a merged PR with meaningful hackathon code -->
- **What Qodo surfaced and what changed:** <!-- TODO: 1-2 sentences on the findings, what
  was fixed, and anything intentionally dismissed with the reason recorded in the thread -->
- **Full pull request history:** https://github.com/bhargava-gumpula/agent-harness-hackathon/pulls?q=is%3Apr

---

## AI assistance disclosure

Per hackathon rule 12, use of AI coding assistants is disclosed here.

<!-- TODO: list which assistants were used and for what. All architecture and technical
     decisions are understood by the author and can be explained (rule 13). -->

---

## Submission checklist

- [ ] Agent runs on TrueForge, with the harness visibly doing the work
- [ ] A real tool reached through MCP
- [ ] Code executed in the sandbox
- [ ] A human approval gate before anything irreversible
- [ ] Public repo with a README a stranger can follow
- [ ] Demo video, about 3 minutes, on YouTube
- [ ] `## Qodo Code Review Evidence` section completed with a merged PR link
- [ ] No keys, credentials or personal data in the repo or the video
- [ ] Blog post published and linked (optional prize track)
- [ ] [Submission form](https://forms.gle/PxGLsWW1HPyroQ5u9) filed before the deadline

---

## License

[MIT](./LICENSE)
