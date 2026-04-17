---
name: harness
description: "Launch a multi-agent harness (Planner + Generator + Evaluator, pass^k reliability) to iteratively build and deliver high-quality software. Accepts either a vague task description OR a detailed pre-written plan — the Planner auto-detects and adapts."
---

# Harness Skill

A GAN-inspired multi-agent development harness that decomposes complex software tasks into a
Planner → Generator ↔ Evaluator iteration loop, delivering high-quality output through
structured feedback cycles.

The Planner accepts both **vague descriptions** (which it expands via project exploration)
and **detailed plans** (which it faithfully translates into the three harness documents).
There is no separate "lite" mode.

## Invocation

```
/harness <task description or detailed plan>
/harness --max-rounds 8 --threshold 9.5 --pass-k 3 --dir ./my-project <description>
```

### Parameters

| Parameter        | Default | Description                                    |
|------------------|---------|------------------------------------------------|
| `<description>`  | —       | Task description OR a detailed plan (any length) |
| `--max-rounds N` | 10      | Maximum generator↔evaluator iteration rounds    |
| `--threshold N`  | 9.5     | Score threshold (1-10) for pass^k evaluation    |
| `--pass-k N`     | 3       | Consecutive rounds above threshold to pass      |
| `--dir PATH`     | `.`     | Working directory for the project               |

## Spawning Policy (must follow)

**All harness teammates (Planner, Generator, Evaluator) MUST be spawned with
`mode: "bypassPermissions"`** on the Agent tool call. This prevents each file read / edit /
bash command from bouncing back to the team leader (you) for approval, which makes the
harness unusable. Example:

```
Agent({
  subagent_type: "harness-planner",
  team_name: "harness-<slug>",
  name: "planner",
  mode: "bypassPermissions",
  prompt: "...",
})
```

The orchestrator (you) stays in the default permission mode — only the spawned teammates
run in bypass. The user has already opted into this by invoking `/harness`.

## Execution Flow

When this skill is invoked, the orchestrator (you) must follow these steps exactly.

### Step 0: Setup

1. Parse arguments: extract `--max-rounds`, `--threshold`, `--pass-k`, `--dir`, and the
   task description.
2. Determine the project working directory (`PROJECT_DIR`).
3. **Classify the input** as `detailed` or `vague`:
   - `detailed` if the description contains a structured plan (numbered steps, file-level
     decisions, explicit acceptance criteria, ≥ ~200 words of concrete direction, or
     references "the plan above" / "Plan Mode" / a pasted plan block).
   - `vague` otherwise (1-4 sentences of intent without implementation detail).
   - When in doubt, treat as `vague`.
   - Record the classification in `state.json` as `input_mode`.
4. **Team Lifecycle Cleanup**: Before creating anything, check if you are currently leading
   a team from a previous harness run. If so:
   - Send shutdown requests to ALL active teammates and wait for confirmation
   - Call `TeamDelete` to cleanly remove the old team
   - If `TeamDelete` fails, manually remove the team directories:
     ```
     rm -rf ~/.claude/teams/<old-team-name> ~/.claude/tasks/<old-team-name>
     ```
   - Only proceed after the old team is fully cleaned up.
5. Create a harness workspace directory:
   ```
   $PROJECT_DIR/.harness/run-<YYYY-MM-DD>-<short-slug>/
   ```
   Where `<short-slug>` is a 2-3 word kebab-case summary of the task (e.g., `add-auth-system`).
   If the same slug already exists for today, append `-2`, `-3`, etc.
6. Create a new git branch from the current branch:
   ```
   git checkout -b harness/<short-slug>
   ```
7. Initialize the harness state file at `.harness/run-<...>/state.json`:
   ```json
   {
     "task": "<original description>",
     "input_mode": "detailed" | "vague",
     "max_rounds": 10,
     "threshold": 9.5,
     "pass_k": 3,
     "current_round": 0,
     "status": "planning",
     "scores": [],
     "consecutive_passes": 0,
     "branch": "harness/<short-slug>"
   }
   ```
8. Ensure `.harness/` is in `.gitignore`. If missing, append it. The `.harness/` directory
   contains process documents only; it must not be committed.

### Step 1: Planning Phase

#### Step 1a: Grading Criteria Confirmation (vague mode only)

If `input_mode == "vague"`, use `AskUserQuestion` to confirm grading criteria before the
Planner runs:

1. **Dimension Selection** (multiSelect): Present candidate dimensions based on project type
   (Functionality, Code Quality, Design & UX, Testing & Reliability, Completeness,
   Performance, Security, API Design).
2. **Weight Priority Order** (single select): Propose 2-3 weight presets and let the user pick:
   - "Functionality-first" — Functionality 35%, Code Quality 20%, Design 20%, Reliability 15%, Completeness 10%
   - "UX-first" — Design & UX 30%, Functionality 25%, Completeness 20%, Code Quality 15%, Reliability 10%
   - "Balanced" — equal weights across selected dimensions

If `input_mode == "detailed"`, **skip this dialog** — the Planner uses sensible defaults
(Functionality 35%, Code Quality 25%, Completeness 25%, Reliability 15%). The user already
showed they want fast execution by providing a plan.

#### Step 1b: Spawn the Planner

Create a Team named `harness-<short-slug>` and spawn the **Planner** agent via the Agent
tool with:
- `subagent_type: "harness-planner"`
- `team_name: "harness-<short-slug>"`
- `name: "planner"`
- `mode: "bypassPermissions"` — **required**
- Prompt containing: `task`, `project_dir`, `harness_dir`, `input_mode`,
  `user_dimensions` (if asked), `user_weights` (if asked).

The Planner will write three files and then stop:
- `spec.md` — Full product/feature specification
- `criteria.md` — Grading criteria
- `contract.md` — What "done" means, how success is verified

**The Planner does NOT enter Plan Mode, does NOT write code, and does NOT spawn any other
agents.** If the Planner starts drifting into implementation, send a shutdown and respawn.

#### Step 1c: Confirm with user (vague mode only)

If `input_mode == "vague"`, after the Planner finishes, show the user a one-paragraph
summary of the spec and ask for confirmation before proceeding. The user may adjust scope.

If `input_mode == "detailed"`, skip confirmation and proceed — the plan was already the
user's.

### Step 1.5: Alignment Phase (Generator ↔ Evaluator)

Before coding begins, Generator and Evaluator align on approach.

1. **Spawn Generator and Evaluator** as teammates in the same team, both with
   `mode: "bypassPermissions"`.
2. **Generator** reads `spec.md`, `criteria.md`, `contract.md`, then writes
   `implementation-plan.md`:
   - Proposed technical architecture and key design decisions
   - File-by-file implementation plan
   - Dependency choices and rationale
   - Risk areas and mitigation
   - Proposed round-by-round delivery breakdown
3. **Evaluator** reviews and writes `alignment-review.md`:
   - Agreement / disagreement on architecture
   - Concerns about testability or verifiability
   - Suggested changes
   - How they will evaluate each deliverable
4. If concerns are raised, Generator revises until both agree. Orchestrator facilitates.

In `input_mode == "detailed"`, this phase can be **compressed**: Generator writes a short
`implementation-plan.md` that restates the user's plan in the template's shape, and
Evaluator confirms in a brief `alignment-review.md`. Do not drag out negotiation if the
user already specified the approach.

### Step 2: Iteration Phase (Generator ↔ Evaluator)

Each iteration round:

1. **Generator** reads `spec.md`, `criteria.md`, `contract.md`, and any previous
   `feedback-round-N.md`, then:
   - Implements the next chunk of work
   - Writes `progress-round-N.md`
   - Commits with message `harness: round N - <summary>`

2. **Evaluator** reads `criteria.md`, `contract.md`, `progress-round-N.md`, and inspects
   the actual code/output.
   - Web: start the app, drive with Puppeteer/Playwright
   - API: curl endpoints
   - Library/CLI: run tests, invoke commands
   - Scores each dimension (1-10)
   - Writes `evaluation-round-N.md` (scores + analysis) and `feedback-round-N.md`
     (actionable items).

3. **Check termination (pass^k model):**

   pass^k = Generator must achieve `k` consecutive rounds above threshold.

   After each Evaluator round, update `state.json`:
   - If this round's weighted avg >= threshold: increment `consecutive_passes`
   - Else: reset `consecutive_passes` to 0

   Then check IN ORDER:

   a. **PASS (Stable)**: `consecutive_passes >= pass_k` → proceed to Step 3.
   b. **PASS (Approaching)**: avg >= threshold but `consecutive_passes < pass_k` →
      tell Generator: "Score is above threshold ({score}/{threshold}),
      {consecutive_passes}/{pass_k} consecutive passes achieved. Maintain quality for
      {remaining} more round(s)." Continue.
   c. **STOP**: `current_round >= max_rounds` → proceed to Step 3.
   d. **PLATEAU**: scores changed < 0.3 for 2+ rounds AND below threshold → Evaluator
      suggests pivot.
   e. **FAIL**: below threshold → continue to next round.

4. Update `state.json` after each round.
5. Report progress to user after each round: round number, scores, key feedback points.

### Step 3: Delivery

1. Generator does a final cleanup pass if needed.
2. Commit all remaining changes.
3. Attempt to rebase the harness branch onto the base branch:
   ```
   git rebase <base-branch>
   ```
   - If conflicts arise, **pause and ask the user**.
   - Do NOT force-push or discard changes.
4. Write `summary.md`:
   - Final scores
   - Total rounds used
   - Key decisions made
   - What was delivered
   - Reliability metrics:
     ```
     ## Reliability Metrics (pass^k)
     - Threshold: X.X
     - Required consecutive passes (k): N
     - Rounds played: N
     - Rounds above threshold: M
     - Max consecutive passes achieved: N
     - pass^k achieved: YES/NO (round N)
     - Score trend: improving / stable / declining / volatile
     - Final score: X.XX (round N)
     ```
5. Report final results to the user.
6. **Team Shutdown** (exact sequence):
   a. Send `shutdown_request` to ALL active teammates and wait for `shutdown_approved`.
   b. Wait for `teammate_terminated` confirmations.
   c. Call `TeamDelete`.
   d. If `TeamDelete` fails, manually clean up:
      ```
      rm -rf ~/.claude/teams/harness-<slug> ~/.claude/tasks/harness-<slug>
      ```
   e. Verify cleanup before reporting done.

The user can then review the branch and merge at their discretion.

## Harness Workspace Structure

```
$PROJECT_DIR/.harness/
└── run-2026-03-28-add-auth-system/
    ├── state.json              # Harness state tracking
    ├── spec.md                 # Product specification (from Planner)
    ├── criteria.md             # Grading criteria (from Planner)
    ├── contract.md             # Sprint contract (from Planner)
    ├── implementation-plan.md  # Generator's technical plan
    ├── alignment-review.md     # Evaluator's review of the plan
    ├── progress-round-1.md     # Generator progress report
    ├── evaluation-round-1.md   # Evaluator scores + analysis
    ├── feedback-round-1.md     # Actionable feedback for Generator
    ├── ...
    └── summary.md              # Final delivery summary
```

## Agent Definitions

Defined in `~/.agents/skills/harness/agents/`:
- `planner.md` — Translates task (vague or detailed) into spec + criteria + contract
- `generator.md` — Implements features iteratively
- `evaluator.md` — Tests and scores against criteria

## Important Notes

- **All teammates spawn with `mode: "bypassPermissions"`.** Never spawn without it; the
  harness becomes unusable when every tool call prompts the leader.
- **Planner never writes code** — it only produces `spec.md`, `criteria.md`, `contract.md`.
  It does not use Plan Mode. If it starts implementing, shut it down and respawn.
- The Planner auto-adapts to vague vs detailed input — no separate skill needed.
- Each harness run gets its own git branch (`harness/<slug>`).
- `.harness/` is gitignored — process documents only, not deliverables.
- Generator and Evaluator MUST align via `implementation-plan.md` before coding (Step 1.5).
- Grading dimensions/weights are user-confirmed for vague inputs; defaulted for detailed.
- Default: `--threshold 9.5 --pass-k 3 --max-rounds 10`.

### Agent Naming Convention

Always use consistent, simple names across runs:
- `planner` — never `planner2`, `planner3`, etc.
- `generator` — never `generator2`, etc.
- `evaluator` — never `evaluator2`, etc.

Each harness run MUST start with a clean team (Step 0.4).

### Team Lifecycle

```
TeamCreate → [spawn agents in bypassPermissions mode] → [work] → [shutdown all] → TeamDelete
```

Never leave a team alive between runs. Cleanup in Step 3; verify in Step 0 before starting.
