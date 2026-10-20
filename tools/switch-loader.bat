@echo off
setlocal
cd /d "%~dp0"

rem 双击运行进入菜单；带参数时直接透传给 PowerShell 脚本。

if not "%~1"=="" goto passthrough

:menu
echo.
echo  OptiScaler 加载器切换
echo  ------------------------
echo   1. dxgi.dll      默认；游戏起不来时改 winmm
echo   2. winmm.dll     部分游戏推荐
echo   3. d3d12.dll
echo   4. winhttp.dll
echo   5. wininet.dll
echo   6. dbghelp.dll
echo   7. version.dll
echo   8. d3d11.dll     非上游默认列表
echo   9. opengl32.dll  非上游默认列表
echo   0. 查看当前加载器
echo   q. 取消
echo.
echo  不要使用 dinput8.dll：此版本没有对应导出，游戏会加载失败。
echo.
set "LOADER="
set /p "CHOICE=请选择: "
if /i "%CHOICE%"=="1" set "LOADER=dxgi"
if /i "%CHOICE%"=="2" set "LOADER=winmm"
if /i "%CHOICE%"=="3" set "LOADER=d3d12"
if /i "%CHOICE%"=="4" set "LOADER=winhttp"
if /i "%CHOICE%"=="5" set "LOADER=wininet"
if /i "%CHOICE%"=="6" set "LOADER=dbghelp"
if /i "%CHOICE%"=="7" set "LOADER=version"
if /i "%CHOICE%"=="8" set "LOADER=d3d11"
if /i "%CHOICE%"=="9" set "LOADER=opengl32"
if "%CHOICE%"=="0" goto show
if /i "%CHOICE%"=="q" exit /b
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
