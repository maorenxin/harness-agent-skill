# Harness Agent Skill

[中文](#中文) | [English](#english)

---

## 中文

面向 [Claude Code](https://claude.com/claude-code) 的多智能体开发框架。灵感来自 Anthropic 的 harness 设计模式（GAN 式对抗迭代），将复杂软件任务分解为 **Planner → Generator ↔ Evaluator** 循环，迭代直到达到质量标准。

### 前置条件

Harness 依赖 Claude Code 的 Agent Team 功能。安装前需要在 `~/.claude/settings.json` 中开启：

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

> 没有专门的指令来开关此功能，只能通过 settings.json 配置。

### 快速安装

```bash
curl -sSL https://raw.githubusercontent.com/maorenxin/harness-agent-skill/master/install.sh | bash
```

手动安装：

```bash
# Skill 定义
mkdir -p ~/.claude/skills/harness
cp SKILL.md ~/.claude/skills/harness/

# Agent 定义
mkdir -p ~/.agents/skills/harness/agents
cp agents/*.md ~/.agents/skills/harness/agents/
```

### 使用方法

在 Claude Code 中输入：

```
/harness 你的需求描述
```

带参数：

```
/harness --max-rounds 8 --threshold 9.5 --pass-k 3 --dir ./my-project 需求描述
```

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `--max-rounds N` | 10 | 最大迭代轮数 |
| `--threshold N` | 9.5 | 通过分数阈值 (1-10) |
| `--pass-k N` | 3 | 连续达标轮数（pass^k） |
| `--dir PATH` | `.` | 工作目录 |

#### 模糊描述 vs 详细计划

`/harness` 接受两种输入，Planner 会自动识别并切换模式：

- **模糊描述**（1-4 句话）— Planner 会浏览项目、扩展成完整规格，并询问你想要的评分维度和权重分布。
- **详细计划**（带编号步骤 / 文件级决策 / 明确验收标准，或粘贴自 Plan Mode 的计划）— Planner 直接把你的计划翻译成 spec / criteria / contract 文档，使用合理的默认评分维度，不再打断询问。

这样就不需要单独的 `/harness-lite` 入口了。

### 工作原理

```
用户需求（模糊描述 或 详细计划）
    │
    ▼
┌─────────┐    spec.md
│ Planner │───▶ criteria.md   ◀── 模糊模式下询问评分维度；详细模式直接翻译
│ (bypass)│    contract.md       (仅写文档，不写代码)
└─────────┘
    │
    ▼
┌───────────┐  implementation-plan.md   ┌───────────┐
│ Generator │◀─────────────────────────▶│ Evaluator │  对齐阶段
│ (bypass)  │  alignment-review.md      │ (bypass)  │  (编码前协商)
└───────────┘                           └───────────┘
    │                                        │
    ▼                                        ▼
┌───────────┐  progress-round-N.md      ┌───────────┐
│ Generator │─────────────────────────▶ │ Evaluator │  迭代阶段
│  (编码)   │◀─────────────────────────│  (评分)   │  (循环直到 pass^k)
└───────────┘  feedback-round-N.md      └───────────┘
```

1. **Planner** 将需求翻译成规格说明、评分标准和冲刺合约。模糊描述走扩展流程，详细计划直接翻译。Planner 只写文档，不碰源码
2. **用户确认** 评分维度和权重分配（仅模糊模式；详细计划使用默认权重，不打断）
3. **对齐阶段** — Generator 编写实施计划，Evaluator 审查。双方协商直到对齐，避免无效编码
4. **迭代阶段** — Generator 编码 → Evaluator 按标准评分 → 未达标则给出具体反馈，Generator 重试。采用 pass^k 模型：需连续 k 轮达标才算通过
5. **交付** — 连续达标后，最终清理和总结

> 所有 Teammate（Planner/Generator/Evaluator）都以 `bypassPermissions` 模式 spawn，避免每次 Read/Bash 都要 leader 审批。

### 实际效果

用两条 prompt 从零构建了一个完整的浏览器贪吃蛇游戏，总计约 50 分钟：

**Prompt 1**（28 分钟，2 轮编码）：
> "做一个贪吃蛇游戏，需要有过关系统，吃item1变长，吃item2变短，道具可配置（内置预设+随机+AI生成）"

- Round 1: 6.95/10 (FAIL) → Round 2: 8.30/10 (PASS)
- 交付：10 个关卡、双道具、可配置预设、连击计分、粒子效果、音效、触屏支持

**Prompt 2**（21 分钟，1 轮编码）：
> "画布变大2倍，增加一条电脑蛇会跟我抢吃的"

- 对齐阶段在编码前捕获了 6 处规格偏差
- Round 1: 9.75/10（首轮通过）
- 交付：40x40 网格、BFS 寻路 AI 蛇、竞争性道具争夺

**在线试玩**：https://maorenxin.github.io/snake-game/

对齐阶段是关键 — Generator 和 Evaluator 在编码前达成一致，第二条 prompt 首轮就以 9.75/10 通过。

### 核心特性

- **单入口，双模式** — `/harness` 同时接受模糊描述和详细计划，Planner 自动识别切换
- **职责清晰** — Planner 只写规格文档，不碰源码；Generator 才是唯一的编码者
- **无审批摩擦** — 所有 Teammate 以 `bypassPermissions` 模式 spawn，不会把每次工具调用都退回给 leader
- **用户驱动评分** — 模糊模式下由你选择评分维度和权重；详细模式使用合理默认值
- **对齐阶段** — Generator 和 Evaluator 在编码前协商实施细节，提前发现规格缺口
- **对抗式评估** — Evaluator 倾向怀疑，分数必须用证据赢得
- **结构化交接** — 所有通信通过 `.harness/` 中的版本化 markdown 文件进行
- **Git 隔离** — 每次 harness 运行使用独立分支 (`harness/<slug>`)
- **自动清理** — `.harness/` 被 gitignore，团队生命周期严格管理

### 文件结构

```
~/.claude/skills/harness/
└── SKILL.md                    # Skill 定义（编排器指令）

~/.agents/skills/harness/agents/
├── planner.md                  # 规格 + 标准 + 合约
├── generator.md                # 迭代实现
└── evaluator.md                # 测试 + 评分 + 反馈
```

运行期间在项目中创建的工作文件：

```
$PROJECT/.harness/run-YYYY-MM-DD-<slug>/
├── state.json                  # Harness 状态追踪
├── spec.md                     # 产品规格说明
├── criteria.md                 # 评分标准（用户确认）
├── contract.md                 # 冲刺合约
├── implementation-plan.md      # Generator 技术方案
├── alignment-review.md         # Evaluator 方案审查
├── progress-round-N.md         # Generator 进度报告
├── evaluation-round-N.md       # Evaluator 评分 + 分析
├── feedback-round-N.md         # 可执行反馈
└── summary.md                  # 最终交付总结
```

### 环境要求

- [Claude Code](https://claude.com/claude-code) CLI
- Git（用于分支隔离）
- Agent Team 模式已开启（见[前置条件](#前置条件)）

### 许可证

MIT

---

## English

A multi-agent development harness for [Claude Code](https://claude.com/claude-code). Inspired by Anthropic's harness design pattern (GAN-style adversarial iteration), it decomposes complex software tasks into a **Planner → Generator ↔ Evaluator** loop that iterates until quality standards are met.

### Prerequisites

Harness relies on Claude Code's Agent Team feature. Enable it in `~/.claude/settings.json` before installing:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

> There is no dedicated command to toggle this — it can only be configured via settings.json.

### Quick Install

```bash
curl -sSL https://raw.githubusercontent.com/maorenxin/harness-agent-skill/master/install.sh | bash
```

Manual install:

```bash
# Skill definition
mkdir -p ~/.claude/skills/harness
cp SKILL.md ~/.claude/skills/harness/

# Agent definitions
mkdir -p ~/.agents/skills/harness/agents
cp agents/*.md ~/.agents/skills/harness/agents/
```

### Usage

In Claude Code, type:

```
/harness your task description
```

With options:

```
/harness --max-rounds 8 --threshold 9.5 --pass-k 3 --dir ./my-project task description
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--max-rounds N` | 10 | Maximum iteration rounds |
| `--threshold N` | 9.5 | Score threshold (1-10) to pass |
| `--pass-k N` | 3 | Consecutive rounds above threshold (pass^k) |
| `--dir PATH` | `.` | Working directory |

#### Vague description vs detailed plan

`/harness` accepts both. The Planner auto-detects which one you supplied:

- **Vague description** (1-4 sentences) — Planner explores the project, expands it into a full spec, and asks you to pick grading dimensions + weights.
- **Detailed plan** (numbered steps / file-level decisions / explicit acceptance criteria, or a plan pasted from Plan Mode) — Planner translates your plan directly into spec / criteria / contract using sensible default weights. No interrupting dialog.

No separate `/harness-lite` entry point is needed.

### How It Works

```
User Prompt (vague description OR detailed plan)
    │
    ▼
┌─────────┐    spec.md
│ Planner │───▶ criteria.md   ◀── Vague mode asks for dimensions;
│ (bypass)│    contract.md       detailed mode translates directly.
└─────────┘                      (Docs only, never code.)
    │
    ▼
┌───────────┐  implementation-plan.md   ┌───────────┐
│ Generator │◀─────────────────────────▶│ Evaluator │  Alignment Phase
│ (bypass)  │  alignment-review.md      │ (bypass)  │  (negotiate before coding)
└───────────┘                           └───────────┘
    │                                        │
    ▼                                        ▼
┌───────────┐  progress-round-N.md      ┌───────────┐
│ Generator │─────────────────────────▶ │ Evaluator │  Iteration Phase
│  (code)   │◀─────────────────────────│  (score)  │  (loop until pass^k)
└───────────┘  feedback-round-N.md      └───────────┘
```

1. **Planner** translates your input into spec / criteria / contract. Vague descriptions get expanded via project exploration; detailed plans are translated directly. Planner only writes docs, never source code.
2. **User confirms** grading dimensions and weights (vague mode only; detailed mode uses sensible defaults without interruption).
3. **Alignment Phase** — Generator writes an implementation plan, Evaluator reviews it. They negotiate until aligned. This prevents wasted coding effort.
4. **Iteration Phase** — Generator codes → Evaluator scores against criteria → if below threshold, Generator gets specific feedback and tries again. Uses pass^k model: k consecutive rounds above threshold required to pass.
5. **Delivery** — once pass^k is achieved, final cleanup and summary.

> All teammates (Planner / Generator / Evaluator) are spawned with `bypassPermissions` mode so that every Read/Bash call doesn't bounce back to the team leader for approval.

### Real-World Results

We built a complete browser-based snake game from scratch using two prompts, ~50 minutes total:

**Prompt 1** (28 min, 2 coding rounds):
> "Build a snake game with a level system, item1 makes snake longer, item2 makes it shorter, configurable items (built-in presets + random + AI-generated)"

- Round 1: 6.95/10 (FAIL) → Round 2: 8.30/10 (PASS)
- Delivered: 10 levels, dual items, configurable presets, combo scoring, particles, audio, touch support

**Prompt 2** (21 min, 1 coding round):
> "Double the canvas size, add a computer snake that competes for items"

- Alignment Phase caught 6 spec deviations before coding started
- Round 1: 9.75/10 (PASS on first try)
- Delivered: 40x40 grid, AI snake with BFS pathfinding, competitive item eating

**Play it live**: https://maorenxin.github.io/snake-game/

The Alignment Phase made the difference — by having Generator and Evaluator agree on the plan before coding, the second prompt passed in one round at 9.75/10.

### Key Features

- **One entry, two modes** — `/harness` handles both vague descriptions and detailed plans; the Planner auto-detects and adapts
- **Clean separation of duties** — Planner only writes spec documents, never source code; Generator is the sole coder
- **No approval friction** — all teammates spawn with `bypassPermissions` mode, so tool calls don't bounce back to the leader
- **User-driven grading** — in vague mode, you pick the dimensions and weights; in detailed mode, sensible defaults are used
- **Alignment Phase** — Generator and Evaluator negotiate implementation details before coding, catching spec gaps early
- **Adversarial evaluation** — Evaluator is tuned toward skepticism, scores must be earned with evidence
- **Structured handoffs** — all communication happens through versioned markdown files in `.harness/`
- **Git isolation** — each harness run gets its own branch (`harness/<slug>`)
- **Auto-cleanup** — `.harness/` is gitignored, team lifecycle is strictly managed

### File Structure

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

### Requirements

- [Claude Code](https://claude.com/claude-code) CLI
- Git (for branch isolation)
- Agent Team mode enabled (see [Prerequisites](#prerequisites))

### License

MIT
