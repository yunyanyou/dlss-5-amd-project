<#
.SYNOPSIS
  Rename the OptiScaler host DLL to the loader name a game expects, with advice.

.DESCRIPTION
  OptiScaler is installed by naming its DLL after a system DLL the game already
  imports (winmm.dll, dxgi.dll, d3d12.dll, ...). Only one loader may exist in a
  game folder, so this script finds the current one by size, checks the target
  name is free (or is the loader itself) and renames it.

  Before choosing, it gathers two independent hints:

    * the PE import probe shipped with OptiScaler (proxy-probe.ps1): which of the
      candidate names the game EXE or its local dependencies actually import;
    * the Wiki profile catalogue (proxy-profiles.json): the preferred and
      alternative proxies recorded for that game.

  Manual choice wins, then the Wiki preference, then the probe result - the same
  order the upstream launcher uses.

.PARAMETER Name
  Loader to install: dxgi, winmm, d3d12, winhttp, wininet, dbghelp, version,
  d3d11 or opengl32.

.PARAMETER Dir
  Game folder. Defaults to the current directory.

.PARAMETER Exe
  Game EXE to probe. Defaults to the largest .exe in the folder.

.PARAMETER Current
  Current loader name. Detected when omitted: the only candidate above 20 MB.

.PARAMETER Interactive
  Show the annotated menu and rename what the user picks.

.PARAMETER List
  Print the current loader plus the advice and exit.

.PARAMETER DryRun
  Print the plan and exit without renaming anything.

.PARAMETER NoProbe
  Skip the PE probe and the Wiki catalogue.

.EXAMPLE
  .\switch-loader.ps1 -Interactive -Dir "F:\Game\Binaries\Win64"

.EXAMPLE
  .\switch-loader.ps1 -Name version -Dir .
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('dxgi', 'winmm', 'd3d12', 'winhttp', 'wininet', 'dbghelp', 'version', 'd3d11', 'opengl32')]
    [string] $Name,
    [string] $Dir = '.',
    [string] $Exe = '',
    [string] $Current = '',
    [switch] $DryRun,
    [switch] $List,
    [switch] $Interactive,
    [switch] $NoProbe
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Step([string] $t) { Write-Host "==> $t" -ForegroundColor Cyan }
function Info([string] $t) { Write-Host "    $t" }
function Warn([string] $t) { Write-Host "    ! $t" -ForegroundColor Yellow }
function Die([string] $t) { Write-Host "错误：$t" -ForegroundColor Red; exit 1 }

# Upstream's install-amd-presr.ps1 validates exactly these seven; d3d11/opengl32
# are extras this script accepts. dinput8 is deliberately absent: this OptiScaler
# build has no DirectInput8Create export, so the game fails to load it.
$candidates = @('dxgi', 'winmm', 'd3d12', 'winhttp', 'wininet', 'dbghelp', 'version', 'd3d11', 'opengl32')

if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Die "找不到目录：$Dir" }
# A trailing separator (common when a .bat passes "%~dp0") makes Test-Path reject the
# path as illegal, so trim it unless only the drive root is left.
if ($Dir.Length -gt 3) { $Dir = $Dir.TrimEnd('\', '/') }
$Dir = (Resolve-Path -LiteralPath $Dir).Path

# ---------------------------------------------------------------- probing

function Resolve-GameExe([string] $folder) {
    Get-ChildItem -LiteralPath $folder -Filter *.exe -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '(?i)unins|setup|launcher|crash|report|update|helper' } |
        Sort-Object Length -Descending |
        Select-Object -First 1
}

function Find-ProbeScript {
    foreach ($p in @((Join-Path $PSScriptRoot 'proxy-probe.ps1'),
                     (Join-Path $PSScriptRoot 'tools\install\proxy-probe.ps1'),
                     (Join-Path $PSScriptRoot '..\tools\install\proxy-probe.ps1'),
                     'F:\hssm\amd-nr\dlss-5-amd-project\tools\install\proxy-probe.ps1')) {
        if (Test-Path -LiteralPath $p -PathType Leaf) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}

function Find-ProfileDoc {
    foreach ($p in @((Join-Path $PSScriptRoot 'proxy-profiles.json'),
                     (Join-Path $PSScriptRoot 'assets\compatibility\proxy-profiles.json'),
                     (Join-Path $PSScriptRoot '..\assets\compatibility\proxy-profiles.json'),
                     'F:\hssm\amd-nr\dlss-5-amd-project\assets\compatibility\proxy-profiles.json')) {
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { }
        }
    }
    return $null
}

# Profiles identify a game by exact (case-insensitive) folder-name segment, the same
# rule the launcher's ProxyRecommendations.Match uses.
function Find-Profile($doc, [string] $folder) {
    if (-not $doc) { return $null }
    $segments = @($folder.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))
    foreach ($profile in @($doc.profiles)) {
        foreach ($segment in @($profile.pathSegments)) {
            foreach ($actual in $segments) {
                if ([string]::Equals($actual, [string]$segment, [StringComparison]::OrdinalIgnoreCase)) { return $profile }
            }
        }
    }
    return $null
}

$advice = @{}
$recommended = $null
$profile = $null
$probe = $null
$exeInfo = $null

if (-not $NoProbe) {
    # Not $exePath: proxy-probe.ps1 declares param($ExePath), and PowerShell names
    # are case-insensitive, so dot-sourcing would blank this variable.
    $gameExePath = if ($Exe) { $Exe } else {
        $found = Resolve-GameExe $Dir
        if ($found) { $found.FullName } else { $null }
    }
    if ($gameExePath -and (Test-Path -LiteralPath $gameExePath -PathType Leaf)) {
        $exeInfo = Get-Item -LiteralPath $gameExePath
        $probeScript = Find-ProbeScript
        if ($probeScript) {
            $prev = $ErrorActionPreference
            try {
                # proxy-probe.ps1 only runs its main block when -ExePath is bound, so
                # dot-sourcing here just defines Get-ProxyRecommendation. Its own
                # param() block leaves the variables unset, which strict mode rejects.
                $ErrorActionPreference = 'Continue'
                Set-StrictMode -Off
                . $probeScript
                $probe = Get-ProxyRecommendation $gameExePath
            } catch {
                Warn ("PE 探测未执行：" + $_.Exception.Message)
                $probe = $null
            } finally {
                $ErrorActionPreference = $prev
                Set-StrictMode -Version Latest
            }
            if ($probe) {
                foreach ($c in @($probe.candidates)) {
                    $n = ([string]$c.name) -replace '\.dll$', ''
                    if ($n) { $advice[$n] = @{ imported = $true; reason = [string]$c.reason } }
                }
                if ($probe.recommend) { $recommended = [string]$probe.recommend }
            }
        }
    }

    $doc = Find-ProfileDoc
    $profile = Find-Profile $doc $Dir
    if ($profile) {
        $pref = ([string]$profile.preferred) -replace '\.dll$', ''
        if ($advice.ContainsKey($pref)) { $advice[$pref].wiki = 'preferred' } else { $advice[$pref] = @{ wiki = 'preferred' } }
        foreach ($alt in @($profile.alternatives)) {
            $a = ([string]$alt) -replace '\.dll$', ''
            if ($advice.ContainsKey($a)) { $advice[$a].wiki = 'alternative' } else { $advice[$a] = @{ wiki = 'alternative' } }
        }
        $recommended = [string]$profile.preferred
    }
}

function Get-Marks([string] $n) {
    $marks = @()
    $key = $n -replace '\.dll$', ''
    if ($advice.ContainsKey($key)) {
        $a = $advice[$key]
        if ($a.ContainsKey('wiki') -and $a.wiki -eq 'preferred') { $marks += '推荐' }
        elseif ($a.ContainsKey('wiki') -and $a.wiki -eq 'alternative') { $marks += '备选' }
        if ($a.ContainsKey('imported') -and $a.imported) { $marks += '游戏导入' }
    }
    if ($marks.Count -eq 0) { return '' }
    return '  [' + ($marks -join '][') + ']'
}

function Show-Advice {
    if ($exeInfo) { Info ("游戏程序：{0}" -f $exeInfo.Name) } else { Info '游戏程序：未找到（可用 -Exe 指定）' }
    if ($profile) {
        $alt = @($profile.alternatives) -join ' / '
        Info ("Wiki 档案：{0} → 首选 {1}{2}" -f $profile.id, $profile.preferred, $(if ($alt) { "；备选 $alt" } else { '' }))
        if ($profile.notesZh) { Info ("  " + $profile.notesZh) }
    } elseif (-not $NoProbe) {
        Info 'Wiki 档案：无此游戏记录'
    }
    if ($probe) {
        $capped = $probe.pe -and $probe.pe.error -eq 'size-cap'
        if ($capped) {
            Warn ('PE 探测：{0} 超过探测的 8 MB 上限，已跳过导入表（以 Wiki 档案为准）' -f $exeInfo.Name)
        } else {
            $imported = @($probe.candidates | ForEach-Object { [string]$_.name }) -join ', '
            if ($imported) { Info ("PE 探测：游戏导入 {0}" -f $imported) }
            else { Info 'PE 探测：未看到候选名被导入（可用任意名字尝试）' }
        }
        foreach ($c in @($probe.conflicts)) { Warn ("同名 DLL 冲突：{0}（{1}）" -f $c.name, $c.detail) }
    }
    if ($recommended) { Info ("推荐：{0}" -f $recommended) -ForegroundColor Green }
}

# ---------------------------------------------------------------- loader state

$present = @()
foreach ($c in $candidates) {
    $f = Join-Path $Dir ($c + '.dll')
    if (Test-Path -LiteralPath $f -PathType Leaf) {
        $len = (Get-Item -LiteralPath $f).Length
        $present += [pscustomobject]@{ Name = $c; Path = $f; MB = [math]::Round($len / 1MB, 1); Bytes = $len }
    }
}

$loader = $null
if ($Current) {
    $cp = Join-Path $Dir ($Current + '.dll')
    if (-not (Test-Path -LiteralPath $cp -PathType Leaf)) { Die "目录里没有 $Current.dll" }
    $loader = $cp
} else {
    $hosts = @($present | Where-Object { $_.Bytes -gt 20MB })
    if ($hosts.Count -gt 1) { Die ('发现多个宿主大小的 DLL（{0}），请用 -Current 指定。' -f (($hosts | ForEach-Object { $_.Name }) -join ', ')) }
    if ($hosts.Count -eq 1) { $loader = $hosts[0].Path }
}

function Show-State {
    Step "目录：$Dir"
    if ($present.Count -eq 0) { Info '没有任何候选 DLL' }
    foreach ($p in $present) {
        Info ("{0}.dll  {1} MB{2}{3}" -f $p.Name, $p.MB, $(if ($p.Bytes -gt 20MB) { '  <- 当前宿主' } else { '' }), (Get-Marks $p.Name))
    }
    Show-Advice
}

if ($List) { Show-State; exit 0 }

function Invoke-Switch([string] $targetName) {
    $targetPath = Join-Path $Dir ($targetName + '.dll')
    if (-not $loader) { Die '没找到 OptiScaler 宿主 DLL（候选名中没有大于 20 MB 的文件）。请用 -Current 指定。' }
    $loaderName = [IO.Path]::GetFileNameWithoutExtension($loader)
    Step "当前加载器：$loaderName.dll"
    if ($loaderName -eq $targetName) { Info '已经是目标名称，无需更改。'; return }

    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
        $existing = (Get-Item -LiteralPath $targetPath).Length
        if ($existing -gt 20MB) {
            Warn "$targetName.dll 已存在且是宿主大小，将删除旧加载器。"
            if ($DryRun) { Step 'DryRun：将删除旧加载器'; return }
            Remove-Item -LiteralPath $loader -Force
            Step "已删除 $loaderName.dll"
        } else {
            Die "$targetName.dll 已存在（$([math]::Round($existing/1KB)) KB）且不是宿主。请先备份或换一个名字。"
        }
    } else {
        if ($DryRun) { Step "DryRun：将把 $loaderName.dll 改名为 $targetName.dll"; return }
        Move-Item -LiteralPath $loader -Destination $targetPath
        Step "已改名：$loaderName.dll -> $targetName.dll"
    }
    Info '重启游戏生效。同一目录只能有一个加载器。'
    Info '本脚本不触碰权重目录（dlssnr-amd / native-game-tiled-assets）。'
}

if ($Interactive) {
    Show-State
    Write-Host ''
    for ($i = 0; $i -lt 7; $i++) {
        $n = $candidates[$i]
        Write-Host ("  {0}. {1}.dll{2}" -f ($i + 1), $n, (Get-Marks $n))
    }
    Write-Host ''
    $choice = Read-Host '请选择（直接回车取消）'
    if ([string]::IsNullOrWhiteSpace($choice)) { Info '已取消。'; exit 0 }
    $pick = 0
    if (-not [int]::TryParse($choice.Trim(), [ref]$pick) -or $pick -lt 1 -or $pick -gt 7) { Die "无效选择：$choice" }
    Invoke-Switch $candidates[$pick - 1]
    exit 0
}

if (-not $Name) { Die '请指定 -Name，或使用 -Interactive / -List。' }
Invoke-Switch $Name
