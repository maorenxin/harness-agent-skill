# Harness Agent Skill

A multi-agent development harness for [Claude Code](https://claude.com/claude-code). Inspired by Anthropic's harness design pattern (GAN-style adversarial iteration), it decomposes complex software tasks into a **Planner → Generator ↔ Evaluator** loop that iterates until quality standards are met.

## Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/maorenxin/harness-agent-skill/master/install.sh | bash
```

Or manually:

```bash
# Skill definition
mkdir -p ~/.claude/skills/harness
cp skill/SKILL.md ~/.claude/skills/harness/

# Agent definitions
mkdir -p ~/.agents/skills/harness/agents
cp agents/*.md ~/.agents/skills/harness/agents/
```

## Usage

In Claude Code, type:

```
/harness 你的需求描述
```

With options:

```
/harness --max-rounds 8 --threshold 9 --dir ./my-project 需求描述
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--max-rounds N` | 10 | Maximum iteration rounds |
| `--threshold N` | 9 | Score threshold (1-10) to pass |
| `--dir PATH` | `.` | Working directory |

## How It Works

```
User Prompt
    │
    ▼
┌─────────┐    spec.md
│ Planner │───▶ criteria.md    ◀── User confirms grading dimensions
│         │    contract.md
└─────────┘
    │
    ▼
┌───────────┐  implementation-plan.md   ┌───────────┐
│ Generator │◀─────────────────────────▶│ Evaluator │  Alignment Phase
│           │  alignment-review.md      │           │  (negotiate before coding)
└───────────┘                           └───────────┘
    │                                        │
    ▼                                        ▼
┌───────────┐  progress-round-N.md      ┌───────────┐
│ Generator │─────────────────────────▶ │ Evaluator │  Iteration Phase
│  (code)   │◀─────────────────────────│  (score)  │  (loop until pass)
└───────────┘  feedback-round-N.md      └───────────┘
```

1. **Planner** expands your brief description into a full spec, grading criteria, and sprint contract
2. **User confirms** which grading dimensions and weight distribution to use
3. **Alignment Phase** — Generator writes an implementation plan, Evaluator reviews it. They negotiate until aligned. This prevents wasted coding effort.
4. **Iteration Phase** — Generator codes → Evaluator scores against criteria → if below threshold, Generator gets specific feedback and tries again
5. **Delivery** — once the score passes the threshold, final cleanup and summary

## Real-World Results

We built a complete browser-based snake game from scratch using two prompts, ~50 minutes total:

**Prompt 1** (28 min, 2 coding rounds):
> "做一个贪吃蛇游戏，需要有过关系统，吃item1变长，吃item2变短，道具可配置（内置预设+随机+AI生成）"

- Round 1: 6.95/10 (FAIL) → Round 2: 8.30/10 (PASS)
- Delivered: 10 levels, dual items, configurable presets, combo scoring, particles, audio, touch support

**Prompt 2** (21 min, 1 coding round):
> "画布变大2倍，增加一条电脑蛇会跟我抢吃的"

- Alignment Phase caught 6 spec deviations before coding started
- Round 1: 9.75/10 (PASS on first try)
- Delivered: 40x40 grid, AI snake with BFS pathfinding, competitive item eating

**Play it live**: https://maorenxin.github.io/snake-game/

The Alignment Phase made the difference — by having Generator and Evaluator agree on the plan before coding, the second prompt passed in one round at 9.75/10.

## Key Features

- **User-driven grading** — you pick the dimensions (Functionality, Code Quality, UX, Reliability, etc.) and weight distribution before work starts
- **Alignment Phase** — Generator and Evaluator negotiate implementation details before coding, catching spec gaps early
- **Adversarial evaluation** — Evaluator is tuned toward skepticism, scores must be earned with evidence
- **Structured handoffs** — all communication happens through versioned markdown files in `.harness/`
- **Git isolation** — each harness run gets its own branch (`harness/<slug>`)
- **Auto-cleanup** — `.harness/` is gitignored, team lifecycle is strictly managed

## File Structure

```
~/.claude/skills/harness/
└── SKILL.md                    # Skill definition (orchestrator instructions)

~/.agents/skills/harness/agents/
├── planner.md                  # Spec + criteria + contract
├── generator.md                # Iterative implementation
└── evaluator.md                # Testing + scoring + feedback
```

During a harness run, workspace files are created in your project:

```
$PROJECT/.harness/run-YYYY-MM-DD-<slug>/
├── state.json                  # Harness state tracking
├── spec.md                     # Product specification
├── criteria.md                 # Grading criteria (user-confirmed)
├── contract.md                 # Sprint contract
├── implementation-plan.md      # Generator's technical plan
├── alignment-review.md         # Evaluator's plan review
├── progress-round-N.md         # Generator progress reports
├── evaluation-round-N.md       # Evaluator scores + analysis
├── feedback-round-N.md         # Actionable feedback
└── summary.md                  # Final delivery summary
```

## Requirements

- [Claude Code](https://claude.com/claude-code) CLI
- Git (for branch isolation)

## License

MIT
