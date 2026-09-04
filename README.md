# Token Taker — Claude Usage Widget

A tiny Windows app for watching your [Claude Code](https://claude.com/claude-code) usage limits without leaving your desktop — a floating always-on-top widget, an optional rich terminal statusline, and an AI-powered self-fix tab, all in one installer/manager.

## Get it

Download **[`ClaudeUsageWidgetSetup.ps1`](./ClaudeUsageWidgetSetup.ps1)**, then right-click it and choose **"Run with PowerShell"** (built into Windows — no setup needed). That's the whole install; Claude Code CLI just needs to already be installed and logged in for real data to show up.

The first run copies itself into `~/.claude/` and drops a desktop shortcut (with its own icon) so future launches are a normal double-click.

> **Why a `.ps1` and not an `.exe`?** An earlier version shipped a compiled `.exe` (via [ps2exe](https://github.com/MScholtes/PS2EXE)), and Windows Defender flagged it as `Trojan:Win32/Wacatac.B!ml` for a real user — a well-known false positive for unsigned compiled wrappers around a script, not an actual detection of anything malicious. Plain PowerShell doesn't trip that heuristic, and the source is fully readable before you run it, so that's what this now ships as.

## What it does

### Floating widget
A small, draggable, resizable, always-on-top window showing your 5-hour and 7-day usage as color-coded progress bars (green → orange → red as you approach the limit), with time-to-reset. Two layouts: one-line or stacked. Remembers its position and size, can start with Windows, and never steals focus.

### Statusline only
Installs a full-featured Claude Code terminal statusline instead of (or alongside) the floating widget — model name, effort level, git branch (with a dirty marker), colored 5h/7d usage bars with reset times, current folder, and context-window usage, all on one line in your prompt. If you already have a statusline configured, it's saved before being replaced and restored exactly if you remove this one later. If the exact same statusline is already active via a different path (e.g. the floating widget's own hook), the tab recognizes that instead of claiming nothing is installed.

### AI Fix
Something broken? Describe the problem in plain English and Claude Code fixes it directly — reading and editing this app's own files under `~/.claude` to resolve the issue, with the fix streamed live into the window. No terminal, no manual editing, nothing to approve step by step. It's restricted to file read/edit tools only (no arbitrary shell commands) and asks for a one-time go-ahead before its first unattended run each session. Requires Claude Code CLI to already be installed and logged in — the app tells you plainly if it isn't.

## How it's built

One self-contained PowerShell + WPF script — no compilation, no external dependencies. It detects whether it's already set up and shows either a first-run **Setup** screen or a full **Manager** screen (start/stop, autostart toggle, layout switch, uninstall) — same file, both roles. The app icon is embedded as base64 inside the script itself and written out to `~/.claude/usage-widget-icon.ico` on first run, so the single `.ps1` file is everything you need to send someone.

### Files in this repo

| File | What it is |
|---|---|
| `ClaudeUsageWidgetSetup.ps1` | The whole app — this is what you actually run. |
| `usage-widget.ps1` | Reference copy of the floating widget script (this is what actually gets written to `~/.claude/` on install — embedded inside the setup script above). |
| `statusline-command.ps1` | Reference copy of the full terminal statusline script (same deal — embedded, written out on install). |
| `usage-widget-icon.ico` | The app/taskbar icon, for reference (also embedded as base64 inside the setup script). |

## Uninstalling

Open the app once it's installed (Manager screen) and click **Uninstall widget** — it stops the widget, removes its statusline hook (only ever touching hooks it can prove it created), and deletes every file it wrote. The installed copy of the app itself is left behind so you can reinstall later.
