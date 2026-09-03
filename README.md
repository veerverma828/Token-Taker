# Token Taker — Claude Usage Widget

A tiny Windows app for watching your [Claude Code](https://claude.com/claude-code) usage limits without leaving your desktop — a floating always-on-top widget, an optional rich terminal statusline, and an AI-powered self-fix tab, all in one installer/manager.

## Get it

Download **`Claude Usage Widget.exe`** from this repo and run it. That's the whole install — no dependencies to set up yourself (Claude Code CLI just needs to already be installed and logged in for real data to show up).

## What it does

### Floating widget
A small, draggable, resizable, always-on-top window showing your 5-hour and 7-day usage as color-coded progress bars (green → orange → red as you approach the limit), with time-to-reset. Two layouts: one-line or stacked. Remembers its position and size, can start with Windows, and lives in the system tray of your attention without ever stealing focus.

### Statusline only
Installs a full-featured Claude Code terminal statusline instead of (or alongside) the floating widget — model name, effort level, git branch (with a dirty marker), colored 5h/7d usage bars with reset times, current folder, and context-window usage, all on one line in your prompt. If you already have a custom statusline configured, the installer wraps it instead of overwriting it, so your existing setup keeps working with usage data layered on top.

### AI Fix
Something broken? Describe the problem in plain English and Claude Code fixes it directly — reading and editing this app's own files under `~/.claude` to resolve the issue, with the fix streamed live into the window. No terminal, no manual editing, nothing to approve step by step. It's restricted to file read/edit tools only (no arbitrary shell commands) and asks for a one-time go-ahead before its first unattended run each session. Requires Claude Code CLI to already be installed and logged in — the app tells you plainly if it isn't.

## How it's built

This is one self-contained PowerShell + WPF application, compiled to a single `.exe` with [ps2exe](https://github.com/MScholtes/PS2EXE). The installer detects whether it's already set up and shows either a first-run **Setup** screen or a full **Manager** screen (start/stop, autostart toggle, layout switch, uninstall) — same binary, both roles.

### Files in this repo

| File | What it is |
|---|---|
| `Claude Usage Widget.exe` | The compiled app — this is what you actually run. |
| `ClaudeUsageWidgetSetup-source.ps1` | Source for the installer/manager GUI (compiles into the exe above). |
| `usage-widget.ps1` | The floating widget itself, written to `~/.claude/` on install. |
| `statusline-command.ps1` | The full terminal statusline script. |
| `usage-widget-icon.ico` | App/taskbar icon. |

### Rebuilding the exe yourself

```powershell
Install-Module ps2exe -Scope CurrentUser
Import-Module ps2exe
Invoke-ps2exe -inputFile .\ClaudeUsageWidgetSetup-source.ps1 -outputFile ".\Claude Usage Widget.exe" -noConsole -icon .\usage-widget-icon.ico -title "Claude Usage Widget"
```

## Uninstalling

Open the app once it's installed (Manager screen) and click **Uninstall widget** — it stops the widget, removes its statusline hook (only ever touching hooks it can prove it created), and deletes every file it wrote. The app itself is left behind so you can reinstall later.
