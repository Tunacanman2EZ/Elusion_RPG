# atlasaudit.ps1 - run the tile-art audit headless.
#
#     .\atlasaudit.ps1
#     .\atlasaudit.ps1 -Godot "C:\full\path\to\Godot.exe"     # if the search misses
#
# Prints painted cell counts per texture, across every scene. It reads and
# prints; it writes nothing and changes nothing, so it is always safe to run.
# The audit itself is src/tools/atlasaudit.gd, and its header explains what the
# numbers mean and - more importantly - what they do not mean.
#
#
# WHY THIS SCRIPT EXISTS AT ALL
# -----------------------------
# The obvious instruction is "run godot --headless --script res://...". That was
# the documented command for about ten minutes, and it fails immediately with
# "The term 'godot' is not recognized", because the engine on this machine is a
# downloaded .exe on the Desktop and was never put on PATH. A tool nobody can
# start is not a tool.
#
# So the binary hunt below is LIFTED FROM run_tests.ps1 DELIBERATELY, comments
# and all. The three Windows traps it documents - directories named like
# executables, launcher stubs without their binary, and a GUI-subsystem exe that
# PowerShell does not wait for - apply exactly the same here, and every one of
# them was hit for real on this machine. Two copies of a solved problem beats one
# copy plus one script that rediscovers it.
#
# KEEP THIS FILE PURE ASCII. Windows PowerShell 5.1 reads a .ps1 without a BOM as
# CP1252, so a UTF-8 em-dash becomes three garbage characters. The test suite
# enforces this - see _test_helper_scripts_ascii() in src/tools/testrunner.gd.

param(
    [string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

if (-not (Test-Path (Join-Path $root "project.godot") -PathType Leaf)) {
    throw "No project.godot next to this script. Keep atlasaudit.ps1 in the project root."
}

function Resolve-GodotStub([string]$Path) {
    # Given a path, return something runnable, or $null.
    # A _console.exe is only runnable if the binary it launches is beside it.
    if (-not (Test-Path $Path -PathType Leaf)) { return $null }
    if ($Path -notlike "*_console.exe") { return $Path }

    $main = Join-Path (Split-Path $Path -Parent) `
                      (((Split-Path $Path -Leaf) -replace '_console\.exe$', '.exe'))
    if (Test-Path $main -PathType Leaf) { return $Path }

    Write-Host "Ignoring $Path" -ForegroundColor Yellow
    Write-Host "  It is a launcher stub and the binary it launches is not beside it." -ForegroundColor DarkGray
    return $null
}

if ($Godot) {
    $Godot = Resolve-GodotStub $Godot
    if (-not $Godot) { throw "The -Godot path given is not a runnable Godot binary." }
}

if (-not $Godot) {
    $onPath = Get-Command godot -ErrorAction SilentlyContinue
    if ($onPath) { $Godot = $onPath.Source }
}

if (-not $Godot) {
    $searchRoots = @(
        [Environment]::GetFolderPath("Desktop"),
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Downloads",
        "$env:LOCALAPPDATA\Programs",
        "$env:ProgramFiles",
        "${env:ProgramFiles(x86)}"
    ) | Where-Object { $_ -and (Test-Path $_ -PathType Container) } |
        Select-Object -Unique

    $all = @()
    foreach ($r in $searchRoots) {
        $all += Get-ChildItem -Path $r -Filter "Godot*.exe" -File -Recurse -Depth 2 `
                    -ErrorAction SilentlyContinue
    }

    # Real engine binaries only. 10MB comfortably separates a ~170MB engine from
    # a ~200KB stub, and keeps working across versions.
    $main = $all |
        Where-Object { $_.Name -notlike "*_console.exe" -and $_.Length -gt 10MB } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($main) {
        # Prefer its console twin when there is one: the plain binary is a
        # GUI-subsystem app whose stdout may go nowhere.
        $twin = Join-Path $main.DirectoryName ($main.BaseName + "_console.exe")
        $Godot = if (Test-Path $twin -PathType Leaf) { $twin } else { $main.FullName }
    }
}

if (-not $Godot -or -not (Test-Path $Godot -PathType Leaf)) {
    Write-Host "Could not find a Godot engine binary." -ForegroundColor Red
    Write-Host "Searched PATH, then Desktop, Downloads, Programs and Program Files (2 levels deep)."
    Write-Host "Point at it directly:  .\atlasaudit.ps1 -Godot 'C:\full\path\to\Godot.exe'"
    exit 1
}

# Same requirement as the test suite: the class index is written by the EDITOR's
# filesystem scan, and a headless run only reads it. Without it every class_name
# in the project reads as undeclared, which looks like a broken project and is
# not one.
$classCache = Join-Path $root ".godot\global_script_class_cache.cfg"
if (-not (Test-Path $classCache -PathType Leaf)) {
    Write-Host "Godot's class index is missing:" -ForegroundColor Yellow
    Write-Host "  $classCache"
    Write-Host ""
    Write-Host "Open the Godot EDITOR on this project once and let it finish scanning."
    exit 1
}

Write-Host "Godot: $Godot" -ForegroundColor DarkGray
Write-Host ""

# Start-Process -Wait, NOT the call operator - see the long note in run_tests.ps1.
# The plain win64 binary is a GUI-subsystem app and `&` returns before it has
# finished, which prints the report after the prompt comes back.
$proc = Start-Process -FilePath $Godot -NoNewWindow -Wait -PassThru `
            -ArgumentList @("--headless", "--path", "`"$root`"",
                            "--script", "res://src/tools/atlasaudit.gd")

exit $proc.ExitCode
