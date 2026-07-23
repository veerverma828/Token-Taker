# Token Taker

A floating widget that shows your Claude Code 5-hour and 7-day usage limits, always sitting above the taskbar — no tray icon, no console window, no dependencies.

![status](https://img.shields.io/badge/platform-Windows%2010%2F11-blue) ![deps](https://img.shields.io/badge/dependencies-zero-brightgreen)

## What it looks like

A slim glass pill in the bottom-right corner:

```
[5H ▓▓░░░░░░░░ 8%  4h12m] │ [7D ▓▓▓▓▓▓▓░░░ 75%  6d3h]
```

- Two color-coded bars (green → yellow → red as usage climbs)
- Live percentage and time-until-reset for both limits, always visible — no hover, no tooltip needed
- Auto-sizes to fit its content exactly
- Drag anywhere with left-click; right-click to exit

## How it works

Claude Code's statusline already receives your rate-limit data (`five_hour` / `seven_day` usage and reset timestamps) on every turn. Your `~/.claude/statusline.ps1` caches that into `~/.claude/.statusline_ratelimit_cache.json`. Token Taker just reads that same file every 15 seconds and draws it — no network calls, no API keys, nothing beyond what Claude Code already fetched for itself.

Built entirely on what ships with Windows: PowerShell + WinForms + GDI+ (`System.Drawing`). No installer runtime, no NuGet packages, no PowerShell modules.

## Requirements

- Windows 10 or 11
- Claude Code CLI installed, with `~/.claude/statusline.ps1` set as your active statusline (it's what populates the cache file this widget reads)

## Install

1. Double-click **`Setup.bat`**
2. Choose **[1] Install**

That's it. The installer will:
- Verify the required files and your `~/.claude` folder exist
- Copy `ratelimit_bar.ps1` + `ratelimit_bar.vbs` into `~/.claude/`
- Register it to start automatically on every login
- Launch it immediately
- Print a summary confirming install path, autostart status, and controls

If you haven't used Claude Code recently, the bars may start at 0% until the statusline reports fresh data.

## Uninstall

Run **`Setup.bat`** → **[2] Uninstall**. Confirms with `Y`, then:
- Stops the running widget
- Removes it from Windows startup
- Deletes the installed files from `~/.claude/`

Your usage cache file is left untouched — it's shared with your statusline and other tools may depend on it.

## Check status

**`Setup.bat`** → **[3] Status** — reports whether it's installed, whether autostart is enabled, and whether it's currently running.

## Using it day-to-day

| Action | How |
|---|---|
| Move it | Left-click and drag |
| Close it | Right-click → Exit |
| See exact reset time | Already inline — no need to hover |
| Restart after closing | Re-run `Setup.bat` → Install (safe to re-run any time) |

## Folder contents

| File | Purpose |
|---|---|
| `Setup.bat` | Entry point — double-click to install/uninstall/check status |
| `setup.ps1` | Installer logic (called by `Setup.bat`) |
| `ratelimit_bar.ps1` | The widget itself |
| `ratelimit_bar.vbs` | Silent launcher (runs the widget with no visible console window) |
| `README.md` | This file |

All install/uninstall logic reads only from files in this folder — nothing is downloaded.

## Troubleshooting

**Nothing shows up after install** — check `Setup.bat` → Status. If "Running: no", try reinstalling; if it still fails, run `ratelimit_bar.ps1` directly in a visible PowerShell window to see any error.

**Bars stuck at 0%** — the cache file hasn't been written yet. Use Claude Code once (any prompt) and it'll populate.

**Widget disappeared on its own** — shouldn't happen; the widget swallows its own errors and keeps running. If it does, reinstall and let us know what you were doing when it happened.

**Wrong corner / off-screen** — drag it back into place; position isn't currently saved between restarts.

## Privacy

Reads one local JSON file. No network access, no telemetry, no external calls of any kind.
