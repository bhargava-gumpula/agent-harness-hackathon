# LLM Council Transcript — "Customs" hackathon idea

**Run:** Saturday 29 August 2026, 12:06 PM PDT
**Deadline at time of run:** Sunday 30 August 2026, 12:00 PM PT (~23.9 hours)
**Question asked:** "check if this idea is good."

---

## The Framed Question

**THE DECISION:** Should the user build "Customs" as their submission for the Agent Harness Hackathon (WeMakeDevs x TrueFoundry), with roughly 23 hours until the deadline?

**THE IDEA (Customs):** An agent that inspects software packages before they enter a project's dependency tree.

When you install an npm package, it can execute arbitrary code on your machine via postinstall scripts — before you run any of your own code. Reading the source doesn't reliably tell you what it does (obfuscation, or the payload is fetched remotely at install time). The only reliable way to know is to run it somewhere disposable and observe.

Flow:
1. Triggered by a pull request that adds or bumps a dependency
2. For each new package, spin up a disposable sandbox
3. Seed the sandbox with decoy/canary credentials: a fake `~/.ssh/id_rsa`, a fake `~/.aws/credentials`, a fake `.env` — each containing unique, unguessable marker values
4. Run `npm install` with install scripts ENABLED, then separately `require()` the package
5. Observe four channels: filesystem diff, network egress, CANARY HITS (did a planted marker appear in an outbound request body or a written file), process spawns
6. Report findings
7. Approval gate 1 before writing to the user's own repository; approval gate 2 before anything public

Subagents: one per package. MCP: GitHub. Skills: a `SKILL.md` encoding benign-vs-suspicious priors.

**PRIOR ART (researched before the council ran):**
- **OpenSSF Package Analysis** (Google-backed, open source) does sandboxed detonation using gVisor, syscall tracing and packet capture. Found 200+ malicious packages. BUT its documentation states it produces analysis DATA ONLY — no decisions, no actions. A scheduled registry-wide pipeline into BigQuery.
- **SafeDep**: commercial, eBPF syscall tracing at scale. A scanner/observability system that generates events and reports rather than taking autonomous actions.
- **Socket.dev** (market leader): STATIC analysis only. Explicitly does NOT execute install scripts. Dynamic analysis announced but not shipped.
- **Canary tokens**: mature in breach detection, but no documented use inside package-analysis sandboxes.

Detonation is NOT novel. Claimed contributions: (a) PLACEMENT — an agent in the pull request loop that decides, gates and acts, rather than a scanner producing data; (b) TECHNIQUE — canary tokens instead of heavyweight surveillance, far cheaper to build.

**CONSTRAINTS:** ~23 hours, solo student builder. TrueForge running but COMPLETELY unconfigured — zero models, zero MCP servers, zero agents, zero skills, no API key, no Daytona account. Repo is a README scaffold, zero code. Judging requires: runs on TrueForge, real MCP tool, sandboxed code execution, human approval gate, public repo, ~3 minute video, Qodo-reviewed merged PR. TrueForge ships a LocalSandboxProvider (macOS seatbelt) so Daytona is optional, but network egress capture likely needs a real container.

**HISTORY — three ideas already rejected:**
1. Flaky-test hunter — "a wrapper around Claude itself."
2. Subscription audit agent — user would author both the synthetic data AND the answer key.
3. Time-travel breakage agent — sandbox produces a failure but a model still judges whether it's a real bug.

**The user's explicit test:** does the sandbox PRODUCE the finding, or merely produce input for a model to have an opinion about?

---

## Round 1 — Advisor Responses

### The Contrarian

The canary is the same trap that killed idea #2. You plant the secret, and — for any demo you can build tonight — you also plant the thing that steals it. The marker value is unguessable only because you generated it; the exfil happens only because you wrote the package that exfils it. That is authoring the data AND the answer key with a sandbox stapled on. Judges will ask "where did the malicious package come from?" and rule 13 forces you to answer honestly.

Worse: your own time-risk mitigation guts the mechanism. You define a canary hit as the marker appearing in an outbound request body OR a file the package wrote. Drop network observation and only the second half survives. Real stealers POST; they do not helpfully leave loot in `./stolen.json`. Filesystem-diff-only Customs detects nothing that Socket's static analysis misses, and you'd be demoing a `diff` command.

And the agent still opines. Filesystem diff → SKILL.md priors → "suspicious?" is a model forming an opinion about sandbox output. Same collapse as time-travel.

What to do with 23 hours (minus sleep, so ~14 working): keep the sandbox, kill the plant. Do not drop network — you don't need Daytona; run the install under a local HTTP proxy plus a resolver that answers everything, and log every host and body. Then point it at real, popular npm packages you did not write — top 200 with install scripts — and report which ones contact hosts or touch paths outside their tree. Those findings are unplanted, reproducible, and embarrassing to somebody. That's an observation. Canaries become a secondary signal, not the thesis.

Commit to that narrowing in the next 30 minutes or don't commit at all.

### The First Principles Thinker

You're asking "is Customs good enough." The right question is "what is the smallest object that produces a fact, and do I already have it?" You do.

Strip Customs to its skeleton: write an unguessable string into a file, run install, grep every outbound byte and every written file for that string. That's it. Everything else — subagents, MCP, skills, egress capture, gate 2 — is rubric decoration bolted onto a fifty-line core. Build the core first, in a terminal, in the next ninety minutes, with zero TrueForge involved. If `plant → install → grep` doesn't produce a hit on a package you wrote to steal, nothing downstream matters and you've burned ninety minutes, not twenty hours. If it does hit, you have your fact and the rest is assembly.

Now the part nobody's flagged. Your real failure risk isn't novelty — it's rejection #2 returning in costume. If you author the malicious package AND the detector, you've planted the answer key again. The canary saves you only if the corpus isn't yours.

So: after the core works, point it at fifty real packages pulled live from npm that have postinstall scripts. Your demo's headline is not "I caught my own malware." It's "fifty real packages, here are the seven that wrote outside their own directory, here's the one that read a file I never told it about, zero canary hits." A clean negative across a real corpus is a measurement. A planted positive is theater. Show both — the real sweep as the finding, your PoC package as the positive control that proves the instrument works.

Cut network egress now, not later. Filesystem-write canary is sufficient and needs no container.

Commit. Start the ninety-minute core immediately.

### The Expansionist

Commit. And then notice you're aiming too low.

The canary is not a security trick — it's a general primitive for turning "did something bad happen?" into a string match. That's why it beats the rejected ideas: no model opinion sits between the observation and the verdict. But npm is the smallest possible market for it. The same sandbox, unchanged, inspects PyPI packages, VS Code extensions, GitHub Actions, Claude skills — and MCP servers. You are submitting to an Agent Harness hackathon. An MCP server is arbitrary code that you voluntarily hand your credentials to, and nobody detonates them before install. Make the sandbox target-agnostic (`customs inspect <target>`) and put one line in the README claiming MCP servers as the next surface. Cost: twenty minutes. It converts a package scanner into infrastructure for the agent ecosystem the judges are personally building.

Second underpriced asset: approval gate 2. Every confirmed finding becomes a public GitHub issue on a real package repo, signed by your tool. That's not a compliance checkbox, it's a distribution flywheel — the project markets itself through its own true positives.

Third: cheapness is the moat, not the compromise. Dropping network egress isn't a downgrade — canaries catch exfil at rest (secret value appearing in any file the package wrote), which needs no packet capture at all. That means Customs runs on a laptop, per-PR, for free, where OpenSSF needs gVisor and BigQuery. Free and local is how you get an installed base; a scanning service is how you get zero users.

For the demo: plant one deliberately hostile fixture package. That's not the subscription-audit failure — you're supplying the disease, not the diagnosis. The mechanism stays generic.

The money shot is ten seconds: here's the fake AWS key I planted, here it is in an outbound POST. Socket.dev cannot produce that frame. Build toward it.

### The Outsider

Commit. But the thing that will sink you isn't the idea, it's the demo.

As someone with no context: "Customs" is the first of these four ideas I understood immediately. Border checkpoint, packages, inspection before entry. I got it from the name alone. The three rejected ideas needed a paragraph each. That's not a small thing — a judge watching video #40 at 2am understands this in five seconds.

The canary logic also survives my naivety test. "The fake password I planted at address A showed up in an outbound request to address B" is a fact. I don't need to trust your model, your prompt, or your judgment. I can check it myself. That's genuinely different from the time-travel idea, where I'd have to take someone's word.

Now the thing nobody in your brief said out loud: where does the malicious package in your demo come from? If you write it, you have rebuilt rejected idea #2 exactly — you planted the canary AND you planted the thief, and the agent "discovers" your own homework. Use a real package with a real postinstall script (esbuild, sharp — they genuinely fetch binaries and write outside their tree) plus one known-bad sample from a public corpus. Show a benign detonation and a malicious one side by side. Real inputs, both outcomes.

And answer the dumb question before a judge asks it: why not just `npm install --ignore-scripts`? I thought of that in ten seconds and I know nothing. Your answer — that you eventually `require()` the code anyway, which also executes — needs to be a line in your video, not something you improvise on stage.

Ship it. Spend your first hour on the demo package selection, not the harness.

### The Executor

Commit. Now. Not because it's the best idea — because it's the only one whose core mechanism is a shell script you can write before dinner.

Strip it to what it actually is:

```
mktemp -d -> fake $HOME with CANARY-<uuid> in .ssh/id_rsa, .aws/credentials, .env
npm install <pkg>   (scripts enabled)
find $HOME -newer /marker  -> files written outside package tree
grep -r "CANARY-<uuid>" $HOME --exclude-dir=<pkg>
```

That's the whole novel part. ~40 lines of bash. Everything else is harness plumbing, and the plumbing is your real risk, not the idea.

Next hour, in order:
1. Get a model API key. Boot TrueForge with one model, one agent, print "hello." If an agent hasn't run by hour 2, stop building Customs and fix that — nothing else counts.
2. Kill Daytona. Kill network egress. LocalSandboxProvider only. Decide this now, once, and never revisit it.
3. Write your villain before you write the agent. A local `file:` tarball package whose postinstall reads `~/.aws/credentials` and POSTs/writes it. This is your demo's money shot and it must exist by hour 3.
4. Then, and only then: GitHub MCP reads the PR diff for changed deps. One skill file. One approval gate — the human "approve" before the PR comment. Drop the second gate.

Cut list, non-negotiable: parallel per-package subagents (loop serially), opening issues on upstream repos, network capture, Daytona.

One defense you must build: run it against 3–4 real packages that legitimately have postinstalls (esbuild, sharp, bcrypt) and show them coming back clean. Planted villain plus clean real-world contrast is what stops a judge saying you wrote both the question and the answer.

Video at hour 20. Merge the PR at hour 21.

---

## Round 2 — Peer Review (anonymised)

**Anonymisation mapping (revealed):**

| Letter | Advisor |
| --- | --- |
| A | The Outsider |
| B | The Executor |
| C | The Contrarian |
| D | The Expansionist |
| E | The First Principles Thinker |

**Tally — strongest response:** E (First Principles) x3, C (Contrarian) x2
**Tally — biggest blind spot:** D (Expansionist) x5 — unanimous

### Review 1
**Strongest: E.** Only one that supplies a falsifiable kill-switch (90-minute core, zero TrueForge), fixes the answer-key problem, and correctly demotes the planted package to a positive control rather than the demo. C diagnoses as well but prescribes a local proxy plus catch-all resolver — new infrastructure at hour 14, solo. B is the best build plan but never interrogates the thesis.
**Blind spot: D.** Contradicts itself: dropping network capture is "not a downgrade," yet the money shot is "here it is in an outbound POST" — the frame the dropped capture cannot produce. Spends the scarcest hours on MCP-generality and auto-filing public issues against real maintainers' repos from a tool with zero validated true positives.
**All missed:** TrueForge's local macOS sandbox is HOME remapping, not an isolation boundary — yet C and E both recommend detonating real corpus packages with install scripts enabled on the builder's own machine, beside his real `~/.ssh`. Nobody costed that risk. Also: cutting capture doesn't cut egress. "Zero canary hits across 50 real packages" measures nothing when the only channel a real stealer uses is the unobserved one.

### Review 2
**Strongest: C.** Alone catches the load-bearing contradiction — the time-saving mitigation (drop network capture) deletes the half of the canary that matters, since real stealers POST rather than leave loot in `./stolen.json`. C also fixes it cheaply: local HTTP proxy plus wildcard resolver, no container, no Daytona. B is the best execution plan; C is the best reasoning. E commits the contradiction it should have caught — "grep every outbound byte," then "cut network egress now."
**Blind spot: D.** Asserts canaries "catch exfil at rest," which is mostly false and inverts C's point — D ships a detector blind to the actual attack, then calls that a moat.
**All missed:** the planted-answer-key debate is moot — OpenSSF's `malicious-packages` repo publishes thousands of real, attributed npm samples. Also: "wrote outside its tree" is normal node-gyp/prebuild behaviour, so the real-corpus sweep C and E stake the demo on returns noise; and detonating live malware in a local macOS sandbox beside the user's real `~/.ssh` is a containment risk nobody names.

### Review 3
**Strongest: E.** The only one that gives a falsifiable go/no-go inside 90 minutes and correctly reframes the headline: the real-corpus sweep is the finding, the planted package is a positive control proving the instrument works. That answers the user's own test and the rejection-#2 objection in one move. C overcorrects, and its claim that filesystem-diff "detects nothing Socket misses" is false, since Socket never executes.
**Blind spot: D.** Writing a seed round pitch for someone with zero lines of code and an unconfigured harness. Only B treats the plumbing as the actual risk. D's gate-2 flywheel is worse than useless.
**All missed:** running arbitrary real npm packages with scripts enabled in a local macOS sandbox means malicious code executes on the user's laptop beside their real `~/.ssh` and `~/.aws` — a fake `$HOME` is not containment, absolute paths defeat it. Also unresolved: an agent-harness rubric rewards agency, but every response argues the model's judgment is the liability.

### Review 4
**Strongest: C.** Only response that caught that the time-saving mitigation destroys the product. Drop network and only the half real stealers never use survives. C also supplies the fix nobody else had: local HTTP proxy with a catch-all resolver.
**Blind spot: D.** Asserts canaries "catch exfil at rest… needs no packet capture," then demands a money shot of "here it is in an outbound POST" — the capture it just cut. And it answers 23 hours with zero code by *adding* surface.
**All missed:** (a) A temp dir with a fake `$HOME` is not a sandbox. All five endorse scripts-enabled install plus `require()`; the Outsider adds real known-bad samples — on the builder's own laptop, real `$HOME` one `..` away, hours before deadline. (b) Attribution: `npm install <pkg>` installs the whole transitive tree. A canary hit indicts the tree, not the package. Every report claim depends on per-process attribution nobody scoped.

### Review 5
**Strongest: E.** The only response with a falsifiable pre-commitment test and the only correct epistemic frame: the planted package is a positive control, the real-package sweep is the finding. B is second and has the better hour-by-hour plus the right risk call (plumbing, not idea) — use E's frame with B's schedule. E is wrong to cut network; C is right that a local proxy is cheap and that filesystem-diff-only lands at Socket parity.
**Blind spot: D.** Spends 23 hours on positioning while the harness has zero models and no API key. Self-contradicts. Gate 2 auto-filing public issues on real maintainers' repos from an unvalidated tool is liability, not distribution.
**All missed:** nobody read the rubric. Judging is a compliance checklist (TrueForge, MCP, gate, merged PR, video); "does the sandbox produce the finding" is the user's standard, not the judges'. Loss mode is elegant-but-doesn't-run. Also unflagged: detonating real malware on the builder's own Mac (local sandbox != container), and a live `npm install` demo that can fail on stage — record it.

---

## Round 3 — Chairman's Verdict

### Where the Council Agrees

**Build it. All five said commit — unanimously, on the first line, without hedging.** No advisor argued for a fourth pivot. With ~23 hours and zero code, the search cost of another idea exceeds any expected quality gain. That question is closed.

**The canary passes your test, and it's the only one of your four ideas that does.** Four advisors independently landed on the same reason: a unique unguessable string appearing where it shouldn't is a fact, not an inference. There is no model between the observation and the verdict. The Outsider's version is cleanest — "I don't need to trust your model, your prompt, or your judgment. I can check it myself."

**The plumbing is the risk, not the idea.** The Executor said it outright and three of five reviewers ratified it. The novel mechanism is ~40 lines of bash. Everything that can actually kill you tonight is assembly.

**A planted villain alone rebuilds rejection #2 — you need real packages in frame.** Every advisor converged here from a different angle. If you author both the malware and the detector, a judge will notice, and rule 13 forces you to admit it.

**Cut list, near-unanimous:** Daytona, parallel per-package subagents, approval gate 2, auto-filing issues on upstream repos. All five reviewers named the Expansionist as the weakest response for adding surface to a project with zero lines of code.

### Where the Council Clashes

**Network capture: cut it or keep it?** First Principles and the Executor say cut. The Contrarian says cutting it destroys the product: real stealers POST, so a filesystem-only Customs lands at Socket.dev parity while executing code Socket refuses to execute. Reviewers split 3-2, and even reviewers who crowned First Principles conceded the Contrarian is right on this specific point. First Principles self-contradicts — "grep every outbound byte," then "cut network egress now." The Expansionist contradicts itself harder.

Cut-side is pricing schedule risk at hour 14 solo. Keep-side is pricing demo-credibility risk. **The Contrarian is right that you need egress, and wrong that a hand-rolled proxy plus catch-all resolver is cheap** — HTTPS means bodies require a MITM CA.

**Whose standard wins — yours or the judges'?** Review 5 caught what nobody else did: judging is a compliance checklist. "Does the sandbox produce the finding" is *your* standard for picking between ideas. It is not the win condition. Your loss mode is elegant-but-doesn't-run. Use your standard to choose, use theirs to allocate hours.

**Is the real-corpus sweep a finding or noise?** Two reviewers destroyed First Principles' headline: writing outside your own tree is *normal* node-gyp/prebuild behaviour, so that sweep returns noise. The sweep is contrast, not the headline.

### Blind Spots the Council Caught

**1. The containment hole — every reviewer flagged it, no advisor named it. The most important thing the council found.**

All five advisors recommend `npm install` with scripts enabled plus `require()`. Three go further and recommend detonating *real* packages, including known-bad samples. All on TrueForge's local macOS sandbox.

**A fake `$HOME` in a temp dir is HOME remapping, not an isolation boundary.** It stops malware that reads `$HOME/.aws/credentials`. It does nothing against malware that reads `/Users/<you>/.aws/credentials` — and real credential stealers use absolute paths precisely because env vars lie. Actual blast radius:

- `~/.ssh/id_rsa` — real key
- `~/.aws/credentials` — real
- `~/.npmrc` — a publish token that could push a package under your name
- `~/.config/gh` — a live GitHub token, for the repo you're about to submit
- `~/.claude/` — **including the API key you are about to add in hour one**

The credential you provision at hour 1 sits inside the blast radius of the malware you detonate at hour 4.

**2. Attribution.** `npm install <pkg>` installs the entire transitive tree. A canary hit indicts *the tree*, not the package named in the PR.

**3. The answer-key debate is partly moot.** OpenSSF publishes `malicious-packages`, thousands of real attributed npm samples. You don't have to write the villain. (This makes blind spot #1 more urgent, not less.)

**4. The dumb question, unanswered.** "Why not just `npm install --ignore-scripts`?" Your answer — you `require()` the code eventually, and `--ignore-scripts` breaks half of npm — must be a scripted line in the video.

**5. Live demos fail.** Record it.

### The Recommendation

**Build Customs. Ship it. Take First Principles' epistemic frame, the Executor's schedule, the Contrarian's insistence on egress — and put all of it inside a Docker container.**

Docker is the synthesis move nobody made. It solves containment and egress capture in one purchase:

- **Containment:** no `$HOME` mount, absolute paths hit a filesystem containing only your fakes. Real keys become unreachable rather than merely unadvertised.
- **Egress:** `--network` gives you a namespace you control. Point everything at a proxy container; log every CONNECT host with zero TLS work, and get full bodies for plaintext HTTP. Your own control package POSTs over HTTP, so the money shot is guaranteed.
- **Attribution fix, nearly free:** install the tree with `--ignore-scripts` first, snapshot, then execute only the target package's own script.

This is not Daytona. It's Docker Desktop, one `docker run`. If Docker isn't working within 45 minutes, **hard abort to: your own authored villain plus benign real packages only, never a real malware sample on the host** — and say so on camera.

Demo structure — three frames:

1. **Positive control:** your fixture package. Planted key at address A, same string in an outbound POST to address B. Ten seconds.
2. **Real known-bad** (from OpenSSF's corpus, in the container): the same instrument on code you did not write.
3. **Real benign contrast:** esbuild, sharp, bcrypt — genuine postinstall scripts, legitimate fetches, **zero canary hits.** This kills "you wrote both the question and the answer."

Rubric compliance is the win condition. Reserve hours 17–23 for README, recorded video, Qodo review, merged PR, submission. One approval gate, before the PR comment. Drop gate 2. Take exactly one thing from the Expansionist: name the CLI `customs inspect <target>` and add one README line claiming MCP servers as the next surface.

### The One Thing to Do First

**Get a model API key and boot TrueForge until one agent prints one line of output — before you write any Customs code.**

Not the 40-line core, and not Docker. The core is under your control and cannot surprise you. The harness is the only task with an *external* dependency and unknown duration — signup, billing verification, quota approval, an unfamiliar config format. It gates every rubric item. If it takes 30 minutes, you've lost nothing. If it takes three hours, discover that at hour zero, not hour twelve.

Store that key somewhere you will remember to treat as inside the blast radius when you start detonating.

---

## Post-council reality check

Run immediately after the verdict:

- **Docker is NOT installed on this machine** (`docker: command not found`). The chairman's central recommendation requires downloading and installing Docker Desktop, which needs an administrator password. This is an unbudgeted cost at hour zero and should be decided before anything else.
- TrueForge is running (PID 12197, `localhost:8790`, healthz OK) but has zero models, zero MCP servers, zero agents, zero skills, and no sandbox provider configured.
- The repository has two commits and no code.
