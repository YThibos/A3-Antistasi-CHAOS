# Token usage review — 2026 week 34 (Mon 17 – Fri 21 Aug)

Written 2026-08-21 from the data reachable inside a cloud session: the
Claude Code Remote session list, the per-session `usage` block where the
platform reports one, this session's own transcript, and the repo's git
history.

## What is and isn't measured

| Source | Sessions | Token data |
|---|---|---|
| `anthropic_cloud` (Claude Code on web/Android) | 2 | exact — `usage` block per session |
| `bridge` (CLI + remote control on the workstation) | 9 | none reported; usage lives in the local `~/.claude` on that machine |

So the week's **total** spend is not knowable from here. What *is* knowable
is the per-token anatomy of a session in this repo, measured exactly, plus
the rate-limit signals that every session carries. Those generalise to the
bridge sessions, which do the same kind of work on the same repo.

To get the missing total, run this on the workstation:

```powershell
py -c "import json,glob,collections;
d=collections.Counter()
for f in glob.glob(r'~/.claude/projects/**/*.jsonl',recursive=True):
    for l in open(f,encoding='utf-8',errors='ignore'):
        try: u=json.loads(l)['message']['usage']
        except Exception: continue
        for k in ('input_tokens','output_tokens','cache_creation_input_tokens','cache_read_input_tokens'): d[k]+=u.get(k,0)
print(d)"
```

Deduplicate by message id — the transcript stamps the same `usage` block on
every content block of a message, so a naive sum over-counts by ~3×.

## The week's shape

Eleven sessions Mon–Fri, across four repos (`A3-Antistasi-CHAOS`,
`firstofficer`, `JustFront-UIComponents`, `firstmate`). Every one ran
**Opus 5**; effort was `high` on most, `xhigh` on the Angular 22 upgrade.

Rate-limit status carried on those sessions:

| When | Bucket | Status |
|---|---|---|
| Tue 18 Aug, ~22:20 UTC | 5-hour | **rejected** |
| Thu 20 Aug, 05:53 UTC | **7-day** | **allowed_warning** (window resets Mon 24 Aug 22:00 UTC) |
| Thu 20 Aug, ~15:40 UTC | 5-hour | **rejected** — 4 sessions simultaneously |
| Fri 21 Aug, 06:15 UTC | 5-hour | allowed |

The 7-day window opened Mon 17 Aug 22:00 UTC. Hitting *warning* by Thursday
05:53 means the weekly budget was in the danger band **one third of the way
into the window**. That is the headline: the burn rate is roughly double
what the week can carry, and it showed up as two hard 5-hour stalls.

The Thursday stall is the clearest own-goal. Between 07:05 and 11:12 UTC four
bridge sessions ran concurrently — the Angular 22 upgrade at `xhigh`, the
session-lock harness fix, and two others. They share one 5-hour bucket, and
all four were rejected at the same boundary.

## Where the tokens actually go

Two cloud sessions, measured exactly. Costs use Opus 5 rates with the
1-hour cache TTL ($5/M input, $25/M output, $10/M cache write, $0.50/M
cache read) — this model reproduces the platform's reported figure for
session A to seven decimal places, so the breakdown below is not an estimate.

**Session A — Thu 20 Aug, "yard-gated Military construction kit", 11 minutes**

```
in-side tokens   4,087,844      of which cache reads: 96.6%
output tokens       23,624
                                        cost      share
  cache read     3,949,463            $1.9747     50.0%
  cache write      138,301            $1.3830     35.0%
  output            23,624            $0.5906     15.0%
  input                 80            $0.0004      0.0%
                                      -------
                                       $3.9487
```

**Session B — this analysis session, 7 turns**

```
  cache write       74,111            $0.7411     71.1%
  cache read       343,111            $0.1716     16.5%
  output             5,194            $0.1298     12.5%
                                      -------
                                       $1.0426
```

Three numbers matter.

**1. 85% of session A's cost was context, not thinking.** Cache reads plus
cache writes were $3.36 of $3.95. The model generated 23,624 tokens of
actual work and paid for 4.09 million tokens of context to do it — a
**167:1** read-to-output ratio. Session A shipped commit `c6681cc`: nine
files, 78 net lines of SQF. At ~80k average context that is roughly **49
turns for 78 lines**.

**2. Every session in this repo starts at 50,850 tokens — $0.51 before the
first useful token.** Measured on turn 1 of this session, which had done
nothing yet. That is the system prompt, the tool schemas (including ~90
deferred GitHub MCP tool names), every skill description, and
`AGENTS.md`. It is paid again on every new session, and every subsequent
turn re-reads it.

**3. Context grew 2,900 tokens per turn**, and each turn re-reads the whole
thing. Cost is quadratic in turn count, which is why turn count — not
context size — is the dominant lever. Halving the turns for the same work
saves more than halving the starting context.

The largest single cache-write in this session was **8,598 tokens for one
`list_sessions(limit=100)` call** — $0.086 for one tool result, permanently
resident in context thereafter. Unbounded tool output is the main variable
cost.

## Findings and what to do about them

Ranked by saving per unit of effort.

### 1. Fewer, denser turns — the 167:1 ratio (largest lever, no downside)

49 turns for 78 lines is the whole problem in one statistic. Batching
independent tool calls into a single response collapses turns directly:
this session made 2–4 parallel calls per turn throughout, which is why its
read-to-output ratio is 66:1 rather than 167:1.

Concretely, for this codebase: read every file you are about to edit in one
turn, not one per turn; run the syntax checker once at the end over
`-Changed` rather than after each file (the `PostToolUse` hook already
covers the per-edit case — the manual re-runs are redundant); and grep once
with a pattern that answers the question rather than three times narrowing
in.

Add to `AGENTS.md` hard rules: *batch independent reads, greps and edits
into one turn.*

### 2. Cut the always-on payload (~$0.10–0.25/session, trivial effort)

`AGENTS.md` is 8,973 bytes (~2,243 tokens) and loads in full at the start of
every session. Its **"Notes for future work" section is 4,059 bytes — 45% of
the file** — and is six dated findings about the SQF checker, the `py`
launcher, `pboextract`, the BAR API, the map Draw EH and StreetArtist.

None of that is needed to *start* a session. The file itself already says
the skills are "usually the better home". Moving those notes into
`antistasi-codebase` and `sqf-scripting` makes them load only when the work
touches that area, and cuts the always-on payload by nearly half.

Same category: `.gitignore` the generated `docs/current_modlist.html`
(20,668 bytes, 519 lines, committed Thursday). It is a build artifact that
will surface in every future grep of `docs/`.

### 3. Guard `Stringtable.xml` (prevents a single catastrophic turn)

`A3A/addons/core/Stringtable.xml` is **1,333,442 bytes — roughly 333,000
tokens**, more than a full context window. Hard rule 7 sends every
string-adding session straight at it. One unbounded `Read` or a loose grep
returning hundreds of matches costs more than an entire ordinary session.

Add a hard rule: *never `Read` a Stringtable whole; grep it with an anchored
pattern and a match limit, and append with a script.* A small
`Tools/stringtable/Add-String.ps1` would remove the need to load it at all —
the same move that `pboextract.py` already made for PBO parsing, which is
the best token decision in the repo this week.

### 4. Stagger concurrent sessions (recovers the Thursday stall)

Four parallel bridge sessions share one 5-hour bucket. Running the Angular
22 upgrade, the session-lock fix and two more against the same bucket is what
produced the 15:40 rejection. Two at a time, with the long build-loop session
started after the short ones have landed, keeps the bucket alive across the
working day.

### 5. Right-size effort and model (largest single line-item saving)

The Angular 22 upgrade ran at **`xhigh`**. It is a dependency bump whose
bottleneck is `npm run build` — the hard part is reading build output, not
reasoning. `high` or `medium` would have produced the same result; `xhigh`
buys thinking tokens on a task that is waiting on a compiler.

Similarly, everything this week ran Opus 5, including changelog appends,
stringtable syncs and syntax-check passes. Those are Haiku or Sonnet work.
Reserve Opus for the sessions that actually design something — `fn_computeInfluenceZones`
(147 lines of BFS/triangulation) earned it; "append a line to CHANGELOG.md"
did not.

### 6. Bound tool output (small but free)

The GitHub MCP server's own guidance — paginate in batches of 5–10, pass
`minimal_output` when full detail is not needed — was not followed this
week, and neither was it here until it cost 8,598 tokens in one call. Ask
for the fields you need.

## Expected effect

Items 2, 3 and 6 are mechanical and cut maybe 10–15% off a typical session.
Item 1 is the one that matters: turn count drives a quadratic, and the gap
between 167:1 and 66:1 is roughly a halving of cost for identical output.
Items 4 and 5 do not reduce tokens so much as stop them landing in the wrong
bucket at the wrong time, which is what actually cost working hours this week.
