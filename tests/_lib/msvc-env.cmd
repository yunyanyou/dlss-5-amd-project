@echo off
rem Enter the x64 MSVC 14.44 environment when cl.exe is not already on PATH.
rem CALL this without setlocal so the environment reaches the caller. CI (and any
rem developer prompt) already has cl, so this is a no-op there.
where cl.exe >nul 2>&1 && exit /b 0
rem Candidate toolchains in priority order: the CI's VS 18 BuildTools, then
rem vswhere-detected and well-known local Visual Studio installs. The first
rem existing vcvarsall wins; vcvars_ver only applies when that install ships
rem MSVC 14.44 (older installs use their default toolset).
set "MSVC_ENV_VCVARS="
for %%V in (
    "C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat"
    "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat"
) do (
    if not defined MSVC_ENV_VCVARS if exist "%%~V" set "MSVC_ENV_VCVARS=%%~V"
)
if not defined MSVC_ENV_VCVARS if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" (
    for /f "usebackq delims=" %%P in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
        if not defined MSVC_ENV_VCVARS if exist "%%P\VC\Auxiliary\Build\vcvarsall.bat" set "MSVC_ENV_VCVARS=%%P\VC\Auxiliary\Build\vcvarsall.bat"
    )
)
if not defined MSVC_ENV_VCVARS (
    echo FAIL: cl.exe is not on PATH and no Visual Studio vcvarsall.bat was found.
    echo Looked in: VS 18 BuildTools, VS 2022 Community/Professional/Enterprise/BuildTools, vswhere latest.
    exit /b 1
)
call "%MSVC_ENV_VCVARS%" x64 10.0.26100.0 -vcvars_ver=14.44 >nul
where cl.exe >nul 2>&1 || (
    echo FAIL: vcvarsall did not put cl.exe on PATH.
    exit /b 1
)
exit /b 0
