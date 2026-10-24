<#
OptiScaler 面板。

放在游戏目录里用：显示当前注入名，点一下即可切换；顺带给出 Wiki 推荐、
OptiPatcher 状态，以及 Mochizuki 画面分享码的导入导出。

用法：
  双击同目录的「OptiScaler面板.bat」
  proxy-gui.ps1 -SelfTest     只跑分享码自检
#>
param(
    [string] $Dir = $PSScriptRoot,
    [switch] $SelfTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

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
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { throw "找不到 OptiScaler.ini" }
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
                Name = $n
                Path = $f
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

# ---------------------------------------------------------------- theme
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    Add-Type 'using System.Runtime.InteropServices; public class Dpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
    [void][Dpi]::SetProcessDPIAware()
} catch { }

$ClrBack = [System.Drawing.Color]::FromArgb(24, 24, 27)
$ClrCard = [System.Drawing.Color]::FromArgb(36, 36, 40)
$ClrCardHover = [System.Drawing.Color]::FromArgb(52, 52, 58)
$ClrText = [System.Drawing.Color]::FromArgb(232, 232, 235)
$ClrMuted = [System.Drawing.Color]::FromArgb(140, 140, 148)
$ClrAccent = [System.Drawing.Color]::FromArgb(10, 132, 255)
$ClrOk = [System.Drawing.Color]::FromArgb(48, 209, 88)
$ClrBad = [System.Drawing.Color]::FromArgb(255, 105, 97)
$FontTitle = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
$FontSub = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$FontSmall = New-Object System.Drawing.Font('Microsoft YaHei UI', 8.5)
$FontBtn = New-Object System.Drawing.Font('Microsoft YaHei UI', 9.5)
$FontCode = New-Object System.Drawing.Font('Consolas', 9)

function New-Card([int]$x, [int]$y, [int]$w, [int]$h) {
    $p = New-Object System.Windows.Forms.Panel
    $p.Location = New-Object System.Drawing.Point($x, $y)
    $p.Size = New-Object System.Drawing.Size($w, $h)
    $p.BackColor = $ClrCard
    return $p
}

function New-FlatButton([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    $b.FlatStyle = 'Flat'
    $b.FlatAppearance.BorderSize = 0
    $b.BackColor = $ClrCard
    $b.ForeColor = $ClrText
    $b.Font = $FontBtn
    $b.Cursor = 'Hand'
    $b.FlatAppearance.MouseOverBackColor = $ClrCardHover
    $b.FlatAppearance.MouseDownBackColor = $ClrAccent
    return $b
}

# ---------------------------------------------------------------- window
$form = New-Object System.Windows.Forms.Form
$form.Text = 'OptiScaler 面板'
$form.ClientSize = New-Object System.Drawing.Size(540, 470)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $ClrBack
$form.ForeColor = $ClrText
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.Font = $FontSub

$title = New-Object System.Windows.Forms.Label
$title.Text = 'OptiScaler'
$title.Font = $FontTitle
$title.ForeColor = $ClrText
$title.Location = New-Object System.Drawing.Point(22, 16)
$title.AutoSize = $true
$form.Controls.Add($title)

$sub = New-Object System.Windows.Forms.Label
$sub.Text = Split-Path $Dir -Leaf
$sub.Font = $FontSub
$sub.ForeColor = $ClrMuted
$sub.Location = New-Object System.Drawing.Point(24, 50)
$sub.AutoSize = $true
$form.Controls.Add($sub)

$lblInject = New-Object System.Windows.Forms.Label
$lblInject.Text = '注入名'
$lblInject.Font = $FontSmall
$lblInject.ForeColor = $ClrMuted
$lblInject.Location = New-Object System.Drawing.Point(24, 82)
$lblInject.AutoSize = $true
$form.Controls.Add($lblInject)

$gridPanel = New-Object System.Windows.Forms.Panel
$gridPanel.Location = New-Object System.Drawing.Point(18, 100)
$gridPanel.Size = New-Object System.Drawing.Size(504, 128)
$gridPanel.BackColor = $ClrBack
$form.Controls.Add($gridPanel)

$infoCard = New-Card 18 238 504 74
$form.Controls.Add($infoCard)

$lblWiki = New-Object System.Windows.Forms.Label
$lblWiki.Text = 'Wiki：'
$lblWiki.ForeColor = $ClrMuted
$lblWiki.Font = $FontSmall
$lblWiki.Location = New-Object System.Drawing.Point(12, 10)
$lblWiki.AutoSize = $true
$infoCard.Controls.Add($lblWiki)

$lblOpti = New-Object System.Windows.Forms.Label
$lblOpti.Text = 'OptiPatcher：'
$lblOpti.ForeColor = $ClrMuted
$lblOpti.Font = $FontSmall
$lblOpti.Location = New-Object System.Drawing.Point(12, 32)
$lblOpti.AutoSize = $true
$infoCard.Controls.Add($lblOpti)

$lblExe = New-Object System.Windows.Forms.Label
$lblExe.Text = '游戏：'
$lblExe.ForeColor = $ClrMuted
$lblExe.Font = $FontSmall
$lblExe.Location = New-Object System.Drawing.Point(12, 52)
$lblExe.AutoSize = $true
$infoCard.Controls.Add($lblExe)

$lblShare = New-Object System.Windows.Forms.Label
$lblShare.Text = '画面分享'
$lblShare.Font = $FontSmall
$lblShare.ForeColor = $ClrMuted
$lblShare.Location = New-Object System.Drawing.Point(24, 326)
$lblShare.AutoSize = $true
$form.Controls.Add($lblShare)

$btnExport = New-FlatButton '晒出我的画面' 18 344 170 34
$btnImport = New-FlatButton '换上同款画面' 196 344 170 34
$btnFolder = New-FlatButton '打开目录' 374 344 148 34
$form.Controls.Add($btnExport)
$form.Controls.Add($btnImport)
$form.Controls.Add($btnFolder)

$codeBox = New-Object System.Windows.Forms.TextBox
$codeBox.Location = New-Object System.Drawing.Point(18, 386)
$codeBox.Size = New-Object System.Drawing.Size(504, 26)
$codeBox.Font = $FontCode
$codeBox.BackColor = $ClrCard
$codeBox.ForeColor = $ClrText
$codeBox.BorderStyle = 'FixedSingle'
$form.Controls.Add($codeBox)

$status = New-Object System.Windows.Forms.Label
$status.Text = ''
$status.Font = $FontSmall
$status.ForeColor = $ClrMuted
$status.Location = New-Object System.Drawing.Point(20, 424)
$status.Size = New-Object System.Drawing.Size(500, 34)
$form.Controls.Add($status)

# ---------------------------------------------------------------- state
$script:Cards = @{}
$script:Current = $null

function Set-Status([string] $text, $color) {
    $status.Text = $text
    $status.ForeColor = if ($color) { $color } else { $ClrMuted }
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-UI {
    $rows = @(Get-LoaderInfo)
    $script:Current = ($rows | Where-Object { $_.Ours } | Select-Object -First 1)
    $occ = @($rows | Where-Object { -not $_.Ours })
    $profile = Get-ProfileHit
    $recommend = if ($profile) { [string]$profile.preferred } elseif ($script:Current) { $script:Current.Name + '.dll' } else { '' }

    $gridPanel.Controls.Clear()
    $script:Cards = @{}
    $w = 158; $h = 56; $gap = 12
    for ($i = 0; $i -lt $Candidates.Count; $i++) {
        $name = $Candidates[$i]
        $col = $i % 3
        $row = [math]::Floor($i / 3)
        $x = $col * ($w + $gap)
        $y = $row * ($h + $gap)
        $isOurs = $script:Current -and $script:Current.Name -eq $name
        $isOcc = $occ | Where-Object { $_.Name -eq $name }
        $isRec = $recommend -eq ($name + '.dll')

        $b = New-FlatButton '' $x $y $w $h
        $b.Font = $FontSub
        $b.TextAlign = 'MiddleLeft'
        $label = "$name.dll"
        $sub2 = if ($isOurs) { "当前注入  $($script:Current.MB) MB" }
                elseif ($isOcc) { "被占用  $($isOcc.MB) MB" }
                elseif ($isRec) { '推荐' }
                else { '' }
        $b.Text = "  $label`r`n  $sub2"
        if ($isOurs) {
            $b.BackColor = [System.Drawing.Color]::FromArgb(32, 58, 40)
            $b.ForeColor = $ClrOk
        } elseif ($isOcc) {
            $b.ForeColor = $ClrBad
        } elseif ($isRec) {
            $b.ForeColor = $ClrAccent
        }
        $b.Tag = $name
        $b.Add_Click({
            param($s, $e)
            Switch-To ([string]$s.Tag)
        })
        $gridPanel.Controls.Add($b)
        $script:Cards[$name] = $b
    }

    if ($profile) {
        $lblWiki.Text = "Wiki：首选 $($profile.preferred)　备选 " + (($profile.alternatives) -join ' / ')
    } else {
        $lblWiki.Text = 'Wiki：无此游戏记录'
    }
    $asi = @((Join-Path $Dir 'plugins\OptiPatcher.asi'), (Join-Path $Dir 'OptiScaler\plugins\OptiPatcher.asi')) |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    $lblOpti.Text = if ($asi) { 'OptiPatcher：已安装' } else { 'OptiPatcher：未安装' }
    $exe = Resolve-GameExe $Dir
    $lblExe.Text = if ($exe) { "游戏：$($exe.Name)" } else { '游戏：未找到 EXE' }
}

function Switch-To([string] $target) {
    $rows = @(Get-LoaderInfo)
    $cur = $rows | Where-Object { $_.Ours } | Select-Object -First 1
    if (-not $cur) { Set-Status '目录里没有找到 OptiScaler 的注入（版本信息不是 OptiScaler）。' $ClrBad; return }
    if ($cur.Name -eq $target) { Set-Status '已经是这个注入名了。'; return }

    $dest = Join-Path $Dir ($target + '.dll')
    if (Test-Path -LiteralPath $dest -PathType Leaf) {
        if (Test-IsOurInjection $dest) {
            $r = [System.Windows.Forms.MessageBox]::Show("$target.dll 已经是旧的注入，删除它并改用当前这份？", '确认', 'YesNo', 'Question')
            if ($r -ne 'Yes') { return }
            Remove-Item -LiteralPath $dest -Force
        } else {
            Set-Status "$target.dll 被游戏或其它 mod 占用，不覆盖。换一个。" $ClrBad
            return
        }
    }
    try {
        Move-Item -LiteralPath $cur.Path -Destination $dest
        Set-Status "已切换到 $target.dll，重启游戏生效。" $ClrOk
    } catch {
        Set-Status "切换失败：$($_.Exception.Message)" $ClrBad
    }
    Update-UI
}

$btnFolder.Add_Click({ Start-Process explorer.exe $Dir })

$btnExport.Add_Click({
    $ini = Join-Path $Dir 'OptiScaler.ini'
    if (-not (Test-Path -LiteralPath $ini)) { Set-Status '当前目录没有 OptiScaler.ini。' $ClrBad; return }
    $values = Read-MzValues $ini
    if ($values.Count -eq 0) { Set-Status '没有改过 Mochizuki 参数，生成的码是空的。'; return }
    $exe = Resolve-GameExe $Dir
    $game = if ($exe) { [IO.Path]::GetFileNameWithoutExtension($exe.Name) } else { '' }
    $code = Encode-MzCode $values $game
    $codeBox.Text = $code
    try { [System.Windows.Forms.Clipboard]::SetText($code) } catch { }
    Set-Status '分享码已复制，发到群里让别人粘贴。' $ClrOk
})

$btnImport.Add_Click({
    $raw = $codeBox.Text
    if (-not $raw) { try { $raw = [System.Windows.Forms.Clipboard]::GetText() } catch { } }
    if (-not $raw) { Set-Status '先粘贴一段分享文字或码。' $ClrBad; return }
    try { $decoded = Decode-MzCode $raw }
    catch { Set-Status "分享码无效：$($_.Exception.Message)" $ClrBad; return }
    $style = if ($decoded.Values.ContainsKey(1)) { [int]$decoded.Values[1] } else { 0 }
    $name = @('标准', '自然', '电影感')[[math]::Max(0, [math]::Min(2, $style))]
    $summary = "风格 $name · 修改 $($decoded.Values.Count) 项"
    if ($decoded.GameTag) { $summary += " · 来自 $($decoded.GameTag)" }
    $r = [System.Windows.Forms.MessageBox]::Show("识别到：$summary`n`n应用到当前游戏？", '确认', 'YesNo', 'Question')
    if ($r -ne 'Yes') { return }
    $ini = Join-Path $Dir 'OptiScaler.ini'
    try {
        $backup = Apply-MzCode $ini $decoded
        Set-Status "已换上这套画面（备份 $(Split-Path -Leaf $backup)），重启游戏生效。" $ClrOk
    } catch { Set-Status "应用失败：$($_.Exception.Message)" $ClrBad }
})

$form.Add_Shown({ Update-UI })
[void]$form.ShowDialog()
