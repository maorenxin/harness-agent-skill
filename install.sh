#!/bin/bash
# Harness Agent Skill - One-line installer for Claude Code
# Usage: curl -sSL https://raw.githubusercontent.com/maorenxin/harness-agent-skill/master/install.sh | bash

set -e

SKILL_DIR="$HOME/.claude/skills/harness"
SKILL_LITE_DIR="$HOME/.claude/skills/harness-lite"
AGENT_DIR="$HOME/.agents/skills/harness/agents"
REPO_URL="https://raw.githubusercontent.com/maorenxin/harness-agent-skill/master"

echo "Installing Harness Agent Skill for Claude Code..."

mkdir -p "$SKILL_DIR" "$SKILL_LITE_DIR" "$AGENT_DIR"

curl -sSL "$REPO_URL/SKILL.md" -o "$SKILL_DIR/SKILL.md"
curl -sSL "$REPO_URL/SKILL-LITE.md" -o "$SKILL_LITE_DIR/SKILL.md"
curl -sSL "$REPO_URL/agents/planner.md" -o "$AGENT_DIR/planner.md"
curl -sSL "$REPO_URL/agents/generator.md" -o "$AGENT_DIR/generator.md"
curl -sSL "$REPO_URL/agents/evaluator.md" -o "$AGENT_DIR/evaluator.md"

echo ""
echo "Installed successfully!"
echo "  Skills: $SKILL_DIR/SKILL.md"
echo "          $SKILL_LITE_DIR/SKILL.md"
echo "  Agents: $AGENT_DIR/*.md"
echo ""
echo "Usage:"
echo "  /harness <task>       Full harness (Planner + Generator + Evaluator, pass^k)"
echo "  /harness-lite <task>  Lite harness (Generator + Evaluator, single-pass)"
