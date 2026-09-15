# run_tests.ps1 - run the game-side test suite headless.
#
#     .\run_tests.ps1
#     .\run_tests.ps1 -Godot "C:\full\path\to\Godot.exe"     # if the search misses
#
# Exits 0 if everything passed, 1 if anything failed, so it can gate a commit.
# The suite itself is src/tools/testrunner.gd. It also writes its full transcript
# to test_results.txt in the project root, so the results survive even when the
# console does not show them.
#
#
# THREE WINDOWS TRAPS THIS SCRIPT EXISTS TO NOT FALL INTO
# -------------------------------------------------------
# All three were hit for real on this machine, in this order.
#
# 1. Test-Path is true for DIRECTORIES. Unzipping Godot can produce a FOLDER
#    named Godot_v4.6.1-stable_win64.exe, and a plain Test-Path on it passes
#    happily. The call operator then says "is not recognized as ... an operable
#    program", which reads like the file is missing when it is right there.
#    Every check here is -PathType Leaf and the search uses -File.
#
# 2. Godot_*_console.exe IS NOT GODOT. It is a ~200 KB launcher stub that runs
#    the real binary sitting next to it and forwards the output. On its own it
#    fails with "Main executable ... not found". The real engine is ~170 MB.
#    That size gap is how this script tells them apart, and it only uses a
#    console stub when it has confirmed the binary it launches.
#
# 3. The engine is not necessarily anywhere sensible. On this machine it is a
#    loose .exe on the Desktop, so the Desktop is searched first.
#
# ASCII ONLY. Windows PowerShell 5.1 reads a BOM-less .ps1 as CP1252, where the
# last byte of a UTF-8 em dash decodes to a right double quote and silently ends
# whatever string it is sitting in. See CLAUDE.md.

[CmdletBinding()]
param(
    [string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot

if (-not (Test-Path (Join-Path $root "project.godot") -PathType Leaf)) {
    throw "No project.godot next to this script. Keep run_tests.ps1 in the project root."
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
    Write-Host "Point at it directly:  .\run_tests.ps1 -Godot 'C:\full\path\to\Godot.exe'"
    exit 1
}

Write-Host "Godot: $Godot" -ForegroundColor DarkGray
Write-Host ""

# Start-Process -Wait, NOT the call operator.
#
# Godot's plain win64 binary is a GUI-subsystem app. PowerShell's `&` launches
# one and returns IMMEDIATELY without waiting, so $LASTEXITCODE is whatever it
# was before, and anything checked afterwards is checked while Godot is still
# starting up. The visible symptom was this script reporting "no test_results.txt,
# the suite did not reach the end" and handing back the prompt, and THEN the
# entire passing test run printing itself into the console underneath.
$proc = Start-Process -FilePath $Godot -NoNewWindow -Wait -PassThru `
            -ArgumentList @("--headless", "--path", "`"$root`"", "res://scene/tests/tests.tscn")
$code = $proc.ExitCode

$results = Join-Path $root "test_results.txt"

Write-Host ""
if ($code -eq 0) {
    Write-Host "PASS (exit 0)" -ForegroundColor Green
} else {
    Write-Host "FAIL (exit $code)" -ForegroundColor Red
}

if (Test-Path $results -PathType Leaf) {
    Write-Host "Transcript: $results" -ForegroundColor DarkGray
} else {
    Write-Host "No test_results.txt was written - the suite did not reach the end." -ForegroundColor Yellow
}

exit $code
