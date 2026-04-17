#!/bin/bash
# Harness Agent Skill - One-line installer for Claude Code
# Usage: curl -sSL https://raw.githubusercontent.com/maorenxin/harness-agent-skill/master/install.sh | bash

set -e

SKILL_DIR="$HOME/.claude/skills/harness"
SKILL_LITE_DIR="$HOME/.claude/skills/harness-lite"
AGENT_DIR="$HOME/.agents/skills/harness/agents"
REPO_URL="https://raw.githubusercontent.com/maorenxin/harness-agent-skill/master"

echo "Installing Harness Agent Skill for Claude Code..."

mkdir -p "$SKILL_DIR" "$AGENT_DIR"

curl -sSL "$REPO_URL/SKILL.md" -o "$SKILL_DIR/SKILL.md"
curl -sSL "$REPO_URL/agents/planner.md" -o "$AGENT_DIR/planner.md"
curl -sSL "$REPO_URL/agents/generator.md" -o "$AGENT_DIR/generator.md"
curl -sSL "$REPO_URL/agents/evaluator.md" -o "$AGENT_DIR/evaluator.md"

# Clean up legacy harness-lite install from earlier versions (now unified into /harness).
if [ -d "$SKILL_LITE_DIR" ]; then
  echo "Removing legacy $SKILL_LITE_DIR (harness-lite is now unified into /harness)"
  rm -rf "$SKILL_LITE_DIR"
fi

echo ""
echo "Installed successfully!"
echo "  Skill:  $SKILL_DIR/SKILL.md"
echo "  Agents: $AGENT_DIR/*.md"
echo ""
echo "Usage:"
echo "  /harness <task>   Full harness (Planner + Generator + Evaluator, pass^k)"
echo "                    Works for both vague descriptions and detailed plans."
