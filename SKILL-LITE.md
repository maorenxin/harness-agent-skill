---
name: harness-lite
description: "Lightweight harness that skips planning — spawns Generator + Evaluator to implement and verify based on the user's existing plan. One pass at 9.5+ to ship. Use when /harness feels too heavy or gets refused for smaller tasks."
---

# Harness Lite Skill

A streamlined version of `/harness` that skips the Planner phase entirely. It trusts the user's
existing plan (from Plan Mode or conversation context) and jumps straight into Generator ↔ Evaluator
iteration with a single-pass acceptance bar.

## When to Use

- The user already has a plan (approved via Plan Mode, or described in conversation)
- The task is well-scoped but benefits from adversarial evaluation
- `/harness` was refused or feels too heavy for the task size

## Invocation

```
/harness-lite <task description>
/harness-lite --max-rounds 5 --threshold 9.5 --dir ./my-project <task description>
```

### Parameters

| Parameter        | Default | Description                                   |
|------------------|---------|-----------------------------------------------|
| `<description>`  | —       | Task description (can reference existing plan) |
| `--max-rounds N` | 5       | Maximum generator↔evaluator iteration rounds   |
| `--threshold N`  | 9.5     | Score threshold for single-pass acceptance      |
| `--dir PATH`     | `.`     | Working directory for the project              |

### Key Differences from /harness

| Aspect              | /harness                        | /harness-lite                    |
|---------------------|----------------------------------|----------------------------------|
| Planner             | Spawns Planner agent             | Skipped — uses user's plan       |
| Spec/Criteria       | Planner writes them              | Orchestrator writes lightweight versions |
| User confirmation   | Grading dimensions dialog        | Skipped — uses sensible defaults |
| Alignment Phase     | Generator ↔ Evaluator negotiate  | Skipped — Generator starts immediately |
| Pass model          | pass^k (k consecutive passes)    | Single pass at threshold         |
| Default max rounds  | 10                               | 5                                |
| Git branch          | `harness/<slug>`                 | `harness-lite/<slug>`            |

### Execution Flow

#### Step 0: Setup

1. Parse arguments: extract `--max-rounds`, `--threshold`, `--dir`, and the task description.
2. Determine the project working directory (`PROJECT_DIR`).
3. **Team Lifecycle Cleanup**: Check for any existing harness team. If found:
   - Send shutdown requests to all active teammates
   - Call `TeamDelete` to remove the old team
   - If `TeamDelete` fails, manually remove: `rm -rf ~/.claude/teams/<old-team> ~/.claude/tasks/<old-team>`
4. Create harness workspace:
   ```
   $PROJECT_DIR/.harness/lite-<YYYY-MM-DD>-<short-slug>/
   ```
5. Create git branch:
   ```
   git checkout -b harness-lite/<short-slug>
   ```
6. Ensure `.harness/` is in `.gitignore`.
7. Initialize `state.json`:
   ```json
   {
     "task": "<description>",
     "max_rounds": 5,
     "threshold": 9.5,
     "current_round": 0,
     "status": "generating",
     "scores": [],
     "branch": "harness-lite/<short-slug>"
   }
   ```

#### Step 1: Bootstrap Spec & Criteria (Orchestrator)

The orchestrator writes lightweight versions of the planning documents directly — no Planner agent needed.

**`spec.md`** — Derive from the user's existing plan or conversation context:

```markdown
# Spec (Lite)

## Task
<paste the user's task description>

## Plan Reference
<paste or summarize the user's existing plan — from Plan Mode approval, conversation, or description>

## Acceptance
Single pass at {threshold}/10 weighted average.
```

**`criteria.md`** — Use sensible defaults based on project type:

```markdown
# Grading Criteria (Lite)

| Dimension        | Weight | Description                                    |
|------------------|--------|------------------------------------------------|
| Functionality    | 35%    | Features work correctly end-to-end             |
| Code Quality     | 25%    | Clean, modular, follows project conventions    |
| Completeness     | 25%    | All requirements from the plan are addressed   |
| Reliability      | 15%    | No crashes, errors handled, edge cases covered |

Score guide: 1-3 broken, 4-6 partial, 7-8 solid, 9-10 excellent.
```

**`contract.md`**:

```markdown
# Contract (Lite)

## Done When
Weighted average score >= {threshold}/10 in a single evaluation round.

## Verification Method
Evaluator runs the 6 mandatory verification phases and scores each dimension.

## Max Rounds
{max_rounds}
```

#### Step 2: Iteration Phase (Generator ↔ Evaluator)

Create a Team named `harness-lite-<short-slug>` and spawn **Generator** and **Evaluator** as teammates.

Use agent definitions at `~/.agents/skills/harness/agents/generator.md` and `~/.agents/skills/harness/agents/evaluator.md`.

Each iteration round:

1. **Send Generator** the task with:
   - `project_dir`, `harness_dir`, `round`, `max_rounds`, `threshold`
   - Tell Generator to skip the Alignment Phase — start implementing immediately
   - If round > 1, point to the latest `feedback-round-{N-1}.md`

2. **Wait for Generator** to finish and write `progress-round-{N}.md`.

3. **Send Evaluator** the evaluation task with:
   - `project_dir`, `harness_dir`, `round`, `threshold`
   - Tell Evaluator to skip the Alignment Phase review — go straight to the 6 verification phases

4. **Wait for Evaluator** to finish and write `evaluation-round-{N}.md` + `feedback-round-{N}.md`.

5. **Check termination** (single-pass model):

   a. **PASS**: weighted average >= threshold → proceed to Step 3 (Delivery)

   b. **STOP**: `current_round >= max_rounds` → proceed to Step 3 with final state

   c. **FAIL**: score below threshold → continue to next round

6. Update `state.json` and report progress to user (round number, score, key issues).

#### Step 3: Delivery

1. Generator does a final cleanup pass if needed.
2. Commit all remaining changes.
3. Attempt to rebase onto the base branch:
   ```
   git rebase <base-branch>
   ```
   If conflicts arise, pause and ask the user.
4. Write `summary.md` to the harness workspace:
   ```markdown
   # Harness Lite Summary

   ## Task
   <description>

   ## Result: PASS / MAX_ROUNDS_REACHED
   - Final score: X.XX/10
   - Rounds used: N/{max_rounds}

   ## What Was Delivered
   <brief summary of changes>
   ```
5. **Team Shutdown**:
   a. Send `shutdown_request` to Generator and Evaluator
   b. Wait for termination confirmations
   c. Call `TeamDelete`
   d. If cleanup fails, manually remove team/task directories
6. Report final results to the user.

### Agent Naming Convention

Always use simple names — no suffixes:
- `generator`
- `evaluator`

### Harness Lite Workspace Structure

```
$PROJECT_DIR/.harness/
└── lite-2026-04-02-add-dark-mode/
    ├── state.json
    ├── spec.md
    ├── criteria.md
    ├── contract.md
    ├── progress-round-1.md
    ├── evaluation-round-1.md
    ├── feedback-round-1.md
    ├── ...
    └── summary.md
```
