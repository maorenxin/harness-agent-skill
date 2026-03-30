---
name: harness
description: "Launch a multi-agent harness (Planner + Generator + Evaluator) to iteratively build and deliver high-quality software. Use when the user invokes /harness or mentions 'harness' for a development task that benefits from plan-generate-evaluate iteration loops. Inspired by Anthropic's harness design pattern."
---

# Harness Skill

A GAN-inspired multi-agent development harness that decomposes complex software tasks into a
Planner → Generator ↔ Evaluator iteration loop, delivering high-quality output through
structured feedback cycles.

## Invocation

```
/harness <task description>
/harness --max-rounds 8 --threshold 9.5 --pass-k 3 --dir ./my-project <task description>
```

### Parameters

| Parameter        | Default | Description                                    |
|------------------|---------|------------------------------------------------|
| `<description>`  | —       | 1-4 sentence natural language task description  |
| `--max-rounds N` | 10      | Maximum generator↔evaluator iteration rounds    |
| `--threshold N`  | 9.5     | Score threshold (1-10) for pass^k evaluation    |
| `--pass-k N`     | 3       | Consecutive rounds above threshold to pass      |
| `--dir PATH`     | `.`     | Working directory for the project               |

## Execution Flow

When this skill is invoked, the orchestrator (you) must follow these steps exactly:

### Step 0: Setup

1. Parse arguments: extract `--max-rounds`, `--threshold`, `--pass-k`, `--dir`, and the task description.
2. Determine the project working directory (`PROJECT_DIR`).
3. **Team Lifecycle Cleanup**: Before creating anything, check if you are currently leading a team from a previous harness run. If so:
   - Send shutdown requests to ALL active teammates and wait for confirmation
   - Call `TeamDelete` to cleanly remove the old team
   - If `TeamDelete` fails (e.g., stale session state), manually remove the team directories:
     ```
     rm -rf ~/.claude/teams/<old-team-name> ~/.claude/tasks/<old-team-name>
     ```
   - Only proceed after the old team is fully cleaned up
4. Create a harness workspace directory:
   ```
   $PROJECT_DIR/.harness/run-<YYYY-MM-DD>-<short-slug>/
   ```
   Where `<short-slug>` is a 2-3 word kebab-case summary of the task (e.g., `add-auth-system`).
   If the same slug already exists for today, append `-2`, `-3`, etc.
5. Create a new git branch from the current branch:
   ```
   git checkout -b harness/<short-slug>
   ```
6. Initialize the harness state file at `.harness/run-<...>/state.json`:
   ```json
   {
     "task": "<original description>",
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
6. Ensure `.harness/` is in `.gitignore`. If `.gitignore` doesn't exist, create it. If it exists but doesn't contain `.harness/`, append it. The `.harness/` directory contains process documents (specs, evaluations, feedback) that should NOT be committed to the repository.
   ```
   echo ".harness/" >> .gitignore
   ```

### Step 1: Planning Phase

Create a Team named `harness-<short-slug>` and spawn the **Planner** agent (use agent definition at `~/.agents/skills/harness/agents/planner.md`).

**IMPORTANT: The Planner MUST enter Plan Mode** (using EnterPlanMode) to design the spec, then present the plan to the user for approval via ExitPlanMode before writing any documents.

The Planner receives:
- The original task description
- The project directory path
- The harness workspace path

#### Step 1a: User Confirmation of Grading Criteria

Before the Planner writes `criteria.md`, the orchestrator MUST use `AskUserQuestion` to confirm grading criteria with the user:

1. **Dimension Selection** (multiSelect): Present candidate grading dimensions based on project type and ask the user to select which ones to include. Example dimensions:
   - Functionality — features work correctly end-to-end
   - Code Quality — clean, modular, well-structured code
   - Design & UX — visual polish, game feel, responsiveness
   - Testing & Reliability — edge cases handled, no crashes
   - Completeness — all spec requirements addressed
   - Performance — fast, efficient, no bottlenecks
   - Security — no vulnerabilities, safe practices
   - API Design — clean, consistent, well-documented API surface

2. **Weight Priority Order** (single select): Based on the selected dimensions, propose 2-3 weight distribution presets (ordered by priority) and let the user pick. For example:
   - "Functionality-first" — Functionality 35%, Code Quality 20%, Design 20%, Reliability 15%, Completeness 10%
   - "UX-first" — Design & UX 30%, Functionality 25%, Completeness 20%, Code Quality 15%, Reliability 10%
   - "Balanced" — equal weights across all selected dimensions

Pass the user's choices to the Planner so `criteria.md` reflects the user's priorities.

#### Step 1b: Planner Outputs

The Planner outputs these files into the harness workspace:
- `spec.md` — Full product/feature specification
- `criteria.md` — Grading criteria with user-confirmed dimensions and weights
- `contract.md` — Sprint contract: what "done" means, how success is verified

After the Planner completes, **show the user a summary of the spec and ask for confirmation** before proceeding. The user may adjust scope or priorities.

### Step 1.5: Alignment Phase (Generator ↔ Evaluator Negotiation)

Before any coding begins, the Generator and Evaluator must align on implementation approach:

1. **Generator** reads `spec.md`, `criteria.md`, and `contract.md`, then writes `implementation-plan.md` to the harness workspace. This document contains:
   - Proposed technical architecture and key design decisions
   - File-by-file implementation plan with responsibilities
   - Dependency choices and rationale
   - Risk areas and mitigation strategies
   - Proposed round-by-round delivery breakdown

2. **Evaluator** reviews `implementation-plan.md` and writes `alignment-review.md` with:
   - Agreement or disagreement on architecture choices
   - Concerns about testability or verifiability
   - Suggested changes to the implementation approach
   - Confirmation of how they will evaluate each deliverable

3. If the Evaluator raises concerns, the Generator revises `implementation-plan.md` until both agents agree. The orchestrator facilitates this exchange via messages.

4. Once aligned, both agents proceed with a shared understanding. The `implementation-plan.md` becomes a reference document alongside the contract.

This step prevents the Generator from building something the Evaluator can't properly test, and ensures both agents share the same mental model of the deliverables.

### Step 2: Iteration Phase (Generator ↔ Evaluator)

Spawn **Generator** and **Evaluator** as teammates in the same team.

Each iteration round:

1. **Generator** reads `spec.md`, `criteria.md`, `contract.md`, and any previous `feedback-round-N.md`.
   - Implements the next chunk of work
   - Writes `progress-round-N.md` to the harness workspace summarizing what was done
   - Commits changes with message: `harness: round N - <summary>`

2. **Evaluator** reads `criteria.md`, `contract.md`, `progress-round-N.md`, and inspects the actual code/output.
   - For Web projects: attempts to start the app and test with Playwright (screenshots, UI interaction, API calls)
   - For other projects: runs linting, tests, code review against criteria
   - Scores each dimension in `criteria.md` (1-10)
   - Writes `evaluation-round-N.md` with scores, detailed feedback, and pass/fail verdict
   - Writes `feedback-round-N.md` with actionable items for the Generator

3. **Check termination conditions (pass^k model):**

   The harness uses a **pass^k** reliability model: the Generator must achieve `k` consecutive rounds
   above the threshold to pass. This ensures quality is stable, not a one-time fluke.

   After each Evaluator round, update `state.json`:
   - If this round's weighted avg >= threshold: increment `consecutive_passes`
   - If this round's weighted avg < threshold: reset `consecutive_passes` to 0

   Then check these conditions IN ORDER:

   a. **PASS (Stable)**: `consecutive_passes >= pass_k`
      - The work has consistently met quality standards for `k` consecutive rounds.
      - Proceed to Step 3 (Delivery).

   b. **PASS (Approaching)**: weighted avg >= threshold BUT `consecutive_passes < pass_k`
      - Tell Generator: "Score is above threshold ({score}/{threshold}), {consecutive_passes}/{pass_k} consecutive passes achieved. Maintain quality for {remaining} more round(s) to confirm stability."
      - Continue to next round.

   c. **STOP**: `current_round >= max_rounds`
      - Report final state including pass^k progress. Proceed to Step 3.

   d. **PLATEAU**: scores changed < 0.3 for 2+ consecutive rounds AND below threshold
      - Evaluator suggests pivot direction in feedback.

   e. **FAIL**: score below threshold, continue to next round.

4. Update `state.json` after each round with current scores and status.

5. **Report progress** to the user after each round: round number, scores, key feedback points.

### Step 3: Delivery

1. Generator does a final cleanup pass if needed.
2. Commit all remaining changes.
3. Attempt to rebase the harness branch onto the base branch:
   ```
   git rebase <base-branch>
   ```
   - If conflicts arise, **pause and ask the user** for resolution guidance.
   - Do NOT force-push or discard changes.
4. Write `summary.md` to the harness workspace with:
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
6. **Team Shutdown** (must follow this exact sequence):
   a. Send `shutdown_request` to ALL active teammates (Generator, Evaluator) and wait for `shutdown_approved` responses
   b. Wait for `teammate_terminated` system messages confirming all agents have exited
   c. Call `TeamDelete` to remove the team and task directories
   d. If `TeamDelete` fails, manually clean up:
      ```
      rm -rf ~/.claude/teams/harness-<slug> ~/.claude/tasks/harness-<slug>
      ```
   e. Verify cleanup is complete before reporting to the user

The user can then review the branch and merge at their discretion.

## Harness Workspace Structure

```
$PROJECT_DIR/.harness/
└── run-2026-03-28-add-auth-system/
    ├── state.json              # Harness state tracking
    ├── spec.md                 # Product specification (from Planner)
    ├── criteria.md             # Grading criteria (from Planner, user-confirmed)
    ├── contract.md             # Sprint contract (from Planner)
    ├── implementation-plan.md  # Generator's technical plan (Alignment Phase)
    ├── alignment-review.md     # Evaluator's review of the plan (Alignment Phase)
    ├── progress-round-1.md     # Generator progress report
    ├── evaluation-round-1.md   # Evaluator scores + analysis
    ├── feedback-round-1.md     # Actionable feedback for Generator
    ├── progress-round-2.md
    ├── evaluation-round-2.md
    ├── feedback-round-2.md
    ├── ...
    └── summary.md              # Final delivery summary
```

## Agent Definitions

The three agents are defined in `~/.agents/skills/harness/agents/`:
- `planner.md` — Expands task into spec + criteria + contract
- `generator.md` — Implements features iteratively
- `evaluator.md` — Tests and scores against criteria

## Important Notes

- Each harness run gets its own git branch (`harness/<slug>`) to isolate changes
- The `.harness/` directory is in `.gitignore` — it contains process documents only, NOT project deliverables
- The `.harness/` directory serves as the communication channel between agents (structured handoffs via files)
- Generator and Evaluator MUST align on implementation approach via `implementation-plan.md` before coding starts (Step 1.5)
- Grading dimensions and weights are confirmed by the user before the Planner writes `criteria.md`
- The Planner uses Plan Mode to get user approval before writing documents
- Multiple harness runs can coexist under `.harness/` — each is independent
- Default pass threshold is 9.5/10 with pass^3 (3 consecutive rounds above threshold required)

### Agent Naming Convention

Always use consistent, simple names for agents across harness runs:
- `planner` — never `planner2`, `planner3`, etc.
- `generator` — never `generator2`, `generator3`, etc.
- `evaluator` — never `evaluator2`, `evaluator3`, etc.

Each harness run MUST have a clean team. If a previous team exists, it must be fully shut down and deleted (Step 0.3) before creating the new team. This ensures agent names stay clean and don't collide.

### Team Lifecycle

A harness team's lifecycle is strictly bounded:
```
TeamCreate → [spawn agents] → [work] → [shutdown all agents] → TeamDelete
```
Never leave a team alive between harness runs. The orchestrator is responsible for ensuring the team is fully cleaned up in Step 3, and for verifying cleanup in Step 0 before starting a new run.
