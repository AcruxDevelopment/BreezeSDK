@echo off
REM Enters the compiler environment a Windows preset needs, in THIS cmd.exe
REM session: what opening "x64 Native Tools Command Prompt for VS" or an MSYS2
REM MINGW64 shell by hand does, without opening a window or leaving the
REM console you are in.
REM
REM Not run directly -- breeze\scripts\build.bat calls it once the preset is known:
REM   call "breeze\scripts\_winenv.bat" ^<preset^>
REM It uses no SETLOCAL on purpose: the variables vcvarsall.bat sets (PATH,
REM INCLUDE, LIB, ...) have to land in the CALLER's session. build.bat's own
REM SETLOCAL discards them again when it ends, so nothing leaks into the
REM prompt you started it from.
REM
REM   preset                                   environment entered
REM   windows-x64-msvc, windows-arm64-msvc     the Visual Studio developer
REM                                            prompt for that target
REM                                            (vcvarsall.bat from the newest
REM                                            Visual Studio or Build Tools
REM                                            that has the C++ tools)
REM   windows-x64-clang-cl,                    the same, plus clang-cl on PATH
REM   windows-arm64-clang-cl                   if it is not already (LLVM's own
REM                                            folder, else the copy Visual
REM                                            Studio ships)
REM   windows-x64-mingw64,                     MSYS2's mingw64\bin or
REM   windows-x86-mingw32                      mingw32\bin first on PATH, unless
REM                                            that compiler is already there
REM   windows-x64-clang,                       MSYS2's clang64\bin or
REM   windows-arm64-clang                      clangarm64\bin first on PATH --
REM                                            always: a clang++ from anywhere
REM                                            else targets a different ABI
REM
REM After entering a Visual Studio environment it checks that the target's runtime
REM libraries exist (lib\TARGET\msvcrt.lib), and for arm64 picks the newest Visual
REM Studio that has the ARM64 component: from an x64 machine that is the only way
REM to build arm64, as a cross build, and without it the failure would only appear
REM at CMake's compiler test. MSYS2 has no CLANGARM64 environment on an x64
REM machine; windows-arm64-clang says so and points at the cross-building presets.
REM
REM Left alone: a shell that is already a developer prompt for the right
REM architecture; any preset not listed (cmake reports an unknown one itself);
REM and everything, when PMN_NO_ENV is set to anything -- for a toolchain this script does
REM not know about, or a prompt you have set up yourself.
REM MSYS2 is looked for in MSYS2_ROOT, else the msys64 folder on the system
REM drive -- the same place breeze\scripts\setup.bat installs it.
REM
REM Exit status: 0 = ready, or nothing to do. 1 = the environment the preset
REM needs is not available, after saying what to install.
REM
REM Flat on purpose: single-line IF and GOTO, no parenthesized blocks. The paths
REM expanded here can contain "(x86)", and an unquoted close-paren ends a block
REM early.

if "%~1"=="" exit /b 0
if defined PMN_NO_ENV exit /b 0

set "_pmn_e_tgt="
set "_pmn_e_llvm="
set "_pmn_e_sub="
set "_pmn_e_exe="
set "_pmn_e_probe="
set "_pmn_e_pkg="
set "_pmn_e_vs="
set "_pmn_e_arg="
set "_pmn_e_need="

if /i "%~1"=="windows-x64-msvc"       goto pick_msvc_x64
if /i "%~1"=="windows-arm64-msvc"     goto pick_msvc_arm64
if /i "%~1"=="windows-x64-clang-cl"   goto pick_clangcl_x64
if /i "%~1"=="windows-arm64-clang-cl" goto pick_clangcl_arm64
if /i "%~1"=="windows-x64-mingw64"    goto pick_mingw64
if /i "%~1"=="windows-x86-mingw32"    goto pick_mingw32
if /i "%~1"=="windows-x64-clang"      goto pick_clang64
if /i "%~1"=="windows-arm64-clang"    goto pick_clangarm64
goto env_ok

:pick_msvc_x64
set "_pmn_e_tgt=x64"
goto run_vs
:pick_msvc_arm64
set "_pmn_e_tgt=arm64"
goto run_vs
:pick_clangcl_x64
set "_pmn_e_tgt=x64"
set "_pmn_e_llvm=1"
goto run_vs
:pick_clangcl_arm64
set "_pmn_e_tgt=arm64"
set "_pmn_e_llvm=1"
goto run_vs
:pick_mingw64
set "_pmn_e_sub=mingw64"
set "_pmn_e_exe=g++.exe"
set "_pmn_e_probe=x86_64-w64-mingw32-g++"
set "_pmn_e_pkg=mingw-w64-x86_64-gcc"
goto run_msys
:pick_mingw32
set "_pmn_e_sub=mingw32"
set "_pmn_e_exe=g++.exe"
set "_pmn_e_probe=i686-w64-mingw32-g++"
set "_pmn_e_pkg=mingw-w64-i686-gcc"
goto run_msys
:pick_clang64
set "_pmn_e_sub=clang64"
set "_pmn_e_exe=clang++.exe"
set "_pmn_e_pkg=mingw-w64-clang-x86_64-clang"
goto run_msys
:pick_clangarm64
set "_pmn_e_sub=clangarm64"
set "_pmn_e_exe=clang++.exe"
set "_pmn_e_pkg=mingw-w64-clang-aarch64-clang"
goto run_msys

REM ---------------------------------------------------------------------
REM Visual Studio: msvc and clang-cl presets
REM ---------------------------------------------------------------------
:run_vs
if not defined VSCMD_VER goto vs_find
if /i "%VSCMD_ARG_TGT_ARCH%"=="%_pmn_e_tgt%" goto vs_have
goto vs_find

:vs_have
where cl >nul 2>nul
if errorlevel 1 goto vs_find
if defined VSINSTALLDIR set "_pmn_e_vs=%VSINSTALLDIR%"
goto vs_verify

:vs_find
set "_pmn_e_vs="
set "_pmn_e_vswhere=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%_pmn_e_vswhere%" goto vs_missing

REM Which component provides the target's compilers and libraries: the x86/x64
REM tools for x64, and for arm64 the ARM64 tools too -- an x64 machine reaches
REM arm64 through them (a cross build), and an ARM64 machine builds natively.
REM The newest install that has what the target needs wins, so an older Visual
REM Studio that has it beats a newer one that does not.
set "_pmn_e_need=Microsoft.VisualStudio.Component.VC.Tools.x86.x64"
if /i "%_pmn_e_tgt%"=="arm64" set "_pmn_e_need=Microsoft.VisualStudio.Component.VC.Tools.x86.x64 Microsoft.VisualStudio.Component.VC.Tools.ARM64"
for /f "usebackq delims=" %%I in (`"%_pmn_e_vswhere%" -latest -products * -requires %_pmn_e_need% -property installationPath`) do set "_pmn_e_vs=%%I"
if defined _pmn_e_vs goto vs_have_install

REM None has it. Is there a Visual Studio with C++ at all? Then it is only the
REM target's component that is missing, which has its own message.
for /f "usebackq delims=" %%I in (`"%_pmn_e_vswhere%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "_pmn_e_vs=%%I"
if not defined _pmn_e_vs goto vs_missing
goto vs_target_missing

:vs_have_install
set "_pmn_e_vcvars=%_pmn_e_vs%\VC\Auxiliary\Build\vcvarsall.bat"
if not exist "%_pmn_e_vcvars%" goto vs_missing

REM vcvarsall's argument is HOST_TARGET, or just TARGET when the two match.
set "_pmn_e_host=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "_pmn_e_host=%PROCESSOR_ARCHITEW6432%"
if /i "%_pmn_e_host%"=="AMD64" goto vs_arg_amd64
if /i "%_pmn_e_host%"=="ARM64" goto vs_arg_arm64
set "_pmn_e_arg=x86_%_pmn_e_tgt%"
goto vs_enter
:vs_arg_amd64
if /i "%_pmn_e_tgt%"=="x64" set "_pmn_e_arg=x64"
if /i "%_pmn_e_tgt%"=="arm64" set "_pmn_e_arg=x64_arm64"
goto vs_enter
:vs_arg_arm64
if /i "%_pmn_e_tgt%"=="x64" set "_pmn_e_arg=arm64_x64"
if /i "%_pmn_e_tgt%"=="arm64" set "_pmn_e_arg=arm64"
goto vs_enter

REM Success is judged by what vcvarsall left behind -- the target it reports
REM and a cl on PATH, which is what the build needs -- not by its exit status.
:vs_enter
set "VSCMD_SKIP_SENDTELEMETRY=1"
echo ==^> Environment: Visual Studio developer prompt for %_pmn_e_tgt% ^(vcvarsall %_pmn_e_arg%^)
call "%_pmn_e_vcvars%" %_pmn_e_arg% >"%TEMP%\pmn-vcvarsall.log" 2>&1
if /i "%VSCMD_ARG_TGT_ARCH%"=="%_pmn_e_tgt%" goto vs_check_cl
goto vs_failed
:vs_check_cl
where cl >nul 2>nul
if errorlevel 1 goto vs_failed
if not defined VCToolsInstallDir goto vs_failed
goto vs_verify

REM The target's runtime libraries must exist: with the target's component
REM missing, vcvarsall can still report the target and leave a cl on PATH (the
REM host's x64 one), and the failure only shows up at CMake's compiler test as
REM "cannot open msvcrt.lib". This catches it first, with the fix.
:vs_verify
if not defined VCToolsInstallDir goto vs_after
if exist "%VCToolsInstallDir%lib\%_pmn_e_tgt%\msvcrt.lib" goto vs_after
goto vs_target_missing

:vs_after
del "%TEMP%\pmn-vcvarsall.log" >nul 2>nul
if not "%_pmn_e_llvm%"=="1" goto env_ok
where clang-cl >nul 2>nul
if not errorlevel 1 goto env_ok
set "_pmn_e_pf=%ProgramW6432%"
if not defined _pmn_e_pf set "_pmn_e_pf=%ProgramFiles%"
if exist "%_pmn_e_pf%\LLVM\bin\clang-cl.exe" goto llvm_standalone
if not defined _pmn_e_vs goto llvm_missing
if exist "%_pmn_e_vs%\VC\Tools\Llvm\x64\bin\clang-cl.exe" goto llvm_vs_x64
if exist "%_pmn_e_vs%\VC\Tools\Llvm\ARM64\bin\clang-cl.exe" goto llvm_vs_arm64
if exist "%_pmn_e_vs%\VC\Tools\Llvm\bin\clang-cl.exe" goto llvm_vs_x86
goto llvm_missing

:llvm_standalone
set "PATH=%_pmn_e_pf%\LLVM\bin;%PATH%"
echo ==^> Environment: clang-cl from %_pmn_e_pf%\LLVM\bin
goto env_ok
:llvm_vs_x64
set "PATH=%_pmn_e_vs%\VC\Tools\Llvm\x64\bin;%PATH%"
echo ==^> Environment: clang-cl from Visual Studio ^(VC\Tools\Llvm\x64\bin^)
goto env_ok
:llvm_vs_arm64
set "PATH=%_pmn_e_vs%\VC\Tools\Llvm\ARM64\bin;%PATH%"
echo ==^> Environment: clang-cl from Visual Studio ^(VC\Tools\Llvm\ARM64\bin^)
goto env_ok
:llvm_vs_x86
set "PATH=%_pmn_e_vs%\VC\Tools\Llvm\bin;%PATH%"
echo ==^> Environment: clang-cl from Visual Studio ^(VC\Tools\Llvm\bin^)
goto env_ok

:llvm_missing
echo error: preset %~1 needs clang-cl, and none was found on PATH, in %_pmn_e_pf%\LLVM\bin or in Visual Studio. 1>&2
echo        Run breeze\scripts\setup.bat to install LLVM, or:  winget install LLVM.LLVM 1>&2
goto env_fail

:vs_missing
echo error: preset %~1 needs Visual Studio or Build Tools with the C++ tools ^(workload "Desktop development with C++"^), and none was found. 1>&2
echo        Run breeze\scripts\setup.bat to install it. If you use a Visual Studio this script cannot find, open its 1>&2
echo        developer prompt for %_pmn_e_tgt% yourself and set PMN_NO_ENV=1. 1>&2
if /i "%_pmn_e_tgt%"=="arm64" echo        For ARM64 targets add the "MSVC ARM64 build tools" component in the Visual Studio Installer. 1>&2
goto env_fail

:vs_target_missing
echo error: preset %~1 needs the MSVC tools and libraries for %_pmn_e_tgt%, and the Visual Studio install here does not have them. 1>&2
if defined VCToolsInstallDir echo        %VCToolsInstallDir%lib\%_pmn_e_tgt%\msvcrt.lib is missing. 1>&2
if exist "%TEMP%\pmn-vcvarsall.log" type "%TEMP%\pmn-vcvarsall.log" 1>&2
if /i "%_pmn_e_tgt%"=="arm64" goto vs_target_missing_arm64
echo        Add the component "MSVC ... C++ x64/x86 build tools (Latest)" in the Visual Studio Installer ^(Modify, Individual components^). 1>&2
goto env_fail
:vs_target_missing_arm64
echo        Building for ARM64 -- from an x64 machine that is a cross build -- needs the component 1>&2
echo        "MSVC ... C++ ARM64/ARM64EC build tools (Latest)". Run breeze\scripts\setup.bat, which offers to add it, or add it in the 1>&2
echo        Visual Studio Installer: Modify, Individual components, search for ARM64. 1>&2
goto env_fail

:vs_failed
echo error: could not enter the Visual Studio environment for %_pmn_e_tgt% ^(vcvarsall %_pmn_e_arg%^). Its output: 1>&2
if exist "%TEMP%\pmn-vcvarsall.log" type "%TEMP%\pmn-vcvarsall.log" 1>&2
echo        If this shell is already a developer prompt for another architecture, open a fresh one. 1>&2
if /i "%_pmn_e_tgt%"=="arm64" echo        ARM64 targets need the "MSVC ARM64 build tools" component of Visual Studio. 1>&2
goto env_fail

REM ---------------------------------------------------------------------
REM MSYS2: mingw and clang presets
REM ---------------------------------------------------------------------
:run_msys
set "_pmn_e_root=%MSYS2_ROOT%"
if not defined _pmn_e_root set "_pmn_e_root=%SystemDrive%\msys64"
if not defined _pmn_e_probe goto msys_enter
where %_pmn_e_probe% >nul 2>nul
if not errorlevel 1 goto env_ok

:msys_enter
if not exist "%_pmn_e_root%\%_pmn_e_sub%\bin\%_pmn_e_exe%" goto msys_missing
set "PATH=%_pmn_e_root%\%_pmn_e_sub%\bin;%PATH%"
echo ==^> Environment: MSYS2 %_pmn_e_sub% ^(%_pmn_e_root%\%_pmn_e_sub%\bin first on PATH^)
goto env_ok

:msys_missing
if /i "%_pmn_e_sub%"=="clangarm64" goto msys_missing_arm
goto msys_missing_pkg

REM MSYS2 has a CLANGARM64 environment only on ARM64 Windows; on an x64 machine
REM there is nothing to install, so say what to use instead.
:msys_missing_arm
set "_pmn_e_host=%PROCESSOR_ARCHITECTURE%"
if defined PROCESSOR_ARCHITEW6432 set "_pmn_e_host=%PROCESSOR_ARCHITEW6432%"
if /i "%_pmn_e_host%"=="ARM64" goto msys_missing_pkg
echo error: preset %~1 needs MSYS2's CLANGARM64 environment, which MSYS2 provides only on ARM64 Windows ^(this machine is %_pmn_e_host%^). 1>&2
echo        To build for Windows ARM64 from here use windows-arm64-clang-cl or windows-arm64-msvc: they cross-compile 1>&2
echo        with Visual Studio's ARM64 build tools ^(breeze\scripts\setup.bat offers to add them^). 1>&2
goto env_fail

:msys_missing_pkg
echo error: preset %~1 needs MSYS2's %_pmn_e_sub% toolchain, and %_pmn_e_root%\%_pmn_e_sub%\bin\%_pmn_e_exe% was not found. 1>&2
echo        Run breeze\scripts\setup.bat to install it, or in an MSYS2 shell:  pacman -S %_pmn_e_pkg% 1>&2
echo        MSYS2 itself:  winget install MSYS2.MSYS2   ^(set MSYS2_ROOT if it lives somewhere other than the msys64 folder on the system drive^) 1>&2
goto env_fail

REM ---------------------------------------------------------------------
REM Exits. Every path out goes through one of these two, which clear the
REM scratch variables this script made (all start with _pmn_e_).
REM ---------------------------------------------------------------------
:env_ok
call :clear
exit /b 0

:env_fail
call :clear
exit /b 1

:clear
set "_pmn_e_tgt="
set "_pmn_e_llvm="
set "_pmn_e_sub="
set "_pmn_e_exe="
set "_pmn_e_probe="
set "_pmn_e_pkg="
set "_pmn_e_vs="
set "_pmn_e_arg="
set "_pmn_e_vswhere="
set "_pmn_e_vcvars="
set "_pmn_e_need="
set "_pmn_e_host="
set "_pmn_e_pf="
set "_pmn_e_root="
goto :eof
