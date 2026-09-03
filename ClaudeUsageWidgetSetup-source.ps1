# Claude Usage Widget - a single app that is both the installer and the
# manager. Shows a Setup screen when not installed, a Manager screen (with
# live status, start/stop, autostart toggle, uninstall) once it is.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$claudeDir      = Join-Path $HOME ".claude"
$widgetPs1      = Join-Path $claudeDir "usage-widget.ps1"
$launchVbs      = Join-Path $claudeDir "usage-widget-launch.vbs"
$posPath        = Join-Path $claudeDir "usage-widget-pos.json"
$stopFlagPath   = Join-Path $claudeDir "usage-widget-stop.flag"
$statusJsonPath = Join-Path $claudeDir "usage-status.json"
$configPath     = Join-Path $claudeDir "usage-widget-config.json"
$ourStatusLine  = Join-Path $claudeDir "statusline-command.ps1"
$wrapperPath    = Join-Path $claudeDir "usage-widget-statusline-wrapper.ps1"
$fullStatusLine = Join-Path $claudeDir "usage-widget-full-statusline.ps1"
$fullStatusLinePrevPath = Join-Path $claudeDir "usage-widget-full-statusline-previous.json"
$settingsPath   = Join-Path $claudeDir "settings.json"
$startupDir     = [Environment]::GetFolderPath('Startup')
$startupVbs     = Join-Path $startupDir "ClaudeUsageWidget.vbs"

try { $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { $exePath = $null }
$desktopDir = [Environment]::GetFolderPath('Desktop')
$desktopShortcut = Join-Path $desktopDir "Claude Usage Widget.lnk"

$WidgetScriptContent = @'
# Claude Code usage widget - floating, draggable, resizable, always-on-top.
# Reads ~/.claude/usage-status.json (written by statusline-command.ps1 while
# a Claude Code session is active) and shows the daily/weekly limit compactly.
# Layout ("oneline" or "stacked") comes from ~/.claude/usage-widget-config.json.
# Uses real (non-transform) layout so text/bars stay crisp at every size.

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# Manual dragging done via WPF's own Left/Top + PointToScreen drifts under
# per-monitor DPI scaling (the widget's HWND lives in physical pixels, WPF's
# properties are DPI-scaled logical units) - the gap between cursor and
# window grows as you drag. Doing the whole drag in raw Win32 pixels via
# GetCursorPos/SetWindowPos sidesteps that mismatch entirely.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class NativeDrag {
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
}
"@
$SWP_NOSIZE = 0x0001
$SWP_NOMOVE = 0x0002
$SWP_NOZORDER = 0x0004
$SWP_NOACTIVATE = 0x0010
$HWND_TOPMOST = [IntPtr]::new(-1)

$dataPath   = Join-Path $HOME ".claude\usage-status.json"
$posPath    = Join-Path $HOME ".claude\usage-widget-pos.json"
$configPath = Join-Path $HOME ".claude\usage-widget-config.json"

$Layout = "oneline"
if (Test-Path $configPath) {
    try {
        $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
        if ($cfg.layout -eq "stacked") { $Layout = "stacked" }
    } catch {}
}

if ($Layout -eq "stacked") {
    $DesignWidth  = 230.0
    $DesignHeight = 84.0
} else {
    $DesignWidth  = 380.0
    $DesignHeight = 46.0
}
$GripSize = 7

if ($Layout -eq "stacked") {
    $ContentXaml = @"
            <Grid x:Name="ContentGrid" Margin="16,10,16,10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock x:Name="FiveHLabel" Grid.Row="0" Grid.Column="0" Text="5h" Foreground="#AAAAAA" FontFamily="Segoe UI" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <Border x:Name="FiveHTrack" Grid.Row="0" Grid.Column="1" Background="#33FFFFFF" VerticalAlignment="Center" Margin="0,0,8,0">
                    <Border x:Name="FiveHFill" HorizontalAlignment="Left" Width="0"/>
                </Border>
                <TextBlock x:Name="FiveHText" Grid.Row="0" Grid.Column="2" Text="--" Foreground="#DDDDDD" FontFamily="Segoe UI" VerticalAlignment="Center"/>

                <TextBlock x:Name="SevenDLabel" Grid.Row="1" Grid.Column="0" Text="7d" Foreground="#AAAAAA" FontFamily="Segoe UI" VerticalAlignment="Center" Margin="0,6,8,0"/>
                <Border x:Name="SevenDTrack" Grid.Row="1" Grid.Column="1" Background="#33FFFFFF" VerticalAlignment="Center" Margin="0,6,8,0">
                    <Border x:Name="SevenDFill" HorizontalAlignment="Left" Width="0"/>
                </Border>
                <TextBlock x:Name="SevenDText" Grid.Row="1" Grid.Column="2" Text="--" Foreground="#DDDDDD" FontFamily="Segoe UI" VerticalAlignment="Center"/>
            </Grid>
"@
} else {
    $ContentXaml = @"
            <Grid x:Name="ContentGrid" Margin="14,0,14,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock x:Name="FiveHLabel" Grid.Column="0" Text="5h" Foreground="#AAAAAA" FontFamily="Segoe UI" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <Border x:Name="FiveHTrack" Grid.Column="1" Background="#33FFFFFF" VerticalAlignment="Center" Margin="0,0,8,0">
                    <Border x:Name="FiveHFill" HorizontalAlignment="Left" Width="0"/>
                </Border>
                <TextBlock x:Name="FiveHText" Grid.Column="2" Text="--" Foreground="#DDDDDD" FontFamily="Segoe UI" VerticalAlignment="Center"/>

                <TextBlock x:Name="Sep" Grid.Column="3" Text="   |   " Foreground="#444444" FontFamily="Segoe UI" VerticalAlignment="Center"/>

                <TextBlock x:Name="SevenDLabel" Grid.Column="4" Text="7d" Foreground="#AAAAAA" FontFamily="Segoe UI" VerticalAlignment="Center" Margin="0,0,8,0"/>
                <Border x:Name="SevenDTrack" Grid.Column="5" Background="#33FFFFFF" VerticalAlignment="Center" Margin="0,0,8,0">
                    <Border x:Name="SevenDFill" HorizontalAlignment="Left" Width="0"/>
                </Border>
                <TextBlock x:Name="SevenDText" Grid.Column="6" Text="--" Foreground="#DDDDDD" FontFamily="Segoe UI" VerticalAlignment="Center"/>
            </Grid>
"@
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:shell="clr-namespace:System.Windows.Shell;assembly=PresentationFramework"
        Title="Claude Usage" Height="$DesignHeight" Width="$DesignWidth"
        MinWidth="120" MinHeight="30" MaxWidth="1400" MaxHeight="320"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="CanResize">
    <shell:WindowChrome.WindowChrome>
        <shell:WindowChrome CaptionHeight="0" ResizeBorderThickness="$GripSize" GlassFrameThickness="0" CornerRadius="0" UseAeroCaptionButtons="False"/>
    </shell:WindowChrome.WindowChrome>
    <Window.ContextMenu>
        <ContextMenu>
            <MenuItem x:Name="StartupMenuItem" Header="Start with Windows" IsCheckable="True"/>
            <Separator/>
            <MenuItem x:Name="CloseMenuItem" Header="Close widget"/>
        </ContextMenu>
    </Window.ContextMenu>
    <Grid>
        <Border x:Name="MoveArea" CornerRadius="20"
                Background="#EE1E1E1E" BorderBrush="#3A3A3A" BorderThickness="1">
$ContentXaml
        </Border>
    </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$fiveHFill    = $window.FindName("FiveHFill")
$fiveHText    = $window.FindName("FiveHText")
$fiveHTrack   = $window.FindName("FiveHTrack")
$fiveHLabel   = $window.FindName("FiveHLabel")
$sevenDFill   = $window.FindName("SevenDFill")
$sevenDText   = $window.FindName("SevenDText")
$sevenDTrack  = $window.FindName("SevenDTrack")
$sevenDLabel  = $window.FindName("SevenDLabel")
$sep          = $window.FindName("Sep")
$moveArea     = $window.FindName("MoveArea")
$contentGrid  = $window.FindName("ContentGrid")
$startupMenuItem = $window.FindName("StartupMenuItem")
$closeMenuItem   = $window.FindName("CloseMenuItem")

$startupDir = [Environment]::GetFolderPath('Startup')
$startupVbs = Join-Path $startupDir "ClaudeUsageWidget.vbs"
$launchVbs  = Join-Path $HOME ".claude\usage-widget-launch.vbs"

$startupMenuItem.IsChecked = Test-Path $startupVbs
$startupMenuItem.Add_Click({
    if ($startupMenuItem.IsChecked) {
        @"
Set shell = CreateObject("WScript.Shell")
shell.Run "wscript.exe ""$launchVbs""", 0, False
"@ | Set-Content -Path $startupVbs -Encoding ASCII
    } else {
        Remove-Item $startupVbs -Force -ErrorAction SilentlyContinue
    }
})
$closeMenuItem.Add_Click({ $window.Close() })

# restore last position/size, else default to top-right corner at design size
if (Test-Path $posPath) {
    try {
        $pos = Get-Content $posPath -Raw | ConvertFrom-Json
        $window.Left = $pos.Left
        $window.Top  = $pos.Top
        if ($pos.Width)  { $window.Width  = $pos.Width }
        if ($pos.Height) { $window.Height = $pos.Height }
    } catch {}
}
$script:hwnd = [IntPtr]::Zero
$window.Add_SourceInitialized({
    $script:hwnd = (New-Object System.Windows.Interop.WindowInteropHelper($window)).Handle
    if ($window.Left -eq 0 -and $window.Top -eq 0) {
        $screen = [System.Windows.SystemParameters]::WorkArea
        $window.Left = $screen.Right - $window.Width - 20
        $window.Top  = 20
    }
})

$moveState = [pscustomobject]@{ Active = $false; StartCursorX = 0; StartCursorY = 0; StartWinX = 0; StartWinY = 0 }

$moveArea.Add_MouseLeftButtonDown({
    param($sender, $e)
    $cursor = New-Object NativeDrag+POINT
    [NativeDrag]::GetCursorPos([ref]$cursor) | Out-Null
    $rect = New-Object NativeDrag+RECT
    [NativeDrag]::GetWindowRect($script:hwnd, [ref]$rect) | Out-Null
    $moveState.Active = $true
    $moveState.StartCursorX = $cursor.X
    $moveState.StartCursorY = $cursor.Y
    $moveState.StartWinX = $rect.Left
    $moveState.StartWinY = $rect.Top
    $moveArea.CaptureMouse()
    $e.Handled = $true
})
$moveArea.Add_MouseMove({
    param($sender, $e)
    if (-not $moveState.Active) { return }
    $cursor = New-Object NativeDrag+POINT
    [NativeDrag]::GetCursorPos([ref]$cursor) | Out-Null
    $newX = $moveState.StartWinX + ($cursor.X - $moveState.StartCursorX)
    $newY = $moveState.StartWinY + ($cursor.Y - $moveState.StartCursorY)
    [NativeDrag]::SetWindowPos($script:hwnd, [IntPtr]::Zero, $newX, $newY, 0, 0, ($SWP_NOSIZE -bor $SWP_NOZORDER -bor $SWP_NOACTIVATE)) | Out-Null
})
$moveArea.Add_MouseLeftButtonUp({
    param($sender, $e)
    $moveState.Active = $false
    $moveArea.ReleaseMouseCapture()
})

$window.Add_Closing({
    try {
        @{ Left = $window.Left; Top = $window.Top; Width = $window.Width; Height = $window.Height } |
            ConvertTo-Json -Compress | Set-Content -Path $posPath -Encoding utf8
    } catch {}
})

# resizing itself is now handled natively by WindowChrome's ResizeBorderThickness
# (proper OS cursors, real edge/corner drag, no hand-rolled hit-testing needed).

# recompute real (non-transform) sizes whenever the window is resized, so
# text and bars are laid out natively at the new size instead of being
# graphically scaled (which is what caused the blurriness).
function Update-Scale {
    $h = $window.ActualHeight
    if ($h -le 0) { return }
    $rowH = if ($Layout -eq "stacked") { $h / 2.0 } else { $h }
    $fontSize    = [math]::Max(8, [math]::Min(40, $rowH * 0.34))
    $barHeight   = [math]::Max(4, [math]::Min(30, $rowH * 0.30))
    $outerRadius = [math]::Min($h / 2.0, 40)
    $barRadius   = $barHeight / 2.0

    $textBlocks = @($fiveHLabel, $fiveHText, $sevenDLabel, $sevenDText)
    if ($sep) { $textBlocks += $sep }
    foreach ($tb in $textBlocks) { $tb.FontSize = $fontSize }

    foreach ($track in @($fiveHTrack, $sevenDTrack)) {
        $track.Height = $barHeight
        $track.CornerRadius = $barRadius
    }
    $fiveHFill.CornerRadius = $barRadius
    $sevenDFill.CornerRadius = $barRadius
    $moveArea.CornerRadius = $outerRadius
    if ($Layout -eq "stacked") {
        $contentGrid.Margin = New-Object System.Windows.Thickness(($outerRadius * 0.7), ($outerRadius * 0.35), ($outerRadius * 0.7), ($outerRadius * 0.35))
    } else {
        $contentGrid.Margin = New-Object System.Windows.Thickness(($outerRadius * 0.8), 0, ($outerRadius * 0.8), 0)
    }
}

$script:lastFiveHPct = $null; $script:lastFiveHReset = $null
$script:lastSevenDPct = $null; $script:lastSevenDReset = $null

$window.Add_SizeChanged({
    Update-Scale
    Set-Bar $fiveHTrack $fiveHFill $fiveHText $script:lastFiveHPct $script:lastFiveHReset
    Set-Bar $sevenDTrack $sevenDFill $sevenDText $script:lastSevenDPct $script:lastSevenDReset
})

function Format-TimeLeft($epoch) {
    if (-not $epoch) { return $null }
    try {
        $dt = [DateTimeOffset]::FromUnixTimeSeconds([long]$epoch).LocalDateTime
        $remaining = [int]($dt - (Get-Date)).TotalSeconds
        if ($remaining -lt 0) { return "resetting" }
        $days = [math]::Floor($remaining / 86400)
        $rem = $remaining % 86400
        $hours = [math]::Floor($rem / 3600)
        $rem = $rem % 3600
        $minutes = [math]::Floor($rem / 60)
        if ($days -gt 0) { return "${days}d ${hours}h" }
        if ($hours -gt 0) { return "${hours}h ${minutes}m" }
        return "${minutes}m"
    } catch { return $null }
}

function Get-BarBrush([double]$pct) {
    if ($pct -ge 90) { $top = "#FF8A80"; $bottom = "#E53935" }
    elseif ($pct -ge 70) { $top = "#FFD180"; $bottom = "#FB8C00" }
    else { $top = "#B9F6CA"; $bottom = "#43A047" }

    $brush = New-Object System.Windows.Media.LinearGradientBrush
    $brush.StartPoint = New-Object System.Windows.Point(0, 0)
    $brush.EndPoint   = New-Object System.Windows.Point(0, 1)
    $brush.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [Windows.Media.ColorConverter]::ConvertFromString($top), 0)))
    $brush.GradientStops.Add((New-Object System.Windows.Media.GradientStop(
        [Windows.Media.ColorConverter]::ConvertFromString($bottom), 1)))
    return $brush
}

function Set-Bar($track, $fill, $textBlock, $pct, $resetEpoch) {
    if ($null -eq $pct) {
        $fill.Width = 0
        $textBlock.Text = "--"
        return
    }
    $pctClamped = [math]::Max(0, [math]::Min(100, $pct))
    $trackWidth = $track.ActualWidth
    if ($trackWidth -gt 0) {
        $fill.Width = $trackWidth * ($pctClamped / 100)
    }
    $fill.Background = Get-BarBrush $pctClamped

    $reset = Format-TimeLeft $resetEpoch
    $textBlock.Text = "$([math]::Round($pctClamped))%" + $(if ($reset) { " $reset" } else { "" })
}

function Refresh {
    if (-not (Test-Path $dataPath)) {
        Set-Bar $fiveHTrack $fiveHFill $fiveHText $null $null
        Set-Bar $sevenDTrack $sevenDFill $sevenDText $null $null
        return
    }
    try {
        $json = Get-Content $dataPath -Raw | ConvertFrom-Json
    } catch { return }

    $script:lastFiveHPct = $json.fiveHourPct; $script:lastFiveHReset = $json.fiveHourReset
    $script:lastSevenDPct = $json.sevenDayPct; $script:lastSevenDReset = $json.sevenDayReset
    Set-Bar $fiveHTrack $fiveHFill $fiveHText $json.fiveHourPct $json.fiveHourReset
    Set-Bar $sevenDTrack $sevenDFill $sevenDText $json.sevenDayPct $json.sevenDayReset
}

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Refresh })
$timer.Start()

# ShowInTaskbar=False means Process.CloseMainWindow() can never find this
# window (Windows treats it as a tool window, excluded like Alt-Tab), so a
# manager app can't close it gracefully that way. Watch for a signal file
# instead, so Stop still triggers our own Closing handler (position save).
$stopFlagPath = Join-Path $HOME ".claude\usage-widget-stop.flag"
$stopTimer = New-Object System.Windows.Threading.DispatcherTimer
$stopTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$stopTimer.Add_Tick({
    if (Test-Path $stopFlagPath) {
        Remove-Item $stopFlagPath -Force -ErrorAction SilentlyContinue
        $window.Close()
    }
})
$stopTimer.Start()

# Windows re-asserts the taskbar to the front of the topmost z-order band
# whenever it's interacted with (e.g. clicking Start), which can push it
# above other topmost windows including this one. Periodically re-assert
# our own topmost position so the widget always wins that race back.
$topmostTimer = New-Object System.Windows.Threading.DispatcherTimer
$topmostTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$topmostTimer.Add_Tick({
    if ($script:hwnd -ne [IntPtr]::Zero) {
        [NativeDrag]::SetWindowPos($script:hwnd, $HWND_TOPMOST, 0, 0, 0, 0, ($SWP_NOMOVE -bor $SWP_NOSIZE -bor $SWP_NOACTIVATE)) | Out-Null
    }
})
$topmostTimer.Start()

Update-Scale
Refresh
$window.ShowDialog() | Out-Null

'@
$MinimalStatusLineContent = @'
# claude-usage-widget:managed-statusline v1 - safe to regenerate/delete, only present on files this installer created
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$stdin = [Console]::In.ReadToEnd()
try { $data = $stdin | ConvertFrom-Json } catch { Write-Output ''; exit }
if ($null -eq $data) { Write-Output ''; exit }

$fiveH = $data.rate_limits.five_hour.used_percentage
$fiveHReset = $data.rate_limits.five_hour.resets_at
$sevenD = $data.rate_limits.seven_day.used_percentage
$sevenDReset = $data.rate_limits.seven_day.resets_at

try {
    [ordered]@{
        updatedAt     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        fiveHourPct   = $fiveH
        fiveHourReset = $fiveHReset
        sevenDayPct   = $sevenD
        sevenDayReset = $sevenDReset
    } | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $HOME '.claude\usage-status.json') -Encoding utf8
} catch {}

$parts = @()
if ($null -ne $fiveH) { $parts += ('5h:' + [math]::Round($fiveH) + '%') }
if ($null -ne $sevenD) { $parts += ('7d:' + [math]::Round($sevenD) + '%') }
Write-Output ($parts -join ' | ')
'@
$FullStatusLineContent = @'
# claude-usage-widget:managed-statusline v1 - safe to regenerate/delete, only present on files this installer created
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
'@
$WrapperTemplate = @'
$ErrorActionPreference = 'SilentlyContinue'
$stdin = [Console]::In.ReadToEnd()
try {
    $data = $stdin | ConvertFrom-Json
    $fiveH = $data.rate_limits.five_hour.used_percentage
    $fiveHReset = $data.rate_limits.five_hour.resets_at
    $sevenD = $data.rate_limits.seven_day.used_percentage
    $sevenDReset = $data.rate_limits.seven_day.resets_at
    [ordered]@{
        updatedAt     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        fiveHourPct   = $fiveH
        fiveHourReset = $fiveHReset
        sevenDayPct   = $sevenD
        sevenDayReset = $sevenDReset
    } | ConvertTo-Json -Compress | Set-Content -Path (Join-Path $HOME '.claude\usage-status.json') -Encoding utf8
} catch {}
__ORIGINAL_INVOKE__
'@

function Write-File($path, $content) {
    Set-Content -Path $path -Value $content -Encoding utf8 -NoNewline
}

function Test-Installed { Test-Path $widgetPs1 }

function Get-Layout {
    if (Test-Path $configPath) {
        try {
            $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($cfg.layout -eq "stacked") { return "stacked" }
        } catch {}
    }
    return "oneline"
}

function Set-Layout([string]$layout) {
    if ((Get-Layout) -eq $layout) { return }
    @{ layout = $layout } | ConvertTo-Json -Compress | Set-Content -Path $configPath -Encoding utf8
    # the two layouts use different design sizes/shapes - drop the saved
    # position/size so the widget picks fresh defaults for the new shape
    # instead of reappearing squashed into the old layout's box.
    Remove-Item $posPath -Force -ErrorAction SilentlyContinue
    if (Get-WidgetProcess) {
        Stop-Widget
        Start-Widget
    }
}

function Test-OurStatusLine($path) {
    if (-not (Test-Path $path)) { return $false }
    $content = Get-Content $path -Raw -ErrorAction SilentlyContinue
    return ($content -and $content.Contains('claude-usage-widget:managed-statusline'))
}

function Test-ClaudeCodeInstalled {
    if (Get-Command claude -ErrorAction SilentlyContinue) { return $true }
    if (Test-Path $claudeDir) { return $true }
    return $false
}

function Test-ClaudeCliOnPath { [bool](Get-Command claude -ErrorAction SilentlyContinue) }

# Quotes a single value as one literal Win32 command-line argument (the
# algorithm CommandLineToArgvW expects), so a multi-line, quote-containing
# problem description survives being handed to Process.Start as one string -
# there's no shell involved here to do that escaping for us.
function Format-ProcessArgument([string]$arg) {
    if ($arg -eq '') { return '""' }
    if ($arg -notmatch '[\s"]') { return $arg }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    for ($i = 0; $i -lt $arg.Length; $i++) {
        $numBackslashes = 0
        while ($i -lt $arg.Length -and $arg[$i] -eq '\') { $numBackslashes++; $i++ }
        if ($i -eq $arg.Length) {
            [void]$sb.Append('\' * ($numBackslashes * 2))
        } elseif ($arg[$i] -eq '"') {
            [void]$sb.Append('\' * ($numBackslashes * 2 + 1))
            [void]$sb.Append('"')
        } else {
            [void]$sb.Append('\' * $numBackslashes)
            [void]$sb.Append($arg[$i])
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Get-WidgetProcess {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*usage-widget.ps1*" }
}

function Start-Widget {
    if (Get-WidgetProcess) { return }
    if (-not (Test-Path $launchVbs)) { return }
    Start-Process wscript.exe -ArgumentList "`"$launchVbs`""
}

function Stop-Widget {
    # the widget is ShowInTaskbar=False (a "tool window"), so
    # Process.CloseMainWindow() can never find it - signal it via a flag
    # file instead so it closes itself gracefully and saves its position.
    if (-not (Get-WidgetProcess)) { return }
    New-Item -Path $stopFlagPath -ItemType File -Force -ErrorAction SilentlyContinue | Out-Null
    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline -and (Get-WidgetProcess)) { Start-Sleep -Milliseconds 150 }
    Get-WidgetProcess | ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }
    Remove-Item $stopFlagPath -Force -ErrorAction SilentlyContinue
}

function Set-StartWithWindows([bool]$enabled) {
    if ($enabled) {
        @"
Set shell = CreateObject("WScript.Shell")
shell.Run "wscript.exe ""$launchVbs""", 0, False
"@ | Set-Content -Path $startupVbs -Encoding ASCII
    } else {
        Remove-Item $startupVbs -Force -ErrorAction SilentlyContinue
    }
}

function New-DesktopShortcut {
    if (-not $exePath) { return }
    if ((Split-Path $exePath -Parent) -eq $desktopDir) { return }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($desktopShortcut)
        $shortcut.TargetPath = $exePath
        $shortcut.Description = "Claude Code usage widget"
        $shortcut.Save()
    } catch {}
}

function Install-StatuslineHook {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

    $statusMsg = ""
    $settings = $null
    if (Test-Path $settingsPath) {
        try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json } catch {}
    }
    if ($null -eq $settings) { $settings = New-Object PSObject }

    $hasStatusLine = $settings.PSObject.Properties.Name -contains 'statusLine'
    $settingsChanged = $false

    if (-not $hasStatusLine) {
        Write-File $ourStatusLine $MinimalStatusLineContent
        $newStatusLine = [ordered]@{
            type    = "command"
            command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $ourStatusLine + '"'
        }
        $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $newStatusLine -Force
        $settingsChanged = $true
        $statusMsg = "Set up a new Claude Code statusline showing live usage."
    } else {
        $existingCmd = $settings.statusLine.command
        $alreadyOurs = ($existingCmd -like "*usage-status.json*") -or
                       ($existingCmd -like "*usage-widget-statusline-wrapper*") -or
                       (($existingCmd -like "*statusline-command.ps1*") -and (Test-OurStatusLine $ourStatusLine))
        if ($existingCmd -and -not $alreadyOurs) {
            # never overwrite the referenced script - it's the user's own file,
            # just wrap it so usage data still gets shown, output unchanged
            $wrapperContent = $WrapperTemplate -replace '__ORIGINAL_INVOKE__', ('$stdin | cmd /c ' + $existingCmd)
            Write-File $wrapperPath $wrapperContent
            $settings.statusLine.command = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $wrapperPath + '"'
            $settingsChanged = $true
            $statusMsg = "Wrapped your existing statusline so it also shows usage data."
        } else {
            $statusMsg = "Statusline already wired up."
        }
    }
    if ($settingsChanged) {
        $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding utf8
    }
    return $statusMsg
}

function Uninstall-StatuslineHook {
    $weOwnStatusLine = Test-OurStatusLine $ourStatusLine

    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains 'statusLine') {
                $cmd = $settings.statusLine.command
                if ($cmd -like "*statusline-command.ps1*" -and $weOwnStatusLine) {
                    $settings.PSObject.Properties.Remove('statusLine')
                    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding utf8
                } elseif ($cmd -like "*usage-widget-statusline-wrapper*") {
                    if (Test-Path $wrapperPath) {
                        $wrapperText = Get-Content $wrapperPath -Raw
                        if ($wrapperText -match '\$stdin \| cmd /c (.+)$') {
                            $settings.statusLine.command = $Matches[1].Trim()
                            $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding utf8
                        }
                    }
                }
            }
        } catch {}
    }
    Remove-Item $wrapperPath -Force -ErrorAction SilentlyContinue
    if ($weOwnStatusLine) {
        Remove-Item $ourStatusLine -Force -ErrorAction SilentlyContinue
    }
}

# The "statusline only" install offers the author's own, full statusline
# (model, effort, git branch, colored 5h/7d bars with reset times, cwd,
# context %) rather than the minimal one the floating widget wires up. It
# lives at its own uniquely-named path (never "statusline-command.ps1",
# which could be someone's own real file) and does a straight replace
# rather than a wrap, since installing it IS the point of this tab - but
# whatever was there before is stashed so removing it can put it back.
function Get-ActiveStatuslineCommand {
    if (-not (Test-Path $settingsPath)) { return $null }
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($settings.PSObject.Properties.Name -contains 'statusLine') { return $settings.statusLine.command }
    } catch {}
    return $null
}

# Follows the settings.json statusLine command to the script file that
# ultimately runs - resolving through the widget's wrapper one level if
# that's what's active, since the wrapper just forwards to another script.
function Get-EffectiveStatuslineScriptPath {
    $cmd = Get-ActiveStatuslineCommand
    if (-not $cmd -or $cmd -notmatch '-File\s+"([^"]+)"') { return $null }
    $path = $Matches[1]
    if ($path -eq $wrapperPath -and (Test-Path $wrapperPath)) {
        $wrapperText = Get-Content $wrapperPath -Raw -ErrorAction SilentlyContinue
        if ($wrapperText -match '-File\s+"([^"]+)"\s*$') { return $Matches[1] }
    }
    return $path
}

# Fingerprints the author's full statusline by a few distinctive strings
# rather than an exact text match, since the live file (e.g. the user's own
# statusline-command.ps1) won't carry this installer's marker comment and
# may differ in incidental whitespace even when it's functionally the same
# script - only its author-specific logic needs to match.
function Test-ScriptIsFullStatusline([string]$path) {
    if (-not $path -or -not (Test-Path $path)) { return $false }
    try {
        $content = Get-Content $path -Raw
        # plain substring checks, not -like: the fingerprint text contains
        # "[math]", and -like treats [...] as a wildcard character class
        # rather than literal brackets, so it silently never matches here
        return $content.Contains('function Format-Reset') -and
               $content.Contains('ctx:$([math]::Round($ctxUsed))%')
    } catch { return $false }
}

# Three real states: "Ours" (installed via this tab's own file - we manage
# it), "Equivalent" (the exact same statusline is already active through some
# other path, e.g. the widget's wrapper - nothing for this tab to do),
# "Foreign" (something else entirely is active), "None" (nothing configured).
function Get-FullStatuslineState {
    $path = Get-EffectiveStatuslineScriptPath
    if ($path -eq $fullStatusLine) { return "Ours" }
    if ($path -and (Test-ScriptIsFullStatusline $path)) { return "Equivalent" }
    if (Get-ActiveStatuslineCommand) { return "Foreign" }
    return "None"
}

function Install-FullStatuslineHook {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

    $settings = $null
    if (Test-Path $settingsPath) {
        try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json } catch {}
    }
    if ($null -eq $settings) { $settings = New-Object PSObject }

    $hasStatusLine = $settings.PSObject.Properties.Name -contains 'statusLine'
    $alreadyOurs = $hasStatusLine -and ($settings.statusLine.command -like "*usage-widget-full-statusline*")
    $hadForeign = $false

    if ($hasStatusLine -and -not $alreadyOurs) {
        $hadForeign = $true
        $settings.statusLine | ConvertTo-Json -Compress | Set-Content -Path $fullStatusLinePrevPath -Encoding utf8
    }

    Write-File $fullStatusLine $FullStatusLineContent
    $cmdStr = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $fullStatusLine + '"'
    if ($hasStatusLine) {
        $settings.statusLine.command = $cmdStr
    } else {
        $newStatusLine = [ordered]@{ type = "command"; command = $cmdStr }
        $settings | Add-Member -NotePropertyName statusLine -NotePropertyValue $newStatusLine -Force
    }
    $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding utf8

    if ($hadForeign) { return "Installed. Your previous statusline was saved and will be restored if you remove this." }
    return "Installed your full statusline."
}

function Uninstall-FullStatuslineHook {
    Remove-Item $fullStatusLine -Force -ErrorAction SilentlyContinue

    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($settings.PSObject.Properties.Name -contains 'statusLine' -and
                $settings.statusLine.command -like "*usage-widget-full-statusline*") {
                if (Test-Path $fullStatusLinePrevPath) {
                    try {
                        $prev = Get-Content $fullStatusLinePrevPath -Raw | ConvertFrom-Json
                        $settings.statusLine = $prev
                    } catch { $settings.PSObject.Properties.Remove('statusLine') }
                } else {
                    $settings.PSObject.Properties.Remove('statusLine')
                }
                $settings | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding utf8
            }
        } catch {}
    }
    Remove-Item $fullStatusLinePrevPath -Force -ErrorAction SilentlyContinue
}

function Install-Everything {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    Write-File $widgetPs1 $WidgetScriptContent

    @"
Set shell = CreateObject("WScript.Shell")
shell.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""$widgetPs1""", 0, False
"@ | Set-Content -Path $launchVbs -Encoding ASCII

    New-DesktopShortcut

    $statusMsg = Install-StatuslineHook

    Set-StartWithWindows $true
    Start-Widget
    return $statusMsg
}

function Uninstall-Everything {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like "*usage-widget.ps1*" } |
        ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }

    Remove-Item $startupVbs -Force -ErrorAction SilentlyContinue
    Remove-Item $launchVbs -Force -ErrorAction SilentlyContinue
    Remove-Item $widgetPs1 -Force -ErrorAction SilentlyContinue
    Remove-Item $posPath -Force -ErrorAction SilentlyContinue
    Remove-Item $stopFlagPath -Force -ErrorAction SilentlyContinue
    Remove-Item $statusJsonPath -Force -ErrorAction SilentlyContinue
    Remove-Item $desktopShortcut -Force -ErrorAction SilentlyContinue

    # only ever remove/restore the statusline if we can PROVE we created it
    # (marker in the file, or it's our uniquely-named wrapper) - a same-named
    # file without our marker is the user's own and must never be touched.
    Uninstall-StatuslineHook
}

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Claude Usage Widget" Width="440" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize"
        Background="#1E1E1E" FontFamily="Segoe UI">
    <Window.Resources>
        <Style TargetType="TabControl">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabControl">
                        <DockPanel>
                            <TabPanel x:Name="HeaderPanel" DockPanel.Dock="Top" IsItemsHost="True" Background="Transparent"/>
                            <Border BorderBrush="#333333" BorderThickness="0,1,0,0" Margin="0,-1,0,0">
                                <ContentPresenter x:Name="PART_SelectedContentHost" ContentSource="SelectedContent" Margin="0,16,0,0"/>
                            </Border>
                        </DockPanel>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="TabItem">
            <Setter Property="Foreground" Value="#AAAAAA"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="Padding" Value="14,8"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Border x:Name="Bd" Background="Transparent" BorderBrush="#7CD97C" BorderThickness="0,0,0,2" Margin="0,0,4,0" Padding="{TemplateBinding Padding}">
                            <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="Foreground" Value="White"/>
                            </Trigger>
                            <Trigger Property="IsSelected" Value="False">
                                <Setter TargetName="Bd" Property="BorderBrush" Value="Transparent"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#3A3A3A"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#4A4A4A"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Bd" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="6">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" TextElement.Foreground="{TemplateBinding Foreground}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.85"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.7"/>
                            </Trigger>
                            <!-- disabled buttons dim in place instead of falling back to WPF's
                                 default disabled chrome, which ignores custom Background/Foreground
                                 entirely and renders a blank white box - confusing on a dark theme -->
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Bd" Property="Opacity" Value="0.4"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <StackPanel Margin="24">
        <TextBlock Text="Claude Usage Widget" Foreground="White" FontSize="20" FontWeight="Bold" Margin="0,0,0,4"/>
        <TextBlock Text="Set up live Claude Code usage tracking." Foreground="#999999" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,12"/>

        <TabControl x:Name="MainTabs">
            <TabItem Header="Floating widget">
                <StackPanel>
                    <TextBlock Text="A small floating widget on your desktop showing your Claude Code 5h/7d usage limits." Foreground="#999999" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,12"/>

                    <StackPanel x:Name="SetupPanel">
                        <Border x:Name="DetectionBanner" CornerRadius="6" Padding="10" Margin="0,0,0,16" Visibility="Collapsed">
                            <TextBlock x:Name="DetectionText" FontSize="12" TextWrapping="Wrap"/>
                        </Border>
                        <Button x:Name="InstallBtn" Content="Install" Height="38" FontSize="14" Margin="0,0,0,10"/>
                    </StackPanel>

                    <StackPanel x:Name="ManagerPanel" Visibility="Collapsed">
                        <Border Background="#2A2A2A" CornerRadius="8" Padding="12" Margin="0,0,0,16">
                            <StackPanel Orientation="Horizontal">
                                <Ellipse x:Name="StatusDot" Width="10" Height="10" Fill="#888888" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <TextBlock x:Name="StatusDotText" Text="Checking..." Foreground="White" FontSize="14" VerticalAlignment="Center"/>
                            </StackPanel>
                        </Border>
                        <Button x:Name="StartBtn" Content="Start widget" Height="34" Margin="0,0,0,8"/>
                        <Button x:Name="StopBtn" Content="Stop widget" Height="34" Margin="0,0,0,16"/>
                        <CheckBox x:Name="StartupCheck" Content="Start with Windows" Foreground="White" Margin="0,0,0,16"/>

                        <TextBlock Text="Widget layout" Foreground="#CCCCCC" FontSize="12" Margin="0,0,0,6"/>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,16">
                            <RadioButton x:Name="ThemeOneLineRadio" Content="One line (5h and 7d side by side)" Foreground="White" GroupName="Theme" Margin="0,0,20,0"/>
                            <RadioButton x:Name="ThemeStackedRadio" Content="Stacked (5h above 7d)" Foreground="White" GroupName="Theme"/>
                        </StackPanel>
                        <Separator Margin="0,0,0,16"/>
                        <Button x:Name="UninstallBtn" Content="Uninstall widget" Height="34" Background="#4A2020" Foreground="White"/>
                    </StackPanel>

                    <TextBlock x:Name="StatusText" Text="" Foreground="#7CD97C" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
                </StackPanel>
            </TabItem>

            <TabItem Header="Statusline only">
                <StackPanel>
                    <TextBlock Text="Installs the author's own full Claude Code statusline exactly as-is - no floating desktop window, nothing else." Foreground="#999999" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,10"/>
                    <TextBlock Text="Shows: model + effort level, git branch (with a dirty marker), 5h and 7d usage as colored progress bars with time-to-reset, current folder, and context window usage - color-coded, all in one line." Foreground="#999999" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,12"/>

                    <TextBlock Text="What it looks like, right in your terminal prompt:" Foreground="#CCCCCC" FontSize="12" Margin="0,0,0,6"/>
                    <Border Background="#111111" CornerRadius="6" Padding="12,10" Margin="0,0,0,16" BorderBrush="#333333" BorderThickness="1">
                        <TextBlock FontFamily="Consolas" FontSize="12.5" TextWrapping="Wrap" LineHeight="20">
                            <Run Text="🤖 Sonnet 5" Foreground="#26C6DA"/><Run Text=" " /><Run Text="[medium]" Foreground="#AB47BC"/><Run Text=" " /><Run Text="🌿(main)" Foreground="#FFB300"/><Run Text=" " /><Run Text="⏱️ 5h ██████░░░░ 62% (2h 15m)" Foreground="#FFB300"/><Run Text=" " /><Run Text="📅 7d ████░░░░░░ 38% (3d 4h)" Foreground="#FFB300"/><Run Text=" " /><Run Text="📁 myproject" Foreground="#FFB300"/><Run Text=" " /><Run Text="🧠 ctx:22%" Foreground="#42A5F5"/>
                        </TextBlock>
                    </Border>
                    <TextBlock Text="(bars turn red past 80% usage; real values update live from your session)" Foreground="#666666" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,16"/>

                    <Border x:Name="SLDetectionBanner" CornerRadius="6" Padding="10" Margin="0,0,0,16" Visibility="Collapsed">
                        <TextBlock x:Name="SLDetectionText" FontSize="12" TextWrapping="Wrap"/>
                    </Border>

                    <Border Background="#2A2A2A" CornerRadius="8" Padding="12" Margin="0,0,0,16">
                        <StackPanel Orientation="Horizontal">
                            <Ellipse x:Name="SLStatusDot" Width="10" Height="10" Fill="#888888" VerticalAlignment="Center" Margin="0,0,10,0"/>
                            <TextBlock x:Name="SLStatusDotText" Text="Checking..." Foreground="White" FontSize="14" VerticalAlignment="Center"/>
                        </StackPanel>
                    </Border>

                    <Button x:Name="SLInstallBtn" Content="Install statusline" Height="38" FontSize="14" Margin="0,0,0,10"/>
                    <Button x:Name="SLUninstallBtn" Content="Remove statusline" Height="34" Background="#4A2020" Foreground="White"/>

                    <TextBlock x:Name="SLStatusText" Text="" Foreground="#7CD97C" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
                </StackPanel>
            </TabItem>

            <TabItem Header="AI Fix">
                <StackPanel>
                    <TextBlock Text="Something broken? Describe it below and Claude Code will diagnose and fix it directly - no manual editing needed." Foreground="#999999" FontSize="12" TextWrapping="Wrap" Margin="0,0,0,12"/>

                    <Border x:Name="AiDetectionBanner" CornerRadius="6" Padding="10" Margin="0,0,0,16" Visibility="Collapsed">
                        <TextBlock x:Name="AiDetectionText" FontSize="12" TextWrapping="Wrap"/>
                    </Border>

                    <TextBlock Text="What's wrong?" Foreground="#CCCCCC" FontSize="12" Margin="0,0,0,6"/>
                    <TextBox x:Name="AiIssueBox" Height="70" AcceptsReturn="True" TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto" Background="#111111" Foreground="White"
                             BorderBrush="#333333" BorderThickness="1" Padding="8" FontSize="13" Margin="0,0,0,10"/>

                    <Button x:Name="AiFixBtn" Content="Ask Claude to fix it" Height="38" FontSize="14" Margin="0,0,0,10"/>

                    <TextBlock Text="Claude's work:" Foreground="#CCCCCC" FontSize="12" Margin="0,0,0,6"/>
                    <Border Background="#111111" BorderBrush="#333333" BorderThickness="1" CornerRadius="6" Height="200">
                        <ScrollViewer VerticalScrollBarVisibility="Auto">
                            <TextBox x:Name="AiOutputBox" IsReadOnly="True" TextWrapping="Wrap" Background="Transparent"
                                     Foreground="#CCCCCC" BorderThickness="0" FontFamily="Consolas" FontSize="12" Padding="10"/>
                        </ScrollViewer>
                    </Border>

                    <TextBlock x:Name="AiStatusText" Text="" Foreground="#7CD97C" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
                </StackPanel>
            </TabItem>
        </TabControl>
    </StackPanel>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

$setupPanel      = $window.FindName("SetupPanel")
$managerPanel    = $window.FindName("ManagerPanel")
$detectionBanner = $window.FindName("DetectionBanner")
$detectionText   = $window.FindName("DetectionText")
$installBtn      = $window.FindName("InstallBtn")
$statusDot       = $window.FindName("StatusDot")
$statusDotText   = $window.FindName("StatusDotText")
$startBtn        = $window.FindName("StartBtn")
$stopBtn         = $window.FindName("StopBtn")
$startupCheck    = $window.FindName("StartupCheck")
$themeOneLineRadio = $window.FindName("ThemeOneLineRadio")
$themeStackedRadio = $window.FindName("ThemeStackedRadio")
$uninstallBtn    = $window.FindName("UninstallBtn")
$statusText      = $window.FindName("StatusText")

$slDetectionBanner = $window.FindName("SLDetectionBanner")
$slDetectionText   = $window.FindName("SLDetectionText")
$slStatusDot       = $window.FindName("SLStatusDot")
$slStatusDotText   = $window.FindName("SLStatusDotText")
$slInstallBtn      = $window.FindName("SLInstallBtn")
$slUninstallBtn    = $window.FindName("SLUninstallBtn")
$slStatusText      = $window.FindName("SLStatusText")

$aiDetectionBanner = $window.FindName("AiDetectionBanner")
$aiDetectionText   = $window.FindName("AiDetectionText")
$aiIssueBox        = $window.FindName("AiIssueBox")
$aiFixBtn          = $window.FindName("AiFixBtn")
$aiOutputBox       = $window.FindName("AiOutputBox")
$aiStatusText      = $window.FindName("AiStatusText")

function Update-StatuslineTabStatus {
    $claudeDetected = Test-ClaudeCodeInstalled
    $slDetectionBanner.Visibility = "Visible"
    if ($claudeDetected) {
        $slDetectionBanner.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1E3A24")
        $slDetectionText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
        $slDetectionText.Text = "Claude Code detected."
    } else {
        $slDetectionBanner.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#4A3A1E")
        $slDetectionText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FFD180")
        $slDetectionText.Text = "Claude Code wasn't detected on this machine. Install Claude Code first, or install here will just wait until it's present."
    }

    switch (Get-FullStatuslineState) {
        "Ours" {
            $slStatusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString("#43A047")
            $slStatusDotText.Text = "Installed"
            $slInstallBtn.IsEnabled = $false
            $slUninstallBtn.IsEnabled = $true
        }
        "Equivalent" {
            $slStatusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString("#43A047")
            $slStatusDotText.Text = "Already installed (wired up via the floating widget)"
            $slInstallBtn.IsEnabled = $false
            $slUninstallBtn.IsEnabled = $false
        }
        "Foreign" {
            $slStatusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString("#FFB300")
            $slStatusDotText.Text = "A different statusline is currently active"
            $slInstallBtn.IsEnabled = $true
            $slUninstallBtn.IsEnabled = $false
        }
        default {
            $slStatusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString("#888888")
            $slStatusDotText.Text = "Not installed"
            $slInstallBtn.IsEnabled = $true
            $slUninstallBtn.IsEnabled = $false
        }
    }
}

$slInstallBtn.Add_Click({
    if (-not (Test-ClaudeCodeInstalled)) {
        $goAhead = [System.Windows.MessageBox]::Show(
            "Claude Code wasn't detected on this machine. The statusline needs it to show real data - install Claude Code first if you haven't. Install anyway?",
            "Claude Code Not Found", "YesNo", "Warning")
        if ($goAhead -ne "Yes") { return }
    }
    if ((Get-FullStatuslineState) -eq "Foreign") {
        $goAhead = [System.Windows.MessageBox]::Show(
            "This replaces your current terminal statusline with this one. Your existing statusline command is saved and will be restored if you remove it later. Continue?",
            "Replace Statusline", "YesNo", "Warning")
        if ($goAhead -ne "Yes") { return }
    }
    try {
        $msg = Install-FullStatuslineHook
        $slStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
        $slStatusText.Text = $msg
        Update-StatuslineTabStatus
    } catch {
        $slStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FF6B5C")
        $slStatusText.Text = "Install failed: $($_.Exception.Message)"
    }
})

$slUninstallBtn.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "This removes the statusline and restores your previous statusline command, if you had one. Continue?",
        "Remove Statusline", "YesNo", "Warning")
    if ($result -ne "Yes") { return }
    try {
        Uninstall-FullStatuslineHook
        $slStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
        $slStatusText.Text = "Statusline removed."
        Update-StatuslineTabStatus
    } catch {
        $slStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FF6B5C")
        $slStatusText.Text = "Remove failed: $($_.Exception.Message)"
    }
})

function Update-AiTabStatus {
    if ($script:aiFixRunning) { return }
    $aiDetectionBanner.Visibility = "Visible"
    if (Test-ClaudeCliOnPath) {
        $aiDetectionBanner.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1E3A24")
        $aiDetectionText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
        $aiDetectionText.Text = "Claude Code detected."
        $aiFixBtn.IsEnabled = $true
    } else {
        $aiDetectionBanner.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#4A2020")
        $aiDetectionText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FF8A80")
        $aiDetectionText.Text = "Claude Code not installed."
        $aiFixBtn.IsEnabled = $false
    }
}

# Runs `claude` headless (no interactive terminal, no permission prompts to
# answer) so it can read and edit this widget's own files directly and report
# back - streamed into AiOutputBox as it runs rather than blocking the UI
# thread, since a fix can take a while. Tool access is limited to file
# read/edit tools (no Bash/WebFetch/etc.) so an unattended run can only ever
# change files, never run arbitrary commands.
function Start-AiFix([string]$issueText) {
    if ($script:aiFixRunning) { return }
    $script:aiFixRunning = $true
    $aiOutputBox.Text = ""
    $aiFixBtn.IsEnabled = $false
    $aiStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FFD180")
    $aiStatusText.Text = "Claude is working on this..."

    $prompt = @"
You are troubleshooting the "Claude Usage Widget" Windows app (a floating desktop widget plus optional terminal statusline showing Claude Code usage limits) for a non-technical user, on this machine, at $claudeDir. Relevant files, if present:
- $widgetPs1 (the floating widget script)
- $launchVbs / $startupVbs (launch and Windows-startup shortcuts for the widget)
- $configPath (widget layout config)
- $posPath (saved widget window position/size)
- $statusJsonPath (usage data the statusline writes and the widget reads)
- $settingsPath (Claude Code settings.json - has the statusLine hook)
- $ourStatusLine / $wrapperPath / $fullStatusLine (statusline scripts this app manages)

You only have file read/write tools available (no shell commands) - diagnose the problem by reading the relevant files, then fix the root cause by editing the file(s) directly. Don't just explain, make the change.

The user describes this problem:
$issueText

When done, reply with a short plain-English summary of what was wrong and what you changed. If fixing this genuinely requires running a command (not just editing a file), say so in your reply instead of guessing at an edit.
"@

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "claude"
    $psi.Arguments = "-p " + (Format-ProcessArgument $prompt) + ' --allowedTools "Read,Edit,Write,Glob,Grep" --output-format text'
    $psi.WorkingDirectory = $claudeDir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.CreateNoWindow = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.EnableRaisingEvents = $true

    $appendLine = {
        param($line)
        if ($null -eq $line) { return }
        $window.Dispatcher.Invoke([action]{
            $aiOutputBox.AppendText($line + "`r`n")
            $aiOutputBox.ScrollToEnd()
        })
    }.GetNewClosure()

    $onFinished = {
        param($exitCode)
        $window.Dispatcher.Invoke([action]{
            $script:aiFixRunning = $false
            $aiFixBtn.IsEnabled = $true
            if ($exitCode -eq 0) {
                $aiStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
                $aiStatusText.Text = "Done."
            } else {
                $aiStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FF6B5C")
                $aiStatusText.Text = "Claude exited with an error (code $exitCode) - see the log above."
            }
        })
    }.GetNewClosure()

    [void](Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action { & $Event.MessageData $EventArgs.Data } -MessageData $appendLine)
    [void](Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action { & $Event.MessageData $EventArgs.Data } -MessageData $appendLine)
    [void](Register-ObjectEvent -InputObject $proc -EventName Exited -Action {
        $p = $Sender
        & $Event.MessageData $p.ExitCode
        Get-EventSubscriber -ErrorAction SilentlyContinue | Where-Object { $_.SourceObject -eq $p } | Unregister-Event
    } -MessageData $onFinished)

    $proc.Start() | Out-Null
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
}

$script:aiConsentGiven = $false
$aiFixBtn.Add_Click({
    $issue = $aiIssueBox.Text.Trim()
    if (-not $issue) {
        $aiStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FF6B5C")
        $aiStatusText.Text = "Describe the problem first."
        return
    }
    if (-not $script:aiConsentGiven) {
        $goAhead = [System.Windows.MessageBox]::Show(
            "Claude Code will run in the background and can read and edit files in this app's own folder ($claudeDir) to fix the problem - it won't ask you to approve each change, and it can't run other commands or touch anything outside that folder. Continue?",
            "Let Claude Fix This", "YesNo", "Warning")
        if ($goAhead -ne "Yes") { return }
        $script:aiConsentGiven = $true
    }
    try {
        Start-AiFix $issue
    } catch {
        $script:aiFixRunning = $false
        $aiFixBtn.IsEnabled = $true
        $aiStatusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FF6B5C")
        $aiStatusText.Text = "Couldn't start Claude: $($_.Exception.Message)"
    }
})

function Show-View {
    if (Test-Installed) {
        $setupPanel.Visibility = "Collapsed"
        $managerPanel.Visibility = "Visible"
    } else {
        $setupPanel.Visibility = "Visible"
        $managerPanel.Visibility = "Collapsed"

        $claudeDetected = Test-ClaudeCodeInstalled
        $detectionBanner.Visibility = "Visible"
        if ($claudeDetected) {
            $detectionBanner.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#1E3A24")
            $detectionText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
            $detectionText.Text = "Claude Code detected."
        } else {
            $detectionBanner.Background = [Windows.Media.BrushConverter]::new().ConvertFromString("#4A3A1E")
            $detectionText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FFD180")
            $detectionText.Text = "Claude Code wasn't detected on this machine. Install Claude Code first, or Install here will just wait until it's present."
        }
    }
}

function Update-ManagerStatus {
    if (Get-WidgetProcess) {
        $statusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString("#43A047")
        $statusDotText.Text = "Running"
        $startBtn.IsEnabled = $false
        $stopBtn.IsEnabled = $true
    } else {
        $statusDot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString("#888888")
        $statusDotText.Text = "Not running"
        $startBtn.IsEnabled = $true
        $stopBtn.IsEnabled = $false
    }
    $startupCheck.IsChecked = Test-Path $startupVbs
    if ((Get-Layout) -eq "stacked") {
        $themeStackedRadio.IsChecked = $true
    } else {
        $themeOneLineRadio.IsChecked = $true
    }
}

$installBtn.Add_Click({
    if (-not (Test-ClaudeCodeInstalled)) {
        $goAhead = [System.Windows.MessageBox]::Show(
            "Claude Code wasn't detected on this machine. The widget needs it to show real data - install Claude Code first if you haven't. Install the widget anyway?",
            "Claude Code Not Found", "YesNo", "Warning")
        if ($goAhead -ne "Yes") { return }
    }
    try {
        $msg = Install-Everything
        $statusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
        $statusText.Text = "Installed and started. $msg"
        Show-View
        Update-ManagerStatus
    } catch {
        $statusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FF6B5C")
        $statusText.Text = "Install failed: $($_.Exception.Message)"
    }
})

$startBtn.Add_Click({ Start-Widget; Start-Sleep -Milliseconds 500; Update-ManagerStatus })
$stopBtn.Add_Click({ Stop-Widget; Start-Sleep -Milliseconds 300; Update-ManagerStatus })
$startupCheck.Add_Click({
    Set-StartWithWindows([bool]$startupCheck.IsChecked)
    $statusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
    $statusText.Text = if ($startupCheck.IsChecked) { "Widget will launch automatically at login." } else { "Removed from Windows startup." }
})

$themeOneLineRadio.Add_Checked({
    Set-Layout "oneline"
    $statusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
    $statusText.Text = "Switched to one-line layout."
})
$themeStackedRadio.Add_Checked({
    Set-Layout "stacked"
    $statusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
    $statusText.Text = "Switched to stacked layout."
})

$uninstallBtn.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "This removes the widget completely: stops it, undoes its statusline hook, and deletes every file it created (this app stays so you can reinstall later). Continue?",
        "Uninstall Claude Usage Widget", "YesNo", "Warning")
    if ($result -ne "Yes") { return }
    try {
        Uninstall-Everything
        $statusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#7CD97C")
        $statusText.Text = "Uninstalled."
        Show-View
        Update-StatuslineTabStatus
    } catch {
        $statusText.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString("#FF6B5C")
        $statusText.Text = "Uninstall failed: $($_.Exception.Message)"
    }
})

$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(2)
$timer.Add_Tick({
    if ($managerPanel.Visibility -eq "Visible") { Update-ManagerStatus }
    Update-StatuslineTabStatus
    Update-AiTabStatus
})
$timer.Start()

Show-View
Update-ManagerStatus
Update-StatuslineTabStatus
Update-AiTabStatus
$window.ShowDialog() | Out-Null