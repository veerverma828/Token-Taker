Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$cacheFile = "$env:USERPROFILE\.claude\.statusline_ratelimit_cache.json"

function Format-ResetIn($epochSeconds) {
    if (-not $epochSeconds) { return "?" }
    try {
        $resetTime = [DateTimeOffset]::FromUnixTimeSeconds([long]$epochSeconds).LocalDateTime
    } catch {
        return "?"
    }
    $span = $resetTime - (Get-Date)
    if ($span.TotalSeconds -le 0) { return "now" }
    if ($span.TotalHours -ge 24) { return "$([math]::Floor($span.TotalDays))d$($span.Hours)h" }
    if ($span.TotalHours -ge 1) { return "$([math]::Floor($span.TotalHours))h$($span.Minutes)m" }
    return "$($span.Minutes)m"
}

function Get-AccentColor($p) {
    if ($p -ge 90) { return [System.Drawing.Color]::FromArgb(255,90,90) }
    if ($p -ge 70) { return [System.Drawing.Color]::FromArgb(240,187,74) }
    return [System.Drawing.Color]::FromArgb(88,199,133)
}

function Get-RoundedRect($rect, $radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc($rect.X, $rect.Y, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Y, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.X, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()
    return $path
}

$lblFont = New-Object System.Drawing.Font "Segoe UI Semibold", 7
$numFont = New-Object System.Drawing.Font "Consolas", 8.5

$centerFmt = New-Object System.Drawing.StringFormat
$centerFmt.LineAlignment = [System.Drawing.StringAlignment]::Center
$centerFmt.Alignment = [System.Drawing.StringAlignment]::Near

$measureBmp = New-Object System.Drawing.Bitmap 1,1
$mg = [System.Drawing.Graphics]::FromImage($measureBmp)

$padX = 12
$gapAfterLabel = 6
$trackW = 44
$trackH = 4
$gapAfterTrack = 7
$gapAfterPct = 4
$gapSegToDiv = 8
$divW = 1
$gapDivToSeg = 12
$pillH = 30

function Measure-Segment($label, $pctStr, $resetTxt) {
    $lblW = $mg.MeasureString($label, $lblFont).Width
    $pctW = $mg.MeasureString($pctStr, $numFont).Width
    $subW = $mg.MeasureString($resetTxt, $lblFont).Width
    return $lblW + $gapAfterLabel + $trackW + $gapAfterTrack + $pctW + $gapAfterPct + $subW
}

$script:lastGoodData = [PSCustomObject]@{
    fiveH       = 0
    sevenD      = 0
    fiveHReset  = "?"
    sevenDReset = "?"
}

function Get-Data {
    $c = $null
    if (Test-Path $cacheFile) {
        for ($i = 0; $i -lt 3 -and -not $c; $i++) {
            try { $c = Get-Content $cacheFile -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { Start-Sleep -Milliseconds 30 }
        }
    }
    if (-not $c) { return $script:lastGoodData }

    try {
        $data = [PSCustomObject]@{
            fiveH       = if ($c.fiveH) { [double]$c.fiveH } else { 0 }
            sevenD      = if ($c.sevenD) { [double]$c.sevenD } else { 0 }
            fiveHReset  = Format-ResetIn $c.fiveHResetsAt
            sevenDReset = Format-ResetIn $c.sevenDResetsAt
        }
    } catch {
        return $script:lastGoodData
    }

    $script:lastGoodData = $data
    return $data
}

# ---- window ----
$form = New-Object System.Windows.Forms.Form
$form.AutoScaleMode = 'None'
$form.FormBorderStyle = 'None'
$form.StartPosition = 'Manual'
$form.ShowInTaskbar = $false
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(1,1,1)
$form.TransparencyKey = [System.Drawing.Color]::FromArgb(1,1,1)
$form.Height = $pillH

$dbProp = [System.Windows.Forms.Control].GetProperty('DoubleBuffered', [System.Reflection.BindingFlags]'Instance,NonPublic')
$dbProp.SetValue($form, $true, $null)
$setStyle = [System.Windows.Forms.Control].GetMethod('SetStyle', [System.Reflection.BindingFlags]'Instance,NonPublic')
$styles = [System.Windows.Forms.ControlStyles]'AllPaintingInWmPaint,UserPaint,OptimizedDoubleBuffer,ResizeRedraw'
$setStyle.Invoke($form, @($styles, $true))

$tip = New-Object System.Windows.Forms.ToolTip
$tip.InitialDelay = 200
$tip.ReshowDelay = 200

function Draw-Segment($g, $x, $label, $pct, $resetTxt) {
    $accent = Get-AccentColor $pct
    $lblBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(120,124,132))
    $numBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $subBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(140,144,152))

    $rowRect = New-Object System.Drawing.RectangleF $x, 0, 300, $pillH
    $lblW = $g.MeasureString($label, $lblFont).Width
    $g.DrawString($label, $lblFont, $lblBrush, $rowRect, $centerFmt)
    $cursorX = $x + $lblW + $gapAfterLabel

    $trackY = [math]::Floor(($pillH - $trackH) / 2)
    $trackRect = New-Object System.Drawing.Rectangle ([int]$cursorX), $trackY, $trackW, $trackH
    $trackPath = Get-RoundedRect $trackRect ($trackH/2)
    $trackBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(58,58,64))
    $g.FillPath($trackBrush, $trackPath)
    $fillW = [math]::Max([math]::Round($trackW * ([math]::Min($pct,100)/100)), $trackH)
    if ($pct -gt 0) {
        $fillRect = New-Object System.Drawing.Rectangle ([int]$cursorX), $trackY, $fillW, $trackH
        $fillPath = Get-RoundedRect $fillRect ($trackH/2)
        $fillBrush = New-Object System.Drawing.SolidBrush $accent
        $g.FillPath($fillBrush, $fillPath)
        $fillBrush.Dispose(); $fillPath.Dispose()
    }
    $trackPath.Dispose()
    $cursorX += $trackW + $gapAfterTrack

    $pctStr = "$([math]::Round($pct))%"
    $pctRect = New-Object System.Drawing.RectangleF $cursorX, 0, 60, $pillH
    $g.DrawString($pctStr, $numFont, $numBrush, $pctRect, $centerFmt)
    $pctW = $g.MeasureString($pctStr, $numFont).Width
    $cursorX += $pctW + $gapAfterPct

    $subRect = New-Object System.Drawing.RectangleF $cursorX, 0, 80, $pillH
    $g.DrawString($resetTxt, $lblFont, $subBrush, $subRect, $centerFmt)
    $subW = $g.MeasureString($resetTxt, $lblFont).Width
    $cursorX += $subW

    $lblBrush.Dispose(); $numBrush.Dispose(); $subBrush.Dispose(); $trackBrush.Dispose()
    return $cursorX
}

$form.Add_Paint({
    param($s, $e)
    try {
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        $d = Get-Data
        $pctA = "$([math]::Round($d.fiveH))%"
        $pctB = "$([math]::Round($d.sevenD))%"
        $segA = Measure-Segment "5H" $pctA $d.fiveHReset
        $segB = Measure-Segment "7D" $pctB $d.sevenDReset
        $pillW = [int][math]::Ceiling($padX + $segA + $gapSegToDiv + $divW + $gapDivToSeg + $segB + $padX)

        if ($form.Width -ne $pillW) {
            $form.Left = $form.Left + $form.Width - $pillW
            $form.Width = $pillW
            $form.Invalidate()
            return
        }

        $rect = New-Object System.Drawing.Rectangle 0, 0, ($pillW-1), ($pillH-1)
        $pillPath = Get-RoundedRect $rect ($pillH/2)
        $bgBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(238,20,21,25))
        $g.FillPath($bgBrush, $pillPath)
        $borderPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(55,255,255,255)), 1
        $g.DrawPath($borderPen, $pillPath)

        $x = $padX
        $x = Draw-Segment $g $x "5H" $d.fiveH $d.fiveHReset
        $x += $gapSegToDiv

        $divPen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(60,255,255,255)), 1
        $g.DrawLine($divPen, $x, 7, $x, $pillH - 7)
        $divPen.Dispose()
        $x += $divW + $gapDivToSeg

        Draw-Segment $g $x "7D" $d.sevenD $d.sevenDReset | Out-Null

        $script:tip.SetToolTip($form, "5-hour limit resets $($d.fiveHReset)`n7-day limit resets $($d.sevenDReset)")

        $borderPen.Dispose(); $bgBrush.Dispose(); $pillPath.Dispose()
    } catch {}
})

$screen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Width = 300
$form.Location = New-Object System.Drawing.Point ($screen.Right - $form.Width - 10), ($screen.Bottom - $pillH - 6)

# drag to reposition
$dragging = $false
$dragStart = New-Object System.Drawing.Point 0,0
$form.Add_MouseDown({
    param($s,$e)
    $script:dragging = $true
    $script:dragStart = New-Object System.Drawing.Point $e.X, $e.Y
})
$form.Add_MouseMove({
    param($s,$e)
    if ($script:dragging) {
        $form.Location = New-Object System.Drawing.Point ($form.Left + $e.X - $script:dragStart.X), ($form.Top + $e.Y - $script:dragStart.Y)
    }
})
$form.Add_MouseUp({ $script:dragging = $false })

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$menu.Items.Add("Exit").Add_Click({ [System.Windows.Forms.Application]::Exit() }) | Out-Null
$form.ContextMenuStrip = $menu

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000
$timer.Add_Tick({ try { $form.Invalidate() } catch {} })
$timer.Start()

[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({ param($s,$e) })
[System.AppDomain]::CurrentDomain.add_UnhandledException({ param($s,$e) })

[System.Windows.Forms.Application]::Run($form)
