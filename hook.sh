#!/usr/bin/env bash
# tmuxvtab Claude Code plugin hook shim.
#
# Each hook event in hooks/hooks.json calls this script. We delegate to
# the `tmux-agent-sidebar` binary (hiroppy/tmux-agent-sidebar), which is
# the implementation that writes the @pane_* tmux options TmuxVTab.app
# reads on its 3-second poll. Keeping the binary as a separate concern
# lets us swap it for a tmuxvtab-native helper later without touching
# anyone's Claude Code settings.
#
# Silent exit 0 when the binary cannot be found, so Claude sessions
# never surface a hook failure on machines without the sidebar binary
# installed.

PLUGIN_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# TPM-installed location for tmux-agent-sidebar — the project that ships
# the hook handler binary today.
SIDEBAR_TPM_DIR="$HOME/.tmux/plugins/tmux-agent-sidebar"

if [ -x "$PLUGIN_DIR/bin/tmux-agent-sidebar" ]; then
  BIN="$PLUGIN_DIR/bin/tmux-agent-sidebar"
elif [ -x "$SIDEBAR_TPM_DIR/bin/tmux-agent-sidebar" ]; then
  BIN="$SIDEBAR_TPM_DIR/bin/tmux-agent-sidebar"
elif [ -x "$SIDEBAR_TPM_DIR/target/release/tmux-agent-sidebar" ]; then
  BIN="$SIDEBAR_TPM_DIR/target/release/tmux-agent-sidebar"
elif command -v tmux-agent-sidebar &>/dev/null; then
  BIN="tmux-agent-sidebar"
else
  exit 0
fi
exec "$BIN" hook "$@"
