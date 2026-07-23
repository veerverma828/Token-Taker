$Host.UI.RawUI.WindowTitle = "Token Taker - Setup"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$srcDir      = $PSScriptRoot
$targetDir   = "$env:USERPROFILE\.claude"
$startupDir  = [Environment]::GetFolderPath('Startup')
$psTarget    = Join-Path $targetDir "ratelimit_bar.ps1"
$vbsTarget   = Join-Path $targetDir "ratelimit_bar.vbs"
$vbsStartup  = Join-Path $startupDir "ratelimit_bar.vbs"
$cacheFile   = Join-Path $targetDir ".statusline_ratelimit_cache.json"

function Write-Line($text, $color = "Gray") { Write-Host $text -ForegroundColor $color }
function Write-Rule { Write-Host ("-" * 58) -ForegroundColor DarkGray }

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  _____     _              _____     _" -ForegroundColor Cyan
    Write-Host " |_   _|__ | |_____ _ _   |_   _|_ _| |_____ _ _" -ForegroundColor Cyan
    Write-Host "   | |/ _ \| / / -_) ' \    | |/ _\` | / / -_) '_|" -ForegroundColor Cyan
    Write-Host "   |_|\___/|_\_\___|_||_|   |_|\__,_|_\_\___|_|" -ForegroundColor Cyan
    Write-Host ""
    Write-Line "  Floating 5-hour / 7-day usage bar for Claude Code" "White"
    Write-Rule
    Write-Host ""
}

function Stop-RunningWidget {
    $procs = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*ratelimit_bar.ps1*" })
    foreach ($p in $procs) {
        try { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    return $procs.Count
}

function Test-Prereqs {
    $issues = @()
    if (-not (Test-Path (Join-Path $srcDir "ratelimit_bar.ps1"))) { $issues += "ratelimit_bar.ps1 missing from this folder" }
    if (-not (Test-Path (Join-Path $srcDir "ratelimit_bar.vbs"))) { $issues += "ratelimit_bar.vbs missing from this folder" }
    if (-not (Test-Path $targetDir)) { $issues += "~/.claude folder not found - is Claude Code installed?" }
    return $issues
}

function Do-Install {
    Show-Banner
    Write-Line "  Checking requirements..." "Yellow"
    $issues = Test-Prereqs
    if ($issues.Count -gt 0) {
        Write-Host ""
        Write-Line "  Cannot install:" "Red"
        foreach ($i in $issues) { Write-Line "   - $i" "Red" }
        Write-Host ""
        Read-Host "  Press Enter to exit"
        return
    }
    Write-Line "  OK" "Green"
    Write-Host ""

    Write-Line "  Stopping any running instance..." "Yellow"
    Stop-RunningWidget | Out-Null
    Start-Sleep -Milliseconds 300
    Write-Line "  OK" "Green"
    Write-Host ""

    Write-Line "  Installing files to $targetDir ..." "Yellow"
    Copy-Item (Join-Path $srcDir "ratelimit_bar.ps1") $psTarget -Force
    Copy-Item (Join-Path $srcDir "ratelimit_bar.vbs") $vbsTarget -Force
    Write-Line "  OK" "Green"
    Write-Host ""

    Write-Line "  Enabling autostart on login..." "Yellow"
    Copy-Item $vbsTarget $vbsStartup -Force
    $autostartOk = Test-Path $vbsStartup
    if ($autostartOk) { Write-Line "  OK" "Green" } else { Write-Line "  FAILED" "Red" }
    Write-Host ""

    Write-Line "  Starting the widget now..." "Yellow"
    Start-Process "wscript.exe" -ArgumentList "`"$vbsTarget`"" -WindowStyle Hidden
    $running = $false
    for ($i = 0; $i -lt 6 -and -not $running; $i++) {
        Start-Sleep -Milliseconds 700
        $running = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -like "*ratelimit_bar.ps1*" }).Count -gt 0
    }
    if ($running) { Write-Line "  OK - running" "Green" } else { Write-Line "  Could not confirm it started - check manually" "Yellow" }

    $cacheReady = Test-Path $cacheFile
    Write-Host ""
    Write-Rule
    Write-Host ""
    Write-Host "   INSTALLATION COMPLETE" -ForegroundColor Black -BackgroundColor Green
    Write-Host ""
    Write-Line "  Look at the bottom-right corner of your screen," "White"
    Write-Line "  just above the taskbar clock." "White"
    Write-Host ""
    Write-Line "  Installed to : $targetDir" "Gray"
    Write-Line "  Autostart    : $(if ($autostartOk) {'enabled (every login)'} else {'NOT enabled'})" "Gray"
    Write-Line "  Move it      : left-click drag" "Gray"
    Write-Line "  Close it     : right-click -> Exit" "Gray"
    if (-not $cacheReady) {
        Write-Host ""
        Write-Line "  Note: no usage data yet. Bars will fill in once you" "Yellow"
        Write-Line "  run Claude Code and its statusline reports usage." "Yellow"
    }
    Write-Host ""
    Write-Rule
    Read-Host "`n  Press Enter to close this window"
}

function Do-Uninstall {
    Show-Banner
    Write-Line "  This will stop the widget, remove it from startup," "White"
    Write-Line "  and delete its files from $targetDir." "White"
    Write-Host ""
    $confirm = Read-Host "  Type Y to confirm uninstall"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Line "`n  Cancelled." "Yellow"
        Start-Sleep -Seconds 1
        return
    }
    Write-Host ""

    Write-Line "  Stopping running instance..." "Yellow"
    $stopped = Stop-RunningWidget
    Write-Line "  OK" "Green"

    Write-Line "  Removing autostart entry..." "Yellow"
    Remove-Item $vbsStartup -Force -ErrorAction SilentlyContinue
    Write-Line "  OK" "Green"

    Write-Line "  Removing installed files..." "Yellow"
    Remove-Item $psTarget -Force -ErrorAction SilentlyContinue
    Remove-Item $vbsTarget -Force -ErrorAction SilentlyContinue
    Write-Line "  OK" "Green"

    Write-Host ""
    Write-Rule
    Write-Host ""
    Write-Host "   UNINSTALL COMPLETE" -ForegroundColor Black -BackgroundColor DarkYellow
    Write-Host ""
    Write-Line "  The widget has been removed and will not start again." "White"
    Write-Line "  (Your Claude Code usage cache file was left untouched.)" "Gray"
    Write-Host ""
    Write-Rule
    Read-Host "`n  Press Enter to close this window"
}

function Show-Status {
    Show-Banner
    $installed = Test-Path $psTarget
    $autostart = Test-Path $vbsStartup
    $matches = @(Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*ratelimit_bar.ps1*" })
    $running = $matches.Count -gt 0
    Write-Line "  Installed : $(if ($installed) {'yes'} else {'no'})" "White"
    Write-Line "  Autostart : $(if ($autostart) {'enabled'} else {'disabled'})" "White"
    Write-Line "  Running   : $(if ($running) {'yes'} else {'no'})" "White"
    Write-Host ""
    Read-Host "  Press Enter to go back"
}

while ($true) {
    Show-Banner
    Write-Line "   [1] Install"     "White"
    Write-Line "   [2] Uninstall"   "White"
    Write-Line "   [3] Status"      "White"
    Write-Line "   [4] Exit"        "White"
    Write-Host ""
    $choice = Read-Host "  Choose an option (1-4)"
    switch ($choice) {
        "1" { Do-Install }
        "2" { Do-Uninstall }
        "3" { Show-Status }
        "4" { break }
        default { continue }
    }
    if ($choice -eq "4") { break }
}
