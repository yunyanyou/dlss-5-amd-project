<#
.SYNOPSIS
  Rename the OptiScaler host DLL to the loader name a game expects.

.DESCRIPTION
  OptiScaler is installed by naming its DLL after a system DLL the game already
  imports (winmm.dll, dxgi.dll, d3d12.dll, ...). Only one loader may exist in a
  game folder, so this script finds the current one by size, checks the target
  name is free (or is the loader itself) and renames it.

  A hand-placed DLL that is not the host is never overwritten: the script stops
  and asks for a backup instead.

.PARAMETER Name
  Loader to install: winmm, dxgi, d3d12, d3d11, version or opengl32.

.PARAMETER Dir
  Game folder. Defaults to the current directory.

.PARAMETER Current
  Current loader name. Detected when omitted: the only candidate above 20 MB.

.PARAMETER DryRun
  Print the plan and exit without renaming anything.

.EXAMPLE
  .\switch-loader.ps1 -Name dxgi -Dir "F:\Game\Binaries\Win64"

.EXAMPLE
  .\switch-loader.ps1 -Name winmm -Dir . -List
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('winmm', 'dxgi', 'd3d12', 'd3d11', 'version', 'opengl32')]
    [string] $Name,
    [string] $Dir = '.',
    [string] $Current = '',
    [switch] $DryRun,
    [switch] $List
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Step([string] $t) { Write-Host "==> $t" -ForegroundColor Cyan }
function Info([string] $t) { Write-Host "    $t" }
function Warn([string] $t) { Write-Host "    ! $t" -ForegroundColor Yellow }
function Die([string] $t) { Write-Host "ERROR: $t" -ForegroundColor Red; exit 1 }

$candidates = @('winmm', 'dxgi', 'd3d12', 'd3d11', 'version', 'opengl32')

if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { Die "Folder not found: $Dir" }
$Dir = (Resolve-Path -LiteralPath $Dir).Path

# The host is a ~27 MB DLL; system stand-ins are far smaller. Size is the only
# signal available without a reference hash, so require it to be unambiguous.
$present = @()
foreach ($c in $candidates) {
    $f = Join-Path $Dir ($c + '.dll')
    if (Test-Path -LiteralPath $f -PathType Leaf) {
        $present += [pscustomobject]@{ Name = $c; Path = $f; MB = [math]::Round((Get-Item -LiteralPath $f).Length / 1MB, 1); Bytes = (Get-Item -LiteralPath $f).Length }
    }
}

Step "Folder: $Dir"
if ($present.Count -eq 0) { Info 'no loader candidates present' }
foreach ($p in $present) { Info ("{0}.dll  {1} MB{2}" -f $p.Name, $p.MB, $(if ($p.Bytes -gt 20MB) { '  <- host-sized' } else { '' })) }
if ($List) { exit 0 }

$targetName = $Name
$targetPath = Join-Path $Dir ($targetName + '.dll')

# Locate the current loader.
$loader = $null
if ($Current) {
    $cp = Join-Path $Dir ($Current + '.dll')
    if (-not (Test-Path -LiteralPath $cp -PathType Leaf)) { Die "$Current.dll not found in $Dir" }
    $loader = $cp
} else {
    $hosts = @($present | Where-Object { $_.Bytes -gt 20MB })
    if ($hosts.Count -gt 1) {
        Die ('Several host-sized DLLs are present ({0}); pass -Current.' -f (($hosts | ForEach-Object { $_.Name }) -join ', '))
    }
    if ($hosts.Count -eq 1) { $loader = $hosts[0].Path }
}

if (-not $loader) { Die 'No OptiScaler host DLL found (none of the candidate names is above 20 MB). Pass -Current.' }

$loaderName = [IO.Path]::GetFileNameWithoutExtension($loader)
Step "Current loader: $loaderName.dll"
if ($loaderName -eq $targetName) { Info 'already installed as the requested name; nothing to do.'; exit 0 }

if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
    $existing = (Get-Item -LiteralPath $targetPath).Length
    if ($existing -gt 20MB) {
        # Another copy of the host under the target name: keep the target, drop the old one.
        Warn "$targetName.dll already exists and is host-sized; removing the old loader instead."
        if ($DryRun) { Step 'DryRun: would remove old loader'; exit 0 }
        Remove-Item -LiteralPath $loader -Force
        Step "Removed $loaderName.dll"
    } else {
        Die "$targetName.dll already exists ($([math]::Round($existing/1KB)) KB) and is not the host. Back it up or pick another loader name."
    }
} else {
    if ($DryRun) { Step "DryRun: would rename $loaderName.dll -> $targetName.dll"; exit 0 }
    Move-Item -LiteralPath $loader -Destination $targetPath
    Step "Renamed $loaderName.dll -> $targetName.dll"
}

Info 'Restart the game. Only one loader may exist in this folder.'
Info 'Weights (dlssnr-amd / native-game-tiled-assets) are not touched by this script.'
