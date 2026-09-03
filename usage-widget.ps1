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
