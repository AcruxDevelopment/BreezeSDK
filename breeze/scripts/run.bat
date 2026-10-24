@echo off
REM Run an executable module by its CMake target name (as registered in
REM that module's own CMakeLists.txt), resolved via the manifest that
REM _write_module_manifest() generates at configure time -- so this script
REM never needs updating when modules are added, removed, or renamed.
REM
REM Usage (from the project root):
REM   breeze\scripts\run.bat [--preset <name>] <target-name> [-- program-args...]
REM
REM   --preset <name>  Run the build made with that preset (out\build\<name>).
REM                    Without it: the build breeze\scripts\build.bat made last, or
REM                    the only one that exists. Must come first if given at
REM                    all; --preset=<name> also works.
REM
REM Examples:
REM   breeze\scripts\run.bat hello_exe
REM   breeze\scripts\run.bat --preset windows-x64-clang-cl hello_exe
REM   breeze\scripts\run.bat farewell_exe -- Ale
REM
REM Set BUILD_DIR to run out of an exact build directory instead.
setlocal enabledelayedexpansion

cd /d "%~dp0..\.."

REM --preset must come first if given at all, same as breeze\scripts\build.bat.
REM cmd.exe splits "--preset=<name>" into "--preset" and "<name>" on its own
REM (see build.bat's note on "="), so both spellings arrive here identically
REM and this one branch handles both.
set "PRESET="
if /i not "%~1"=="--preset" goto preset_done
if "%~2"=="" (
    echo error: --preset requires a value, e.g. --preset windows-x64-clang-cl 1>&2
    exit /b 1
)
set "PRESET=%~2"
shift
shift
:preset_done
REM Suffix for the error hints below that say to run build.bat first.
set "_pmn_hint="
if defined PRESET set "_pmn_hint= --preset %PRESET%"

if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help
if "%~1"=="" goto usage

set "TARGET_NAME=%~1"
shift

REM Collect any remaining args to pass through to the program (skipping a
REM leading "--" separator if present).
set "PASSTHROUGH="
set "skip_next_dashes=1"
:collect
if "%~1"=="" goto collected
if "!skip_next_dashes!"=="1" if "%~1"=="--" (
    set "skip_next_dashes=0"
    shift
    goto collect
)
set "skip_next_dashes=0"
set "PASSTHROUGH=!PASSTHROUGH! "%~1""
shift
goto collect
:collected

REM BUILD_DIR from the environment beats everything; otherwise --preset, else
REM whichever build was made last (see breeze\cmake\BuildDir.cmake). Explains itself
REM and stops if there's nothing to pick.
if not "%BUILD_DIR%"=="" goto build_dir_known
where cmake >nul 2>nul
if errorlevel 1 (
    echo error: cmake not found on PATH -- it is needed to work out which build directory to use. 1>&2
    echo        Put it on PATH, or set BUILD_DIR to the directory explicitly, e.g. out\build\^<preset^>. 1>&2
    exit /b 1
)
call :resolve_build_dir "%PRESET%" BUILD_DIR
if errorlevel 1 exit /b 1
:build_dir_known

set "MANIFEST="
for %%F in ("%BUILD_DIR%\module_manifest-*.txt") do (
    if not defined MANIFEST set "MANIFEST=%%F"
)
if not defined MANIFEST (
    echo error: no build manifest found in "%BUILD_DIR%". Run breeze\scripts\build.bat%_pmn_hint% first. 1>&2
    exit /b 1
)

set "BIN_PATH="
for /f "usebackq tokens=1,* delims==" %%K in ("%MANIFEST%") do (
    if "%%K"=="%TARGET_NAME%" set "BIN_PATH=%%L"
)

if not defined BIN_PATH (
    echo error: no executable target named "%TARGET_NAME%" in "%BUILD_DIR%". 1>&2
    echo Available targets: 1>&2
    for /f "usebackq tokens=1 delims==" %%T in ("%MANIFEST%") do echo   %%T 1>&2
    exit /b 1
)

if not exist "%BIN_PATH%" (
    echo error: "%BIN_PATH%" was not found. Rebuild with breeze\scripts\build.bat%_pmn_hint%. 1>&2
    exit /b 1
)

REM Which build this came from -- to stderr, so a program's own stdout stays
REM clean to pipe.
echo ==^> Running %TARGET_NAME% ^(%BUILD_DIR%^) 1>&2
"%BIN_PATH%" !PASSTHROUGH!
exit /b %ERRORLEVEL%

:usage
REM Best-effort here: usage should still print with nothing built yet.
if "%BUILD_DIR%"=="" call :resolve_build_dir "%PRESET%" BUILD_DIR quiet
echo Usage: %~nx0 [--preset ^<name^>] ^<cmake-target-name^> [-- program-args...] 1>&2
echo. 1>&2
echo Available executable targets: 1>&2
set "found=0"
for %%F in ("%BUILD_DIR%\module_manifest-*.txt") do (
    set "found=1"
    for /f "usebackq tokens=1 delims==" %%T in ("%%F") do echo   %%T 1>&2
)
if "!found!"=="0" echo   (none found -- did you run breeze\scripts\build.bat?) 1>&2
exit /b 1

:show_help
REM Best-effort here: help should still print with nothing built yet.
if "%BUILD_DIR%"=="" call :resolve_build_dir "%PRESET%" BUILD_DIR quiet
echo Usage: %~nx0 [--preset ^<name^>] ^<cmake-target-name^> [-- program-args...]
echo.
echo Runs an executable module by its CMake target name, resolved via the
echo manifest breeze\scripts\build.bat generates at configure time -- see the
echo comment at the top of this script.
echo.
echo   --preset ^<name^>  Run the build made with that preset. Default: the
echo                    build breeze\scripts\build.bat made last.
echo.
echo Available executable targets:
set "found=0"
for %%F in ("%BUILD_DIR%\module_manifest-*.txt") do (
    set "found=1"
    for /f "usebackq tokens=1 delims==" %%T in ("%%F") do echo   %%T
)
if "!found!"=="0" echo   (none found -- did you run breeze\scripts\build.bat?)
echo.
echo Examples:
echo   breeze\scripts\run.bat hello_exe
echo   breeze\scripts\run.bat --preset windows-x64-clang-cl hello_exe
echo   breeze\scripts\run.bat farewell_exe -- Ale
exit /b 0

REM ---------------------------------------------------------------------
REM :resolve_build_dir <name-or-empty> <LocalVarName> [quiet]
REM
REM Asks breeze\cmake\BuildDir.cmake which build directory to use -- %1 is a preset
REM name, or "default"; empty means "discover one" (the build made last, or
REM the only one) -- and stores it into %2 in the CALLER's scope, with
REM backslashes. Same shape as build.bat's, and the same `cmake -P`
REM one-line-answer protocol: "-- BUILD_DIR=<path>" or "-- ERROR=<text>"
REM (see that file). On failure it prints the reason to stderr, unless a
REM third argument "quiet" is given, and returns errorlevel 1.
REM ---------------------------------------------------------------------
:resolve_build_dir
setlocal
set "_pmn_key="
set "_pmn_val="
for /f "usebackq tokens=1,* delims==" %%A in (`cmake "-DPMN_NAME=%~1" -P breeze\cmake\BuildDir.cmake`) do (
    set "_pmn_key=%%A"
    set "_pmn_val=%%B"
)
if "%_pmn_key%"=="-- BUILD_DIR" if defined _pmn_val goto resolve_ok
if /i "%~3"=="quiet" goto resolve_failed
if defined _pmn_val (
    echo error: %_pmn_val% 1>&2
) else (
    echo error: breeze\cmake\BuildDir.cmake did not answer. 1>&2
)
:resolve_failed
endlocal
exit /b 1

:resolve_ok
endlocal & set "%~2=%_pmn_val:/=\%"
goto :eof
