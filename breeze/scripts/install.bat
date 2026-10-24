@echo off
REM Install this project's own build artifacts to
REM out\install\<platform>-<arch>-<compiler>\ (INSTALL_OUTPUT_DIR in
REM project/Configuration.cmake; see breeze\cmake\Breeze.cmake's install() DESTINATION paths) --
REM the same name as the out\build\<preset> directory they came from, since
REM a preset is named after its target.
REM
REM Always passes --component to `cmake --install`. Without it, any
REM vendored/fetched dependency's own install() rules (see
REM breeze\cmake\Dependencies.cmake) would also run, typically dumping files under
REM CMAKE_INSTALL_PREFIX -- COMPONENT is what keeps `cmake --install`
REM scoped to just this project's own targets.
REM
REM Usage (from the project root):
REM   breeze\scripts\install.bat [--preset <name>] [BUILD_TYPE]
REM   breeze\scripts\install.bat --help
REM
REM   --preset <name>  Install the build made with that preset
REM                    (out\build\<name>). Without it: the build
REM                    breeze\scripts\build.bat made last, or the only one that
REM                    exists. Must come first if given at all;
REM                    --preset=<name> also works.
REM   BUILD_TYPE       Debug|Release|RelWithDebInfo|MinSizeRel
REM                    (default: project/Configuration.cmake's DEFAULT_BUILD_TYPE) --
REM                    only relevant for a Ninja Multi-Config build.
REM
REM Set BUILD_DIR to install from an exact build directory instead.
setlocal enabledelayedexpansion

if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help
goto after_help

:show_help
echo Usage: breeze\scripts\install.bat [--preset ^<name^>] [BUILD_TYPE]
echo.
echo Installs this project's own build artifacts to
echo out\install\^<platform^>-^<arch^>-^<compiler^>\ ^(INSTALL_OUTPUT_DIR in
echo project/Configuration.cmake^), scoped to just this project via `cmake --install
echo --component` -- see the comment at the top of this script.
echo.
echo   --preset ^<name^>  Install the build made with that preset
echo                    ^(out\build\^<name^>^). Default: the build
echo                    breeze\scripts\build.bat made last. Must come first if given
echo                    at all; --preset=^<name^> also works.
echo   BUILD_TYPE       Debug^|Release^|RelWithDebInfo^|MinSizeRel
echo                    ^(default: project/Configuration.cmake's DEFAULT_BUILD_TYPE^) --
echo                    only relevant for a Ninja Multi-Config build.
exit /b 0

:after_help
cd /d "%~dp0..\.."

where cmake >nul 2>nul
if errorlevel 1 (
    echo error: cmake not found on PATH.
    exit /b 1
)

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

REM BUILD_DIR from the environment beats everything; otherwise --preset, else
REM whichever build was made last (see breeze\cmake\BuildDir.cmake). Explains itself
REM and stops if there's nothing to pick.
if not "%BUILD_DIR%"=="" goto build_dir_known
call :resolve_build_dir "%PRESET%" BUILD_DIR
if errorlevel 1 exit /b 1
:build_dir_known

REM A plain %~1 is safe here (unlike build.bat's arguments): a build type
REM like "Debug" never contains "=", so cmd.exe's positional-parameter
REM splitting on it never comes into play.
set "BUILD_TYPE=%~1"
if "%BUILD_TYPE%"=="" call :read_config DEFAULT_BUILD_TYPE BUILD_TYPE
call :read_config PROJECT_CODE_NAME COMPONENT

if not exist "%BUILD_DIR%" (
    echo error: "%BUILD_DIR%" not found. Run breeze\scripts\build.bat%_pmn_hint% first.
    exit /b 1
)

echo ==^> Installing (component: %COMPONENT%) from %BUILD_DIR%
cmake --install "%BUILD_DIR%" --config %BUILD_TYPE% --component %COMPONENT%
exit /b %ERRORLEVEL%

REM ---------------------------------------------------------------------
REM :read_config <ConfigurationVarName> <LocalVarName>
REM
REM Reads one value out of project/Configuration.cmake -- this project's single
REM source of truth -- via breeze\cmake\PrintConfig.cmake, instead of hardcoding
REM a second copy of a default that can silently drift out of sync, and
REM stores it into %2 in the CALLER's scope. See breeze\cmake\PrintConfig.cmake
REM for exactly what's being stripped off of its output below.
REM ---------------------------------------------------------------------
:read_config
setlocal
set "_pmn_line="
for /f "usebackq delims=" %%V in (`cmake "-DPRINT_VARS=%~1" -P breeze\cmake\PrintConfig.cmake`) do set "_pmn_line=%%V"
for /f "tokens=1,* delims==" %%A in ("%_pmn_line%") do set "_pmn_value=%%B"
endlocal & set "%~2=%_pmn_value%"
goto :eof

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
