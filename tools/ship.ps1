# ship.ps1 - ship everything that is waiting, in the right order, in one command.
#
#     .\tools\ship.ps1 -Status     # what is waiting in each repository - changes nothing
#     .\tools\ship.ps1 -DryRun     # say every step, run none of them
#     .\tools\ship.ps1             # commit, push, update the server, deploy the web build
#
# WHY IT EXISTS. On 17 Oct the owner believed everything was shipped. It was
# not: 0.50.0 to 0.52.0 sat uncommitted in all three repositories, the server
# ran the 0.49.0 API, and the web build was a version behind. Nothing had
# failed; there were simply four repositories' worth of steps, done by hand,
# in an order that had to be remembered. This is that order, written down once:
#
#   1. THE API      commit and push (C:\Users\Robert\Desktop\game\api)
#   2. THE SERVER   update_server.sh --restart over ssh - it pulls what step 1 pushed
#   3. THE ART PACK commit and push (art\pack in this repository - the private
#                   submodule of purchased Clockwork Raven art)
#   4. THE GAME     commit and push (this repository)
#   5. THE WEB      tools\deploy_web.ps1 -Export - Godot exports, then it goes live
#   6. THE SITE     commit and push (C:\Users\Robert\Desktop\site) - Netlify builds it
#
# The API goes before the game so a new game never meets an old server. The
# art pack goes before the game because the game's commit records WHICH commit
# of the pack it was built with: committed the other way round, the game would
# point at a pack commit that does not exist on GitHub yet.
#
# THE MESSAGES. Each repository's commit message is a file in the commit folder:
# SHIP_api.txt, SHIP_pack.txt, SHIP_game.txt, SHIP_site.txt. They are written for you with
# every batch. A repository with changes and no message file is not committed -
# the script says so and goes on to the next. After a commit the file is renamed
# SHIPPED_<date>_<repo>.txt, so the same message is never used twice.
#
# THE GUARDS. Before anything is committed it is listed, and the script asks.
# It refuses outright - whatever you answer - to commit a database (*.db and its
# -wal/-shm), a .env, an SSH key, an .exe or .pck, anything under builds/, or any
# file over 50 MB. .gitignore should already keep those out; this is the second
# lock on the same door.
#
# It never prints the server's address, a password or a key. ssh and scp ask for
# the password themselves, as when you type the commands.

[CmdletBinding()]
param(
    [switch]$Status,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$SkipServer,
    [switch]$SkipWeb,
    [string]$GameRepo = (Split-Path $PSScriptRoot -Parent),
    [string]$ApiRepo = "C:\Users\Robert\Desktop\game\api",
    [string]$SiteRepo = "C:\Users\Robert\Desktop\site",
    [string]$MessageFolder = "C:\Users\Robert\Desktop\elusion commit folder",
    [string]$ServerUpdate = "ssh root@api.elusionrpg.com bash /opt/elusion/api/deploy/update_server.sh --restart"
)

$ErrorActionPreference = "Stop"
$MostBytes = 50MB
# Never committed, whatever the answer. Matched against the path git reports, with / between folders.
$Forbidden = @(
    '(^|/)[^/]*\.db$', '\.db-(wal|shm|journal)$', '(^|/)\.env$', '\.env$', 'id_ed25519', 'id_rsa',
    '\.pem$', '\.key$', '\.exe$', '\.pck$', '(^|/)builds/', '(^|/)Claude outputs/'
)

function Say([string]$text, [string]$colour = "Gray") { Write-Host $text -ForegroundColor $colour }
function Heading([string]$text) { Write-Host ""; Write-Host $text -ForegroundColor Cyan }

# NOT NAMED "Git": PowerShell finds a function before a program, so a function
# called Git would answer its own "& git" and call itself forever.
function RunGit([string]$repo, [string[]]$arguments) {
    # Output back as lines; stderr (git's progress) goes straight to the screen.
    $global:LASTEXITCODE = 0
    $out = & git -C $repo @arguments
    if ($LASTEXITCODE -ne 0) { throw "git $($arguments -join ' ') failed in $repo (exit $LASTEXITCODE)." }
    return $out
}

# The paths with changes - modified, new, deleted - as git reports them, new
# files one by one (-uall), a rename by its new name. -z, so a name with a
# space in it is one name.
function Waiting([string]$repo) {
    $raw = (RunGit $repo @("status", "--porcelain=v1", "-z", "-uall")) -join ""
    $items = $raw -split [char]0 | Where-Object { $_ -ne "" }
    $paths = @()
    $skipNext = $false
    foreach ($item in $items) {
        if ($skipNext) { $skipNext = $false; continue }
        $code = $item.Substring(0, 2)
        $path = $item.Substring(3)
        if ($code[0] -eq 'R' -or $code[0] -eq 'C') { $skipNext = $true }
        $paths += [pscustomobject]@{ Code = $code; Path = $path }
    }
    return $paths
}

# Why each path may not be committed, if it may not.
function Refusals([string]$repo, $paths) {
    $out = @()
    foreach ($p in $paths) {
        foreach ($pattern in $Forbidden) {
            if ($p.Path -match $pattern) { $out += "$($p.Path)  (never committed: matches $pattern)"; break }
        }
        $full = Join-Path $repo $p.Path
        if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Get-Item -LiteralPath $full -Force).Length -gt $MostBytes) {
            $out += "$($p.Path)  (over 50 MB)"
        }
    }
    return $out
}

# Commits made here and not pushed yet; -1 when the branch has no upstream.
function Ahead([string]$repo) {
    # Continue, not Stop: Windows PowerShell turns a native command's words on
    # stderr into a terminating error when they are redirected under Stop.
    $ErrorActionPreference = "Continue"
    $global:LASTEXITCODE = 0
    $count = & git -C $repo rev-list --count "@{u}..HEAD" 2>$null
    if ($LASTEXITCODE -ne 0) { return -1 }
    return [int]$count
}

function Ask([string]$question) {
    if ($Yes) { return $true }
    $answer = Read-Host "$question (y/n)"
    return $answer -match '^(y|yes)$'
}

$Repos = @(
    [pscustomobject]@{ Name = "api";  Title = "THE API";  Path = $ApiRepo },
    [pscustomobject]@{ Name = "pack"; Title = "THE ART PACK"; Path = (Join-Path $GameRepo "art\pack") },
    [pscustomobject]@{ Name = "game"; Title = "THE GAME"; Path = $GameRepo },
    [pscustomobject]@{ Name = "site"; Title = "THE SITE"; Path = $SiteRepo }
)

# A SUBMODULE IS OFTEN ON NO BRANCH AT ALL. `git submodule update` checks out
# the commit the game recorded, "detached", and a commit made there belongs to
# no branch and cannot be pushed. Before the pack is shipped it is put back on
# main - but only when that loses nothing: HEAD must already contain
# everything GitHub's main has. Anything else is said and left alone.
function Attach([string]$repo) {
    $branch = (RunGit $repo @("rev-parse", "--abbrev-ref", "HEAD")) | Select-Object -First 1
    if ($branch -ne "HEAD") { return $branch }
    $ErrorActionPreference = "Continue"
    $global:LASTEXITCODE = 0
    & git -C $repo fetch -q origin main 2>$null | Out-Null
    $global:LASTEXITCODE = 0
    & git -C $repo merge-base --is-ancestor origin/main HEAD 2>$null
    if ($LASTEXITCODE -ne 0) { return "HEAD" }
    RunGit $repo @("checkout", "-q", "-B", "main") | Out-Null
    $global:LASTEXITCODE = 0
    & git -C $repo branch -q --set-upstream-to=origin/main main 2>$null | Out-Null
    return "main"
}

# --- WHAT IS WAITING ---------------------------------------------------------
foreach ($tool in @("git", "ssh")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "$tool is not on this PC's PATH." }
}
Heading "What is waiting"
$plan = @()
foreach ($r in $Repos) {
    if (-not (Test-Path (Join-Path $r.Path ".git"))) { Say ("  {0,-5} not found at {1}" -f $r.Name, $r.Path) "Yellow"; continue }
    $branch = (RunGit $r.Path @("rev-parse", "--abbrev-ref", "HEAD")) | Select-Object -First 1
    if ($r.Name -eq "pack" -and $branch -eq "HEAD" -and -not $Status -and -not $DryRun) { $branch = Attach $r.Path }
    $paths = @(Waiting $r.Path)
    $ahead = Ahead $r.Path
    $message = Join-Path $MessageFolder ("SHIP_{0}.txt" -f $r.Name)
    $hasMessage = Test-Path $message -PathType Leaf
    $line = "  {0,-5} on {1}: {2} file(s) changed, {3} commit(s) not pushed" -f $r.Name, $branch, $paths.Count, $(if ($ahead -lt 0) { "?" } else { $ahead })
    Say $line $(if ($paths.Count -gt 0 -or $ahead -gt 0) { "Yellow" } else { "Green" })
    if ($paths.Count -gt 0) {
        Say ("        message: {0}" -f $(if ($hasMessage) { "SHIP_$($r.Name).txt is ready" } else { "NONE - SHIP_$($r.Name).txt is not in the commit folder" })) $(if ($hasMessage) { "Gray" } else { "Red" })
    }
    $plan += [pscustomobject]@{ Repo = $r; Branch = $branch; Paths = $paths; Ahead = $ahead; Message = $message; HasMessage = $hasMessage }
}
if ($Status) {
    Say ""
    Say "Nothing was changed. To ship it:  .\tools\ship.ps1" "DarkGray"
    Say "On their own: the server  $ServerUpdate" "DarkGray"
    Say "              the web     .\tools\deploy_web.ps1 -Export   (Godot closed)" "DarkGray"
    exit 0
}

# --- COMMIT AND PUSH, ONE REPOSITORY AT A TIME -------------------------------
function Ship($entry) {
    $r = $entry.Repo
    Heading ("{0}  ({1})" -f $r.Title, $r.Path)
    if ($entry.Branch -ne "main") { Say "  On branch '$($entry.Branch)', not main - left alone." "Red"; return $false }
    if ($entry.Paths.Count -eq 0 -and $entry.Ahead -le 0) { Say "  Nothing waiting." "Green"; return $false }
    if ($entry.Paths.Count -gt 0) {
        $refused = @(Refusals $r.Path $entry.Paths)
        if ($refused.Count -gt 0) {
            Say "  STOPPED - these must never be committed:" "Red"
            $refused | ForEach-Object { Say "    $_" "Red" }
            Say "  Add them to .gitignore (or move them out), then run this again." "Red"
            return $false
        }
        if (-not $entry.HasMessage) {
            Say "  Not committed: there is no SHIP_$($r.Name).txt in the commit folder." "Red"
            return $false
        }
        Say ("  {0} file(s):" -f $entry.Paths.Count)
        $entry.Paths | Select-Object -First 40 | ForEach-Object { Say ("    {0} {1}" -f $_.Code, $_.Path) "DarkGray" }
        if ($entry.Paths.Count -gt 40) { Say ("    ... and {0} more" -f ($entry.Paths.Count - 40)) "DarkGray" }
        Say ("  Message: " + ((Get-Content $entry.Message -TotalCount 1) -join "")) "Gray"
        if ($DryRun) { Say "  (dry run) would: git add -A, git commit -F SHIP_$($r.Name).txt, git push" "DarkGray"; return $true }
        if (-not (Ask "  Commit and push these?")) { Say "  Skipped." "Yellow"; return $false }
        RunGit $r.Path @("add", "-A") | Out-Null
        # THE SECOND LOOK: what is staged now, checked again - add -A sees more than status did if a file appeared since.
        $staged = @(RunGit $r.Path @("diff", "--cached", "--name-only")) | ForEach-Object { [pscustomobject]@{ Code = "A "; Path = $_ } }
        $late = @(Refusals $r.Path $staged)
        if ($late.Count -gt 0) {
            RunGit $r.Path @("reset", "-q") | Out-Null
            Say "  STOPPED after staging - unstaged again, nothing committed:" "Red"
            $late | ForEach-Object { Say "    $_" "Red" }
            return $false
        }
        RunGit $r.Path @("commit", "-q", "-F", $entry.Message) | Out-Null
        $stamp = Get-Date -Format "yyyyMMdd-HHmm"
        Rename-Item -Path $entry.Message -NewName ("SHIPPED_{0}_{1}.txt" -f $stamp, $r.Name)
        Say ("  Committed {0}." -f ((RunGit $r.Path @("rev-parse", "--short", "HEAD")) | Select-Object -First 1)) "Green"
    } elseif ($DryRun) {
        Say "  (dry run) would push $($entry.Ahead) commit(s) made earlier" "DarkGray"; return $true
    }
    $global:LASTEXITCODE = 0
    & git -C $r.Path push | Out-Host
    if ($LASTEXITCODE -ne 0) { Say "  The push failed - see git's words above. Nothing after this repository was run." "Red"; throw "push failed" }
    if ((Ahead $r.Path) -ne 0) { throw "  Pushed, but git still counts commits not on GitHub in $($r.Path)." }
    Say "  Pushed - GitHub has it." "Green"
    return $true
}

$apiShipped = $false
$gameShipped = $false
foreach ($entry in $plan) {
    $shipped = Ship $entry
    if ($entry.Repo.Name -eq "api") {
        $apiShipped = $shipped
        if ($shipped -and -not $SkipServer) {
            Heading "THE SERVER  (update_server.sh --restart)"
            if ($DryRun) { Say "  (dry run) would run the server update over ssh" "DarkGray" }
            elseif (Ask "  Update the server now? It pulls what was just pushed and restarts the API") {
                $global:LASTEXITCODE = 0
                Invoke-Expression $ServerUpdate
                if ($LASTEXITCODE -ne 0) { Say "  The server update failed (exit $LASTEXITCODE). The game and the web build were NOT shipped after it." "Red"; exit 1 }
                Say "  The server runs the new API." "Green"
            } else { Say "  Not updated. Later:  $ServerUpdate" "Yellow" }
        }
    }
    if ($entry.Repo.Name -eq "game") {
        $gameShipped = $shipped
        if ($shipped -and -not $SkipWeb) {
            Heading "THE WEB BUILD  (tools\deploy_web.ps1 -Export)"
            $godot = Get-Process | Where-Object { $_.ProcessName -like "Godot*" }
            if ($godot) {
                Say "  Godot is open. Close it (it writes export_presets.cfg back from memory), then:" "Yellow"
                Say "    .\tools\deploy_web.ps1 -Export" "Yellow"
            } elseif ($DryRun) {
                Say "  (dry run) would export and deploy the web build" "DarkGray"
            } elseif (Ask "  Export and deploy the web build now?") {
                $global:LASTEXITCODE = 0
                & (Join-Path $PSScriptRoot "deploy_web.ps1") -Export
                if ($LASTEXITCODE -ne 0) { Say "  The web deploy stopped (exit $LASTEXITCODE) - its own words are above." "Red"; exit 1 }
            } else { Say "  Not deployed. Later:  .\tools\deploy_web.ps1 -Export" "Yellow" }
        }
    }
}

Heading "Done"
Say "  Run  .\tools\ship.ps1 -Status  any time to see what is still waiting." "Gray"
if ($gameShipped -and -not $DryRun) { Say "  Players with the game open are told a new version is out within five minutes." "Gray" }
