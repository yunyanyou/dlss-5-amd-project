<#
.SYNOPSIS
  Stage and zip the standalone OptiScaler ASI Launcher package:
    - Official unmodified OptiScaler release (fetched/verified by tools/build/fetch-optiscaler.ps1)
    - dist/upstream/        (SHA-256-verified upstream payload trees via tools/build/fetch-upstream.ps1)
    - cache/upstream/       (fetched-tree cache with .stamp.json validation; offline via -MochiDir/-OpenRrDir)
    - cache/upstream/optipatcher/ (rolling OptiPatcher.asi, PE-validated)
    - OptiScalerNRLauncher.exe + Setup.ps1
#>
[CmdletBinding()]
param(
    [string]$Version = '',
    [string]$OutDir = 'dist',
    [string]$Name = '',
    [string]$OptiArchive = '',
    [string]$OptiDir = '',
    [string]$SigningThumbprint = '',
    [switch]$LocalTest
)
$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$path) {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $fs = [IO.File]::OpenRead($path)
        try { return ([BitConverter]::ToString($sha.ComputeHash($fs))).Replace('-', '') }
        finally { $fs.Dispose() }
    } finally { $sha.Dispose() }
}

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $Version) {
    $vf = Join-Path $root 'VERSION'
    if (Test-Path -LiteralPath $vf -PathType Leaf) {
        $Version = (Get-Content -LiteralPath $vf -Encoding UTF8 -TotalCount 1).Trim()
    }
    if (-not $Version) { $Version = '2.0.0' }
}
if (-not $Name) { $Name = "OptiScaler-NR-$Version" }

$stage = Join-Path $root (Join-Path $OutDir $Name)
$zip   = Join-Path $root (Join-Path $OutDir ($Name + '.zip'))

# 1. Fetch / verify official OptiScaler release (Mochi-style)
$fetchScript = Join-Path $root 'tools/build/fetch-optiscaler.ps1'
$optiInfo = & $fetchScript -OptiArchive $OptiArchive -OptiDir $OptiDir
$optiReleaseDir = $optiInfo.ReleaseDir
$optiLicense    = $optiInfo.LicensePath

# 2. Verify ASI payloads exist
# Pinned upstream payloads (SHA-256 verified, cached in cache/downloads + cache/upstream).
# Offline overrides: -MochiDir/-MochiArchive/-OpenRrDir/-OpenRrArchive/-OptiPatcherFile.
$upstreamInfo = & (Join-Path $root 'tools/build/fetch-upstream.ps1') -UpstreamDir (Join-Path $root (Join-Path 'dist' 'upstream'))
$asiPayload = $upstreamInfo.DlssnrDir
foreach ($required in @(
    'OptiScaler/plugins/dlssnr-amd.asi',
    'nr_present_probe.exe',
    'ini/dlssnr-amd-optiscaler.ini',
    'ini/dlssnr-amd-optiscaler-renodx.ini',
    'model-tools/dlssnr_extract_model.exe',
    'model-tools/dlssnr-int4-weights.exe',
    'model-tools/dlssnr-int4.sha256',
    'experimental/dlssnr-small-experimental.delta',
    'experimental/CC_SMALL_FP8_EXPERIMENTAL.bin.sha256',
    'optimized/dlssnr-optimized.delta',
    'optimized/CC_SILVER_AARDWOLD_OPTIMIZED.bin.sha256'
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $asiPayload $required) -PathType Leaf)) {
        throw "dlssnr-amd payload incomplete: $required"
    }
}
$openRrPayload = $upstreamInfo.OpenRrDir
$openRrAsiSrc = $null
foreach ($cand in @('OptiScaler/plugins/openrr-amd.asi', 'openrr-amd/aco/gfx1201/openrr-d3d12-v1/manifest.msgpack', 'openrr-amd/lang/zh-CN.txt', 'openrr-amd.asi', 'OptiScaler/plugins/openrr.asi', 'plugins/openrr-amd.asi', 'plugins/openrr.asi')) {
    $p = Join-Path $openRrPayload $cand
    if (Test-Path -LiteralPath $p -PathType Leaf) { $openRrAsiSrc = $p; break }
}
if (-not $openRrAsiSrc) {
    throw 'openrr payload missing OptiScaler/plugins/openrr-amd.asi (or openrr.asi).'
}
if (-not (Test-Path -LiteralPath (Join-Path $openRrPayload 'openrr-amd/shaders') -PathType Container)) {
    throw 'openrr payload missing openrr-amd/shaders.'
}
if (-not (Test-Path -LiteralPath (Join-Path $openRrPayload 'openrr-amd/shaders-gfx11') -PathType Container)) {
    throw 'openrr payload missing openrr-amd/shaders-gfx11.'
}
$optiPatcherAsiSrc = $upstreamInfo.OptiPatcherAsi
if (-not (Test-Path -LiteralPath $optiPatcherAsiSrc -PathType Leaf)) {
    throw 'optipatcher payload missing OptiScaler/plugins/OptiPatcher.asi.'
}

# 3. Prepare clean staging directory
if (Test-Path -LiteralPath $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $stage, (Join-Path $stage 'OptiScaler'), (Join-Path $stage 'Licenses') | Out-Null

# 4. Copy unmodified official OptiScaler release files
Copy-Item -LiteralPath (Join-Path $optiReleaseDir 'OptiScaler.dll') -Destination (Join-Path $stage 'OptiScaler.dll') -Force
Copy-Item -LiteralPath (Join-Path $optiReleaseDir 'OptiScaler.ini') -Destination (Join-Path $stage 'OptiScaler.ini') -Force
Get-ChildItem -LiteralPath (Join-Path $optiReleaseDir 'OptiScaler') | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $stage 'OptiScaler') -Recurse -Force
}
# CHS host extras: the Chinese menu font (loaded as font/wqy-microhei.ttc next to the DLL)
# and its fakenvapi defaults.
$chsFont = Join-Path $optiReleaseDir 'font'
if (Test-Path -LiteralPath $chsFont -PathType Container) {
    Copy-Item -LiteralPath $chsFont (Join-Path $stage 'font') -Recurse -Force
}
$chsfakenvapi = Join-Path $optiReleaseDir 'fakenvapi.ini'
if (Test-Path -LiteralPath $chsfakenvapi -PathType Leaf) {
    Copy-Item -LiteralPath $chsfakenvapi (Join-Path $stage 'fakenvapi.ini') -Force
}
if (Test-Path -LiteralPath (Join-Path $optiReleaseDir 'Licenses') -PathType Container) {
    Get-ChildItem -LiteralPath (Join-Path $optiReleaseDir 'Licenses') -File | Copy-Item -Destination (Join-Path $stage 'Licenses') -Force
}
Copy-Item -LiteralPath $optiLicense -Destination (Join-Path $stage 'Licenses/OptiScaler_LICENSE.txt') -Force

# Update official OptiScaler.ini in-place (Mochi-style: LoadAsiPlugins=true, LogToFile=true, LogLevel=2, FGShortcutKey=-1)
$iniPath = Join-Path $stage 'OptiScaler.ini'
$wanted = [ordered]@{
    'Plugins|LoadAsiPlugins' = 'true'
    'Log|LogToFile'          = 'true'
    'Log|LogLevel'           = '2'
    'Menu|FGShortcutKey'     = '-1'
    # Fork look: crimson accent for the host menu, matching NR Control's Theme=4
    # (Crimson) and the launcher's #E3122B accent.
    'Menu|AccentColorR'      = '0.89'
    'Menu|AccentColorG'      = '0.07'
    'Menu|AccentColorB'      = '0.17'
    # Fork FG chain, verified on NTE: DLSSG via Streamline as the input, XeFG as the output
    # with 4X interpolation (InterpolationCount 3 = 4X per the ini docs).
    # Enabled=true is required: with the key unset the host follows the game's DLSSG
    # state, and NTE asks for 2X — so XeFG would run 2X instead of 4X.
    'FrameGen|Enabled'       = 'true'
    'FrameGen|FGInput'       = 'dlssg'
    'FrameGen|FGOutput'      = 'xefg'
    'XeFG|InterpolationCount' = '3'
    # Fork sharpening baseline: fixed 0.6 (override required or the value is ignored).
    'Sharpness|OverrideSharpness' = 'true'
    'Sharpness|Sharpness'    = '0.6'
}
$raw = [IO.File]::ReadAllText($iniPath)
$newline = if ($raw.Contains("`r`n")) { "`r`n" } else { "`n" }
$lines = $raw -split [regex]::Escape($newline)
$section = $null; $seen = @{}
for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^\s*\[([^\]]+)\]') { $section = $Matches[1]; continue }
    if ($section -and $lines[$i] -match '^\s*([A-Za-z0-9_]+)\s*=') {
        $key = "$section|$($Matches[1])"
        if ($wanted.Contains($key) -and -not $seen.ContainsKey($key)) {
            $lines[$i] = "$($Matches[1])=$($wanted[$key])"
            $seen[$key] = 1
        }
    }
}
[IO.File]::WriteAllText($iniPath, ($lines -join $newline), [Text.UTF8Encoding]::new($false))

# 5. Stage OptiScaler/plugins/ and OptiPatcher.asi
$optiPluginDst = Join-Path $stage 'OptiScaler/plugins'
New-Item -ItemType Directory -Path $optiPluginDst -Force | Out-Null
$pluginReadme = @(
    'OptiScaler(NR) - ASI Plugins Directory'
    '====================================='
    'Place custom .asi plugins (for example MFGUnlocker.asi or XeFGUnlock.asi) in this folder.'
) -join "`r`n"
[IO.File]::WriteAllText((Join-Path $optiPluginDst 'OptScaler-NR-plugins-README.txt'), ($pluginReadme + "`r`n"), [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $optiPatcherAsiSrc -Destination (Join-Path $optiPluginDst 'OptiPatcher.asi') -Force

# 6. Stage ASI 1: dlssnr-amd.asi + resources
$mzAssets = Join-Path $stage 'dlssnr-amd'
New-Item -ItemType Directory -Force $mzAssets, (Join-Path $stage 'model-tools'), (Join-Path $stage 'experimental') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $asiPayload 'dlssnr-amd') -Recurse -File | ForEach-Object {
    $relative = $_.FullName.Substring((Join-Path $asiPayload 'dlssnr-amd').Length).TrimStart('\', '/')
    $dest = Join-Path $mzAssets $relative
    $destDir = Split-Path -Parent $dest
    if ($destDir) { New-Item -ItemType Directory -Force $destDir | Out-Null }
    Copy-Item -LiteralPath $_.FullName -Destination $dest -Force
}
Copy-Item -LiteralPath (Join-Path $asiPayload 'OptiScaler/plugins/dlssnr-amd.asi') -Destination (Join-Path $optiPluginDst 'dlssnr-amd.asi') -Force
Copy-Item -LiteralPath (Join-Path $asiPayload 'nr_present_probe.exe') -Destination $mzAssets -Force
Copy-Item -LiteralPath (Join-Path $asiPayload 'ini/dlssnr-amd-optiscaler.ini') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $asiPayload 'ini/dlssnr-amd-optiscaler-renodx.ini') -Destination $stage -Force
Get-ChildItem -LiteralPath (Join-Path $asiPayload 'ini') -Filter 'dlssnr-amd-standalone.ini' -File | Copy-Item -Destination $stage -Force
Get-ChildItem -LiteralPath (Join-Path $asiPayload 'ini') -Filter 'dlssnr-amd-addon.ini' -File | Copy-Item -Destination $stage -Force
# Fork tuning replay onto the vendor templates (RenoDX chain, NRControl language/theme):
# vendor template + fork delta, so upstream's new keys survive automatically.
$forkIniSrc = Join-Path $root 'tools/release/fork-overrides/dlssnr-amd-fork.ini'
function Merge-ForkIni([string]$TargetFile, [string]$ForkFile) {
    $tLines = [IO.File]::ReadAllLines($TargetFile)
    $fLines = [IO.File]::ReadAllLines($ForkFile)
    $delta = [ordered]@{}
    $sec = ''
    foreach ($fl in $fLines) {
        $s = $fl.Trim()
        if ($s -eq '' -or $s.StartsWith(';') -or $s.StartsWith('#')) { continue }
        if ($s.StartsWith('[') -and $s.EndsWith(']')) { $sec = $s.Trim('[',']'); if (-not $delta.Contains($sec)) { $delta[$sec] = [ordered]@{} }; continue }
        if ($sec -and $s.Contains('=')) { $i = $s.IndexOf('='); $delta[$sec][$s.Substring(0,$i).Trim()] = $s.Substring($i+1).Trim() }
    }
    $out = New-Object System.Collections.Generic.List[string]
    $inSec = ''
    foreach ($line in $tLines) {
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $secName = $Matches[1].Trim()
            if ($inSec -and $delta.Contains($inSec)) {
                foreach ($k in $delta[$inSec].Keys) {
                    $set = $false
                    foreach ($ol in $out) { if ($ol -match ('^\s*' + [regex]::Escape($k) + '\s*=')) { $set = $true; break } }
                    if (-not $set) { $out.Add(("$k=" + $delta[$inSec][$k])) }
                }
            }
            $inSec = $secName
            $out.Add($line)
            continue
        }
        if ($inSec -and $delta.Contains($inSec) -and $line -match '^\s*([A-Za-z0-9_]+)\s*=') {
            $k = $Matches[1].Trim()
            if ($delta[$inSec].Contains($k)) { $line = "$k=" + $delta[$inSec][$k] }
        }
        $out.Add($line)
    }
    if ($inSec -and $delta.Contains($inSec)) {
        foreach ($k in $delta[$inSec].Keys) {
            $set = $false
            foreach ($ol in $out) { if ($ol -match ('^\s*' + [regex]::Escape($k) + '\s*=')) { $set = $true; break } }
            if (-not $set) { $out.Add(("$k=" + $delta[$inSec][$k])) }
        }
    }
    foreach ($secName in $delta.Keys) {
        $present = $false
        foreach ($ol in $out) { if ($ol -match ('^\s*\[' + [regex]::Escape($secName) + '\]\s*$')) { $present = $true; break } }
        if (-not $present) {
            $out.Add('')
            $out.Add(("[$secName]"))
            foreach ($k in $delta[$secName].Keys) { $out.Add(("$k=" + $delta[$secName][$k])) }
        }
    }
    [IO.File]::WriteAllText($TargetFile, (($out -join "`r`n") + "`r`n"), [Text.UTF8Encoding]::new($false))
}
Merge-ForkIni (Join-Path $stage 'dlssnr-amd-optiscaler.ini') $forkIniSrc
Merge-ForkIni (Join-Path $stage 'dlssnr-amd-optiscaler-renodx.ini') $forkIniSrc
Get-ChildItem -LiteralPath (Join-Path $asiPayload 'experimental') -File | Copy-Item -Destination (Join-Path $stage 'experimental') -Force
if (Test-Path -LiteralPath (Join-Path $asiPayload 'optimized') -PathType Container) {
    New-Item -ItemType Directory -Force (Join-Path $stage 'optimized') | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $asiPayload 'optimized') -File | Copy-Item -Destination (Join-Path $stage 'optimized') -Force
}
Get-ChildItem -LiteralPath (Join-Path $asiPayload 'model-tools') -File | Copy-Item -Destination (Join-Path $stage 'model-tools') -Force
Get-ChildItem -LiteralPath (Join-Path $asiPayload 'Licenses') -File | Copy-Item -Destination (Join-Path $stage 'Licenses') -Force
Copy-Item -LiteralPath (Join-Path $root 'tools/install/mochizuki-owned.txt') -Destination $stage -Force

# v2.1 multi-mode asset groups: standalone kit, ReShade feeder, DXVK/Vulkan hosts, RTX Remix MC
foreach ($mzSub in @('standalone', 'reshade', 'dxvk', 'vulkan')) {
    $mzSubSrc = Join-Path $asiPayload $mzSub
    if (Test-Path -LiteralPath $mzSubSrc -PathType Container) {
        Copy-Item -LiteralPath $mzSubSrc -Destination $stage -Recurse -Force
    }
}
$rtxMcPayload = $upstreamInfo.RtxRemixMcDir
$rtxMcStageDir = Join-Path $stage 'rtx-remix-mc'
New-Item -ItemType Directory -Force $rtxMcStageDir | Out-Null
Copy-Item -LiteralPath (Join-Path $rtxMcPayload 'rtx-remix-mc/remixbridge.dll') -Destination (Join-Path $rtxMcStageDir 'remixbridge.dll') -Force
Get-ChildItem -LiteralPath (Join-Path $rtxMcPayload 'Licenses') -File | Copy-Item -Destination (Join-Path $stage 'Licenses') -Force

@'
@echo off
setlocal
set "SOURCE=%~1"
if not defined SOURCE set "SOURCE=%~dp0nvngx_dlssnr.dll"
if not exist "%SOURCE%" (
  echo Put nvngx_dlssnr.dll 310.9.16 or 310.8.0 beside this file, or pass its path.
  pause
  exit /b 1
)
"%~dp0model-tools\dlssnr_extract_model.exe" "%SOURCE%" "%~dp0dlssnr-amd"
set "RC=%ERRORLEVEL%"
if not "%RC%"=="0" echo Model extraction failed ^(exit code %RC%^).
echo Base models only: Setup generates Experimental from Small and Optimized from Original.
pause
exit /b %RC%
'@ | Set-Content -LiteralPath (Join-Path $stage 'Mochizuki-Model.bat') -Encoding ASCII

# 7. Stage ASI 2: openrr-amd.asi (placeholder or PE) + openrr-amd/shaders/*.spv
Copy-Item -LiteralPath $openRrAsiSrc -Destination (Join-Path $optiPluginDst 'openrr-amd.asi') -Force
$openRrHostSrc = Join-Path $openRrPayload 'OptiScaler/plugins/openrr-ngx-host.dll'
if (Test-Path -LiteralPath $openRrHostSrc -PathType Leaf) {
    Copy-Item -LiteralPath $openRrHostSrc -Destination (Join-Path $optiPluginDst 'openrr-ngx-host.dll') -Force
}
$openRrIniSrc = $null
foreach ($cand in @('openrr-amd.ini', 'OptiScaler/openrr-amd.ini')) {
    $p = Join-Path $openRrPayload $cand
    if (Test-Path -LiteralPath $p -PathType Leaf) { $openRrIniSrc = $p; break }
}
if ($openRrIniSrc) {
    Copy-Item -LiteralPath $openRrIniSrc -Destination (Join-Path $stage 'openrr-amd.ini') -Force
    # Fork default: Chinese RR menu (the package ships the CJK lang pack)
    $rrIni = Join-Path $stage 'openrr-amd.ini'
    $rrRaw = [IO.File]::ReadAllText($rrIni)
    if ($rrRaw -match '(?m)^\s*;?\s*Language\s*=') {
        $rrRaw = [regex]::Replace($rrRaw, '(?m)^(\s*);?\s*Language\s*=.*$', '$1Language = zh-CN', 1)
    } else {
        $rrRaw = $rrRaw.Replace('[OpenRR]', "[OpenRR]`r`nLanguage = zh-CN", 1)
    }
    [IO.File]::WriteAllText($rrIni, $rrRaw, [Text.UTF8Encoding]::new($false))
}
$openRrShaderDst = Join-Path $stage 'openrr-amd/shaders'
New-Item -ItemType Directory -Path $openRrShaderDst -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $openRrPayload 'openrr-amd/shaders') -Filter '*.spv' -File | Copy-Item -Destination $openRrShaderDst -Force
$openRrShaderGfx11Dst = Join-Path $stage 'openrr-amd/shaders-gfx11'
New-Item -ItemType Directory -Path $openRrShaderGfx11Dst -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $openRrPayload 'openrr-amd/shaders-gfx11') -Filter '*.spv' -File | Copy-Item -Destination $openRrShaderGfx11Dst -Force
# v0.1.7plus: precompiled Mesa 26.3 FP8 ACO records + the CJK menu language pack
foreach ($rrSub in @('aco', 'lang')) {
    $rrSubSrc = Join-Path $openRrPayload (Join-Path 'openrr-amd' $rrSub)
    if (Test-Path -LiteralPath $rrSubSrc -PathType Container) {
        Copy-Item -LiteralPath $rrSubSrc -Destination (Join-Path $stage 'openrr-amd') -Recurse -Force
    }
}
# vendor licenses now ship inside openrr-amd/ (OpenRR v0.1.7plus layout)

# 8. Build & stage Launcher + Installer scripts
& (Join-Path $root 'tools/build/build-launcher.ps1') -OutDir (Join-Path $root 'exports/launcher')
$launcherExe = Join-Path $root 'exports/launcher/OptiScalerNRLauncher.exe'
if (-not (Test-Path -LiteralPath $launcherExe -PathType Leaf)) { throw 'Launcher EXE was not produced' }
Copy-Item -LiteralPath $launcherExe -Destination (Join-Path $stage 'OptiScalerNRLauncher.exe') -Force
foreach ($pair in @(
    @('tools/install/install.ps1', 'Setup.ps1'),
    @('tools/install/uninstall.ps1', 'Uninstall_OptiScaler_NR.ps1'),
    @('tools/install/launcher-worker.ps1', 'launcher-worker.ps1'),
    @('tools/install/install-capabilities.ps1', 'install-capabilities.ps1'),
    @('tools/install/library-scan.ps1', 'library-scan.ps1'),
    @('tools/install/proxy-probe.ps1', 'proxy-probe.ps1'),
    @('tools/install/xess-compat.ps1', 'xess-compat.ps1'),
    @('tools/compat-repair.ps1', 'compat-repair.ps1')
)) {
    $srcPs1 = Join-Path $root $pair[0]
    $dstPs1 = Join-Path $stage $pair[1]
    $psContent = [IO.File]::ReadAllText($srcPs1, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($dstPs1, $psContent, [Text.UTF8Encoding]::new($true))
}
$installShSrc = Join-Path $root 'tools/install/install.sh'
$installShContent = [IO.File]::ReadAllText($installShSrc, [Text.Encoding]::UTF8).Replace("`r`n", "`n")
[IO.File]::WriteAllText((Join-Path $stage 'install.sh'), $installShContent, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath (Join-Path $root 'assets/compatibility/proxy-profiles.json') -Destination $stage -Force
Copy-Item -LiteralPath (Join-Path $root 'assets/compatibility/README.md') -Destination (Join-Path $stage 'Licenses/OptiScaler-wiki-profiles.md') -Force
# Proxy-switch panel: same theme/share-code sources as the launcher, standalone exe
# placed beside the game dir launcher. Start it via the .bat below.
& (Join-Path $root 'tools/build/build-panel.ps1') -OutDir (Join-Path $root 'exports/panel')
$panelExe = Join-Path $root 'exports/panel/OptiScalerPanel.exe'
if (-not (Test-Path -LiteralPath $panelExe -PathType Leaf)) { throw 'Panel EXE was not produced' }
Copy-Item -LiteralPath $panelExe -Destination (Join-Path $stage 'OptiScalerPanel.exe') -Force
(@'
@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0OptiScalerPanel.exe" (
  echo OptiScalerPanel.exe is missing. Unzip the full package again.
  pause
  exit /b 1
)
start "" "%~dp0OptiScalerPanel.exe" "%~dp0."
'@) | Set-Content -LiteralPath (Join-Path $stage 'OptiScaler代理切换.bat') -Encoding ASCII
Copy-Item -LiteralPath (Join-Path $root 'LICENSE'), (Join-Path $root 'NOTICE') -Destination $stage -Force
foreach ($doc in @('README.md', 'README.en.md', 'README.es.md')) {
    $p = Join-Path $root $doc
    if (Test-Path -LiteralPath $p -PathType Leaf) { Copy-Item -LiteralPath $p -Destination $stage -Force }
}
if (Test-Path -LiteralPath (Join-Path $root 'docs/legacy-readme') -PathType Container) {
    $legacyReadmeDst = Join-Path $stage 'docs/legacy-readme'
    New-Item -ItemType Directory -Force -Path $legacyReadmeDst | Out-Null
    Get-ChildItem -LiteralPath (Join-Path $root 'docs/legacy-readme') -File | Copy-Item -Destination $legacyReadmeDst -Force
}
Set-Content -LiteralPath (Join-Path $stage 'VERSION') -Value ($Version + "`n") -Encoding UTF8

(@'
@echo off
setlocal
title OptiScaler(NR) @VERSION@ - Uninstall
if "%~1"=="" (
  powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Uninstall_OptiScaler_NR.ps1" -NoPause
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Uninstall_OptiScaler_NR.ps1" -GameDir "%~1" -NoPause
)
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" echo Uninstall failed ^(exit code %EC%^). See the error above.
pause
exit /b %EC%
'@).Replace('@VERSION@', $Version) | Set-Content -LiteralPath (Join-Path $stage 'Uninstall_OptiScaler_NR.bat') -Encoding ASCII

if ($LocalTest) {
    [IO.File]::WriteAllText((Join-Path $stage 'LOCAL-TEST.txt'),
        "Local test package $Version.`n",
        [Text.UTF8Encoding]::new($false))
}

# 9. Forbidden proprietary/model file gate
$forbidden = '(?i)^(nvngx.*\.dll|dlssnr_amd_pass.*\.dll|dlssnr_on_amd_weights\.bin|dlssnr(?:-int4|-small)?\.bin|CC_(?:SMALL_FP8|SMALL_FP8_EXPERIMENTAL|SILVER_AARDWOLD|SILVER_AARDWOLD_OPTIMIZED|SILVER_AARDWOLD_OPTIMIZED_INT4)\.bin|version\.dll|dlssnr_on_amd_setup\.exe)$'
$badAll = Get-ChildItem -LiteralPath $stage -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $forbidden }
if ($badAll) {
    throw "Refusing to package proprietary/user-supplied file: $(($badAll | ForEach-Object { $_.FullName.Substring($stage.Length+1) }) -join ', ')"
}

# 10. Sign unstamped PE files (skips 0-byte placeholder openrr.asi automatically)
. (Join-Path $PSScriptRoot 'package-signing.ps1')
Invoke-PackageSigning -Stage $stage -Thumbprint $SigningThumbprint

# 11. Generate SHA256SUMS.txt & ZIP
$expectedEntries = @{}
$hashes = Get-ChildItem -LiteralPath $stage -Recurse -File |
    Where-Object { $_.Name -ne 'SHA256SUMS.txt' } |
    Sort-Object FullName |
    ForEach-Object {
        $relative = $_.FullName.Substring($stage.Length + 1).Replace('\', '/')
        $digest = Get-Sha256 $_.FullName
        $expectedEntries[$relative] = $digest
        '{0} *{1}' -f $digest, $relative
    }
[IO.File]::WriteAllText((Join-Path $stage 'SHA256SUMS.txt'), (($hashes -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
$expectedEntries['SHA256SUMS.txt'] = Get-Sha256 (Join-Path $stage 'SHA256SUMS.txt')

New-Item -ItemType Directory -Force -Path (Join-Path $root $OutDir) | Out-Null
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
try {
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal -Force
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $seen = @{}
        foreach ($entry in $archive.Entries) {
            $relative = $entry.FullName.Replace('\', '/')
            if ([string]::IsNullOrEmpty($entry.Name)) { continue }
            if ($entry.Name -match $forbidden -or -not $expectedEntries.ContainsKey($relative) -or $seen.ContainsKey($relative)) {
                throw "Unexpected, forbidden or duplicate archive entry: $relative"
            }
            $seen[$relative] = $true
            $stream = $entry.Open()
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
            finally { $stream.Dispose(); $sha.Dispose() }
            if ($actual -ne $expectedEntries[$relative]) { throw "Archive checksum mismatch: $relative" }
        }
        foreach ($required in @('OptiScaler.dll', 'OptiScaler.ini', 'Setup.ps1', 'install.sh', 'OptiScalerNRLauncher.exe', 'OptiScalerPanel.exe', 'OptiScaler代理切换.bat', 'launcher-worker.ps1', 'proxy-probe.ps1', 'library-scan.ps1', 'install-capabilities.ps1', 'xess-compat.ps1', 'compat-repair.ps1', 'proxy-profiles.json', 'OptiScaler/plugins/dlssnr-amd.asi', 'OptiScaler/plugins/openrr-amd.asi', 'dlssnr-amd/nr_present_probe.exe', 'model-tools/dlssnr_extract_model.exe', 'experimental/dlssnr-small-experimental.delta', 'dlssnr-amd-optiscaler.ini', 'dlssnr-amd-optiscaler-renodx.ini', 'mochizuki-owned.txt', 'rtx-remix-mc/remixbridge.dll', 'Licenses/RTX-Remix-Minecraft-AMD-Patch_LICENSE.txt', 'Licenses/RTX-Remix-Minecraft-AMD-Patch_NOTICE.txt', 'Licenses/NVIDIA-rtx-remix-minecraft-Apache-2.0.txt', 'standalone/dxgi.dll', 'standalone/vk-override/implicit_layer/dlssnr_standalone.json', 'reshade/ReShade64.dll', 'reshade/dlssnr_amd.addon64', 'dxvk/dxgi.dll', 'vulkan/vulkan-1.dll', 'dlssnr-amd/lang/zh-CN.txt', 'dlssnr-amd/lang/fonts/NotoSansCJKsc-Regular.ttf') + @($expectedEntries.Keys)) {
            if (-not $seen.ContainsKey($required)) { throw "Package archive missing required component: $required" }
        }
    } finally {
        $archive.Dispose()
    }
} catch {
    if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
    throw "Package archive validation failed; zip removed: $($_.Exception.Message)"
}

Write-Host "Product: $Version" -ForegroundColor Green
Write-Host "Staged:  $stage" -ForegroundColor Green
Write-Host "Zip:     $zip" -ForegroundColor Green
