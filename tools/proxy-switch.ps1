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
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Step([string] $t) { Write-Host "==> $t" -ForegroundColor Cyan }
function Info([string] $t) { Write-Host "    $t" }
function Warn([string] $t) { Write-Host "    ! $t" -ForegroundColor Yellow }
function Die([string] $t) {
    Write-Host "错误：$t" -ForegroundColor Red
    if ($Interactive) { Wait-Key }
    exit 1
}

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

# Mirrors tools/install/library-scan.ps1: upstream's three exclusion groups plus its
# shipping-name ranking, so a large editor/tool EXE cannot win over the game build.
$exeExcludeStart = '(?i)^(setup|install|unins|crash|unitycrash|vc_redist|dxsetup|easyanticheat|eac_|battleye|beclient|beservice|unrealcef|webview|cefsubprocess|shadercompile|bugsplat|crs-|redprelauncher|larilauncher|2klauncher).*\.exe$'
$exeExcludeEnd = '(?i)(prelauncher|launcher|crashreport|crashhandler|crs-handler|errorreporter|updater|patcher|uninstaller|benchmark|dedicatedserver)\.exe$'
$exeExcludeName = '(?i)^(gamelaunchhelper|person-worker|activationui|cleanup|touchup|config)\.exe$'

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
            ($n -notmatch $exeExcludeStart) -and ($n -notmatch $exeExcludeEnd) -and ($n -notmatch $exeExcludeName)
        } |
        Sort-Object @{ Expression = { Get-ExeRank $_.Name } }, @{ Expression = { $_.Length }; Descending = $true } |
        Select-Object -First 1
}

function Select-GameExe([string] $folder) {
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = '选择游戏主程序（EXE）'
        $dlg.Filter = '可执行文件 (*.exe)|*.exe|所有文件 (*.*)|*.*'
        $dlg.CheckFileExists = $true
        if (Test-Path -LiteralPath $folder) { $dlg.InitialDirectory = $folder }
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    } catch {
        Warn ('无法打开文件选择框：' + $_.Exception.Message)
    }
    return $null
}

function Wait-Key {
    Write-Host ''
    Write-Host '请按任意键继续...' -NoNewline
    try { $null = [Console]::ReadKey($true) } catch { }
    Write-Host ''
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

$profileUrl = 'https://raw.githubusercontent.com/TheAutomatic/dlss-5-amd-project/main/assets/compatibility/proxy-profiles.json'
$script:profileSource = ''

function Read-ProfileJson([string] $path) {
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# Remote only: nothing is written to disk, so the tool stays self-contained and never
# leaves state on the machine. When the network is unavailable the bundled copy is used.
function Get-ProfileDoc {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    try {
        $text = (Invoke-WebRequest -Uri $profileUrl -UseBasicParsing -TimeoutSec 5).Content
        if ($text) {
            $doc = $text | ConvertFrom-Json
            if ($doc) { $script:profileSource = '远程'; return $doc }
        }
    } catch { }

    foreach ($p in @((Join-Path $PSScriptRoot 'proxy-profiles.json'),
                     (Join-Path $PSScriptRoot 'assets\compatibility\proxy-profiles.json'),
                     (Join-Path $PSScriptRoot '..\assets\compatibility\proxy-profiles.json'))) {
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            $doc = Read-ProfileJson $p
            if ($doc) { $script:profileSource = '随包文件'; return $doc }
        }
    }
    $script:profileSource = '不可用'
    return $null
}

# Profiles identify a game by exact (case-insensitive) folder-name segment, the same
# rule the launcher's ProxyRecommendations.Match uses.
function Find-Profile($doc, [string] $folder) {
    if (-not $doc) { return $null }
    $segments = @($folder.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))
    foreach ($profile in @($doc.profiles)) {
        foreach ($segment in @($profile.pathSegments)) {
            $needle = [string]$segment
            # Store launchers append the app id to the folder ("Wuthering Waves(2002137)"),
            # so containment is required; short segments are skipped to avoid false hits.
            if ($needle.Length -lt 4) { continue }
            foreach ($actual in $segments) {
                if ($actual.IndexOf($needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $profile }
            }
        }
    }
    return $null
}

# The profile catalogue only covers a handful of games, while the OptiScaler wiki
# lists every tested one. The wiki is an asciidoc table: cache it for a week and
# pull the proxy names out of the note column when no profile matched.
# Folder segments that say nothing about which game it is; matching on them would
# hit unrelated rows (a folder called "game" would match any title containing it).
$genericSegments = @('game', 'games', 'bin', 'binaries', 'win64', 'win32', 'x64', 'x86', 'client',
                     'content', 'engine', 'app', 'apps', 'rail_apps', 'steamapps', 'common',
                     'windowsnoeditor', 'windows', 'project', 'build', 'release', 'shipping')

$wikiUrl = 'https://raw.githubusercontent.com/wiki/optiscaler/OptiScaler/Compatibility-List.md'

function Get-WikiText {
    try { return (Invoke-WebRequest -Uri $wikiUrl -UseBasicParsing -TimeoutSec 10).Content } catch { return $null }
}

function Get-NormalizedName([string] $s) {
    # Folders and the wiki disagree on spacing and punctuation
    # ("GhostwireTokyo" vs "Ghostwire: Tokyo"), so compare without them.
    # Codes: space, tab, colon, hyphen, dot, parens, quotes, acute, right apostrophe.
    $strip = @(32, 9, 58, 45, 46, 40, 41, 39, 34, 180, 8217) | ForEach-Object { [char]$_ }
    $t = $s.ToLowerInvariant()
    foreach ($ch in $strip) { $t = $t.Replace([string]$ch, '') }
    return $t
}

function Get-WikiEntry($text, [string] $folder) {
    if (-not $text) { return $null }
    # Launcher folder names carry the app id ("Wuthering Waves(2002137)").
    $names = @($folder.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_ -replace '\s*\(\d+\)\s*$', '' } |
        ForEach-Object { Get-NormalizedName $_ } |
        Where-Object { $_.Length -ge 4 -and $script:genericSegments -notcontains $_ })
    $rxLink = '\[([^\]]+)\]\([^)]*\)'
    $rxDll = '(?i)\b(dxgi|winmm|d3d12|winhttp|wininet|dbghelp|version|d3d11|opengl32)\.dll\b'
    foreach ($line in ($text -split "`n")) {
        if ($line -notmatch '^\s*\|') { continue }
        $cells = $line.Trim().Trim('|').Split('|')
        if ($cells.Count -lt 2) { continue }
        $rawName = $cells[0].Trim()
        $name = if ($rawName -match $rxLink) { $Matches[1].Trim() } else { $rawName }
        # The wiki keeps its row template inside a comment; it must never match a folder.
        if ($name -match '(?i)^\s*GAME\s*NAME\s*$') { continue }
        $nameNorm = Get-NormalizedName $name
        if ($nameNorm.Length -lt 4) { continue }
        if ($cells[1].Trim() -notmatch '✅') { continue }
        $hit = $false
        foreach ($n in $names) {
            if ($n.Contains($nameNorm) -or $nameNorm.Contains($n)) { $hit = $true; break }
        }
        if (-not $hit) { continue }
        $dlls = @([regex]::Matches($line, $rxDll) | ForEach-Object { $_.Groups[1].Value.ToLower() + '.dll' } | Select-Object -Unique)
        # Keep the entry even without a DLL: "listed but no proxy recorded" is more
        # useful than "no record at all".
        return [pscustomobject]@{ name = $name; proxies = $dlls }
    }
    return $null
}

# OptiPatcher support list. Upstream decides at runtime: the plugin's PatchResult()
# returns true and OptiScaler then disables Dxgi/Vulkan spoofing itself. The table is
# documentation only, so this is an advisory check, not a guarantee.
$optiUrl = 'https://raw.githubusercontent.com/optiscaler/OptiPatcher/main/GameSupport.md'

function Get-OptiText {
    try { return (Invoke-WebRequest -Uri $optiUrl -UseBasicParsing -TimeoutSec 10).Content } catch { return $null }
}

function Get-OptiSupport($text, [string] $folder) {
    if (-not $text) { return $null }
    $names = @($folder.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries) |
        ForEach-Object { $_ -replace '\s*\(\d+\)\s*$', '' } |
        ForEach-Object { Get-NormalizedName $_ } |
        Where-Object { $_.Length -ge 4 -and $script:genericSegments -notcontains $_ })
    foreach ($line in ($text -split "`n")) {
        if ($line -notmatch '^\s*\|') { continue }
        $cells = $line.Trim().Trim('|').Split('|')
        if ($cells.Count -lt 4) { continue }
        $name = $cells[0].Trim()
        # Skip the table header and the commented-out "GAME NAME" template row.
        if ($name -match '^\s*Game\s*$' -or $name -match '^[-:\s]+$' -or $name -match '(?i)^game\s*name$') { continue }
        $nameNorm = Get-NormalizedName $name
        if ($nameNorm.Length -lt 4) { continue }
        $hit = $false
        foreach ($n in $names) {
            if ($n.Contains($nameNorm) -or $nameNorm.Contains($n)) { $hit = $true; break }
        }
        if (-not $hit) { continue }
        return [pscustomobject]@{ name = $name; dlss = $cells[1].Trim(); fg = $cells[2].Trim() }
    }
    return $null
}

$advice = @{}
$recommended = $null
$optiSupport = $null
$profile = $null
$wikiHit = $null
$probe = $null
$exeInfo = $null

if (-not $NoProbe) {
    if (-not [Console]::IsOutputRedirected) {
        Write-Host '  正在获取 Wiki 与支持列表...' -ForegroundColor DarkGray
    }
    # Not $exePath: proxy-probe.ps1 declares param($ExePath), and PowerShell names
    # are case-insensitive, so dot-sourcing would blank this variable.
    $gameExePath = if ($Exe) { $Exe } else {
        $found = Resolve-GameExe $Dir
        if ($found) { $found.FullName } else { $null }
    }
    # No obvious game EXE: ask for one, like the upstream launcher does.
    if (-not $gameExePath -and $Interactive) { $gameExePath = Select-GameExe $Dir }
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
                    $reason = [string]$c.reason
                    if ($n) { $advice[$n] = @{ imported = $true; reason = $reason } }
                    # Only a real import counts as a recommendation. "existing project
                    # proxy" just means this folder already has a loader; it says nothing
                    # about which name the game accepts.
                    if (-not $recommended -and $reason -like 'imported*') { $recommended = $n + '.dll' }
                }
            }
        }
    }

    $doc = Get-ProfileDoc
    $profile = Find-Profile $doc $Dir
    if ($profile) {
        $pref = ([string]$profile.preferred) -replace '\.dll$', ''
        if ($advice.ContainsKey($pref)) { $advice[$pref].wiki = 'preferred' } else { $advice[$pref] = @{ wiki = 'preferred' } }
        foreach ($alt in @($profile.alternatives)) {
            $a = ([string]$alt) -replace '\.dll$', ''
            if ($advice.ContainsKey($a)) { $advice[$a].wiki = 'alternative' } else { $advice[$a] = @{ wiki = 'alternative' } }
        }
        $recommended = [string]$profile.preferred
    } else {
        # No curated profile: fall back to the wiki compatibility table.
        $wikiHit = Get-WikiEntry (Get-WikiText) $Dir
        if ($wikiHit -and @($wikiHit.proxies).Count -gt 0) { $recommended = [string]$wikiHit.proxies[0] }
        $optiSupport = Get-OptiSupport (Get-OptiText) $Dir
    }
}

function Get-Marks([string] $n) {
    $marks = @()
    $key = $n -replace '\.dll$', ''
    if ($advice.ContainsKey($key)) {
        $a = $advice[$key]
        if ($a.ContainsKey('wiki') -and $a.wiki -eq 'preferred') { $marks += '推荐' }
        if ($a.ContainsKey('reason') -and ([string]$a.reason) -like 'existing*') { $marks += '已安装' }
        elseif ($a.ContainsKey('imported') -and $a.imported) { $marks += '游戏导入' }
    }
    if ($marks.Count -eq 0) { return '' }
    return '  [' + ($marks -join '][') + ']'
}

function Show-Advice {
    if ($exeInfo) { Info ("游戏程序：{0}" -f $exeInfo.Name) } else { Info '游戏程序：未找到（可用 -Exe 指定）' }
    if ($profile) {
        $alt = @($profile.alternatives) -join ' / '
        Info ("Wiki 档案：{0} → 首选 {1}{2}" -f $profile.id, $profile.preferred, $(if ($alt) { "；备选 $alt" } else { '' }))
    } elseif ($wikiHit) {
        if (@($wikiHit.proxies).Count -gt 0) {
            Info ("Wiki 兼容列表：{0} → {1}" -f $wikiHit.name, ($wikiHit.proxies -join ' / '))
        } else {
            Info ("Wiki 兼容列表：{0}（未注明 DLL，可任选尝试）" -f $wikiHit.name)
        }
    } elseif (-not $NoProbe) {
        Info 'Wiki 档案：无此游戏记录'
    }
    if ($probe) {
        # A size-capped probe simply has no import data; saying so adds noise.
        $capped = $probe.pe -and $probe.pe.error -eq 'size-cap'
        if (-not $capped) {
            $imported = @($probe.candidates | ForEach-Object { [string]$_.name }) -join ', '
            if ($imported) { Info ("PE 探测：游戏导入 {0}" -f $imported) }
            else { Info 'PE 探测：未看到候选名被导入（可用任意名字尝试）' }
        }
        foreach ($c in @($probe.conflicts)) { Warn ("同名 DLL 冲突：{0}（{1}）" -f $c.name, $c.detail) }
    }
    # The DLL lives in the game folder (flat package) or in OptiScaler\ (official layout).
    $optiAsi = @((Join-Path $Dir 'plugins\OptiPatcher.asi'),
                 (Join-Path $Dir 'OptiScaler\plugins\OptiPatcher.asi')) |
        Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    # Whether the plugin is already present is an install detail; what this line answers
    # is "does the wiki know this game", so that is all it reports.
    if ($optiSupport) {
        Info ("OptiPatcher：Wiki 收录，支持 DLSS {0} / DLSS-FG {1}" -f $optiSupport.dlss, $optiSupport.fg)
    } else {
        Info 'OptiPatcher：Wiki 未收录此游戏'
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
        Info ("{0}.dll  {1} MB{2}{3}" -f $p.Name, $p.MB, $(if ($p.Bytes -gt 20MB) { '  <- 当前注入' } else { '' }), (Get-Marks $p.Name))
    }
    Show-Advice
}

if ($List) { Show-State; exit 0 }

function Install-OptiPatcher {
    $url = 'https://github.com/optiscaler/OptiPatcher/releases/download/rolling/OptiPatcher.asi'
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('OptiPatcher-' + [guid]::NewGuid().ToString('N') + '.asi')
    $source = $null
    try {
        Invoke-WebRequest -Uri $url -OutFile $tmp -TimeoutSec 30 -UseBasicParsing
        $fs = [IO.File]::OpenRead($tmp)
        try {
            $b = New-Object byte[] 2
            [void]$fs.Read($b, 0, 2)
            if ($b[0] -eq 0x4D -and $b[1] -eq 0x5A) { $source = $tmp }
        } finally { $fs.Dispose() }
    } catch { }

    if (-not $source) {
        foreach ($cand in @((Join-Path $PSScriptRoot 'plugins\OptiPatcher.asi'),
                            (Join-Path $PSScriptRoot 'OptiScaler\plugins\OptiPatcher.asi'))) {
            if (Test-Path -LiteralPath $cand) { $source = $cand; break }
        }
    }
    if (-not $source) { Warn 'OptiPatcher 下载失败，且目录里没有离线副本。'; return $false }

    $plugins = Join-Path $Dir 'plugins'
    if (-not (Test-Path -LiteralPath $plugins)) { [void][IO.Directory]::CreateDirectory($plugins) }
    Copy-Item -LiteralPath $source -Destination (Join-Path $plugins 'OptiPatcher.asi') -Force
    if ($source -eq $tmp) { Remove-Item -LiteralPath $tmp -Force -EA 0 }

    # Turn the loader on the same way the upstream installer does.
    $ini = Join-Path $Dir 'OptiScaler.ini'
    if (Test-Path -LiteralPath $ini) {
        $t = Get-Content -LiteralPath $ini -Raw -Encoding UTF8
        if ($t -match '(?m)^LoadAsiPlugins=') {
            $t = $t -replace '(?m)^LoadAsiPlugins=.*$', 'LoadAsiPlugins=true'
        } elseif ($t -match '(?m)^\[Plugins\]') {
            $t = $t -replace '(?m)^(\[Plugins\][ \t]*)$', "`$1`r`nLoadAsiPlugins=true"
        } else {
            $t = $t.TrimEnd() + "`r`n`r`n[Plugins]`r`nLoadAsiPlugins=true`r`n"
        }
        [IO.File]::WriteAllText($ini, $t, (New-Object Text.UTF8Encoding($false)))
    } else {
        Warn '目录里没有 OptiScaler.ini，未写入 LoadAsiPlugins，请在游戏内手动开启。'
    }
    return $true
}

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
        if ($DryRun) { Step "DryRun：将把 $loaderName.dll 切换为 $targetName.dll"; return }
        Move-Item -LiteralPath $loader -Destination $targetPath
        Step "已切换：$loaderName.dll -> $targetName.dll"
    }
    Info '重启游戏生效。同一目录只能有一个加载器。'
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
    if ([string]::IsNullOrWhiteSpace($choice)) { Info '已取消。'; Wait-Key; exit 0 }
    $pick = 0
    if (-not [int]::TryParse($choice.Trim(), [ref]$pick) -or $pick -lt 1 -or $pick -gt 7) { Die "无效选择：$choice" }
    Invoke-Switch $candidates[$pick - 1]

    # OptiPatcher is offered regardless of whether the wiki lists the game: the
    # plugin decides at runtime (PatchResult), and an unlisted game simply falls back
    # to spoofing.
    Write-Host ''
    $ans = Read-Host '是否安装/更新 OptiPatcher（从 GitHub 下载，并开启 ASI 插件）？[Y/n]'
    if ([string]::IsNullOrWhiteSpace($ans) -or $ans -match '^(?i)y') {
        if (Install-OptiPatcher) { Info 'OptiPatcher 已放入 plugins，LoadAsiPlugins=true。' }
    } else {
        Info '已跳过 OptiPatcher。'
    }

    Wait-Key
    exit 0
}

if (-not $Name) { Die '请指定 -Name，或使用 -Interactive / -List。' }
Invoke-Switch $Name
