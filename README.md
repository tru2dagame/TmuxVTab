# TmuxVTab

A vertical tab bar for tmux, built as a lightweight macOS companion app for [Ghostty](https://ghostty.org).

![TmuxVTab Screenshot](assets/screenshot.png)

## Features

- **Floating sidebar** that docks to Ghostty's left or right edge
- **Auto show/hide** -- appears when Ghostty launches, hides when it quits
- **Real-time tracking** -- follows Ghostty's window position every 300ms
- **Agent detection** -- identifies Claude Code, Codex, Aider, and Copilot via process tree walking
- **No dock icon, no menubar icon** -- pure background agent app
- **Tmux commands** -- control everything from tmux, no keybindings needed

## Install

### TPM (Tmux Plugin Manager)

Add to your `~/.tmux.conf` or `~/.tmux.conf.local`:

```bash
set -g @plugin 'tru2dagame/TmuxVTab'
```

Then press `prefix + I` to install. TmuxVTab will automatically download the pre-built binary from GitHub Releases and start.

### Manual

```bash
git clone https://github.com/tru2dagame/TmuxVTab.git ~/.tmux/plugins/TmuxVTab
~/.tmux/plugins/TmuxVTab/bin/tmuxvtab start
```

### Build from Source

Requires macOS 15+ and Swift 6.0+.

```bash
git clone https://github.com/tru2dagame/TmuxVTab.git
cd TmuxVTab
swift build -c release
bin/tmuxvtab start    # starts using locally built binary
```

## Optional: Live agent state via Claude Code hooks

Stream per-turn agent state (status, prompt, permission mode, subagents, wait
reason) into the sidebar in real time. The hook handler binary comes from
[tru2dagame/tmux-agent-sidebar](https://github.com/tru2dagame/tmux-agent-sidebar)
— a stability fork of [hiroppy/tmux-agent-sidebar](https://github.com/hiroppy/tmux-agent-sidebar)
that pulls binaries from its own release pipeline. TmuxVTab ships its own
Claude Code plugin manifest that delegates to it.

### 1. Install the hook handler binary

Add to `~/.tmux.conf`:

```bash
set -g @plugin 'tru2dagame/tmux-agent-sidebar'
```

Press `prefix + I` to install. The binary lands at
`~/.tmux/plugins/tmux-agent-sidebar/bin/tmux-agent-sidebar`.

### 2. Register the TmuxVTab Claude Code plugin

In any running Claude Code session:

```
/plugin marketplace add ~/.tmux/plugins/TmuxVTab
/plugin install tmuxvtab@tru2dagame
/reload-plugins
```

This registers 16 hook events (`SessionStart`, `UserPromptSubmit`, `Stop`,
`Notification`, `SubagentStart`, …) that write `@pane_*` tmux options. TmuxVTab
reads those options on every poll.

Verify it's working — send any prompt in a Claude pane, then:

```bash
tmux show-options -p -t <pane> @pane_agent     # → claude
tmux show-options -p -t <pane> @pane_status    # → running / idle
tmux show-options -p -t <pane> @pane_prompt    # → your last prompt
```

## Usage

All commands are available as tmux command aliases (no keybindings needed):

| Command                    | Shell             | tmux command mode (`prefix :`) |
|----------------------------|-------------------|--------------------------------|
| **Toggle** (restart/start) | `tmux vtab`       | `vtab`                         |
| Start                      | `tmux vtab-start` | `vtab-start`                   |
| Stop                       | `tmux vtab-stop`  | `vtab-stop`                    |
| Dock left                  | `tmux vtab-left`  | `vtab-left`                    |
| Dock right                 | `tmux vtab-right` | `vtab-right`                   |
| Always on top              | `tmux vtab-pin`   | `vtab-pin`                     |
| Follow Ghostty focus       | `tmux vtab-unpin` | `vtab-unpin`                   |

Settings (`left`/`right`, `pin`/`unpin`) are persisted and take effect immediately without restarting.

Font size is adjustable via right-click context menu on the panel.

## Update

### TPM

```bash
# Press prefix + U to update all plugins, then restart:
tmux vtab
```

### Manual

```bash
cd ~/.tmux/plugins/TmuxVTab
git pull
rm -f .build/release/TmuxVTab    # remove old binary
tmux vtab                        # downloads new release binary and starts
```

## Requirements

- macOS 15 (Sequoia) or later
- [Ghostty](https://ghostty.org) terminal
- tmux

## How It Works

TmuxVTab is a native macOS app (AppKit + SwiftUI) that runs as a background agent:

1. Monitors Ghostty via `NSWorkspace` notifications and `CGWindowListCopyWindowInfo` polling
2. Polls tmux sessions/windows every 3 seconds via CLI
3. Detects coding agents by walking the process tree from each pane's PID
4. Renders a floating `NSPanel` that tracks Ghostty's window frame

## Thanks

The hook handler binary and the `@pane_*` data model come from
[hiroppy/tmux-agent-sidebar](https://github.com/hiroppy/tmux-agent-sidebar) —
TmuxVTab's live agent state is a thin macOS UI on top of that work. We mirror
that codebase at [tru2dagame/tmux-agent-sidebar](https://github.com/tru2dagame/tmux-agent-sidebar)
so TmuxVTab installs stay reproducible.

## License

MIT
