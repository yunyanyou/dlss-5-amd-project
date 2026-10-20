@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

rem Double-click: annotated menu from the PowerShell script.
rem With arguments: pass them straight through.

if not "%~1"=="" goto passthrough

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch-loader.ps1" -Interactive -Dir "%~dp0."
echo.
pause
exit /b

:passthrough
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch-loader.ps1" %*

:done
rem Keep the window open only when double-clicked (no arguments).
if "%~1"=="" pause
