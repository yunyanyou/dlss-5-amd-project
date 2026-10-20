@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

rem Double-click: the PowerShell script shows the menu and waits for a key.
rem With arguments they are passed straight through.
rem Keep this file ASCII only: cmd mis-parses non-ASCII lines after chcp 65001.

if not "%~1"=="" goto passthrough

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0proxy-switch.ps1" -Interactive -Dir "%~dp0."
exit /b %ERRORLEVEL%

:passthrough
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0proxy-switch.ps1" %*
exit /b %ERRORLEVEL%
