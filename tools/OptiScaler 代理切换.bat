@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"

rem 双击运行：由 PowerShell 脚本显示菜单。
rem 带参数：直接透传。

if not "%~1"=="" goto passthrough

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0proxy-switch.ps1" -Interactive -Dir "%~dp0."
echo.
echo 请按任意键继续...
pause >nul
exit /b

:passthrough
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0proxy-switch.ps1" %*

:done
rem 仅在双击（无参数）时暂停，命令行调用不留阻塞。
if "%~1"=="" (
    echo.
    echo 请按任意键继续...
    pause >nul
)
