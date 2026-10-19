<#
.SYNOPSIS
  Minimal, idempotent OptiScaler AM(D)-NR installer for a game folder.

.DESCRIPTION
  Mirrors a compiled package into a game folder the same way the release package is
  laid out: OptiScaler.dll becomes the loader name the game already uses (winmm.dll
  by default), the root runtime DLLs and data folders go beside the game exe, and
  OptiScaler\ keeps the XeSS/FFX runtimes. It picks the lmxxf model set explicitly,
  writes the matching ini keys and verifies the result. Unlike the launcher it never
  offers a model the install does not have, and it treats
  native-game-tiled-assets\small\model-manifest.json as valid evidence of a Small install.

.PARAMETER GameDir
  Folder that contains the game exe (e.g. ...\WindowsNoEditor\HT\Binaries\Win64).

.PARAMETER Backend
  NrBackend to write: mochizuki (default), lmxxf or daniel.

.PARAMETER Model
  lmxxf model set: both (default), original or small.

.PARAMETER Loader
  Loader DLL name to install as. Defaults to the one already present in GameDir
  (winmm.dll / d3d12.dll / dxgi.dll / version.dll), otherwise winmm.dll.

.PARAMETER Source
  Package folder. Defaults to the newest OptScaler-NR-* under F:\hssm\amd-nr.

.PARAMETER NoBackup
  Skip the OptiScaler.bak-<timestamp> backup.

.PARAMETER DryRun
  Print the plan and exit without touching the game folder.

.EXAMPLE
  .\install-lite.ps1 -GameDir "F:\Game\Binaries\Win64" -Backend mochizuki -Model small -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $GameDir,
    [ValidateSet('mochizuki', 'lmxxf', 'daniel')] [string] $Backend = 'mochizuki',
    [ValidateSet('both', 'original', 'small')] [string] $Model = 'both',
    [string] $Loader = '',
    [string] $Source = '',
    [switch] $NoBackup,
    [switch] $DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Step([string] $text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Info([string] $text) { Write-Host "    $text" }
function Warn([string] $text) { Write-Host "    ! $text" -ForegroundColor Yellow }
function Die([string] $text) { Write-Host "ERROR: $text" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------- resolve source
if (-not (Test-Path -LiteralPath $GameDir -PathType Container)) { Die "GameDir not found: $GameDir" }
$GameDir = (Resolve-Path -LiteralPath $GameDir).Path

if ([string]::IsNullOrWhiteSpace($Source)) {
    # Prefer the folder this script ships in when it is itself a package, so running
    # it from a release folder installs that release rather than whatever happens to
    # be newest on the build machine.
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'OptiScaler.dll')) {
        $Source = $PSScriptRoot
    } else {
        $base = 'F:\hssm\amd-nr'
        $candidates = Get-ChildItem -LiteralPath $base -Directory -Filter 'OptScaler-NR-*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
        if (-not $candidates) { Die "No OptScaler-NR-* package under $base; pass -Source." }
        $Source = $candidates[0].FullName
    }
}
if (-not (Test-Path -LiteralPath $Source -PathType Container)) { Die "Source not found: $Source" }
$Source = (Resolve-Path -LiteralPath $Source).Path

if (-not (Test-Path -LiteralPath (Join-Path $Source 'OptiScaler.dll'))) {
    Die "Package is missing OptiScaler.dll at its root: $Source"
}

# --------------------------------------------------------------- classify model
$assets = Join-Path $Source 'native-game-tiled-assets'
$hasOriginal = $false
$hasSmall = $false
if (Test-Path -LiteralPath $assets) {
    $hasOriginal = (Test-Path -LiteralPath (Join-Path $assets 'block0-ffn.f16')) -or
                   (Test-Path -LiteralPath (Join-Path $assets 'block0-ffn.f32'))
    $hasSmall = Test-Path -LiteralPath (Join-Path $assets 'small\model-manifest.json')
}
Step "Package: $Source"
if ($hasOriginal) { Info 'original weights (root block*.f16/f32): yes' } else { Info 'original weights: no' }
if ($hasSmall) { Info 'small weights (small\model-manifest.json): yes' } else { Info 'small weights: no' }

if ($Backend -eq 'lmxxf') {
    if ($Model -eq 'original' -and -not $hasOriginal) { Die "Model=original but the package has no root block0-ffn weights." }
    if ($Model -eq 'small' -and -not $hasSmall) { Die "Model=small but the package has no small\model-manifest.json." }
    if ($Model -eq 'both' -and (-not $hasOriginal -or -not $hasSmall)) {
        Warn 'Model=both requested but the package lacks one model set; installing what exists.'
    }
}

# ----------------------------------------------------------------- loader name
$loaderCandidates = @('winmm.dll', 'd3d12.dll', 'dxgi.dll', 'version.dll')
if ([string]::IsNullOrWhiteSpace($Loader)) {
    $existing = $loaderCandidates | Where-Object { Test-Path -LiteralPath (Join-Path $GameDir $_) } | Select-Object -First 1
    if ($existing) { $Loader = $existing } else { $Loader = 'winmm.dll' }
}
Step "Loader: $Loader"

# ------------------------------------------------------------------- plan files
$sharedExt = @('.cso', '.hlsl', '.hlsli', '.i32')
$sharedDirs = @('HIP')
$originalExtra = @('post70-history-head.f16')   # belongs to Small even though it sits at root
$rootFiles = @('OptiScaler.ini', 'nvngx_dlssnr.dll', 'LmxxfNrRuntime.dll', 'MochizukiNrRuntime.dll')
$rootDirs = @('dlssnr-amd', 'lmxxf-modules', 'shaders', 'person-model', 'experimental_lighting', 'Licenses')

$plan = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[string]

function Add-File([string] $src, [string] $dst) {
    if (Test-Path -LiteralPath $src -PathType Leaf) {
        $plan.Add([pscustomobject]@{ Source = $src; Destination = $dst }) | Out-Null
    }
}
function Add-Tree([string] $srcDir, [string] $dstDir) {
    if (-not (Test-Path -LiteralPath $srcDir)) { return }
    Get-ChildItem -LiteralPath $srcDir -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($srcDir.Length).TrimStart('\')
        $plan.Add([pscustomobject]@{ Source = $_.FullName; Destination = (Join-Path $dstDir $rel) }) | Out-Null
    }
}

# main loader + root runtime
Add-File (Join-Path $Source 'OptiScaler.dll') (Join-Path $GameDir $Loader)
foreach ($f in $rootFiles) { Add-File (Join-Path $Source $f) (Join-Path $GameDir $f) }
foreach ($d in $rootDirs) { Add-Tree (Join-Path $Source $d) (Join-Path $GameDir $d) }

# OptiScaler\ subdir: XeSS/FFX runtimes, D3D12 shim and plugins
Add-Tree (Join-Path $Source 'OptiScaler') (Join-Path $GameDir 'OptiScaler')

# weights live beside the OptiScaler subdir (the installer and the runtime look there)
$gameWeights = Join-Path $GameDir 'OptiScaler\native-game-tiled-assets'
if (Test-Path -LiteralPath $assets) {
    $wantShared = $true
    $wantOriginal = ($Model -eq 'both' -or $Model -eq 'original') -and $hasOriginal
    $wantSmall = ($Model -eq 'both' -or $Model -eq 'small') -and $hasSmall

    if ($wantShared) {
        Get-ChildItem -LiteralPath $assets -File | Where-Object { $sharedExt -contains $_.Extension } | ForEach-Object {
            Add-File $_.FullName (Join-Path $gameWeights $_.Name)
        }
        foreach ($d in $sharedDirs) { Add-Tree (Join-Path $assets $d) (Join-Path $gameWeights $d) }
    }
    if ($wantOriginal) {
        Get-ChildItem -LiteralPath $assets -File | Where-Object {
            ($_.Extension -eq '.f16' -or $_.Extension -eq '.f32') -and ($originalExtra -notcontains $_.Name)
        } | ForEach-Object {
            Add-File $_.FullName (Join-Path $gameWeights $_.Name)
        }
    }
    if ($wantSmall) {
        Add-Tree (Join-Path $assets 'small') (Join-Path $gameWeights 'small')
        foreach ($name in $originalExtra) { Add-File (Join-Path $assets $name) (Join-Path $gameWeights $name) }
    }
    if (-not $wantOriginal -and $hasOriginal) { $skipped.Add('root .f16/.f32 original weights') | Out-Null }
    if (-not $wantSmall -and $hasSmall) { $skipped.Add('small\ weights') | Out-Null }
}

Step ("Plan: " + $plan.Count + " file(s)")
if ($skipped.Count -gt 0) { Info ("skipped: " + ($skipped -join ', ')) }
$plan | Group-Object { Split-Path -Parent $_.Destination } | Sort-Object Count -Descending | Select-Object -First 8 |
    ForEach-Object { Info ($_.Count.ToString().PadLeft(5) + '  ' + $_.Name) }

if ($DryRun) { Step 'DryRun only; nothing was written.'; exit 0 }

# ---------------------------------------------------------------------- backup
$gameOpti = Join-Path $GameDir 'OptiScaler'
if (-not $NoBackup -and (Test-Path -LiteralPath $gameOpti)) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = Join-Path $GameDir ("OptiScaler.bak-$stamp")
    Step "Backup: $bak"
    Copy-Item -LiteralPath $gameOpti -Destination $bak -Recurse -Force
}

# ----------------------------------------------------------------------- copy
Step 'Copying'
foreach ($item in $plan) {
    $dir = Split-Path -Parent $item.Destination
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item -LiteralPath $item.Source -Destination $item.Destination -Force
}

# ------------------------------------------------------------------ write ini
$iniPath = Join-Path $GameDir 'OptiScaler.ini'
if (Test-Path -LiteralPath $iniPath) {
    Step 'Updating ini keys'
    $lines = @(Get-Content -LiteralPath $iniPath)
    $modelValue = '0'
    if ($Model -eq 'small') { $modelValue = '1' }
    $updates = [ordered]@{
        'NrBackend'         = $Backend
        'LmxxfNetworkModel' = $modelValue
    }
    foreach ($key in $updates.Keys) {
        $pattern = '^' + [regex]::Escape($key) + '\s*=\s*.*$'
        $found = $false
        $newLines = foreach ($line in $lines) {
            if ($line -match $pattern) { $found = $true; $key + '=' + $updates[$key] } else { $line }
        }
        $lines = @($newLines)
        if (-not $found) { $lines += ($key + '=' + $updates[$key]) }
        Info ($key + '=' + $updates[$key])
    }
    Set-Content -LiteralPath $iniPath -Value $lines -Encoding UTF8
}

# --------------------------------------------------------------------- verify
Step 'Verifying'
$failures = New-Object System.Collections.Generic.List[string]

$vOriginal = (Test-Path -LiteralPath (Join-Path $gameWeights 'block0-ffn.f16')) -or
             (Test-Path -LiteralPath (Join-Path $gameWeights 'block0-ffn.f32'))
$vSmall = Test-Path -LiteralPath (Join-Path $gameWeights 'small\model-manifest.json')

if ($Backend -eq 'lmxxf') {
    if (($Model -eq 'original' -or $Model -eq 'both') -and -not $vOriginal) {
        $failures.Add('original weights missing after install') | Out-Null
    }
    if (($Model -eq 'small' -or $Model -eq 'both') -and -not $vSmall) {
        $failures.Add('small\model-manifest.json missing after install') | Out-Null
    }
    if (Test-Path -LiteralPath $iniPath) {
        $ini = @(Get-Content -LiteralPath $iniPath)
        $modelLine = $ini | Select-String -Pattern '^LmxxfNetworkModel\s*=\s*(\d+)' | Select-Object -First 1
        if ($modelLine) {
            $modelValue = [int]$modelLine.Matches[0].Groups[1].Value
            if ($modelValue -eq 1 -and -not $vSmall) { $failures.Add('LmxxfNetworkModel=1 but small\ is not present') | Out-Null }
            if ($modelValue -eq 0 -and -not $vOriginal) { $failures.Add('LmxxfNetworkModel=0 but root weights are not present') | Out-Null }
        }
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $GameDir $Loader))) {
    $failures.Add($Loader + ' missing') | Out-Null
}

if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Warn $f }
    Die ('Installed with ' + $failures.Count + ' verification failure(s).')
}

Step 'Done'
Info ('backend: ' + $Backend + ' | model: ' + $Model + ' | loader: ' + $Loader)
$origText = 'no'; if ($vOriginal) { $origText = 'yes' }
$smallText = 'no'; if ($vSmall) { $smallText = 'yes' }
Info ('original weights: ' + $origText + ' | small weights: ' + $smallText)
Info 'Restart the game. The menu only offers models that are actually installed.'
