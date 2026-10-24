@echo off
REM One-time (or re-run any time) environment setup for this template.
REM Windows; on Linux and macOS it is breeze/scripts/setup.sh.
REM
REM   1. Checks for the tools this project builds with -- Git, CMake 3.25+ and a
REM      C++ compiler (Visual Studio Build Tools, or MinGW-w64 through MSYS2:
REM      required), plus LLVM, the MSVC ARM64 build tools and the other MSYS2
REM      toolchains (optional) -- and
REM      offers to install whatever is missing, ONE TOOL AT A TIME, showing the
REM      exact command before running it. Nothing is installed without
REM      your yes. The work is done by breeze\scripts\_tools.ps1 (PowerShell: prompts,
REM      PATH handling and winget are far more robust there than in batch).
REM   2. Fetches the pinned ninja (breeze\cmake\FetchNinja.cmake) -- used by
REM      breeze\scripts\build.bat if found (see there); a system ninja still
REM      works fine too, this just avoids needing one installed at all.
REM   3. Fetches the pinned Doxygen (breeze\cmake\FetchDoxygen.cmake) -- NOT
REM      required to build the project itself (see breeze\cmake\Documentation.cmake),
REM      only to run breeze\scripts\docs.bat afterward.
REM   4. Activates the pre-commit hook (breeze\githooks\pre-commit) for this
REM      clone, if it's a git repository.
REM
REM A failure in step 2 or 3 (no pinned binary for this machine, no network)
REM is reported and setup carries on -- it used to stop there, before the hook
REM was activated.
REM
REM Usage (from the project root):
REM   breeze\scripts\setup.bat [--yes] [--all] [--everything] [--check] [--skip-tools]
REM   breeze\scripts\setup.bat --help
REM
REM No delayed expansion in this file, on purpose: PATH is edited below, and
REM with delayed expansion on, a "!" in any directory name would be eaten.
setlocal

REM %~dp0 is captured first: a plain SHIFT (used to walk the arguments below)
REM shifts %0 as well.
set "_PMN_HERE=%~dp0"

set "_PMN_TOOLS_ARGS="
set "_PMN_SKIP_TOOLS=0"
set "_PMN_CHECK=0"
set "_PMN_TOOLS_RC=0"

:parse_args
if "%~1"=="" goto args_done
if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help
if /i "%~1"=="-y" goto opt_yes
if /i "%~1"=="--yes" goto opt_yes
if /i "%~1"=="--all" goto opt_all
REM --everything: on Linux it also does slow extras (AUR builds); nothing on
REM Windows needs more than --all, so it means the same here.
if /i "%~1"=="--everything" goto opt_all
if /i "%~1"=="--check" goto opt_check
if /i "%~1"=="--skip-tools" goto opt_skip_tools
echo error: unknown option "%~1" 1>&2
echo Run breeze\scripts\setup.bat --help for usage. 1>&2
exit /b 1

:opt_yes
set "_PMN_TOOLS_ARGS=%_PMN_TOOLS_ARGS% -Yes"
shift
goto parse_args

:opt_all
set "_PMN_TOOLS_ARGS=%_PMN_TOOLS_ARGS% -All"
shift
goto parse_args

:opt_check
set "_PMN_TOOLS_ARGS=%_PMN_TOOLS_ARGS% -Check"
set "_PMN_CHECK=1"
shift
goto parse_args

:opt_skip_tools
set "_PMN_SKIP_TOOLS=1"
shift
goto parse_args

:show_help
echo Usage: breeze\scripts\setup.bat [--yes] [--all] [--everything] [--check] [--skip-tools]
echo.
echo One-time ^(or re-run any time^) environment setup for this template:
echo   1. Checks the tools the project builds with and offers to install what's
echo      missing, one tool at a time ^(Git, CMake and a C++ compiler are
echo      required; LLVM, the MSVC ARM64 build tools and the other MSYS2
echo      toolchains are optional^). Each
echo      install shows its exact command and waits for your yes.
echo   2. Fetches the pinned ninja ^(breeze\cmake\FetchNinja.cmake^).
echo   3. Fetches the pinned Doxygen ^(breeze\cmake\FetchDoxygen.cmake^).
echo   4. Activates the pre-commit hook ^(breeze\githooks\pre-commit^) for this clone,
echo      if it's a git repository.
echo.
echo Options:
echo   -y, --yes       Install the REQUIRED tools without asking. For scripts and
echo                   CI; without a terminal and without this, nothing is asked
echo                   and nothing is installed.
echo       --all       Also install the optional tools without asking ^(implies
echo                   --yes^).
echo       --everything  Same as --all here. ^(On Linux, breeze/scripts/setup.sh --everything
echo                   also does slow extras such as AUR builds; Windows has none.^)
echo       --check     Only report what is and isn't installed; change nothing,
echo                   fetch nothing. Exits 1 if a required tool is missing.
echo       --skip-tools  Skip step 1 and go straight to the pinned downloads.
echo.
echo At each question:  y  install it   n  not this one   a  install everything
echo left   s  skip the rest of the optional tools   q  stop asking.
echo.
echo See the comment at the top of this script for more on each step.
exit /b 0

:args_done
cd /d "%_PMN_HERE%..\.."

REM ---- 1. tools --------------------------------------------------------------
if "%_PMN_SKIP_TOOLS%"=="1" goto tools_done
where powershell >nul 2>nul
if errorlevel 1 goto no_powershell

set "_PMN_PATHFILE=%TEMP%\pmn-path-%RANDOM%%RANDOM%.txt"
powershell -NoProfile -ExecutionPolicy Bypass -File "%_PMN_HERE%_tools.ps1" %_PMN_TOOLS_ARGS% -PathOut "%_PMN_PATHFILE%"
set "_PMN_TOOLS_RC=%ERRORLEVEL%"

REM The installer adds tool folders (CMake, Git, ...) to ITS copy of PATH so
REM it can use them; a child process can't change ours, so it hands the list
REM back in a file and they're appended here, for the steps below.
if exist "%_PMN_PATHFILE%" call :take_path_additions
echo.
goto tools_done

:no_powershell
echo error: powershell.exe not found on PATH -- it runs the tool installer. 1>&2
echo        Install the tools yourself and re-run with --skip-tools. 1>&2
exit /b 1

:tools_done
if not "%_PMN_CHECK%"=="1" goto after_check
if "%_PMN_TOOLS_RC%"=="0" goto check_ok
echo ==^> Required tools are missing. Run breeze\scripts\setup.bat to install them.
exit /b %_PMN_TOOLS_RC%
:check_ok
echo ==^> All required tools are present.
exit /b 0
:after_check

REM Everything below runs CMake scripts.
where cmake >nul 2>nul
if errorlevel 1 goto no_cmake
goto have_cmake
:no_cmake
echo error: cmake not found on PATH -- nothing below can run without it. 1>&2
if "%_PMN_SKIP_TOOLS%"=="1" goto no_cmake_skip
echo        Install CMake ^(3.25 or newer^), open a new terminal, and re-run this script. 1>&2
exit /b 1
:no_cmake_skip
echo        Re-run without --skip-tools to be offered an install. 1>&2
exit /b 1
:have_cmake

REM ---- 2. pinned ninja -------------------------------------------------------
echo ==^> Fetching pinned ninja (breeze\cmake\FetchNinja.cmake)
cmake -P breeze\cmake\FetchNinja.cmake
if errorlevel 1 goto ninja_failed
goto ninja_done
:ninja_failed
echo.
echo     No pinned ninja here ^(no upstream binary for this machine, or the
echo     download failed -- see above^).
where ninja >nul 2>nul
if errorlevel 1 goto ninja_missing
echo     The ninja on PATH will be used instead.
goto ninja_done
:ninja_missing
echo     breeze\scripts\build.bat needs a ninja: e.g.  winget install Ninja-build.Ninja
:ninja_done

REM ---- 3. pinned Doxygen -----------------------------------------------------
echo.
echo ==^> Fetching pinned Doxygen (breeze\cmake\FetchDoxygen.cmake)
cmake -P breeze\cmake\FetchDoxygen.cmake
if errorlevel 1 goto doxygen_failed
goto doxygen_done
:doxygen_failed
echo.
echo     Documentation ^(breeze\scripts\docs.bat^) won't be available: there's no pinned
echo     Doxygen for this machine, or the download failed -- see above.
echo     The project itself builds fine without it.
:doxygen_done

REM ---- 4. pre-commit hook ----------------------------------------------------
echo.
git rev-parse --is-inside-work-tree >nul 2>nul
if errorlevel 1 goto hook_skip
echo ==^> Activating pre-commit hook
git config core.hooksPath breeze/githooks
echo     core.hooksPath = breeze/githooks
goto hook_done
:hook_skip
echo ==^> Skipping pre-commit hook activation ^(not a git repository yet^)
echo     Once you've run "git init", re-run this script or:
echo       git config core.hooksPath breeze/githooks
:hook_done

echo.
if "%_PMN_TOOLS_RC%"=="0" goto setup_ok
echo ==^> Setup finished, but a required tool is still missing -- see above.
exit /b 1
:setup_ok
echo ==^> Setup complete. breeze\scripts\build.bat and breeze\scripts\docs.bat are ready to use.
exit /b 0

REM ---------------------------------------------------------------------
REM :take_path_additions
REM
REM Appends every directory listed in %_PMN_PATHFILE% to PATH, then deletes
REM the file. One "for /f ... do call" line, deliberately not a parenthesized
REM block: a directory like "C:\Program Files (x86)\..." would close it early.
REM ---------------------------------------------------------------------
:take_path_additions
for /f "usebackq delims=" %%D in ("%_PMN_PATHFILE%") do call :add_path "%%D"
del "%_PMN_PATHFILE%" >nul 2>nul
goto :eof

:add_path
set "PATH=%PATH%;%~1"
goto :eof
