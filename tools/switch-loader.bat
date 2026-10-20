@echo off
setlocal
cd /d "%~dp0"

rem 双击运行进入菜单；带参数时直接透传给 PowerShell 脚本。

if not "%~1"=="" goto passthrough

:menu
echo.
echo  OptiScaler 加载器切换
echo  ------------------------
echo   1. winmm.dll    （大多数游戏）
echo   2. dxgi.dll
echo   3. d3d12.dll
echo   4. d3d11.dll
echo   5. version.dll
echo   6. opengl32.dll
echo   0. 查看当前加载器
echo   9. 取消
echo.
set "LOADER="
set /p "CHOICE=请选择: "
if "%CHOICE%"=="1" set "LOADER=winmm"
if "%CHOICE%"=="2" set "LOADER=dxgi"
if "%CHOICE%"=="3" set "LOADER=d3d12"
if "%CHOICE%"=="4" set "LOADER=d3d11"
if "%CHOICE%"=="5" set "LOADER=version"
if "%CHOICE%"=="6" set "LOADER=opengl32"
if "%CHOICE%"=="0" goto show
if "%CHOICE%"=="9" exit /b
if not defined LOADER goto menu

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch-loader.ps1" -Name %LOADER% -Dir "%~dp0."
goto done

:show
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch-loader.ps1" -Name winmm -Dir "%~dp0." -List
echo.
pause
goto menu

:passthrough
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0switch-loader.ps1" %*

:done
rem 仅在双击（无参数）时暂停，命令行调用不留阻塞。
if "%~1"=="" pause
