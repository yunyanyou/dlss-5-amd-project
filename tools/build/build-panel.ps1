# Compile the slim panel (OptiScalerPanel.exe) with the machine's .NET Framework WPF.
# It reuses the launcher's theme, share-code and preset code, so the look and the
# behaviour come from the same sources as the upstream launcher.
# Output: exports/panel/ (never the repo root).
[CmdletBinding()]
param(
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$panel = Join-Path $root 'tools/install/panel'
$launcher = Join-Path $root 'tools/install/launcher'

if (-not $OutDir) { $OutDir = Join-Path $root 'exports/panel' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$fw = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319'
$csc = Join-Path $fw 'csc.exe'
$wpf = Join-Path $fw 'WPF'
foreach ($need in @($csc, (Join-Path $wpf 'PresentationFramework.dll'))) {
    if (-not (Test-Path -LiteralPath $need)) { throw "Missing compiler dependency: $need" }
}

$exe = Join-Path $OutDir 'OptiScalerPanel.exe'
$obj = Join-Path $OutDir 'obj'
New-Item -ItemType Directory -Force -Path $obj | Out-Null

$cs = @(
    (Join-Path $panel 'PanelProgram.cs'),
    (Join-Path $panel 'PanelWindow.cs'),
    (Join-Path $launcher 'LauncherTheme.cs'),
    (Join-Path $launcher 'DialogTheme.cs'),
    (Join-Path $launcher 'MochizukiShareCode.cs'),
    (Join-Path $launcher 'IniProfiles.cs'),
    (Join-Path $launcher 'ProxyRecommendations.cs'),
    (Join-Path $launcher 'Protocol.cs'),
    (Join-Path $launcher 'GamePaths.cs')
)

$refs = @(
    (Join-Path $fw 'mscorlib.dll'),
    (Join-Path $fw 'System.dll'),
    (Join-Path $fw 'System.Core.dll'),
    (Join-Path $fw 'System.Runtime.Serialization.dll'),
    (Join-Path $fw 'System.Xaml.dll'),
    (Join-Path $wpf 'WindowsBase.dll'),
    (Join-Path $wpf 'PresentationCore.dll'),
    (Join-Path $wpf 'PresentationFramework.dll'),
    (Join-Path $fw 'System.Drawing.dll')
)

$res = @(
    "/resource:`"$(Join-Path $panel 'PanelWindow.xaml')`",OptiScalerPanel.PanelWindow.xaml",
    "/resource:`"$(Join-Path $launcher 'DialogTheme.xaml')`",OptiScalerPanel.DialogTheme.xaml",
    "/resource:`"$(Join-Path $root 'assets/compatibility/proxy-profiles.json')`",OptiScalerPanel.proxy-profiles.json"
)

$argFile = Join-Path $obj 'csc.rsp'
$lines = @(
    '/nologo',
    '/t:winexe',
    '/platform:x64',
    '/optimize+',
    '/debug:pdbonly',
    "/out:`"$exe`""
)
$lines += $refs | ForEach-Object { "/r:`"$_`"" }
$lines += $res
$lines += $cs | ForEach-Object { "`"$_`"" }
Set-Content -LiteralPath $argFile -Value $lines -Encoding ASCII

& $csc "@$argFile"
if ($LASTEXITCODE -ne 0) { throw "csc failed: $LASTEXITCODE" }
if (-not (Test-Path -LiteralPath $exe)) { throw 'Panel EXE was not produced' }

Write-Host "PANEL_OK $exe"
