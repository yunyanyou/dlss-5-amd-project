# compat-repair.ps1 - CLI entry the panel drives over the upstream xess-compat transaction
# library. All file mutations, journal handling and rollback stay in xess-compat.ps1;
# this wrapper only picks the action so the C# side never re-implements the hash logic.
#
# Usage:
#   compat-repair.ps1 -Action Repair  -GameDir <dir> -Group sr,fg
#   compat-repair.ps1 -Action Restore -GameDir <dir>
#   compat-repair.ps1 -Action Keep    -GameDir <dir>
#
# Output: one line "OK:<message>" on success, "ERROR:<message>" on failure (exit 1).
param(
    [Parameter(Mandatory = $true)][ValidateSet('Repair', 'Restore', 'Keep')][string] $Action,
    [Parameter(Mandatory = $true)][string] $GameDir,
    [string[]] $Group
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }

. (Join-Path $PSScriptRoot 'xess-compat.ps1')

try {
    switch ($Action) {
        'Repair' {
            # Repair re-verifies the fingerprint internally (twice); passing it straight from
            # the fresh report keeps the panel out of the fingerprint business.
            $report = Get-XessCompatibility -GameDir $GameDir -PackageRoot $PSScriptRoot
            Repair-XessCompatibility -GameDir $GameDir -PackageRoot $PSScriptRoot -Groups $Group -Fingerprint $report.fingerprint
            Write-Output ('OK:已备份并修复 ' + (@($Group | Where-Object { $_ }) -join '、'))
        }
        'Restore' {
            Restore-XessCompatibility -GameDir $GameDir
            Write-Output 'OK:已恢复游戏原文件'
        }
        'Keep' {
            $journal = Get-XessJournal -GameDir $GameDir
            if ($null -eq $journal -or $journal.state -notin @('pending', 'applied')) { throw '当前没有可结束的修复记录。' }
            Complete-XessCompatibility -GameDir $GameDir -Transaction $journal.transaction
            Write-Output 'OK:已保留当前文件并结束修复（备份仍保留）'
        }
    }
    exit 0
}
catch {
    Write-Output ('ERROR:' + $_.Exception.Message)
    exit 1
}
