<#
.SYNOPSIS
    Interactive installer for the tools this project builds with. Windows;
    called by breeze\scripts\setup.bat (Linux and macOS have breeze/scripts/_tools.sh).

.DESCRIPTION
    Checks each tool, and for every one that is missing asks -- ONE TOOL AT
    A TIME -- whether to install it, showing the exact command first. Nothing
    is installed without an explicit yes (or -Yes / -All).

      Required   Git, CMake 3.25+, and a C++ compiler: at least one of
                 Visual Studio Build Tools (MSVC) or MinGW-w64 (via MSYS2)
      Optional   LLVM (clang-cl, Clang, clang-format, clang-tidy), the MSVC
                 ARM64 build tools (to build the windows-arm64-msvc and
                 -clang-cl presets), and the other MSYS2 toolchains (32-bit
                 MinGW, CLANG64)

    Installs go through winget (Windows Package Manager, part of the App
    Installer that ships with Windows 10 1809+ and Windows 11). Two things
    winget does not do for you, and this script does:

      * put CMake and LLVM on PATH -- their installers leave it to you, and
        every guide that runs `winget install Kitware.CMake` ends with "now
        add C:\Program Files\CMake\bin to PATH by hand". A tool found in its
        usual folder but not on PATH is added to this session's PATH (which
        is handed back to setup.bat through -PathOut so the rest of setup
        can use it) and, if you agree, to your user PATH permanently.
      * update a fresh MSYS2, whose package databases are stale (twice, as
        MSYS2 itself recommends -- updating its runtime asks for a restart)
        before installing MinGW-w64 into it.

    Written for Windows PowerShell 5.1 as much as for PowerShell 7: no ??,
    no ternary, no && / ||, nested Join-Path (5.1 has no -AdditionalChildPath),
    and plain ASCII only (5.1 reads a BOM-less file as the ANSI code page).

.PARAMETER Yes
    Install the REQUIRED tools without asking. For scripts and CI. Without a
    terminal and without this, nothing is asked and nothing is installed.

.PARAMETER All
    Also install the optional tools without asking (implies -Yes).

.PARAMETER Check
    Only report what is and is not installed; change nothing. Exits 1 if a
    required tool is missing.

.PARAMETER PathOut
    File to write the directories that were added to this session's PATH to,
    one per line, so the calling batch file can add them to its own.

.NOTES
    Exit status: 0 if every required tool is present at the end, 1 if not.
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$All,
    [switch]$Check,
    [string]$PathOut = ''
)

if ($All) { $Yes = $true }

# Oldest CMake this project supports (cmake_minimum_required in
# CMakeLists.txt, breeze/cmake/Breeze.cmake, and the presets files' cmakeMinimumRequired).
$script:MinCmake = New-Object System.Version 3, 25

# The Visual Studio Build Tools package. 'Microsoft.VisualStudio.BuildTools'
# (no year) is the newest release; the 2022 one is the long-established,
# documented path, so it is the default -- change the id here to prefer
# the newer one.
$script:MsvcWingetId = 'Microsoft.VisualStudio.2022.BuildTools'
$script:MsvcOverride = '--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'

# Answers that carry over from one prompt to the next.
$script:AnsAll = $false          # "a": yes to everything still to come
$script:AnsSkipOptional = $false # "s": no to every OPTIONAL tool still to come
$script:AnsQuit = $false         # "q": stop asking altogether

# Directories added to this session's PATH, for setup.bat to pick up.
$script:PathAdds = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------
# Small helpers
# ---------------------------------------------------------------------------

function Say([string]$Text = '')  { Write-Host $Text }
function Note([string]$Text)      { Write-Host $Text -ForegroundColor DarkGray }
function Good([string]$Text)      { Write-Host $Text -ForegroundColor Green }
function Warn([string]$Text)      { Write-Host $Text -ForegroundColor Yellow }
function Bad([string]$Text)       { Write-Host $Text -ForegroundColor Red }

# Nested Join-Path: Windows PowerShell 5.1's Join-Path takes only two parts.
function Join-Parts {
    $p = [string]$args[0]
    for ($i = 1; $i -lt $args.Count; $i++) { $p = Join-Path $p ([string]$args[$i]) }
    return $p
}

function Get-ProgramFiles   { return $env:ProgramFiles }
function Get-ProgramFilesX86 { return ${env:ProgramFiles(x86)} }

# MSYS2's install folder: C:\msys64 unless MSYS2_ROOT says otherwise.
function Get-Msys2Root {
    if ($env:MSYS2_ROOT) { return $env:MSYS2_ROOT }
    $drive = $env:SystemDrive
    if (-not $drive) { $drive = 'C:' }
    return (Join-Path ($drive + '\') 'msys64')
}

# The first executable called $Name on PATH, or one in $FallbackDirs (the
# folder the installer puts it in even when it doesn't touch PATH), or $null.
function Find-Exe([string]$Name, [string[]]$FallbackDirs) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($dir in $FallbackDirs) {
        if (-not $dir) { continue }
        foreach ($ext in @('.exe', '')) {
            $candidate = Join-Path $dir ($Name + $ext)
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return $null
}

function New-Status([string]$State, [string]$Detail = '') {
    return [pscustomobject]@{ State = $State; Detail = $Detail }
}

# ---------------------------------------------------------------------------
# PATH (session and user)
#
# Wrapped in functions so a test can replace the two that touch the real
# registry.
# ---------------------------------------------------------------------------

function Get-UserPathValue          { return [Environment]::GetEnvironmentVariable('Path', 'User') }
function Set-UserPathValue([string]$Value) { [Environment]::SetEnvironmentVariable('Path', $Value, 'User') }
function Get-MachinePathValue       { return [Environment]::GetEnvironmentVariable('Path', 'Machine') }

function Split-PathList([string]$List) {
    if (-not $List) { return @() }
    $sep = [System.IO.Path]::PathSeparator
    $items = @()
    foreach ($part in $List.Split($sep)) {
        $trimmed = $part.Trim().TrimEnd('\', '/')
        if ($trimmed) { $items += $trimmed }
    }
    return $items
}

function Test-InList([string]$List, [string]$Dir) {
    $want = $Dir.TrimEnd('\', '/')
    foreach ($item in (Split-PathList $List)) {
        if ($item -ieq $want) { return $true }
    }
    return $false
}

function Test-OnSessionPath([string]$Dir) { return (Test-InList $env:Path $Dir) }

function Test-OnPersistentPath([string]$Dir) {
    return ((Test-InList (Get-UserPathValue) $Dir) -or (Test-InList (Get-MachinePathValue) $Dir))
}

function Add-ToSessionPath([string]$Dir) {
    if (Test-OnSessionPath $Dir) { return }
    $sep = [System.IO.Path]::PathSeparator
    $current = $env:Path
    if (-not $current) { $current = '' }
    $env:Path = $current.TrimEnd($sep) + $sep + $Dir
    [void]$script:PathAdds.Add($Dir)
}

function Add-ToUserPath([string]$Dir) {
    $current = Get-UserPathValue
    $sep = [System.IO.Path]::PathSeparator
    if ($current) { $new = $current.TrimEnd($sep) + $sep + $Dir } else { $new = $Dir }
    Set-UserPathValue $new
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

function Get-WingetStatus {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return (New-Status 'ok' 'winget') }
    return (New-Status 'missing')
}

function Get-GitStatus {
    $exe = Find-Exe 'git' @((Join-Parts (Get-ProgramFiles) 'Git' 'cmd'))
    if (-not $exe) { return (New-Status 'missing') }
    $ver = ''
    try { $ver = (& $exe --version 2>$null | Select-Object -First 1) -replace '^git version ', '' } catch { }
    return (New-Status 'ok' $ver)
}

function Get-CmakeStatus {
    $exe = Find-Exe 'cmake' @((Join-Parts (Get-ProgramFiles) 'CMake' 'bin'))
    if (-not $exe) { return (New-Status 'missing') }
    $ver = ''
    try {
        $first = & $exe --version 2>$null | Select-Object -First 1
        if ($first -match '(\d+\.\d+(\.\d+)?)') { $ver = $Matches[1] }
    } catch { }
    if (-not $ver) { return (New-Status 'ok' '') }
    $parsed = $null
    if ([System.Version]::TryParse($ver, [ref]$parsed) -and $parsed -lt $script:MinCmake) {
        return (New-Status 'old' $ver)
    }
    return (New-Status 'ok' $ver)
}

# MSVC: the Visual Studio Installer ships vswhere.exe, which knows whether
# the C++ x86/x64 tools are installed in ANY Visual Studio or Build Tools.
function Get-MsvcStatus {
    $pf86 = Get-ProgramFilesX86
    if (-not $pf86) { return (New-Status 'missing') }
    $vswhere = Join-Parts $pf86 'Microsoft Visual Studio' 'Installer' 'vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { return (New-Status 'missing') }
    $where = $null
    try {
        $where = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1
    } catch { }
    if ($where) { return (New-Status 'ok' ([string]$where)) }
    return (New-Status 'missing')
}

# The ARM64 half of the Visual Studio tools: what an x64 machine cross-compiles
# the windows-arm64-* presets with (the x64-hosted ARM64 compiler and the ARM64
# runtime libraries), and an ARM64 machine builds them natively with. vswhere
# again, asking for both components: the x86/x64 one is what the ARM64 tools run
# on from an x64 machine.
function Get-MsvcArm64Status {
    $pf86 = Get-ProgramFilesX86
    if (-not $pf86) { return (New-Status 'missing') }
    $vswhere = Join-Parts $pf86 'Microsoft Visual Studio' 'Installer' 'vswhere.exe'
    if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) { return (New-Status 'missing') }
    $where = $null
    try {
        $where = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 Microsoft.VisualStudio.Component.VC.Tools.ARM64 -property installationPath 2>$null | Select-Object -First 1
    } catch { }
    if ($where) { return (New-Status 'ok' ([string]$where)) }
    return (New-Status 'missing')
}

function Get-LlvmStatus {
    $exe = Find-Exe 'clang-cl' @((Join-Parts (Get-ProgramFiles) 'LLVM' 'bin'))
    if (-not $exe) { return (New-Status 'missing') }
    return (New-Status 'ok' (Split-Path -Parent $exe))
}

function Get-Msys2Status {
    $bash = Join-Parts (Get-Msys2Root) 'usr' 'bin' 'bash.exe'
    if (Test-Path -LiteralPath $bash -PathType Leaf) { return (New-Status 'ok' (Get-Msys2Root)) }
    return (New-Status 'missing')
}

function Get-MingwStatus([string]$Subdir) {
    $gpp = Join-Parts (Get-Msys2Root) $Subdir 'bin' 'g++.exe'
    if (Test-Path -LiteralPath $gpp -PathType Leaf) { return (New-Status 'ok' (Split-Path -Parent $gpp)) }
    return (New-Status 'missing')
}

function Get-Clang64Status {
    $clang = Join-Parts (Get-Msys2Root) 'clang64' 'bin' 'clang++.exe'
    if (Test-Path -LiteralPath $clang -PathType Leaf) { return (New-Status 'ok' (Split-Path -Parent $clang)) }
    return (New-Status 'missing')
}

# ---------------------------------------------------------------------------
# Asking
# ---------------------------------------------------------------------------

function Test-CanAsk { return (-not [Console]::IsInputRedirected) }

# One line from the user, or $null at end of input. A function of its own so
# a test can stand in for the console.
function Read-Answer { return [Console]::ReadLine() }

# Would an OPTIONAL tool be offered (asked about, or installed by -All) now?
function Test-OptionalWanted {
    if ($script:AnsQuit -or $script:AnsSkipOptional) { return $false }
    if ($All -or $script:AnsAll) { return $true }
    return (Test-CanAsk)
}

# Returns $true for "install it". Sets $script:Ans* for answers that outlast
# one prompt.
function Confirm-Install([string]$Kind, [string]$Question) {
    if ($script:AnsQuit) { return $false }
    if ($script:AnsAll) { return $true }
    if ($Kind -eq 'optional' -and $script:AnsSkipOptional) { return $false }

    # Flags answer for you...
    if ($Kind -eq 'required' -and $Yes) { return $true }
    if ($All) { return $true }

    # ...and with no terminal there is nobody to ask.
    if (-not (Test-CanAsk)) {
        Note '    (not asking: no terminal. Re-run interactively, or pass --yes / --all.)'
        return $false
    }

    if ($Kind -eq 'required') { $prompt = "  $Question [Y/n/a/q] " } else { $prompt = "  $Question [y/N/a/s/q] " }
    while ($true) {
        Write-Host $prompt -NoNewline
        $answer = Read-Answer
        if ($null -eq $answer) {
            # End of input (Ctrl-Z): stop asking rather than loop on it.
            Write-Host ''
            $script:AnsQuit = $true
            return $false
        }
        switch ($answer.Trim().ToLowerInvariant()) {
            { $_ -in @('y', 'yes') } { return $true }
            { $_ -in @('n', 'no') }  { return $false }
            ''                       { return ($Kind -eq 'required') }
            { $_ -in @('a', 'all') } { $script:AnsAll = $true; return $true }
            { $_ -in @('s', 'skip') } { $script:AnsSkipOptional = $true; return $false }
            { $_ -in @('q', 'quit') } { $script:AnsQuit = $true; return $false }
            default {
                if ($Kind -eq 'required') {
                    Note '    y = install   n = not this one   a = install everything left   q = stop asking'
                } else {
                    Note '    y = install   n = not this one   a = install everything left   s = skip the rest of the optional tools   q = stop asking'
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Installing
# ---------------------------------------------------------------------------

function Invoke-Winget([string]$Id, [string]$Override = '') {
    $winget = @('install', '--id', $Id, '-e', '--source', 'winget',
                '--accept-package-agreements', '--accept-source-agreements')
    $shown = 'winget ' + ($winget -join ' ')
    if ($Override) {
        $winget += @('--override', $Override)
        $shown += ' --override "' + $Override + '"'
    }
    Write-Host ('    $ ' + $shown) -ForegroundColor DarkGray
    & winget @winget
    return ($LASTEXITCODE -eq 0)
}

# Adds a component to the Visual Studio (or Build Tools) install Get-MsvcStatus
# found, with the Visual Studio Installer's own `modify` command: the documented
# way to add a component to an existing install. It needs administrator rights,
# so the installer is started elevated (the usual UAC prompt) and waited for.
# Exit code 3010 means "done, restart needed", which is still a success.
function Install-MsvcComponent([string]$ComponentId) {
    $pf86 = Get-ProgramFilesX86
    if (-not $pf86) { return $false }
    $setup = Join-Parts $pf86 'Microsoft Visual Studio' 'Installer' 'setup.exe'
    $vswhere = Join-Parts $pf86 'Microsoft Visual Studio' 'Installer' 'vswhere.exe'
    if (-not ((Test-Path -LiteralPath $setup -PathType Leaf) -and (Test-Path -LiteralPath $vswhere -PathType Leaf))) {
        Bad '    The Visual Studio Installer was not found.'
        return $false
    }
    $installPath = $null
    try {
        $installPath = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1
    } catch { }
    if (-not $installPath) {
        Bad '    No Visual Studio install with the C++ tools was found to add it to.'
        return $false
    }
    $installerArgs = @('modify', '--installPath', ('"' + $installPath + '"'), '--add', $ComponentId, '--passive', '--norestart')
    Write-Host ('    $ "' + $setup + '" ' + ($installerArgs -join ' ')) -ForegroundColor DarkGray
    try {
        $proc = Start-Process -FilePath $setup -ArgumentList $installerArgs -Verb RunAs -Wait -PassThru
    } catch {
        Bad ('    Could not start the Visual Studio Installer: ' + $_.Exception.Message)
        return $false
    }
    return (($proc.ExitCode -eq 0) -or ($proc.ExitCode -eq 3010))
}

# Whether Update-Msys2Base has already run (successfully or not) in this
# process, so installing several MSYS2-hosted toolchains in one setup.bat
# run (e.g. -All pulling in mingw64, mingw32 AND clang64) only pays for the
# update dance -- the slow, disruptive part -- once, not once per package.
$script:Msys2BaseUpdated = $false

# Brings the MSYS2 installation's OWN packages (msys2-runtime, bash, pacman,
# filesystem, ...) up to date, which a fresh install -- what a winget install
# just produced -- badly needs: its package databases are whatever shipped
# in that installer image.
#
# This is exactly the three-step sequence msys2/setup-msys2 -- the official
# GitHub Action, and about as battle-tested a reference as this gets --
# uses, confirmed by reading its source (main.js): an update whose result is
# NOT trusted, an explicit taskkill, then a second, final update whose
# result IS. It exists because updating msys2-runtime/bash/pacman while
# they are the very things running the update can end with MSYS2 force-
# closing every one of its own processes for safety (mid-transaction, to
# avoid the heap corruption a live-running old copy of msys2-runtime would
# otherwise risk) rather than the update finishing normally -- documented
# behavior (msys2.org/docs/updating), not a bug in this project, and not
# something --noconfirm reliably suppresses in every MSYS2-pacman version
# (see msys2/MSYS2-packages#1141, "Updating MSYS2 unattended is broken").
# Running the update a second time is what actually finishes the job (per
# that same documentation: "you need to start a new terminal and run the
# update again"); the taskkill in between is what makes that safe to do
# from the SAME script, back-to-back, without a real terminal to close --
# and it must run from OUTSIDE the MSYS2 process tree to have any effect,
# i.e. from PowerShell, exactly as done here (see the discussion on
# msys2/MSYS2-packages#4340, where MSYS2's own maintainers say so).
# `-FI "MODULES eq msys-2.0.dll"` targets any process with that DLL loaded,
# not any process literally named bash.exe/pacman.exe -- so it cannot catch
# an unrelated bash.exe (WSL's, Git for Windows', a plain MSYS bash someone
# else is using) that never loaded MSYS2's runtime in the first place.
# `--overwrite '*'` on every pacman call, also lifted from that same
# reference implementation, avoids pacman refusing an update over an
# unimportant file conflict -- a real, if uncommon, way this could
# otherwise still stall unattended.
function Update-Msys2Base {
    if ($script:Msys2BaseUpdated) { return $true }
    $bash = Join-Parts (Get-Msys2Root) 'usr' 'bin' 'bash.exe'
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
        Bad '    MSYS2 is not installed at the expected place -- install it first.'
        return $false
    }
    Write-Host '    $ bash -lc "pacman --noconfirm --overwrite ''*'' -Syuu"   (updates MSYS2 itself; may need to close and reopen)' -ForegroundColor DarkGray
    & $bash -lc "pacman --noconfirm --overwrite '*' -Syuu"
    Write-Host '    $ taskkill /F /FI "MODULES eq msys-2.0.dll"   (clears any MSYS2 process the update above force-closed)' -ForegroundColor DarkGray
    & taskkill /F /FI 'MODULES eq msys-2.0.dll' 2>$null | Out-Null
    Write-Host '    $ bash -lc "pacman --noconfirm --overwrite ''*'' -Syuu"   (final update)' -ForegroundColor DarkGray
    & $bash -lc "pacman --noconfirm --overwrite '*' -Syuu"
    $script:Msys2BaseUpdated = $true
    return ($LASTEXITCODE -eq 0)
}

function Invoke-Msys2Packages([string[]]$Packages) {
    $bash = Join-Parts (Get-Msys2Root) 'usr' 'bin' 'bash.exe'
    if (-not (Test-Path -LiteralPath $bash -PathType Leaf)) {
        Bad '    MSYS2 is not installed at the expected place -- install it first.'
        return $false
    }
    if (-not (Update-Msys2Base)) {
        Bad '    Updating MSYS2 itself failed -- see the output above. Try re-running breeze\scripts\setup.bat once MSYS2 has settled (it may need a moment after force-closing its own processes), or update it by hand in an MSYS2 terminal: pacman -Syuu (repeat until it reports nothing to do).'
        return $false
    }
    $list = $Packages -join ' '
    Write-Host ('    $ ' + $bash + ' -lc "pacman -S --needed --noconfirm --overwrite ''*'' ' + $list + '"') -ForegroundColor DarkGray
    & $bash -lc ("pacman -S --needed --noconfirm --overwrite '*' " + $list)
    return ($LASTEXITCODE -eq 0)
}

# ---------------------------------------------------------------------------
# The catalog
#
# Ordered as they are asked. Each row: a stable Id, whether it is Required or
# optional (msvc is decided at run time -- see below), a label, why it
# matters, how to tell if it is there, how to install it, and the folder
# that has to be on PATH for it to be usable (or $null).
# ---------------------------------------------------------------------------

function Get-Catalog {
    $pf = Get-ProgramFiles
    $msys = Get-Msys2Root
    return @(
        @{ Id = 'git';   Kind = 'required'; Label = 'Git';
           Why = 'FetchContent clones dependencies (fmt) with it';
           Status = { Get-GitStatus }; Install = { Invoke-Winget 'Git.Git' };
           PathDir = (Join-Parts $pf 'Git' 'cmd'); PathDefault = $true },

        @{ Id = 'cmake'; Kind = 'required'; Label = 'CMake 3.25 or newer';
           Why = 'configures and drives every build';
           Status = { Get-CmakeStatus }; Install = { Invoke-Winget 'Kitware.CMake' };
           PathDir = (Join-Parts $pf 'CMake' 'bin'); PathDefault = $true },

        # A compiler: at least one of MSVC or MinGW-w64 is required. Which
        # kind msvc is depends on whether one is already there (see Main).
        @{ Id = 'msvc';  Kind = 'compiler'; Label = 'Visual Studio Build Tools (MSVC)';
           Why = 'the windows-*-msvc presets, and the headers/libraries the windows-*-clang-cl ones need';
           Status = { Get-MsvcStatus };
           Install = { Invoke-Winget $script:MsvcWingetId $script:MsvcOverride };
           PathDir = $null },

        # Needs msvc: it adds a component to that install. Without it an x64
        # machine cannot build the windows-arm64-msvc and -clang-cl presets, which
        # cross-compile through it.
        @{ Id = 'msvc-arm64'; Kind = 'optional'; Label = 'MSVC ARM64 build tools';
           Why = 'the windows-arm64-msvc and windows-arm64-clang-cl presets (a cross build from an x64 machine)';
           Needs = 'msvc';
           Status = { Get-MsvcArm64Status };
           Install = { Install-MsvcComponent 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' };
           PathDir = $null },

        @{ Id = 'llvm';  Kind = 'optional'; Label = 'LLVM (clang-cl, Clang, clang-format, clang-tidy)';
           Why = 'the windows-*-clang-cl presets, breeze\scripts\refactor.bat and the pre-commit hook';
           Status = { Get-LlvmStatus }; Install = { Invoke-Winget 'LLVM.LLVM' };
           PathDir = (Join-Parts $pf 'LLVM' 'bin'); PathDefault = $true },

        @{ Id = 'msys2'; Kind = 'optional'; Label = 'MSYS2';
           Why = 'the home of MinGW-w64 on Windows (needed for the windows-*-mingw* presets)';
           Status = { Get-Msys2Status }; Install = { Invoke-Winget 'MSYS2.MSYS2' };
           PathDir = $null },

        @{ Id = 'mingw64'; Kind = 'optional'; Label = 'MinGW-w64 GCC, 64-bit';
           Why = 'the windows-x64-mingw64 preset'; Needs = 'msys2';
           Status = { Get-MingwStatus 'mingw64' };
           Install = { Invoke-Msys2Packages @('mingw-w64-x86_64-gcc') };
           PathDir = (Join-Parts $msys 'mingw64' 'bin'); PathDefault = $false },

        @{ Id = 'mingw32'; Kind = 'optional'; Label = 'MinGW-w64 GCC, 32-bit';
           Why = 'the windows-x86-mingw32 preset'; Needs = 'msys2';
           Status = { Get-MingwStatus 'mingw32' };
           Install = { Invoke-Msys2Packages @('mingw-w64-i686-gcc') };
           PathDir = (Join-Parts $msys 'mingw32' 'bin'); PathDefault = $false },

        @{ Id = 'clang64'; Kind = 'optional'; Label = 'MSYS2 CLANG64 (GNU-style Clang)';
           Why = 'the windows-x64-clang preset'; Needs = 'msys2';
           Status = { Get-Clang64Status };
           Install = { Invoke-Msys2Packages @('mingw-w64-clang-x86_64-clang') };
           PathDir = (Join-Parts $msys 'clang64' 'bin'); PathDefault = $false }
    )
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

function Show-ManualHelp {
    Say '    Install these yourself instead:'
    Say '      Git         https://git-scm.com/download/win'
    Say '      CMake       https://cmake.org/download/   (tick "Add CMake to the system PATH")'
    Say '      MSVC        https://visualstudio.microsoft.com/visual-cpp-build-tools/   (workload: Desktop development with C++)'
    Say '      LLVM        https://github.com/llvm/llvm-project/releases'
    Say '      MSYS2       https://www.msys2.org/'
}

function Invoke-Main {
    $catalog = Get-Catalog
    $wingetStatus = Get-WingetStatus
    $haveWinget = ($wingetStatus.State -eq 'ok')

    Say ('==> Checking the tools this project builds with (Windows, winget: ' + $(if ($haveWinget) { 'found' } else { 'NOT found' }) + ')')

    # ---- report ---------------------------------------------------------
    $status = @{}
    foreach ($row in $catalog) { $status[$row.Id] = (& $row.Status) }

    $haveCompiler = ($status['msvc'].State -eq 'ok') -or ($status['mingw64'].State -eq 'ok') -or ($status['mingw32'].State -eq 'ok')
    foreach ($row in $catalog) {
        $st = $status[$row.Id]
        $kind = $row.Kind
        if ($kind -eq 'compiler') { if ($haveCompiler) { $kind = 'optional' } else { $kind = 'required' } }
        $row.EffKind = $kind
        switch ($st.State) {
            'ok' {
                if ($st.Detail) { Write-Host ('    [ ok ]  ' + $row.Label.PadRight(50) + ' ') -NoNewline -ForegroundColor Green; Note $st.Detail }
                else { Good ('    [ ok ]  ' + $row.Label) }
            }
            'old' { Warn ('    [old ]  ' + $row.Label.PadRight(50) + ' ' + $st.Detail + ' (needs ' + $script:MinCmake.ToString() + '+)') }
            default {
                if ($kind -eq 'required') { Bad ('    [ !! ]  ' + $row.Label.PadRight(50) + ' missing (required)') }
                else { Note ('    [ -- ]  ' + $row.Label.PadRight(50) + ' missing (optional)') }
            }
        }
    }
    if (-not $haveCompiler) {
        Warn '    A C++ compiler is required: Visual Studio Build Tools, or MinGW-w64 through MSYS2 (either one).'
    }

    # ---- -Check: report only --------------------------------------------
    if ($Check) {
        $missing = ($status['git'].State -ne 'ok') -or ($status['cmake'].State -ne 'ok') -or (-not $haveCompiler)
        if ($missing) { return 1 }
        return 0
    }

    $anythingToInstall = $false
    foreach ($row in $catalog) { if ($status[$row.Id].State -ne 'ok') { $anythingToInstall = $true } }
    if ($anythingToInstall -and -not $haveWinget) {
        Say ''
        Warn '    winget (Windows Package Manager) was not found, so this script cannot install anything.'
        Say '    It comes with the App Installer: https://aka.ms/getwinget (or the Microsoft Store).'
        Show-ManualHelp
    }

    # ---- offer installs, one at a time ----------------------------------
    $skipped = @()
    $failed = @()
    foreach ($row in $catalog) {
        if ($script:AnsQuit) { break }
        $st = & $row.Status          # re-check: an earlier install may have provided it
        if ($st.State -eq 'ok') { continue }
        if (-not $haveWinget) { continue }

        # MinGW rows live inside MSYS2.
        if ($row.Needs) {
            $needRow = $catalog | Where-Object { $_.Id -eq $row.Needs } | Select-Object -First 1
            $needed = & $needRow.Status
            if ($needed.State -ne 'ok') { continue }
        }

        # After the msvc row, "a compiler exists" may have changed the kind
        # of the rows still to come.
        $kind = $row.EffKind
        if ($kind -eq 'required' -and $row.Id -eq 'msvc') {
            $now = ((Get-MingwStatus 'mingw64').State -eq 'ok') -or ((Get-MingwStatus 'mingw32').State -eq 'ok')
            if ($now) { $kind = 'optional' }
        }

        if ($kind -eq 'optional' -and -not (Test-OptionalWanted)) {
            $skipped += $row.Label
            continue
        }

        Say ''
        Write-Host ('  ' + $row.Label) -NoNewline -ForegroundColor White
        Say (' -- ' + $row.Why)
        if ($st.State -eq 'old') { Note ('    (installed: ' + $st.Detail + ', but too old)') }

        if (Confirm-Install $kind ('Install ' + $row.Label + '?')) {
            $ok = & $row.Install
            $after = & $row.Status
            if ($after.State -eq 'ok') {
                Good '    installed'
            } elseif ($after.State -eq 'old') {
                Warn ('    CMake ' + $after.Detail + ' is older than the ' + $script:MinCmake.ToString() + ' this project needs.')
                $failed += $row.Label
            } elseif (-not $ok) {
                Bad '    install failed -- see the output above.'
                $failed += $row.Label
            } else {
                Warn ('    the install finished, but ' + $row.Label + ' still is not found -- open a new terminal, or check the output above.')
                $failed += $row.Label
            }
        } elseif ($kind -eq 'optional') {
            $skipped += $row.Label
        }
    }
    if ($skipped.Count -gt 0) {
        Say ''
        Note ('  Optional, not installed: ' + ($skipped -join ', '))
        Note '  (breeze\scripts\setup.bat, run interactively, offers each one; --all installs them all.)'
    }

    # ---- PATH ------------------------------------------------------------
    # A tool that is installed but whose folder is not on PATH is unusable
    # from a plain terminal -- and, for CMake, from the rest of setup.bat.
    foreach ($row in $catalog) {
        if (-not $row.PathDir) { continue }
        $st = & $row.Status
        if ($st.State -ne 'ok') { continue }
        if (-not (Test-Path -LiteralPath $row.PathDir -PathType Container)) { continue }
        if (Test-OnSessionPath $row.PathDir) { continue }

        # This session, always: what follows in setup needs it.
        Add-ToSessionPath $row.PathDir
        if (Test-OnPersistentPath $row.PathDir) { continue }

        Say ''
        Say ('  ' + $row.Label + ' is installed, but its folder is not on your PATH:')
        Say ('    ' + $row.PathDir)
        if ($row.PathDefault) { $kind = 'required' } else { $kind = 'optional' }
        if (-not $row.PathDefault) {
            Note '    (breeze\scripts\build.bat does not need this: it puts the right MSYS2 toolchain folder first on PATH'
            Note '     for the preset it builds, for that run only. Adding the folder here puts its g++/gcc on PATH for every program.)'
        }
        if (Confirm-Install $kind 'Add it to your user PATH (new terminals will see it)?') {
            Add-ToUserPath $row.PathDir
            Good '    added -- open a new terminal to use it there.'
        }
    }

    # ---- hand this session's PATH additions back to setup.bat ------------
    if ($PathOut -and $script:PathAdds.Count -gt 0) {
        Set-Content -LiteralPath $PathOut -Value ($script:PathAdds.ToArray()) -Encoding ASCII
    }

    # ---- verdict ---------------------------------------------------------
    $exit = 0
    $needGit = (Get-GitStatus).State -ne 'ok'
    $needCmake = (Get-CmakeStatus).State -ne 'ok'
    $needCompiler = -not (((Get-MsvcStatus).State -eq 'ok') -or ((Get-MingwStatus 'mingw64').State -eq 'ok') -or ((Get-MingwStatus 'mingw32').State -eq 'ok'))
    if ($needGit)      { Bad '  still missing (required): Git'; $exit = 1 }
    if ($needCmake)    { Bad '  still missing (required): CMake 3.25 or newer'; $exit = 1 }
    if ($needCompiler) { Bad '  still missing (required): a C++ compiler (Visual Studio Build Tools, or MinGW-w64 via MSYS2)'; $exit = 1 }
    if ($failed.Count -gt 0 -and $exit -eq 0) { Warn ('  These did not install: ' + ($failed -join ', ')) }
    return $exit
}

# Run only when executed, not when dot-sourced (a test dot-sources this file
# to replace the functions that touch the registry).
if ($MyInvocation.InvocationName -ne '.') {
    $code = Invoke-Main
    exit $code
}
