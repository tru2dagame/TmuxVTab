#!/usr/bin/env bash
# Fast, fail-open adapter for Claude Code and Codex lifecycle hooks.
# The TmuxVTab executable normalizes stdin and writes one bounded event to the
# private Unix socket owned by the running TmuxVTab app.

AGENT="${1:-auto}"
EVENT="${2:-}"
PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd -P)"
HOOK_VERSION_FILE="$PLUGIN_DIR/hooks/VERSION"
HOOK_VERSION="unknown"
if [[ -f "$HOOK_VERSION_FILE" ]]; then
  HOOK_VERSION="$(tr -d '[:space:]' < "$HOOK_VERSION_FILE")"
fi

if [[ "$AGENT" == "--version" || "$AGENT" == "version" ]]; then
  printf '%s\n' "$HOOK_VERSION"
  exit 0
fi

export TMUXVTAB_HOOK_VERSION="$HOOK_VERSION"
TMUXVTAB_TPM_DIR="$HOME/.tmux/plugins/TmuxVTab"
TMUXVTAB_TPM_DIR_LOWER="$HOME/.tmux/plugins/tmuxvtab"
PUBLISHED_BIN="$HOME/Library/Application Support/TmuxVTab/TmuxVTab-hook"

if [[ -n "${TMUXVTAB_BINARY:-}" && -x "$TMUXVTAB_BINARY" ]]; then
  BIN="$TMUXVTAB_BINARY"
elif [[ -x "$PUBLISHED_BIN" ]]; then
  BIN="$PUBLISHED_BIN"
elif [[ -x "$PLUGIN_DIR/.build/debug/TmuxVTab" ]]; then
  BIN="$PLUGIN_DIR/.build/debug/TmuxVTab"
elif [[ -x "$PLUGIN_DIR/.build/release/TmuxVTab" ]]; then
  BIN="$PLUGIN_DIR/.build/release/TmuxVTab"
elif [[ -x "$TMUXVTAB_TPM_DIR/.build/release/TmuxVTab" ]]; then
  BIN="$TMUXVTAB_TPM_DIR/.build/release/TmuxVTab"
elif [[ -x "$TMUXVTAB_TPM_DIR_LOWER/.build/release/TmuxVTab" ]]; then
  BIN="$TMUXVTAB_TPM_DIR_LOWER/.build/release/TmuxVTab"
elif command -v TmuxVTab >/dev/null 2>&1; then
  BIN="$(command -v TmuxVTab)"
elif command -v tmuxvtab >/dev/null 2>&1; then
  exec "$(command -v tmuxvtab)" hook "$AGENT" "$EVENT"
else
  # Current Codex Stop/SubagentStop hooks expect JSON even for a no-op.
  case "$EVENT" in
    stop|subagent-stop) printf '{}\n' ;;
  esac
  exit 0
fi

exec "$BIN" hook "$AGENT" "$EVENT"
