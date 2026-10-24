@echo off
REM Build Doxygen documentation for every module (see breeze\cmake\Documentation.cmake)
REM and print the path to the landing page. A no-op with a clear message if
REM Doxygen isn't installed or ENABLE_DOXYGEN=OFF.
REM
REM Output goes to out\docs\ (DOCS_OUTPUT_DIR in project/Configuration.cmake) --
REM note this is a sibling of out\build, not nested inside it, and shared by
REM every preset: documentation doesn't depend on which compiler built the
REM code. The docs targets just need SOME configured build directory to run
REM from, so this uses the one built last unless you pick with --preset. If
REM you've overridden DOCS_OUTPUT_DIR at configure time, also set DOCS_DIR here
REM to match so the printed path is correct (docs still land in the right
REM place either way -- this only affects the message below).
REM
REM Usage (from the project root):
REM   breeze\scripts\docs.bat              REM every module
REM   breeze\scripts\docs.bat core_lib      REM just one module's docs (docs_<target>)
REM   breeze\scripts\docs.bat --preset windows-x64-clang-cl   REM ... from that preset's build directory
REM   breeze\scripts\docs.bat --help
REM
REM --preset must come first if given at all; --preset=<name> also works. Set
REM BUILD_DIR to use an exact build directory instead.
setlocal

if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help
goto after_help

:show_help
echo Usage: breeze\scripts\docs.bat [--preset ^<name^>] [module-target-name]
echo.
echo Builds Doxygen documentation for every module ^(see breeze\cmake\Documentation.cmake^)
echo and prints the path to the landing page. A no-op with a clear message if
echo Doxygen isn't installed or ENABLE_DOXYGEN=OFF.
echo.
echo   --preset ^<name^>       Run from that preset's build directory
echo                         ^(out\build\^<name^>^). Default: the build
echo                         breeze\scripts\build.bat made last. Must come first if
echo                         given at all; --preset=^<name^> also works.
echo   ^(no argument^)         Build docs for every module.
echo   module-target-name    Build docs for just that one module ^(its own
echo                         docs_^<name^> target^), e.g.:
echo                           breeze\scripts\docs.bat core_lib
echo.
echo Output goes to out\docs\ ^(DOCS_OUTPUT_DIR in project/Configuration.cmake^), shared
echo by every preset -- see the comment at the top of this script if you've
echo overridden that.
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
if "%DOCS_DIR%"=="" set "DOCS_DIR=out\docs"

if not exist "%BUILD_DIR%" (
    echo error: "%BUILD_DIR%" not found. Run breeze\scripts\build.bat%_pmn_hint% first.
    exit /b 1
)

echo ==^> Using build directory %BUILD_DIR%

if "%~1"=="" (
    cmake --build "%BUILD_DIR%" --target docs
    if exist "%DOCS_DIR%\index.html" (
        echo ==^> Open: %DOCS_DIR%\index.html
    )
) else (
    cmake --build "%BUILD_DIR%" --target docs_%1
    echo ==^> Open: %DOCS_DIR%\%1\html\index.html
)
exit /b %ERRORLEVEL%

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
