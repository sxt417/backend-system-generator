#!/usr/bin/env bash

set -euo pipefail

SKILL_NAME="backend-system-generator"
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_SKILLS_ROOT="${CODEX_SKILLS_DIR:-${CODEX_HOME:-$HOME/.codex}/skills}"
CLAUDE_SKILLS_ROOT="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
FORCE=0

usage() {
  cat <<'USAGE'
Usage:
  ./install.sh codex [--force]
  ./install.sh claude [--force]
  ./install.sh all [--force]
  ./install.sh claude-project <project-directory> [--force]

Environment overrides for custom locations or testing:
  CODEX_SKILLS_DIR=/custom/codex/skills
  CLAUDE_SKILLS_DIR=/custom/claude/skills

When --force is used, the existing installation is moved to a timestamped
backup before the new version is installed.
USAGE
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

MODE="$1"
shift
PROJECT_DIR=""

if [[ "$MODE" == "claude-project" ]]; then
  if [[ $# -lt 1 || "$1" == "--force" ]]; then
    echo "Error: claude-project requires a project directory." >&2
    usage
    exit 2
  fi
  PROJECT_DIR="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

case "$MODE" in
  codex|claude|all|claude-project)
    ;;
  *)
    echo "Error: mode must be codex, claude, all, or claude-project." >&2
    usage
    exit 2
    ;;
esac

if [[ "$MODE" == "claude-project" && ! -d "$PROJECT_DIR" ]]; then
  echo "Error: project directory does not exist: $PROJECT_DIR" >&2
  exit 2
fi

CODEX_TARGET="$CODEX_SKILLS_ROOT/$SKILL_NAME"
CLAUDE_TARGET="$CLAUDE_SKILLS_ROOT/$SKILL_NAME"

if [[ "$MODE" == "claude-project" ]]; then
  PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
  CLAUDE_PROJECT_TARGET="$PROJECT_DIR/.claude/skills/$SKILL_NAME"
fi

preflight() {
  local target="$1"
  if [[ -e "$target" || -L "$target" ]]; then
    if [[ "$FORCE" -ne 1 ]]; then
      echo "Error: installation already exists: $target" >&2
      echo "Re-run with --force to replace it after creating a backup." >&2
      exit 3
    fi
  fi
}

install_to() {
  local target="$1"
  local client="$2"
  local parent
  local stage
  local backup

  parent="$(dirname "$target")"
  mkdir -p "$parent"

  if [[ -e "$target" || -L "$target" ]]; then
    backup="${target}.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$target" "$backup"
    echo "Backed up existing installation to: $backup"
  fi

  stage="$(mktemp -d "$parent/.${SKILL_NAME}.install.XXXXXX")"
  cp "$SOURCE_DIR/SKILL.md" "$stage/SKILL.md"
  cp -R "$SOURCE_DIR/assets" "$stage/assets"
  cp -R "$SOURCE_DIR/references" "$stage/references"

  if [[ "$client" == "codex" ]]; then
    cp -R "$SOURCE_DIR/agents" "$stage/agents"
  fi

  mv "$stage" "$target"
  echo "Installed $SKILL_NAME for $client: $target"
}

case "$MODE" in
  codex)
    preflight "$CODEX_TARGET"
    install_to "$CODEX_TARGET" "codex"
    ;;
  claude)
    preflight "$CLAUDE_TARGET"
    install_to "$CLAUDE_TARGET" "claude"
    ;;
  all)
    preflight "$CODEX_TARGET"
    preflight "$CLAUDE_TARGET"
    install_to "$CODEX_TARGET" "codex"
    install_to "$CLAUDE_TARGET" "claude"
    ;;
  claude-project)
    preflight "$CLAUDE_PROJECT_TARGET"
    install_to "$CLAUDE_PROJECT_TARGET" "claude-project"
    ;;
esac

echo
echo "Verification:"
if [[ "$MODE" == "codex" || "$MODE" == "all" ]]; then
  echo "  Codex: start a new task and invoke \$backend-system-generator."
fi
if [[ "$MODE" == "claude" || "$MODE" == "all" || "$MODE" == "claude-project" ]]; then
  echo "  Claude Code: run /skills, then invoke /backend-system-generator."
  echo "  Restart Claude Code only if its top-level skills directory was created after the session started."
fi
