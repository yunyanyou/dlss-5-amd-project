@echo off
setlocal
cd /d "%~dp0"

rem Double-click: show a menu. With arguments: pass them to the PowerShell script.

if not "%~1"=="" goto passthrough

:menu
echo.
echo  OptiScaler loader switch
echo  ------------------------
echo   1. winmm.dll    (most games)
echo   2. dxgi.dll
echo   3. d3d12.dll
echo   4. d3d11.dll
echo   5. version.dll
echo   6. opengl32.dll
echo   0. show current loader
echo   9. cancel
echo.
set "LOADER="
set /p "CHOICE=Choose: "
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
rem Keep the window open only when double-clicked (no arguments).
if "%~1"=="" pause
