# deploy_web.ps1 - put the web build on the live server in one command,
# keeping the build it replaces so it can be put straight back.
#
#     .\tools\deploy_web.ps1 -Export        # export Web, upload, swap it in
#     .\tools\deploy_web.ps1                # upload the builds\web you already exported
#     .\tools\deploy_web.ps1 -Rollback      # put the previous build back
#     .\tools\deploy_web.ps1 -DryRun        # say every step, run none of them
#
# WHAT IT REPLACES. The swap used to be four commands across two windows - make
# room on the server, scp from the PC, then one long line on the server - and
# every step was a copy and paste that could land in the wrong window. This is
# the same four steps, in order, with the checks a person skips at midnight:
#
#   1. (with -Export) Godot exports the Web preset to builds\web, headless.
#   2. The export is refused if it is older than the code: a build exported
#      before the last change ships the change's version number with none of
#      the change in it.
#   3. builds\web goes up under a NEW name (elusion-web-new-<time>), so there
#      is nothing on the server to delete first and nothing half-copied is ever
#      live.
#   4. One ssh line swaps it in: the live build becomes elusion-web-old, the
#      upload becomes elusion-web, everyone can read it. Then the page is
#      asked for, to see it answers.
#
# A PASSWORD IS ASKED TWICE (once by scp, once by ssh) unless this PC has an
# SSH key on the server. The script never sees it; ssh and scp ask for it
# themselves, the same as when you type the commands.
#
# Nothing here touches the API or the database. The server's own update is
# deploy/update_server.sh in the API repository.

[CmdletBinding()]
param(
    [switch]$Export,
    [switch]$Rollback,
    [switch]$DryRun,
    [switch]$Force,
    [string]$Server = "root@159.65.67.51",
    [string]$Site = "https://play.elusionrpg.com/",
    [string]$Godot = $env:GODOT
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $root "project.godot") -PathType Leaf)) {
    throw "No project.godot one folder up. Keep deploy_web.ps1 in the project's tools folder."
}
$web = Join-Path $root "builds\web"

foreach ($tool in @("ssh", "scp")) {
    if (-not $DryRun -and -not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not on this PC's PATH. It ships with Windows (Settings > Optional features > OpenSSH Client)."
    }
}

function Say([string]$text, [string]$colour = "Gray") { Write-Host $text -ForegroundColor $colour }

# WAIT FOR IT, AND READ ITS OWN EXIT CODE. Godot_v4.6.1-stable_win64.exe with
# no _console twin is a windowed program, and PowerShell does not wait for one
# run bare: it started the export and went straight on, read the exit code the
# last program left behind - the 1 from a deploy refused a minute before - and
# stopped with "The export failed (exit 1)" while the export ran on, finished
# and printed behind the prompt. So: the old code is cleared first ($global:,
# or a local copy would hide the real one), and -Windowed pipes the program,
# which makes PowerShell wait for either kind. ssh and scp run bare, so scp
# keeps its progress bar.
function Run([string]$what, [string]$exe, [string[]]$arguments, [switch]$Windowed) {
    Say ("  > {0} {1}" -f $exe, ($arguments -join " ")) "DarkGray"
    if ($DryRun) { return }
    $global:LASTEXITCODE = 0
    if ($Windowed) {
        & $exe @arguments | Out-Host
    } else {
        & $exe @arguments
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$what failed (exit $LASTEXITCODE). Nothing after it was run."
    }
}

# --- ROLLBACK -----------------------------------------------------------------
if ($Rollback) {
    Say "Putting the previous web build back on $Server ..." "Cyan"
    # elusion-web-bad keeps the build being taken down, in case it is wanted
    # after all; the previous -bad goes first so there is only ever one.
    $line = "cd /srv && test -d elusion-web-old && rm -rf elusion-web-bad && mv elusion-web elusion-web-bad && mv elusion-web-old elusion-web && ls /srv"
    Run "The rollback" "ssh" @($Server, $line)
    Say "Rolled back. The build that was live is in /srv/elusion-web-bad." "Green"
    exit 0
}

# --- WHICH VERSION -----------------------------------------------------------
$apiGd = Join-Path $root "src\systems\api.gd"
$version = "?"
$m = Select-String -Path $apiGd -Pattern 'DISPLAY_VERSION\s*:=\s*"([^"]+)"' | Select-Object -First 1
if ($m) { $version = $m.Matches[0].Groups[1].Value }
Say "Elusion $version - web deploy to $Server" "Cyan"

# --- 1. EXPORT ---------------------------------------------------------------
if ($Export) {
    # Found the way run_tests.ps1 finds it: -Godot, then GODOT, then PATH, then
    # the usual folders two levels deep.
    if (-not $Godot) {
        $onPath = Get-Command godot -ErrorAction SilentlyContinue
        if ($onPath) { $Godot = $onPath.Source }
    }
    if (-not $Godot) {
        # C:\Godot FIRST - where the owner keeps the editor (22 Oct, "should b
        # c/godot"). Then the usual folders. The first folder holding an engine
        # wins, its newest engine if it holds more than one.
        $searchRoots = @(
            "C:\Godot",
            [Environment]::GetFolderPath("Desktop"),
            "$env:USERPROFILE\Desktop",
            "$env:USERPROFILE\Downloads",
            "$env:LOCALAPPDATA\Programs",
            "$env:ProgramFiles",
            "${env:ProgramFiles(x86)}"
        ) | Where-Object { $_ -and (Test-Path $_ -PathType Container) } | Select-Object -Unique
        $main = $null
        foreach ($r in $searchRoots) {
            $main = Get-ChildItem -Path $r -Filter "Godot*.exe" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -notlike "*_console.exe" -and $_.Length -gt 10MB } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($main) { break }
        }
        if ($main) {
            $twin = Join-Path $main.DirectoryName ($main.BaseName + "_console.exe")
            $Godot = if (Test-Path $twin -PathType Leaf) { $twin } else { $main.FullName }
        }
    }
    if (-not $Godot -or -not (Test-Path $Godot -PathType Leaf)) {
        throw "Could not find Godot to export with (looked in C:\Godot first). Pass it: -Godot 'C:\Godot\Godot_v4.7.2-stable_win64_console.exe'"
    }

    # THE WEB TEMPLATES FOR THIS GODOT, before an export that would only fail
    # on them (22 Oct: 4.7.2 had none, and the export's own words were buried
    # in a page of output). Each Godot version has its own; a self-contained
    # Godot (a ._sc_ or _sc_ file beside it) keeps them in its own folder.
    if (-not $DryRun) {
        # In a try: Windows PowerShell 5.1 with "Stop" turns any line a program
        # writes to stderr into an error, and this check must never be the
        # thing that stops a deploy.
        $said = $null
        try { $said = (& $Godot --version 2>$null | Select-Object -First 1) } catch { $said = $null }
        $global:LASTEXITCODE = 0
        if ($said -match '^(\d+\.\d+(\.\d+)?)\.([a-z0-9]+)') {
            $tag = $Matches[1] + "." + $Matches[3]
            $home_dir = Split-Path $Godot -Parent
            $selfContained = (Test-Path (Join-Path $home_dir "._sc_")) -or (Test-Path (Join-Path $home_dir "_sc_"))
            $templates = Join-Path $env:APPDATA "Godot\export_templates\$tag"
            if ($selfContained) { $templates = Join-Path $home_dir "editor_data\export_templates\$tag" }
            if (-not (Test-Path (Join-Path $templates "web_nothreads_release.zip") -PathType Leaf)) {
                Say "Godot $tag has no web export templates (looked in $templates)." "Red"
                Say "  1. Open that Godot: $Godot" "Gray"
                Say "  2. Editor > Manage Export Templates > Download and Install" "Gray"
                Say "     (or Install from File, with the .tpz from godotengine.org/download/archive)" "Gray"
                Say "  3. Close Godot, then run this again." "Gray"
                exit 1
            }
        }
    }
    Say "1. Exporting the Web preset with $Godot" "Cyan"
    if (-not $DryRun) { New-Item -ItemType Directory -Force -Path $web | Out-Null }
    # The editor rewrites export_presets.cfg when it exports; the command line
    # does not. Either way, export with the editor CLOSED or reopened since the
    # last export, so it does not save its stale copy over the file later.
    Run "The export" $Godot @("--headless", "--path", $root, "--export-release", "Web", "builds/web/index.html") -Windowed
}

# --- 2. IS THE EXPORT THERE, AND NEWER THAN THE CODE -------------------------
if (-not $DryRun) {
    foreach ($need in @("index.html", "index.pck", "index.wasm", "index.js")) {
        if (-not (Test-Path (Join-Path $web $need) -PathType Leaf)) {
            throw "builds\web\$need is missing. Export the Web preset first (or run with -Export)."
        }
    }
    $pck = Get-Item (Join-Path $web "index.pck")
    $newest = Get-ChildItem -Path (Join-Path $root "src"), (Join-Path $root "scene"), (Join-Path $root "data") `
                  -Recurse -File -Include *.gd, *.tscn, *.tres, *.json -ErrorAction SilentlyContinue |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($newest -and $newest.LastWriteTime -gt $pck.LastWriteTime -and -not $Force) {
        Say "The export is older than the code." "Red"
        Say ("  exported:      {0}" -f $pck.LastWriteTime) "Gray"
        Say ("  newest change: {0}  {1}" -f $newest.LastWriteTime, $newest.FullName.Substring($root.Length + 1)) "Gray"
        Say "Export again (or run with -Export). -Force sends it anyway." "Gray"
        exit 1
    }
    Say ("2. builds\web is ready: {0:N1} MB, exported {1}" -f `
        ((Get-ChildItem $web -File | Measure-Object Length -Sum).Sum / 1MB), $pck.LastWriteTime) "Cyan"
}

# --- 3. UPLOAD UNDER A NEW NAME ----------------------------------------------
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$upload = "elusion-web-new-$stamp"
Say "3. Uploading to /srv/$upload" "Cyan"
Run "The upload" "scp" @("-r", $web, "${Server}:/srv/$upload")

# --- 4. SWAP IT IN ------------------------------------------------------------
Say "4. Swapping it in (the live build becomes elusion-web-old)" "Cyan"
# KEEP THE DATE OF EVERY FILE THAT DID NOT CHANGE. The web server's ETag is the
# file's date and size, and every export writes every file fresh - so a plain
# swap made each returning player download all 45 MB again, the 38 MB engine
# (index.wasm) included, though its bytes had not changed since 4.6.1. A file
# whose bytes match the live one gets the live one's date (touch -r), its ETag
# stays the same, and the browser's check comes back 304: a player downloads
# only what really changed, usually the 9 MB index.pck.
#
# Single quotes on purpose: $f, $n and $k are the server's shell variables,
# not PowerShell's. No double quotes inside, because Windows PowerShell 5.1
# mangles them on the way to ssh.exe; no file in an export has a space.
$swap = 'cd /srv && k=0 && test -f ' + $upload + '/index.html && ' +
        'for f in elusion-web/*; do n=' + $upload + '/${f#elusion-web/}; ' +
        'if [ -f $n ] && cmp -s $f $n; then touch -r $f $n; k=$((k+1)); fi; done && ' +
        'echo unchanged files keeping their dates: $k && ' +
        'rm -rf elusion-web-old && mv elusion-web elusion-web-old && mv ' + $upload + ' elusion-web && ' +
        'chmod -R a+rX elusion-web && rm -rf elusion-web-new elusion-web-new-* && ls /srv'
Run "The swap" "ssh" @($Server, $swap)

# --- DOES IT ANSWER ----------------------------------------------------------
if (-not $DryRun) {
    try {
        $r = Invoke-WebRequest -Uri $Site -Method Head -UseBasicParsing -TimeoutSec 20
        Say ("The page answers {0}. Elusion {1} is live." -f [int]$r.StatusCode, $version) "Green"
    } catch {
        Say "The swap is done, but $Site did not answer: $($_.Exception.Message)" "Yellow"
        Say "If it stays down, put the last build back:  .\tools\deploy_web.ps1 -Rollback" "Yellow"
        exit 1
    }
}
Say "To put the previous build back:  .\tools\deploy_web.ps1 -Rollback" "DarkGray"
