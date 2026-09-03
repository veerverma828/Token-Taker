# Claude Code status line. Reads JSON session data on stdin, prints one line.
# PowerShell port of statusline-command.sh (no Python dependency).

$ErrorActionPreference = 'SilentlyContinue'

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

function Get-Path {
    param($Obj, [string[]]$Path)
    $cur = $Obj
    foreach ($k in $Path) {
        if ($null -eq $cur) { return $null }
        $cur = $cur.PSObject.Properties[$k]
        if ($null -eq $cur) { return $null }
        $cur = $cur.Value
    }
    return $cur
}

function Color {
    param([string]$Code, [string]$Text)
    return "$([char]27)[${Code}m$Text$([char]27)[0m"
}

function Bar {
    param([double]$Pct, [int]$Width = 10)
    $filled = [int][math]::Round(($Pct / 100) * $Width)
    if ($filled -lt 0) { $filled = 0 }
    if ($filled -gt $Width) { $filled = $Width }
    return ('█' * $filled) + ('░' * ($Width - $filled))
}

function Format-Reset {
    param($Epoch, [bool]$WithDay = $true)
    try {
        $dt = [DateTimeOffset]::FromUnixTimeSeconds([long]$Epoch).LocalDateTime
        $remaining = [int]($dt - (Get-Date)).TotalSeconds
        if ($remaining -lt 0) { $remaining = 0 }
        $days = [math]::Floor($remaining / 86400)
        $rem = $remaining % 86400
        $hours = [math]::Floor($rem / 3600)
        $rem = $rem % 3600
        $minutes = [math]::Floor($rem / 60)
        if ($WithDay -and $days -gt 0) { return "${days}d ${hours}h" }
        if ($hours -gt 0) { return "${hours}h ${minutes}m" }
        return "${minutes}m"
    } catch {
        return ""
    }
}

$stdin = [Console]::In.ReadToEnd()
try {
    $data = $stdin | ConvertFrom-Json
} catch {
    Write-Output ""
    exit
}
if ($null -eq $data) {
    Write-Output ""
    exit
}

$model = Get-Path $data @('model', 'display_name')
$effort = Get-Path $data @('effort', 'level')
$cwd = Get-Path $data @('workspace', 'current_dir')
if ([string]::IsNullOrEmpty($cwd)) { $cwd = "." }
$dirDisplay = Split-Path -Leaf ($cwd.TrimEnd('/', '\'))
if ([string]::IsNullOrEmpty($dirDisplay)) { $dirDisplay = $cwd }

$branch = ""
$dirty = ""
if (Get-Command git -ErrorAction SilentlyContinue) {
    $inside = git -C $cwd --no-optional-locks rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) {
        $branch = (git -C $cwd --no-optional-locks branch --show-current 2>$null) -join ""
        $status = git -C $cwd --no-optional-locks status --porcelain 2>$null
        if ($status) { $dirty = "*" }
    }
}

$ctxUsed = Get-Path $data @('context_window', 'used_percentage')
$fiveH = Get-Path $data @('rate_limits', 'five_hour', 'used_percentage')
$fiveHReset = Get-Path $data @('rate_limits', 'five_hour', 'resets_at')
$sevenD = Get-Path $data @('rate_limits', 'seven_day', 'used_percentage')
$sevenDReset = Get-Path $data @('rate_limits', 'seven_day', 'resets_at')

$parts = @()
if ($model) { $parts += Color "36" "🤖 $model" }
if ($effort) { $parts += Color "35" "[$effort]" }
if ($branch) { $parts += Color "33" "🌿($branch$dirty)" }

if ($null -ne $fiveH) {
    $seg = "⏱️ 5h $(Bar $fiveH) $([math]::Round($fiveH))%"
    if ($fiveHReset) { $seg += " ($(Format-Reset $fiveHReset $false))" }
    $code = if ($fiveH -ge 80) { "31" } else { "33" }
    $parts += Color $code $seg
}
if ($null -ne $sevenD) {
    $seg = "📅 7d $(Bar $sevenD) $([math]::Round($sevenD))%"
    if ($sevenDReset) { $seg += " ($(Format-Reset $sevenDReset $true))" }
    $code = if ($sevenD -ge 80) { "31" } else { "33" }
    $parts += Color $code $seg
}

if ($dirDisplay) { $parts += Color "33" "📁 $dirDisplay" }
if ($null -ne $ctxUsed) { $parts += Color "34" "🧠 ctx:$([math]::Round($ctxUsed))%" }

Write-Output ($parts -join " ")
