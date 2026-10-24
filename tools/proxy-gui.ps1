<#
OptiScaler 面板（游戏目录用）。

配色与卡片尺寸照上游 Launcher 的 Dark 调色板（LauncherTheme.cs）：
  背景 #0E1117 · 卡片 #161B22 · 描边 #30363D · 正文 #F0F6FC
  次要 #9BA8BA · 强调 #E3122B · 成功 #4ADE80
功能沿用上游的 IniProfiles 思路（保存/套用整套 ini 预设）与 MochizukiShareCode（MZ1/2/3）。

双击同目录的「OptiScaler面板.bat」启动；proxy-gui.ps1 -SelfTest 只跑分享码自检。
#>
param(
    [string] $Dir = $PSScriptRoot,
    [switch] $SelfTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Drawing
try { Add-Type -AssemblyName Microsoft.VisualBasic } catch { }

# ---------------------------------------------------------------- palette
$ClrBg = [System.Drawing.ColorTranslator]::FromHtml('#0E1117')
$ClrSurface = [System.Drawing.ColorTranslator]::FromHtml('#161B22')
$ClrSubtle = [System.Drawing.ColorTranslator]::FromHtml('#1F242D')
$ClrInk = [System.Drawing.ColorTranslator]::FromHtml('#F0F6FC')
$ClrMuted = [System.Drawing.ColorTranslator]::FromHtml('#9BA8BA')
$ClrBorder = [System.Drawing.ColorTranslator]::FromHtml('#30363D')
$ClrAccent = [System.Drawing.ColorTranslator]::FromHtml('#E3122B')
$ClrHover = [System.Drawing.ColorTranslator]::FromHtml('#29313E')
$ClrSuccess = [System.Drawing.ColorTranslator]::FromHtml('#4ADE80')
$ClrSuccessBg = [System.Drawing.ColorTranslator]::FromHtml('#172E23')
$ClrWarning = [System.Drawing.ColorTranslator]::FromHtml('#FFCA70')
$ClrWarningBg = [System.Drawing.ColorTranslator]::FromHtml('#392D18')

# ---------------------------------------------------------------- look codes
$keyFile = Join-Path $PSScriptRoot 'mz-keys.psd1'
$MzKeys = $null
if (Test-Path -LiteralPath $keyFile) { $MzKeys = (Import-PowerShellDataFile $keyFile)['Keys'] }

function Get-MzCrc16([string] $payload) {
    $crc = 0xFFFF
    foreach ($b in [Text.Encoding]::UTF8.GetBytes($payload)) {
        $crc = ($crc -bxor ([int]$b -shl 8)) -band 0xFFFF
        for ($i = 0; $i -lt 8; $i++) {
            if ($crc -band 0x8000) { $crc = (($crc -shl 1) -bxor 0x1021) -band 0xFFFF }
            else { $crc = ($crc -shl 1) -band 0xFFFF }
        }
    }
    return $crc
}

function ConvertTo-MzNumber([string] $text, $key) {
    if ($text.Trim() -eq 'auto') { return [double]$key[3] }
    if ($key[2] -eq 'Bool') {
        if ($text -match '^(?i)(true|1)$') { return [double]1 }
        if ($text -match '^(?i)(false|0)$') { return [double]0 }
        return $null
    }
    $v = 0.0
    if (-not [double]::TryParse($text.Trim(), [ref]$v)) { return $null }
    if ($key[2] -eq 'Int' -and $v -ne [math]::Truncate($v)) { return $null }
    return $v
}

function Format-MzValue($key, [double] $value) {
    if ($key[2] -eq 'Bool') { return $(if ($value -ge 0.5) { 'true' } else { 'false' }) }
    if ($key[2] -eq 'Int') { return ([int][math]::Round($value)).ToString([Globalization.CultureInfo]::InvariantCulture) }
    return $value.ToString('0.0##', [Globalization.CultureInfo]::InvariantCulture)
}

function Read-MzValues([string] $iniPath) {
    $values = @{}
    if (-not $MzKeys -or -not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { return $values }
    $text = [IO.File]::ReadAllText($iniPath)
    $inSection = $false
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s*\[([^\]]+)\]') { $inSection = ([string]$matches[1]).Trim() -eq 'DlssNr'; continue }
        if (-not $inSection) { continue }
        if ($line -notmatch '^\s*([^=;#]+?)\s*=\s*([^;#]*)') { continue }
        $name = $matches[1].Trim()
        foreach ($k in $MzKeys) {
            if ($k[1] -ne $name) { continue }
            $n = ConvertTo-MzNumber $matches[2] $k
            if ($null -ne $n) { $values[[int]$k[0]] = [double]$n }
            break
        }
    }
    return $values
}

function Encode-MzCode($values, [string] $game = '', [string] $note = '') {
    $pairs = New-Object System.Collections.Generic.List[string]
    foreach ($k in $MzKeys) {
        $idx = [int]$k[0]
        if (-not $values.ContainsKey($idx)) { continue }
        $v = [double]$values[$idx]
        if ($k[2] -eq 'Float') {
            $raw = [double][math]::Round($v * 100, 0, [MidpointRounding]::AwayFromZero)
            if ($raw / 100 -eq [double]$k[3]) { continue }
            $pairs.Add(("{0}={1}" -f $idx, ([int]$raw)))
        } else {
            if ($v -eq [double]$k[3]) { continue }
            $pairs.Add(("{0}={1}" -f $idx, ([int]$v)))
        }
    }
    $payload = $pairs -join ','
    $tag = if ($game) { $game } else { '' }
    if ($note) {
        $noted = "$payload|$tag|$note"
        return 'MZ3:' + $noted + ';' + (Get-MzCrc16 $noted).ToString('X4')
    }
    if (-not $tag) { return 'MZ1:' + $payload + ';' + (Get-MzCrc16 $payload).ToString('X4') }
    $tagged = "$payload|$tag"
    return 'MZ2:' + $tagged + ';' + (Get-MzCrc16 $tagged).ToString('X4')
}

function Decode-MzCode([string] $code) {
    if ($code -match '(MZ[123]:[^\r\n]+)') { $code = $matches[1] }
    $code = $code.Trim()
    if ($code -notmatch '^(MZ1|MZ2|MZ3):') { throw '不是分享码（应以 MZ1/MZ2/MZ3 开头）' }
    $kind = $matches[1]
    $end = $code.LastIndexOf(';')
    if ($end -lt 4 -or $code.Length -ne $end + 5) { throw '格式不完整' }
    $crc = 0
    if (-not [int]::TryParse($code.Substring($end + 1), [Globalization.NumberStyles]::AllowHexSpecifier, $null, [ref]$crc)) { throw 'CRC 不是十六进制' }
    $payload = $code.Substring(4, $end - 4)
    if ((Get-MzCrc16 $payload) -ne $crc) { throw '校验失败（复制不完整）' }
    $game = ''; $note = ''
    if ($kind -eq 'MZ3') {
        $parts = $payload.Split('|')
        if ($parts.Count -ne 3 -or -not $parts[2]) { throw 'MZ3 格式错误' }
        $payload = $parts[0]; $game = $parts[1]; $note = $parts[2]
    } elseif ($kind -eq 'MZ2') {
        $parts = $payload.Split('|')
        if ($parts.Count -ne 2 -or -not $parts[1]) { throw 'MZ2 格式错误' }
        $payload = $parts[0]; $game = $parts[1]
    }
    $values = @{}
    if ($payload) {
        foreach ($pair in $payload.Split(',')) {
            if ($pair -notmatch '^(\d+)=(-?\d+)$') { throw "条目格式错误：$pair" }
            $idx = [int]$matches[1]; $raw = [double]$matches[2]
            if ($idx -lt 0 -or $idx -ge $MzKeys.Count) { throw "索引越界：$idx" }
            $k = $MzKeys[$idx]
            $v = if ($k[2] -eq 'Float') { $raw / 100 } else { $raw }
            $tol = if ($k[2] -eq 'Float') { 0.01 } else { 0 }
            if ($v -lt ([double]$k[4] - $tol) -or $v -gt ([double]$k[5] + $tol)) { throw "数值越界：$($k[1])=$v" }
            $values[$idx] = [math]::Max([double]$k[4], [math]::Min([double]$k[5], $v))
        }
    }
    return [pscustomobject]@{ Kind = $kind; Values = $values; GameTag = $game; Note = $note }
}

function Set-KeyInSection([string] $text, [string] $section, [string] $name, [string] $value) {
    $pattern = "(?ms)^(\[$([regex]::Escape($section))\][^\r\n]*\r?\n)(.*?)(?=^\[|\z)"
    if ($text -notmatch $pattern) { return $text.TrimEnd() + "`r`n`r`n[$section]`r`n$name=$value`r`n" }
    $head = $matches[1]; $body = $matches[2]
    if ($body -match "(?m)^\s*$([regex]::Escape($name))\s*=") {
        $body = $body -replace "(?m)^(\s*$([regex]::Escape($name))\s*=\s*)[^\r\n]*", "`$1$value"
    } else {
        $body = $body.TrimEnd() + "`r`n$name=$value`r`n"
    }
    return $head + $body
}

function Apply-MzCode([string] $iniPath, $decoded) {
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { throw '找不到 OptiScaler.ini' }
    $text = [IO.File]::ReadAllText($iniPath)
    $backup = "$iniPath.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $iniPath -Destination $backup -Force
    foreach ($idx in $decoded.Values.Keys) {
        $k = $MzKeys[$idx]
        $text = Set-KeyInSection $text 'DlssNr' $k[1] (Format-MzValue $k $decoded.Values[$idx])
    }
    [IO.File]::WriteAllText($iniPath, $text, (New-Object Text.UTF8Encoding($false)))
    return $backup
}

if ($SelfTest) {
    if (-not $MzKeys) { throw 'mz-keys.psd1 缺失' }
    $v = @{ 1 = 2.0; 0 = 1.35; 135 = 1.0 }
    $code = Encode-MzCode $v 'Neverness To Everness'
    "encode: $code"
    $d = Decode-MzCode $code
    "decode: style=$($d.Values[1]) intensity=$($d.Values[0]) wp=$($d.Values[135]) game=$($d.GameTag)"
    "empty:  " + (Encode-MzCode @{})
    try { Decode-MzCode ($code.Substring(0, $code.Length - 2) + '00') | Out-Null; 'crc: FAILED' } catch { 'crc: ok' }
    return
}

# ---------------------------------------------------------------- probe
$Candidates = @('dxgi', 'winmm', 'd3d12', 'winhttp', 'wininet', 'dbghelp', 'version')
$ExeExcludeStart = '(?i)^(setup|install|unins|crash|unitycrash|vc_redist|dxsetup|easyanticheat|eac_|battleye|beclient|beservice|unrealcef|webview|cefsubprocess|shadercompile|bugsplat|crs-|redprelauncher|larilauncher|2klauncher).*\.exe$'
$ExeExcludeEnd = '(?i)(prelauncher|launcher|crashreport|crashhandler|crs-handler|errorreporter|updater|patcher|uninstaller|benchmark|dedicatedserver)\.exe$'
$ExeExcludeName = '(?i)^(gamelaunchhelper|person-worker|activationui|cleanup|touchup|config)\.exe$'

function Get-ExeRank([string] $name) {
    if ($name -match '(?i)WinGDK-Shipping\.exe$') { return 0 }
    if ($name -match '(?i)-Win64-Shipping\.exe$') { return 1 }
    if ($name -match '(?i)Shipping\.exe$') { return 2 }
    return 3
}

function Resolve-GameExe([string] $folder) {
    Get-ChildItem -LiteralPath $folder -Filter *.exe -File -ErrorAction SilentlyContinue |
        Where-Object {
            $n = $_.Name
            ($n -notmatch $ExeExcludeStart) -and ($n -notmatch $ExeExcludeEnd) -and ($n -notmatch $ExeExcludeName)
        } |
        Sort-Object @{ Expression = { Get-ExeRank $_.Name } }, @{ Expression = { $_.Length }; Descending = $true } |
        Select-Object -First 1
}

function Test-IsOurInjection([string] $path) {
    try {
        $vi = (Get-Item -LiteralPath $path).VersionInfo
        if ($vi.ProductName -eq 'OptiScaler' -or $vi.FileDescription -eq 'OptiScaler') { return $true }
    } catch { }
    return $false
}

function Get-LoaderInfo {
    $rows = @()
    foreach ($n in $Candidates) {
        $f = Join-Path $Dir ($n + '.dll')
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            $rows += [pscustomobject]@{
                Name = $n; Path = $f
                MB   = [math]::Round((Get-Item -LiteralPath $f).Length / 1MB, 1)
                Ours = (Test-IsOurInjection $f)
            }
        }
    }
    return $rows
}

function Get-ProfileHit {
    $json = Join-Path $Dir 'proxy-profiles.json'
    if (-not (Test-Path -LiteralPath $json)) { return $null }
    try { $doc = Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
    $segs = @($Dir.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))
    foreach ($p in @($doc.profiles)) {
        foreach ($seg in @($p.pathSegments)) {
            $needle = [string]$seg
            if ($needle.Length -lt 4) { continue }
            foreach ($a in $segs) { if ($a.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $p } }
        }
    }
    return $null
}

# ---------------------------------------------------------------- presets (upstream IniProfiles idea)
$PresetDir = Join-Path $env:LOCALAPPDATA 'OptiScalerNR\profiles'

function Get-Presets {
    if (-not (Test-Path -LiteralPath $PresetDir)) { return @() }
    return @(Get-ChildItem -LiteralPath $PresetDir -Filter *.ini | Sort-Object Name | ForEach-Object { $_.BaseName })
}

function Save-Preset([string] $name) {
    $ini = Join-Path $Dir 'OptiScaler.ini'
    if (-not (Test-Path -LiteralPath $ini)) { throw '目录里没有 OptiScaler.ini' }
    if (-not (Test-Path -LiteralPath $PresetDir)) { [void][IO.Directory]::CreateDirectory($PresetDir) }
    $safe = ($name -replace '[\\/:*?"<>|]', '_').Trim()
    if (-not $safe) { throw '名字不能为空' }
    $dest = Join-Path $PresetDir ($safe + '.ini')
    Copy-Item -LiteralPath $ini -Destination $dest -Force
    return $safe
}

function Apply-Preset([string] $name) {
    $src = Join-Path $PresetDir ($name + '.ini')
    if (-not (Test-Path -LiteralPath $src)) { throw "预设不存在：$name" }
    $dst = Join-Path $Dir 'OptiScaler.ini'
    if (Test-Path -LiteralPath $dst) {
        Copy-Item -LiteralPath $dst -Destination ("$dst.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
    }
    Copy-Item -LiteralPath $src -Destination $dst -Force
}

# ---------------------------------------------------------------- theme helpers
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    Add-Type 'using System.Runtime.InteropServices; public class Dpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
    [void][Dpi]::SetProcessDPIAware()
} catch { }

$FontTitle = New-Object System.Drawing.Font('Microsoft YaHei UI', 15, [System.Drawing.FontStyle]::Bold)
$FontBody = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$FontSmall = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$FontCardTitle = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5, [System.Drawing.FontStyle]::Bold)
$FontCode = New-Object System.Drawing.Font('Consolas', 9)

function Set-RoundedRegion($ctrl, [int] $radius) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc($ctrl.Width - $d, 0, $d, $d, 270, 90)
    $p.AddArc($ctrl.Width - $d, $ctrl.Height - $d, $d, $d, 0, 90)
    $p.AddArc(0, $ctrl.Height - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    $ctrl.Region = New-Object System.Drawing.Region($p)
}

function New-Panel([int]$x, [int]$y, [int]$w, [int]$h, $color) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $(if ($color) { $color } else { $ClrSurface })
    Set-RoundedRegion $p 10
    return $p
}

function New-Flat([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $ClrSubtle
    $b.ForeColor = $ClrInk
    $b.Font = $FontBody
    $b.Cursor = 'Hand'
    $b.FlatAppearance.MouseOverBackColor = $ClrHover
    $b.FlatAppearance.MouseDownBackColor = $ClrAccent
    Set-RoundedRegion $b 8
    return $b
}

# ---------------------------------------------------------------- window
$form = New-Object System.Windows.Forms.Form
$form.Text = 'OptiScaler'
$form.ClientSize = New-Object System.Drawing.Size(560, 560)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $ClrBg
$form.ForeColor = $ClrInk
$form.Font = $FontBody
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

# logo + title
$logo = New-Object System.Windows.Forms.Label
$logo.Text = 'N'
$logo.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$logo.ForeColor = [System.Drawing.Color]::White
$logo.BackColor = $ClrAccent
$logo.TextAlign = 'MiddleCenter'
$logo.Location = New-Object System.Drawing.Point(20, 18)
$logo.Size = New-Object System.Drawing.Size(30, 30)
Set-RoundedRegion $logo 9
$form.Controls.Add($logo)

$title = New-Object System.Windows.Forms.Label
$title.Text = 'OptiScaler'
$title.Font = $FontTitle
$title.ForeColor = $ClrInk
$title.Location = New-Object System.Drawing.Point(60, 14)
$title.AutoSize = $true
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = ''
$sub.Font = $FontSmall
$sub.ForeColor = $ClrMuted
$sub.Location = New-Object System.Drawing.Point(62, 42)
$sub.AutoSize = $true
$form.Controls.Add($sub)

# injection grid
$lblInject = New-Object System.Windows.Forms.Label
$lblInject.Text = '注入名'
$lblInject.Font = $FontSmall
$lblInject.ForeColor = $ClrMuted
$lblInject.Location = New-Object System.Drawing.Point(22, 82)
$lblInject.AutoSize = $true
$form.Controls.Add($lblInject)

$grid = New-Object System.Windows.Forms.Panel
$grid.Location = New-Object System.Drawing.Point(16, 100)
$grid.Size = New-Object System.Drawing.Size(528, 140)
$grid.BackColor = $ClrBg
$form.Controls.Add($grid)

# info card
$info = New-Panel 16 250 528 84
$form.Controls.Add($info)

$lblWiki = New-Object System.Windows.Forms.Label
$lblWiki.Font = $FontSmall
$lblWiki.ForeColor = $ClrMuted
$lblWiki.Location = New-Object System.Drawing.Point(14, 12)
$lblWiki.Size = New-Object System.Drawing.Size(500, 20)
$info.Controls.Add($lblWiki)

$lblOpti = New-Object System.Windows.Forms.Label
$lblOpti.Font = $FontSmall
$lblOpti.ForeColor = $ClrMuted
$lblOpti.Location = New-Object System.Drawing.Point(14, 34)
$lblOpti.Size = New-Object System.Drawing.Size(500, 20)
$info.Controls.Add($lblOpti)

$lblExe = New-Object System.Windows.Forms.Label
$lblExe.Font = $FontSmall
$lblExe.ForeColor = $ClrMuted
$lblExe.Location = New-Object System.Drawing.Point(14, 56)
$lblExe.Size = New-Object System.Drawing.Size(500, 20)
$info.Controls.Add($lblExe)

# presets
$lblPreset = New-Object System.Windows.Forms.Label
$lblPreset.Text = '配置预设'
$lblPreset.Font = $FontSmall
$lblPreset.ForeColor = $ClrMuted
$lblPreset.Location = New-Object System.Drawing.Point(22, 348)
$lblPreset.AutoSize = $true
$form.Controls.Add($lblPreset)

$presetList = New-Object System.Windows.Forms.ComboBox
$presetList.DropDownStyle = 'DropDownList'
$presetList.Location = New-Object System.Drawing.Point(16, 366)
$presetList.Size = New-Object System.Drawing.Size(250, 26)
$presetList.BackColor = $ClrSubtle
$presetList.ForeColor = $ClrInk
$presetList.FlatStyle = 'Flat'
$form.Controls.Add($presetList)

$btnPresetApply = New-Flat '套用' 274 364 76 30
$btnPresetSave = New-Flat '保存当前' 356 364 96 30
$btnPresetDelete = New-Flat '删除' 458 364 64 30
$form.Controls.Add($btnPresetApply)
$form.Controls.Add($btnPresetSave)
$form.Controls.Add($btnPresetDelete)

# share
$lblShare = New-Object System.Windows.Forms.Label
$lblShare.Text = '画面分享'
$lblShare.Font = $FontSmall
$lblShare.ForeColor = $ClrMuted
$lblShare.Location = New-Object System.Drawing.Point(22, 408)
$lblShare.AutoSize = $true
$form.Controls.Add($lblShare)

$btnExport = New-Flat '晒出我的画面' 16 426 160 32
$btnImport = New-Flat '换上同款画面' 184 426 160 32
$btnFolder = New-Flat '打开目录' 352 426 92 32
$form.Controls.Add($btnExport)
$form.Controls.Add($btnImport)
$form.Controls.Add($btnFolder)

$codeBox = New-Object System.Windows.Forms.TextBox
$codeBox.Location = New-Object System.Drawing.Point(16, 466)
$codeBox.Size = New-Object System.Drawing.Size(528, 26)
$codeBox.Font = $FontCode
$codeBox.BackColor = $ClrSubtle
$codeBox.ForeColor = $ClrInk
$codeBox.BorderStyle = 'FixedSingle'
$form.Controls.Add($codeBox)

$status = New-Object System.Windows.Forms.Label
$status.Text = ''
$status.Font = $FontSmall
$status.ForeColor = $ClrMuted
$status.Location = New-Object System.Drawing.Point(18, 504)
$status.Size = New-Object System.Drawing.Size(528, 40)
$form.Controls.Add($status)

# ---------------------------------------------------------------- state
$script:Current = $null
$script:Profile = $null

function Set-Status([string] $text, $color) {
    $status.Text = $text
    $status.ForeColor = $(if ($color) { $color } else { $ClrMuted })
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-UI {
    $rows = @(Get-LoaderInfo)
    $script:Current = ($rows | Where-Object { $_.Ours } | Select-Object -First 1)
    $occ = @($rows | Where-Object { -not $_.Ours })
    $script:Profile = Get-ProfileHit
    $recommend = if ($script:Profile) { [string]$script:Profile.preferred } else { '' }

    $grid.Controls.Clear()
    $w = 160; $h = 62; $gap = 10
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $name = $Candidates[$i]
        $col = $i % 3
        $row = [math]::Floor($i / 3)
        $x = $col * ($w + $gap)
        $y = $row * ($h + $gap)
        $isOurs = $script:Current -and $script:Current.Name -eq $name
        $occRow = $occ | Where-Object { $_.Name -eq $name }
        $isRec = $recommend -eq ($name + '.dll')

        $b = New-Flat '' $x $y $w $h
        $b.TextAlign = 'MiddleLeft'
        $line1 = "  $name.dll"
        $line2 = if ($isOurs) { "  ● 当前注入" } elseif ($occRow) { "  ● 被占用" } elseif ($isRec) { "  ★ 推荐" } else { '' }
        $b.Text = "$line1`r`n$line2"
        $b.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9, [System.Drawing.FontStyle]::Regular)
        if ($isOurs) {
            $b.BackColor = $ClrSuccessBg
            $b.ForeColor = $ClrSuccess
        } elseif ($occRow) {
            $b.ForeColor = $ClrWarning
            $b.BackColor = $ClrWarningBg
        } elseif ($isRec) {
            $b.ForeColor = $ClrAccent
        }
        $b.Tag = $name
        $b.Add_Click({ param($s, $e) Switch-To ([string]$s.Tag) })
        $grid.Controls.Add($b)
    }

    $lblWiki.Text = if ($script:Profile) {
        "Wiki：首选 $($script:Profile.preferred)　备选 " + (@($script:Profile.alternatives) -join ' / ')
    } else { 'Wiki：无此游戏记录' }
    $asi = @((Join-Path $Dir 'plugins\OptiPatcher.asi'), (Join-Path $Dir 'OptiScaler\plugins\OptiPatcher.asi')) |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $lblOpti.Text = if ($asi) { 'OptiPatcher：已安装' } else { 'OptiPatcher：未安装' }
    $exe = Resolve-GameExe $Dir
    $lblExe.Text = if ($exe) { "游戏：$($exe.Name)" } else { '游戏：未找到 EXE' }
    $sub.Text = "$(Split-Path $Dir -Leaf)" + $(if ($exe) { " · $($exe.Name)" } else { '' })

    $presetList.Items.Clear()
    $names = @(Get-Presets)
    if ($names.Count -eq 0) { [void]$presetList.Items.Add('（还没有预设）') }
    else { foreach ($n in $names) { [void]$presetList.Items.Add($n) }; $presetList.SelectedIndex = 0 }
}

function Switch-To([string] $target) {
    $rows = @(Get-LoaderInfo)
    $cur = $rows | Where-Object { $_.Ours } | Select-Object -First 1
    if (-not $cur) { Set-Status '目录里没有找到 OptiScaler 的注入。' $ClrAccent; return }
    if ($cur.Name -eq $target) { Set-Status '已经是这个注入名了。'; return }
    $dest = Join-Path $Dir ($target + '.dll')
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
        if (Test-IsOurInjection $dest) {
            $r = [System.Windows.Forms.MessageBox]::Show("$target.dll 是旧的注入，删除它并改用当前这份？", '确认', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            Remove-Item -LiteralPath $dest -Force
        } else {
            Set-Status "$target.dll 被游戏或其它 mod 占用，不覆盖。" $ClrAccent
            return
        }
    }
    try {
        Move-Item -LiteralPath $cur.Path -Destination $dest
        Set-Status "已切换到 $target.dll，重启游戏生效。" $ClrSuccess
    } catch { Set-Status "切换失败：$($_.Exception.Message)" $ClrAccent }
    Update-UI
}

$btnFolder.Add_Click({ Start-Process explorer.exe $Dir })

$btnPresetSave.Add_Click({
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('预设名字', '保存配置', (Get-Date -Format 'yyyyMMdd-HHmm'))
    if (-not $name) { return }
    try {
        $saved = Save-Preset $name
        Set-Status "已保存预设「$saved」。" $ClrSuccess
        Update-UI
    } catch { Set-Status "保存失败：$($_.Exception.Message)" $ClrAccent }
})

$btnPresetApply.Add_Click({
    $name = [string]$presetList.SelectedItem
    if (-not $name -or $name -like '（*') { Set-Status '还没有可套用的预设。'; return }
    $r = [System.Windows.Forms.MessageBox]::Show("套用「$name」到当前游戏？`n`n当前 ini 会先备份。", '确认', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    try {
        Apply-Preset $name
        Set-Status "已套用「$name」，重启游戏生效。" $ClrSuccess
    } catch { Set-Status "套用失败：$($_.Exception.Message)" $ClrAccent }
})

$btnPresetDelete.Add_Click({
    $name = [string]$presetList.SelectedItem
    if (-not $name -or $name -like '（*') { return }
    $r = [System.Windows.Forms.MessageBox]::Show("删除预设「$name」？", '确认', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    Remove-Item -LiteralPath (Join-Path $PresetDir ($name + '.ini')) -Force -ErrorAction SilentlyContinue
    Set-Status "已删除「$name」。" $ClrMuted
    Update-UI
})

$btnExport.Add_Click({
    $ini = Join-Path $Dir 'OptiScaler.ini'
    if (-not (Test-Path -LiteralPath $ini)) { Set-Status '当前目录没有 OptiScaler.ini。' $ClrAccent; return }
    $values = Read-MzValues $ini
    if ($values.Count -eq 0) { Set-Status '没有改过 Mochizuki 参数，生成的码是空的。'; return }
    $exe = Resolve-GameExe $Dir
    $game = if ($exe) { [IO.Path]::GetFileNameWithoutExtension($exe.Name) } else { '' }
    $code = Encode-MzCode $values $game
    $codeBox.Text = $code
    try { [System.Windows.Forms.Clipboard]::SetText($code) } catch { }
    Set-Status '分享码已复制，发到群里让别人粘贴。' $ClrSuccess
})

$btnImport.Add_Click({
    $raw = $codeBox.Text
    if (-not $raw) { try { $raw = [System.Windows.Forms.Clipboard]::GetText() } catch { } }
    if (-not $raw) { Set-Status '先粘贴一段分享文字或码。' $ClrAccent; return }
    try { $decoded = Decode-MzCode $raw }
    catch { Set-Status "分享码无效：$($_.Exception.Message)" $ClrAccent; return }
    $style = if ($decoded.Values.ContainsKey(1)) { [int]$decoded.Values[1] } else { 0 }
    $name = @('标准', '自然', '电影感')[[math]::Max(0, [math]::Min(2, $style))]
    $summary = "风格 $name · 修改 $($decoded.Values.Count) 项"
    if ($decoded.GameTag) { $summary += " · 来自 $($decoded.GameTag)" }
    $r = [System.Windows.Forms.MessageBox]::Show("识别到：$summary`n`n应用到当前游戏？", '确认', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    try {
        $backup = Apply-MzCode (Join-Path $Dir 'OptiScaler.ini') $decoded
        Set-Status "已换上这套画面（备份 $(Split-Path -Leaf $backup)），重启游戏生效。" $ClrSuccess
    } catch { Set-Status "应用失败：$($_.Exception.Message)" $ClrAccent }
})

$form.Add_Shown({ Update-UI })
[void]$form.ShowDialog()
