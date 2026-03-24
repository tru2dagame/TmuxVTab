#!/usr/bin/env bash
# TPM plugin entry point for TmuxVTab
# Usage in tmux.conf:
#   set -g @plugin 'tru2dagame/tmuxvtab'

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$CURRENT_DIR/bin/tmuxvtab"

# Start TmuxVTab (builds if needed)
"$WRAPPER" start

# Register tmux command aliases
tmux set -s 'command-alias[100]' vtab="run-shell '$WRAPPER restart'"
tmux set -s 'command-alias[101]' vtab-start="run-shell '$WRAPPER start'"
tmux set -s 'command-alias[102]' vtab-stop="run-shell '$WRAPPER stop'"
tmux set -s 'command-alias[103]' vtab-left="run-shell '$WRAPPER left'"
tmux set -s 'command-alias[104]' vtab-right="run-shell '$WRAPPER right'"
tmux set -s 'command-alias[105]' vtab-pin="run-shell '$WRAPPER pin'"
tmux set -s 'command-alias[106]' vtab-unpin="run-shell '$WRAPPER unpin'"

# Auto-stop when tmux server exits
tmux set-hook -g session-closed "run-shell 'if ! tmux list-sessions 2>/dev/null | grep -q .; then $WRAPPER stop; fi'"
