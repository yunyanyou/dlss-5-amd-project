<#
OptiScaler 快速安装器。

把游戏目录（含 EXE 的那一层）拖进窗口，选后端和注入名，点安装即可。
安装本身复用上游的 tools/install/launcher-worker.ps1，这里只做三件事：
  1. 探测游戏目录（EXE、已注入的 DLL、Wiki 推荐）
  2. 把选择写成 DecisionJson 交给 worker
  3. 读写 Mochizuki 画面分享码（MZ1 / MZ2 / MZ3）

用法：
  quick-launcher.ps1              打开窗口
  quick-launcher.ps1 -SelfTest    只跑分享码的编码/解码自检
#>
param(
    [string] $PackageRoot = $PSScriptRoot,
    [switch] $SelfTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

# ---------------------------------------------------------------- look codes
$MzData = Import-PowerShellDataFile (Join-Path $PSScriptRoot 'mz-keys.psd1')
$MzKeys = $MzData['Keys']
if (-not $MzKeys -or $MzKeys.Count -lt 100) { throw 'mz-keys.psd1 缺失或损坏' }

function Get-MzCrc16([string] $payload) {
    # CCITT-16, init 0xFFFF, poly 0x1021 — the exact loop the launcher uses.
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
    if ([string]::Equals($text.Trim(), 'auto', 'OrdinalIgnoreCase')) { return [double]$key[3] }
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
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { return $values }
    $text = [IO.File]::ReadAllText($iniPath)
    $inSection = $false
    foreach ($line in ($text -split "`r?`n")) {
        if ($line -match '^\s*\[([^\]]+)\]') {
            $inSection = ([string]$matches[1]).Trim() -eq 'DlssNr'
            continue
        }
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
    # Pull the code out of arbitrary chat text, but keep inner spaces: the game tag
    # ("Neverness To Everness") is part of the CRC. Only the ends are trimmed.
    if ($code -match '(MZ[123]:[^\r\n]+)') { $code = $matches[1] }
    $code = $code.Trim()
    if ($code -notmatch '^(MZ1|MZ2|MZ3):') { throw '不是分享码（应以 MZ1/MZ2/MZ3 开头）' }
    $kind = $matches[1]
    $end = $code.LastIndexOf(';')
    if ($end -lt 4 -or $code.Length -ne $end + 5) { throw '格式不完整' }
    $crc = 0
    if (-not [int]::TryParse($code.Substring($end + 1), [Globalization.NumberStyles]::AllowHexSpecifier, $null, [ref]$crc)) {
        throw 'CRC 不是十六进制'
    }
    $payload = $code.Substring(4, $end - 4)
    if ((Get-MzCrc16 $payload) -ne $crc) { throw 'CRC 校验失败（复制不完整）' }

    $game = ''
    $note = ''
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
            $idx = [int]$matches[1]
            $raw = [double]$matches[2]
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

function Get-MzSummary($decoded) {
    $changed = $decoded.Values.Count
    $style = if ($decoded.Values.ContainsKey(1)) { [int]$decoded.Values[1] } else { 0 }
    $styleName = @('标准', '自然', '电影感')[[math]::Max(0, [math]::Min(2, $style))]
    $from = if ($decoded.GameTag) { " · 来自 $($decoded.GameTag)" } else { '' }
    $note = if ($decoded.Note) { " · $($decoded.Note)" } else { '' }
    return "风格 $styleName · 修改 $changed 项$from$note"
}

function Set-IniValueInSection([string] $text, [string] $section, [string] $name, [string] $value) {
    $pattern = "(?ms)^(\[$([regex]::Escape($section))\][^\r\n]*\r?\n)(.*?)(?=^\[|\z)"
    if ($text -notmatch $pattern) {
        return $text.TrimEnd() + "`r`n`r`n[$section]`r`n$name=$value`r`n"
    }
    $head = $matches[1]
    $body = $matches[2]
    if ($body -match "(?m)^\s*$([regex]::Escape($name))\s*=") {
        $body = $body -replace "(?m)^(\s*$([regex]::Escape($name))\s*=\s*)[^\r\n]*", "`$1$value"
    } else {
        $body = $body.TrimEnd() + "`r`n$name=$value`r`n"
    }
    return $head + $body
}

function Apply-MzCode([string] $iniPath, $decoded) {
    if (-not (Test-Path -LiteralPath $iniPath -PathType Leaf)) { throw "找不到 OptiScaler.ini：$iniPath" }
    $text = [IO.File]::ReadAllText($iniPath)
    $backup = "$iniPath.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss')
    Copy-Item -LiteralPath $iniPath -Destination $backup -Force
    foreach ($idx in $decoded.Values.Keys) {
        $k = $MzKeys[$idx]
        $text = Set-IniValueInSection $text 'DlssNr' $k[1] (Format-MzValue $k $decoded.Values[$idx])
    }
    [IO.File]::WriteAllText($iniPath, $text, (New-Object Text.UTF8Encoding($false)))
    return $backup
}

if ($SelfTest) {
    $v = @{ 1 = 2.0; 0 = 1.35; 135 = 1.0 }
    $code = Encode-MzCode $v 'Neverness To Everness'
    "encode: $code"
    $d = Decode-MzCode $code
    "decode: style=$($d.Values[1]) intensity=$($d.Values[0]) wp=$($d.Values[135]) game=$($d.GameTag)"
    $empty = Encode-MzCode @{}
    "empty:  $empty"
    $n = Decode-MzCode $empty
    "empty decoded items = $($n.Values.Count)"
    try { Decode-MzCode ($code.Substring(0, $code.Length - 2) + '00') | Out-Null; 'crc test: FAILED (no throw)' }
    catch { "crc test: ok ($($_.Exception.Message))" }
    return
}

# ---------------------------------------------------------------- probe helpers
$CandidateNames = @('dxgi', 'winmm', 'd3d12', 'winhttp', 'wininet', 'dbghelp', 'version')
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

function Get-ProxyState([string] $dir) {
    $rows = @()
    foreach ($n in $CandidateNames) {
        $f = Join-Path $dir ($n + '.dll')
        if (Test-Path -LiteralPath $f -PathType Leaf) {
            $item = Get-Item -LiteralPath $f
            $rows += [pscustomobject]@{
                Name = $n
                MB   = [math]::Round($item.Length / 1MB, 1)
                Ours = (Test-IsOurInjection $f)
            }
        }
    }
    return $rows
}

# ---------------------------------------------------------------- window
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
try {
    Add-Type @"
using System.Runtime.InteropServices;
public class DpiHelper { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
    [void][DpiHelper]::SetProcessDPIAware()
} catch { }

$font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)
$form = New-Object System.Windows.Forms.Form
$form.Text = 'OptiScaler 快速安装'
$form.ClientSize = New-Object System.Drawing.Size(560, 430)
$form.StartPosition = 'CenterScreen'
$form.Font = $font
$form.AllowDrop = $true
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false

$drop = New-Object System.Windows.Forms.Label
$drop.Text = "把游戏目录拖到这里`r`n（含游戏 EXE 的那一层）"
$drop.TextAlign = 'MiddleCenter'
$drop.BorderStyle = 'FixedSingle'
$drop.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$drop.Location = New-Object System.Drawing.Point(16, 16)
$drop.Size = New-Object System.Drawing.Size(528, 86)
$form.Controls.Add($drop)

$pathBox = New-Object System.Windows.Forms.TextBox
$pathBox.Location = New-Object System.Drawing.Point(16, 112)
$pathBox.Size = New-Object System.Drawing.Size(420, 24)
$pathBox.ReadOnly = $true
$form.Controls.Add($pathBox)

$browse = New-Object System.Windows.Forms.Button
$browse.Text = '选择…'
$browse.Location = New-Object System.Drawing.Point(444, 110)
$browse.Size = New-Object System.Drawing.Size(100, 26)
$form.Controls.Add($browse)

$lblBackend = New-Object System.Windows.Forms.Label
$lblBackend.Text = '后端'
$lblBackend.Location = New-Object System.Drawing.Point(16, 150)
$lblBackend.Size = New-Object System.Drawing.Size(36, 22)
$form.Controls.Add($lblBackend)

$backend = New-Object System.Windows.Forms.ComboBox
$backend.DropDownStyle = 'DropDownList'
$backend.Location = New-Object System.Drawing.Point(56, 148)
$backend.Size = New-Object System.Drawing.Size(150, 24)
[void]$backend.Items.AddRange(@('mochizuki', 'lmxxf', 'daniel', 'auto'))
$backend.SelectedIndex = 0
$form.Controls.Add($backend)

$lblProxy = New-Object System.Windows.Forms.Label
$lblProxy.Text = '注入名'
$lblProxy.Location = New-Object System.Drawing.Point(222, 150)
$lblProxy.Size = New-Object System.Drawing.Size(50, 22)
$form.Controls.Add($lblProxy)

$proxy = New-Object System.Windows.Forms.ComboBox
$proxy.DropDownStyle = 'DropDownList'
$proxy.Location = New-Object System.Drawing.Point(276, 148)
$proxy.Size = New-Object System.Drawing.Size(130, 24)
$proxyNames = @($CandidateNames | ForEach-Object { "$_.dll" })
[void]$proxy.Items.AddRange([object[]]$proxyNames)
$proxy.SelectedIndex = 1
$form.Controls.Add($proxy)

$hint = New-Object System.Windows.Forms.Label
$hint.Text = ''
$hint.ForeColor = [System.Drawing.Color]::DimGray
$hint.Location = New-Object System.Drawing.Point(414, 150)
$hint.Size = New-Object System.Drawing.Size(130, 22)
$form.Controls.Add($hint)

$install = New-Object System.Windows.Forms.Button
$install.Text = '安装到游戏目录'
$install.Location = New-Object System.Drawing.Point(16, 182)
$install.Size = New-Object System.Drawing.Size(150, 30)
$install.Enabled = $false
$form.Controls.Add($install)

$openFolder = New-Object System.Windows.Forms.Button
$openFolder.Text = '打开目录'
$openFolder.Location = New-Object System.Drawing.Point(174, 182)
$openFolder.Size = New-Object System.Drawing.Size(100, 30)
$openFolder.Enabled = $false
$form.Controls.Add($openFolder)

$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = 'Vertical'
$log.ReadOnly = $true
$log.Location = New-Object System.Drawing.Point(16, 222)
$log.Size = New-Object System.Drawing.Size(528, 96)
$log.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($log)

$lblShare = New-Object System.Windows.Forms.Label
$lblShare.Text = '画面分享'
$lblShare.Location = New-Object System.Drawing.Point(16, 330)
$lblShare.Size = New-Object System.Drawing.Size(80, 22)
$form.Controls.Add($lblShare)

$export = New-Object System.Windows.Forms.Button
$export.Text = '晒出我的画面'
$export.Location = New-Object System.Drawing.Point(96, 326)
$export.Size = New-Object System.Drawing.Size(130, 28)
$export.Enabled = $false
$form.Controls.Add($export)

$import = New-Object System.Windows.Forms.Button
$import.Text = '换上同款画面'
$import.Location = New-Object System.Drawing.Point(234, 326)
$import.Size = New-Object System.Drawing.Size(130, 28)
$import.Enabled = $false
$form.Controls.Add($import)

$shareBox = New-Object System.Windows.Forms.TextBox
$shareBox.Location = New-Object System.Drawing.Point(16, 360)
$shareBox.Size = New-Object System.Drawing.Size(528, 24)
$shareBox.Font = New-Object System.Drawing.Font('Consolas', 9)
$form.Controls.Add($shareBox)

$status = New-Object System.Windows.Forms.Label
$status.Text = '把游戏目录拖进来开始'
$status.ForeColor = [System.Drawing.Color]::DimGray
$status.Location = New-Object System.Drawing.Point(16, 392)
$status.Size = New-Object System.Drawing.Size(528, 22)
$form.Controls.Add($status)

# ---------------------------------------------------------------- state
$script:GameDir = ''
$script:GameExe = ''
$script:Busy = $false

function Write-Log([string] $text) {
    $log.AppendText(((Get-Date).ToString('HH:mm:ss')) + '  ' + $text + "`r`n")
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Busy([bool] $busy) {
    $script:Busy = $busy
    $browse.Enabled = -not $busy
    $openFolder.Enabled = (-not $busy) -and [bool]$script:GameDir
    $install.Enabled = (-not $busy) -and [bool]$script:GameDir
    $export.Enabled = (-not $busy) -and [bool]$script:GameDir
    $import.Enabled = -not $busy
    [System.Windows.Forms.Application]::DoEvents()
}

function Update-ProxyHint {
    $rows = @(Get-ProxyState $script:GameDir)
    $ours = @($rows | Where-Object { $_.Ours })
    $busy = @($rows | Where-Object { -not $_.Ours })
    if ($ours.Count -gt 0) {
        $proxy.SelectedItem = ($ours[0].Name + '.dll')
        $hint.Text = '已注入：' + ($ours | ForEach-Object { $_.Name }) -join '/'
        $hint.ForeColor = [System.Drawing.Color]::SeaGreen
    } elseif ($busy.Count -gt 0) {
        $hint.Text = '占用：' + (($busy | ForEach-Object { $_.Name }) -join '/')
        $hint.ForeColor = [System.Drawing.Color]::Firebrick
    } else {
        $hint.Text = '推荐 winmm.dll'
        $hint.ForeColor = [System.Drawing.Color]::DimGray
    }
}

function Use-GameFolder([string] $dir) {
    if (-not $dir) { return }
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show("不是文件夹：`n$dir", '提示', 'OK', 'Warning') | Out-Null
        return
    }
    $exe = Resolve-GameExe $dir
    if (-not $exe) {
        [System.Windows.Forms.MessageBox]::Show("这个目录里没找到游戏 EXE。`n请拖入含 EXE 的那一层（通常是 Binaries\Win64）。", '提示', 'OK', 'Warning') | Out-Null
        return
    }
    $script:GameDir = $dir
    $script:GameExe = $exe.Name
    $pathBox.Text = $dir
    $drop.Text = "已选择：$($exe.Name)"
    $status.Text = "准备安装：$($exe.Name)"
    Update-ProxyHint
    Set-Busy $false
}

$drop.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = '选择含游戏 EXE 的目录'
    if ($dlg.ShowDialog() -eq 'OK') { Use-GameFolder $dlg.SelectedPath }
})
$browse.Add_Click({ $drop.PerformClick() })

$form.Add_DragEnter({
    param($s, $e)
    if ($e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' }
})
$form.Add_DragDrop({
    param($s, $e)
    $items = $e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop)
    if (-not $items -or $items.Count -lt 1) { return }
    $first = [string]$items[0]
    if (Test-Path -LiteralPath $first -PathType Leaf) { $first = Split-Path -Parent $first }
    Use-GameFolder $first
})

$openFolder.Add_Click({
    if ($script:GameDir) { Start-Process explorer.exe $script:GameDir }
})

$install.Add_Click({
    if (-not $script:GameDir -or $script:Busy) { return }
    $worker = @(
        (Join-Path $PSScriptRoot 'launcher-worker.ps1'),
        (Join-Path $PSScriptRoot 'install\launcher-worker.ps1'),
        (Join-Path $PSScriptRoot '..\install\launcher-worker.ps1')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $worker) {
        [System.Windows.Forms.MessageBox]::Show('找不到 launcher-worker.ps1，请确认这是完整的整合包。', '提示', 'OK', 'Error') | Out-Null
        return
    }
    Set-Busy $true
    $log.Clear()
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $tmp = Join-Path $env:TEMP ("opti-quick-$stamp")
    $reqPath = "$tmp.request.json"
    $evtPath = "$tmp.events.jsonl"
    $resPath = "$tmp.result.json"
    $req = [ordered]@{
        schema   = 1
        requestId = [guid]::NewGuid().ToString()
        gameDir  = $script:GameDir
        backends = @($backend.SelectedItem.ToString())
        proxy    = $proxy.SelectedItem.ToString()
        existingIni = 'keep'
    }
    [IO.File]::WriteAllText($reqPath, ($req | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
    Write-Log ("安装到 " + $script:GameDir)
    Write-Log ("后端 " + $req.backends[0] + " · 注入名 " + $req.proxy)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command powershell.exe).Source
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$worker`" -RequestJson `"$reqPath`" -EventsJsonl `"$evtPath`" -ResultJson `"$resPath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 400
    $timer.Add_Tick({
        if (Test-Path -LiteralPath $evtPath) {
            try {
                $lines = [IO.File]::ReadAllLines($evtPath)
                $last = $lines | Select-Object -Last 1
                if ($last) {
                    $o = $last | ConvertFrom-Json
                    if ($o.message) { $status.Text = [string]$o.message }
                }
            } catch { }
        }
        if ($proc.HasExited) {
            $timer.Stop()
            $timer.Dispose()
            $ok = $false
            if (Test-Path -LiteralPath $resPath) {
                try {
                    $r = Get-Content -LiteralPath $resPath -Raw -Encoding UTF8 | ConvertFrom-Json
                    if ($r.status -eq 'ok' -or $r.status -eq 'success') { $ok = $true }
                    if ($r.error) { Write-Log ('错误：' + $r.error) }
                } catch { }
            }
            if ($ok) {
                Write-Log '安装完成'
                $status.Text = '安装完成，进游戏按 Insert 打开菜单'
                $status.ForeColor = [System.Drawing.Color]::SeaGreen
            } else {
                Write-Log '安装未完成，见上面的日志'
                $status.Text = '安装失败，看日志'
                $status.ForeColor = [System.Drawing.Color]::Firebrick
            }
            Set-Busy $false
        }
    })
    $timer.Start()
})

$export.Add_Click({
    if (-not $script:GameDir) { return }
    $ini = Join-Path $script:GameDir 'OptiScaler.ini'
    if (-not (Test-Path -LiteralPath $ini)) {
        [System.Windows.Forms.MessageBox]::Show('这个目录里没有 OptiScaler.ini，先安装再用。', '提示', 'OK', 'Warning') | Out-Null
        return
    }
    $values = Read-MzValues $ini
    if ($values.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('当前没有改过任何 Mochizuki 参数，生成的码是空的。', '提示', 'OK', 'Information') | Out-Null
        return
    }
    $code = Encode-MzCode $values ([System.IO.Path]::GetFileNameWithoutExtension($script:GameExe))
    $shareBox.Text = $code
    try { [System.Windows.Forms.Clipboard]::SetText($code) } catch { }
    $status.Text = '分享码已复制，发到群里让别人粘贴'
    $status.ForeColor = [System.Drawing.Color]::SeaGreen
})

$import.Add_Click({
    $raw = $shareBox.Text.Trim()
    if (-not $raw) {
        try { $raw = [System.Windows.Forms.Clipboard]::GetText() } catch { }
    }
    if ($raw -match '(MZ[123]:[^\s]+)') { $raw = $matches[1] }
    if (-not $raw) {
        [System.Windows.Forms.MessageBox]::Show('先粘贴一段分享文字或码。', '提示', 'OK', 'Information') | Out-Null
        return
    }
    try {
        $decoded = Decode-MzCode $raw
    } catch {
        [System.Windows.Forms.MessageBox]::Show("分享码无效：$($_.Exception.Message)", '提示', 'OK', 'Warning') | Out-Null
        return
    }
    $summary = Get-MzSummary $decoded
    if (-not $script:GameDir) {
        [System.Windows.Forms.MessageBox]::Show("已识别：$summary`n`n先选游戏目录才能应用。", '提示', 'OK', 'Information') | Out-Null
        return
    }
    $ini = Join-Path $script:GameDir 'OptiScaler.ini'
    $answer = [System.Windows.Forms.MessageBox]::Show("识别到：$summary`n`n应用到当前游戏？", '确认', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    try {
        $backup = Apply-MzCode $ini $decoded
        Write-Log ('已应用分享码，备份：' + (Split-Path -Leaf $backup))
        $status.Text = '已换上这套画面，重启游戏生效'
        $status.ForeColor = [System.Drawing.Color]::SeaGreen
    } catch {
        [System.Windows.Forms.MessageBox]::Show("应用失败：$($_.Exception.Message)", '提示', 'OK', 'Error') | Out-Null
    }
})

$form.Add_Shown({
    Write-Log '把游戏目录拖进上面的框，或点「选择…」'
    Write-Log '安装复用上游 launcher-worker.ps1；分享码兼容 MZ1/MZ2/MZ3'
})

[void]$form.ShowDialog()
