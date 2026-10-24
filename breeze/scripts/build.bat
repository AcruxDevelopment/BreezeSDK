@echo off
REM Configure (if needed) and build the project, preferably with Ninja.
REM
REM Usage (from the project root):
REM   breeze\scripts\build.bat [--preset ^<name^>] [BUILD_TYPE] [CMAKE_ARGS...]
REM   breeze\scripts\build.bat --list-presets
REM   breeze\scripts\build.bat --help
REM
REM   --preset <name>  Use a CMakePresets.json preset. A preset selects that
REM                    target's toolchain file (breeze\cmake\toolchains\<name>.cmake),
REM                    which picks the compiler and declares the DIST_TARGET
REM                    together, instead of you having to pass a matching
REM                    pair by hand:
REM                      breeze\scripts\build.bat --preset windows-x64-mingw64
REM                    Each preset builds in its own directory,
REM                    out\build\<name>, so switching between presets never
REM                    invalidates -- or deletes -- another one's build.
REM                    Run --list-presets to see every preset for your OS.
REM                    Must come first if given at all; --preset=<name>
REM                    also works. Given with no value (or a value that
REM                    looks like another flag), this fails fast with that
REM                    same preset list shown right there. A value that IS
REM                    given but isn't a real preset name is instead
REM                    caught by cmake itself failing to configure, at
REM                    which point this script shows the preset list too
REM                    -- see the "configure" step below.
REM   BUILD_TYPE       Debug^|Release^|RelWithDebInfo^|MinSizeRel
REM                    (default: project/Configuration.cmake's DEFAULT_BUILD_TYPE)
REM   CMAKE_ARGS       Anything else is forwarded to `cmake` verbatim, e.g.:
REM                      breeze\scripts\build.bat --preset windows-x64-mingw64 Debug -DBUILD_TESTS=ON
REM                      breeze\scripts\build.bat -DBUILD_TESTS=ON
REM                                (BUILD_TYPE omitted -- recognized by not
REM                                starting with "-")
REM
REM Picking a DIST_TARGET: three ways; the first two set the compiler and the
REM label together, and this script rejects mixing --preset with a
REM -DDIST_TARGET rather than leaving it ambiguous which one wins.
REM   1. --preset <name>       The recommended way; see --list-presets.
REM   2. -DCMAKE_TOOLCHAIN_FILE=breeze\cmake\toolchains\<name>.cmake
REM      (no --preset)         What a preset does, by hand, as one of
REM                            CMAKE_ARGS above.
REM   3. -DDIST_TARGET=<value> Sets the label alone, as one of CMAKE_ARGS
REM      (no --preset)         above. Without also passing a matching
REM                            compiler (or, better, the toolchain file
REM                            above), DIST_TARGET is auto-detected from
REM                            whatever compiler CMake finds on its own; if
REM                            the two disagree, TargetSelection.cmake
REM                            FATAL_ERRORs rather than silently building
REM                            the wrong toolchain and mislabeling the
REM                            result -- see that file and the README.
REM Passing --preset together with an explicit -DDIST_TARGET=... in
REM CMAKE_ARGS is rejected by this script before cmake even runs: the
REM preset's toolchain already declares DIST_TARGET, so a second value
REM alongside it is always either redundant or contradictory -- never
REM useful.
REM
REM cmd.exe splits %1, %2, ... (and SHIFT) on space, comma, semicolon, AND
REM "=" -- type "-DFOO=BAR" as an argument and it arrives as TWO separate
REM parameters, %1=-DFOO %2=BAR, silently, with no way to tell after the
REM fact. This script never reads a "="-laden argument (or --preset's own
REM value) through %1 or SHIFT; everything is peeled off of the raw,
REM unsplit %* instead using FOR /F (which only ever splits on space/tab),
REM so "=" survives intact -- see the parsing block below. (bash's
REM "$@"/shift has no such bug -- see build.sh for that half of this same
REM feature.)
REM
REM Compiler environment: for a Windows preset (windows-*-msvc, -clang-cl,
REM -mingw* and -clang) this script first enters the environment that preset's
REM compiler needs, for this run only: the Visual Studio developer prompt for the
REM preset's target (vcvarsall.bat), or MSYS2's toolchain folder first on PATH. So
REM it works from any prompt -- no need to open the x64 Native Tools Command
REM Prompt for VS or an MSYS2 shell first. A prompt that is already right is left alone;
REM set PMN_NO_ENV=1 to skip all of this and use your shell as it is. See
REM _winenv.bat for exactly what it does.
REM
REM Build directory: out\build\<preset> for --preset <preset>; without a
REM preset, out\build\default (the compiler is auto-detected there, so keep
REM to one compiler per directory or use presets). Set BUILD_DIR to use an
REM exact directory of your own instead. breeze\scripts\run.bat, install.bat and
REM docs.bat use the directory built last, or --preset <name> to pick another.
setlocal enabledelayedexpansion

REM -h/--help is checked here, off the raw %1, before anything else --
REM including whether cmake is even on PATH below -- since help shouldn't
REM depend on that.
if /i "%~1"=="-h" goto show_help
if /i "%~1"=="--help" goto show_help
goto after_help

:show_help
echo Usage: breeze\scripts\build.bat [--preset ^<name^>] [BUILD_TYPE] [CMAKE_ARGS...]
echo        breeze\scripts\build.bat --list-presets
echo        breeze\scripts\build.bat --help
echo.
echo   --preset ^<name^>  Use a CMakePresets.json preset: it selects the target's
echo                     toolchain file ^(compiler and DIST_TARGET together^) and
echo                     builds in its own directory, out\build\^<name^>. Must come
echo                     first if given at all; --preset=^<name^> also works. Run
echo                     --list-presets to see every preset for your OS.
echo   BUILD_TYPE        Debug^|Release^|RelWithDebInfo^|MinSizeRel
echo                     ^(default: project/Configuration.cmake's DEFAULT_BUILD_TYPE^)
echo   CMAKE_ARGS        Anything else is forwarded to `cmake` verbatim, e.g.
echo                     -DDIST_TARGET=^<value^> or -DBUILD_TESTS=ON.
echo.
echo Windows presets: the compiler's environment ^(the Visual Studio developer prompt
echo                     for the target, or MSYS2's toolchain folder^) is entered for you,
echo                     for this run only -- no special prompt needed first. Set
echo                     PMN_NO_ENV=1 to use your shell as it is.
echo.
echo Don't combine --preset with an explicit -DDIST_TARGET=... in CMAKE_ARGS --
echo the preset's toolchain already declares one; see the comment at the top of
echo this script ^(breeze\scripts\build.bat^) and TargetSelection.cmake's "Target selection"
echo section for why picking a DIST_TARGET is one or the other, not both.
echo.
echo Examples:
echo   breeze\scripts\build.bat --preset linux-x64-clang
echo   breeze\scripts\build.bat --preset windows-x64-mingw64 Debug -DBUILD_TESTS=ON
echo   breeze\scripts\build.bat -DBUILD_TESTS=ON
exit /b 0

:after_help
cd /d "%~dp0..\.."

REM An explicit BUILD_DIR from the environment beats the one-directory-per-
REM preset layout resolved below, and is then also not recorded as "the
REM build made last" (run/install/docs would otherwise be sent to a
REM directory the layout doesn't know about).
set "_pmn_record_build=1"
if not "%BUILD_DIR%"=="" set "_pmn_record_build=0"

where cmake >nul 2>nul
if errorlevel 1 (
    echo error: cmake not found on PATH.
    exit /b 1
)

REM Which cmake the user's PATH resolves to, so it can be put back in front after
REM a Visual Studio environment is entered below: that puts Visual Studio's own
REM cmake -- often an older one -- ahead of it.
set "_pmn_cmake_dir="
for /f "delims=" %%C in ('where cmake') do if not defined _pmn_cmake_dir set "_pmn_cmake_dir=%%~dpC"

REM See the header comment above for why this doesn't use %1/SHIFT.
set "ALL_ARGS=%*"
set "PRESET="
set "BUILD_TYPE="
set "EXTRA_ARGS="
if not defined ALL_ARGS goto args_done

for /f "tokens=1,* delims= " %%A in ("%ALL_ARGS%") do (
    set "_FIRST=%%A"
    set "_REST=%%B"
)

if /i "%_FIRST%"=="--list-presets" (
    cmake --list-presets
    exit /b !ERRORLEVEL!
)
if /i "%_FIRST%"=="--preset" goto preset_space_form
if /i "%_FIRST:~0,9%"=="--preset=" goto preset_equals_form
goto no_preset

:preset_space_form
if not defined _REST (
    echo error: --preset requires a value, e.g. --preset windows-x64-mingw64
    echo.
    cmake --list-presets
    exit /b 1
)
for /f "tokens=1,* delims= " %%A in ("%_REST%") do (
    set "PRESET=%%A"
    set "_REST=%%B"
)
if "%PRESET:~0,1%"=="-" (
    echo error: --preset requires a value, e.g. --preset windows-x64-mingw64
    echo.
    cmake --list-presets
    exit /b 1
)
goto have_preset

:preset_equals_form
set "PRESET=%_FIRST:~9%"
if not defined PRESET (
    echo error: --preset= requires a value, e.g. --preset=windows-x64-mingw64
    echo.
    cmake --list-presets
    exit /b 1
)
goto have_preset

:have_preset
set "ALL_ARGS=%_REST%"
if not defined ALL_ARGS goto args_done
for /f "tokens=1,* delims= " %%A in ("%ALL_ARGS%") do (
    set "_FIRST=%%A"
    set "_REST=%%B"
)

:no_preset
if "%_FIRST:~0,1%"=="-" (
    set "EXTRA_ARGS=%ALL_ARGS%"
) else (
    set "BUILD_TYPE=%_FIRST%"
    set "EXTRA_ARGS=%_REST%"
)

:args_done
if "%BUILD_TYPE%"=="" call :read_config DEFAULT_BUILD_TYPE BUILD_TYPE
if "%TOOLCACHE_DIR%"=="" call :read_config TOOLCACHE_DIR TOOLCACHE_DIR

REM One build directory per preset (out\build\<preset>; "default" when no
REM preset was given), so switching presets never has to reuse -- or wipe -- a
REM directory configured for another compiler. breeze\cmake\BuildDir.cmake owns the
REM layout (project/Configuration.cmake's BUILD_OUTPUT_DIR); goto rather than an
REM if-block for the reason given further down about nesting.
set "_pmn_name=default"
if defined PRESET set "_pmn_name=%PRESET%"
if not "%BUILD_DIR%"=="" goto build_dir_known
call :resolve_build_dir "%_pmn_name%" BUILD_DIR
if errorlevel 1 exit /b 1
:build_dir_known

REM Combining --preset with an explicit -DDIST_TARGET=... in CMAKE_ARGS is
REM ambiguous (the preset already sets one) -- caught here, before cmake
REM ever runs, rather than leaving it to whichever of the two CMake
REM happens to prefer. findstr's /C: does a literal (non-regex) substring
REM search, which sidesteps cmd.exe's own "=" splitting quirk (see the
REM header comment) entirely -- there's no argument-parsing involved here,
REM just a plain string search over EXTRA_ARGS as already assembled.
if defined PRESET (
    echo %EXTRA_ARGS%| findstr /C:"-DDIST_TARGET=" >nul
    if not errorlevel 1 (
        echo error: both --preset %PRESET% and an explicit -DDIST_TARGET=... were given.
        echo        A preset's toolchain already declares DIST_TARGET ^(and picks the compiler^) -- pick one:
        echo          breeze\scripts\build.bat --preset %PRESET%
        echo          breeze\scripts\build.bat -DCMAKE_TOOLCHAIN_FILE=breeze\cmake\toolchains\^<target^>.cmake
        echo        See the comment at the top of this script, or TargetSelection.cmake's
        echo        "Target selection" section, for why these two aren't combined.
        exit /b 1
    )
)

REM Prefer a pinned ninja (fetched by breeze\scripts\setup.bat -- see
REM breeze\cmake\FetchNinja.cmake) over a system one, same "always the pinned
REM copy" preference as Doxygen. Needed whether or not --preset is used:
REM every preset sets its generator to Ninja but doesn't hardcode which
REM ninja binary to use (that would just be TOOLCACHE_DIR's default
REM duplicated a third time -- see project/Configuration.cmake) --
REM CMAKE_MAKE_PROGRAM supplies it either way; only -G Ninja itself is
REM skipped below when a preset already sets the generator.
REM
REM Deliberately goto-based, and deliberately `pushd` + a bare wildcard
REM rather than `for /d %%D in ("path\*")` -- both tested directly; a
REM path-prefixed wildcard didn't match here, this form does, and it also
REM sidesteps nesting a FOR loop inside an if/else block, which
REM separately corrupts cmd.exe's paren-matching for the enclosing block
REM (see breeze\scripts\refactor.bat for that one).
set "NINJA_BIN="
if not exist "%TOOLCACHE_DIR%" goto check_system_ninja

pushd "%TOOLCACHE_DIR%"
for /d %%D in (ninja-*) do if exist "%%D\ninja.exe" if not defined NINJA_BIN set "NINJA_BIN=%%~fD\ninja.exe"
popd

if defined NINJA_BIN goto have_pinned_ninja

:check_system_ninja
where ninja >nul 2>nul
if errorlevel 1 goto no_ninja
echo ==^> Using system ninja
if not defined PRESET set "GENERATOR_ARGS=-G Ninja"
goto configure

:have_pinned_ninja
echo ==^> Using pinned ninja: %NINJA_BIN%
if defined PRESET (
    set "GENERATOR_ARGS=-DCMAKE_MAKE_PROGRAM=%NINJA_BIN%"
) else (
    set "GENERATOR_ARGS=-G Ninja -DCMAKE_MAKE_PROGRAM=%NINJA_BIN%"
)
goto configure

:no_ninja
if defined PRESET (
    echo warning: ninja not found ^(no pinned copy, none on PATH^) -- the '%PRESET%'
    echo          preset requires it; configure will likely fail. Run
    echo          breeze\scripts\setup.bat to fetch a pinned ninja, or install ninja
    echo          yourself.
) else (
    echo warning: ninja not found ^(no pinned copy, none on PATH^) -- falling back to
    echo          CMake's default generator for this platform. Run breeze\scripts\setup.bat
    echo          to fetch a pinned ninja, or install ninja yourself, for a faster
    echo          and more consistent build. Continuing without it.
)
set "GENERATOR_ARGS="

:configure
if not defined PRESET goto configure_env_done
call "%~dp0_winenv.bat" "%PRESET%"
if errorlevel 1 exit /b 1
if defined _pmn_cmake_dir set "PATH=%_pmn_cmake_dir%;%PATH%"
:configure_env_done
echo ==^> Configuring (%BUILD_TYPE%) into %BUILD_DIR%\
if defined PRESET echo     Preset: %PRESET%
if defined EXTRA_ARGS echo     Extra CMake arguments: %EXTRA_ARGS%
if defined PRESET (
    cmake --preset %PRESET% -S . -B "%BUILD_DIR%" %GENERATOR_ARGS% -DCMAKE_BUILD_TYPE=%BUILD_TYPE% %EXTRA_ARGS%
) else (
    cmake %GENERATOR_ARGS% -S . -B "%BUILD_DIR%" -DCMAKE_BUILD_TYPE=%BUILD_TYPE% %EXTRA_ARGS%
)
if errorlevel 1 (
    if defined PRESET (
        echo.
        echo error: configuring with preset '%PRESET%' failed -- see the cmake output above.
        echo        If '%PRESET%' isn't the preset name you meant, here is what --list-presets
        echo        shows for this OS:
        echo.
        cmake --list-presets
    )
    exit /b 1
)

REM Configure succeeded: this is now the build the other scripts default to.
if "%_pmn_record_build%"=="1" cmake "-DPMN_NAME=%_pmn_name%" -DPMN_RECORD=ON -P breeze\cmake\BuildDir.cmake >nul

echo ==^> Building
cmake --build "%BUILD_DIR%"
if errorlevel 1 exit /b 1

echo ==^> Done. Run a module with:  breeze\scripts\run.bat ^<target-name^>
exit /b 0

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
REM backslashes. Same shape as :read_config above, and the same
REM `cmake -P` one-line-answer protocol: "-- BUILD_DIR=<path>" or
REM "-- ERROR=<text>" (see that file). On failure it prints the reason to
REM stderr, unless a third argument "quiet" is given, and returns errorlevel 1.
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
