# orphancheck.ps1 - what a fresh clone would be missing.
#
# WHY THIS EXISTS. scene/ui/players/playerspanel.tscn was on the development
# machine and in no commit, ever. characterhud.gd - which WAS committed - held
#
#     const PLAYERS_PANEL_SCENE := preload("res://scene/ui/players/playerspanel.tscn")
#
# and preload() resolves at COMPILE TIME, so in a clone characterhud.gd did not
# parse. Not "the Players button is missing": no CharacterHud at all - no nav
# bar, no chat, no hotbar, no status strip. One uncommitted scene file took out
# the whole interface, silently, on every machine but one.
#
# THE TEST SUITE CANNOT CATCH THIS AND NEVER WILL. It runs inside Godot, Godot
# cannot see git, and every question it asks is "is this file present" - which
# on the machine that wrote the file is always yes. Same shape as the
# empty-directory trap in CLAUDE.md: a thing that exists for you and for nobody
# who clones. The suite goes green while the repository is broken.
#
# So this asks from the other side. Not "is it here" but "would anyone else get
# it". It reads and prints; it writes nothing.
#
#   .\orphancheck.ps1              full report
#   .\orphancheck.ps1 -Quiet       print only problems, for a hook or CI
#
# PURE ASCII ON PURPOSE. Windows PowerShell 5.1 reads a BOM-less .ps1 as CP1252,
# where a UTF-8 em-dash's third byte (0x94) decodes as a closing quotation mark
# and silently ends a string early. run_tests.ps1 and split_art.ps1 are held to
# this by the Godot suite; this is a third entry point and gets the same rule.
# Written for 5.1 - nothing here needs PowerShell 7.

[CmdletBinding()]
param(
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

function Read-GitPaths {
    # -z GIVES NUL-SEPARATED PATHS, AND THAT IS NOT A DETAIL. Splitting git's
    # output on whitespace shreds every path containing a space - "art/enemy/
    # perfect bushmage.png" becomes two entries matching nothing - and this
    # project has dozens. That exact mistake was made while investigating the
    # bug this script exists for and invented 66 missing files that were tracked
    # the whole time. A tool that cries wolf gets switched off. -z also means
    # core.quotePath cannot bite: git emits raw bytes, never quoted or escaped.
    param([string[]]$GitArgs)
    $raw = & git @GitArgs
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($p in ($raw -split "`0")) { if ($p) { [void]$set.Add($p) } }
    return $set
}

git rev-parse --is-inside-work-tree 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "orphancheck: not a git repository - run it from the project root." -ForegroundColor Red
    exit 2
}

$tracked = Read-GitPaths @("ls-files", "-z")
if ($tracked.Count -eq 0) {
    Write-Host "orphancheck: git lists no tracked files. Wrong folder?" -ForegroundColor Red
    exit 2
}

# THE CANDIDATE SET, IN ONE COMMAND. --others is untracked, --exclude-standard
# applies .gitignore - so everything deliberately excluded (.godot/, builds/,
# commit_*.txt, test_results.txt) is already gone and nothing here needs a
# second list of exceptions to drift out of date.
$untracked = Read-GitPaths @("ls-files", "--others", "--exclude-standard", "-z")

# -----------------------------------------------------------------------------
# WHAT TRACKED CODE REACHES FOR
# -----------------------------------------------------------------------------
# Only TRACKED sources are read. An untracked script naming an untracked scene
# is consistent - a clone gets neither - and reporting it would bury the pairs
# that actually break. The question is always: does something a clone HAS reach
# something a clone does NOT.
$sources = @()
foreach ($t in $tracked) { if ($t -match '\.(gd|tscn|tres|godot)$') { $sources += $t } }

$RES       = [regex]'"(res://[^"]+)"'
$PRELOAD   = [regex]'preload\(\s*"(res://[^"]+)"'
$CLASSNAME = [regex]'(?m)^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)'

$refPaths    = @{}   # relative path -> list of tracked files naming it
$preloaded   = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$trackedText = @{}

foreach ($src in $sources) {
    if (-not (Test-Path -LiteralPath $src)) { continue }
    $text = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $src))
    $trackedText[$src] = $text

    foreach ($m in $PRELOAD.Matches($text)) {
        [void]$preloaded.Add($m.Groups[1].Value.Substring("res://".Length))
    }
    foreach ($m in $RES.Matches($text)) {
        $rel = $m.Groups[1].Value.Substring("res://".Length)
        if (-not $refPaths.ContainsKey($rel)) { $refPaths[$rel] = @() }
        $refPaths[$rel] += $src
    }
}

# -----------------------------------------------------------------------------
# A class_name IS A REFERENCE WITH NO PATH IN IT
# -----------------------------------------------------------------------------
# src/shared/panelwindow.gd declares `class_name PanelWindow` and sixteen
# tracked panels call PanelWindow.attach(). Nothing anywhere writes
# "res://src/shared/panelwindow.gd", so a res:// scan sees no dependency at all
# - and a clone missing that file fails to compile sixteen scripts. Same for
# LocalTime and SafeSpot. So untracked scripts are asked what they declare, and
# the tracked sources are searched for the name.
$classRefs = @{}
foreach ($u in $untracked) {
    if ($u -notmatch '\.gd$') { continue }
    if (-not (Test-Path -LiteralPath $u)) { continue }
    $utext = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $u))
    $cm = $CLASSNAME.Match($utext)
    if (-not $cm.Success) { continue }
    $name = $cm.Groups[1].Value
    # WHOLE WORD. Without \b a class called Api matches ApiClient, Rapid and
    # every comment containing the letters - the same trap the Godot suite's
    # unused-parameter check was fixed for.
    $word = [regex]("\b" + [regex]::Escape($name) + "\b")
    $users = @()
    foreach ($src in $trackedText.Keys) {
        if ($word.IsMatch($trackedText[$src])) { $users += $src }
    }
    if ($users.Count -gt 0) { $classRefs[$u] = @{ Name = $name; By = $users } }
}

# -----------------------------------------------------------------------------
# THE VERDICT
# -----------------------------------------------------------------------------
$breaksClones  = @()   # untracked and something tracked reaches it
$absent        = @()   # preloaded by tracked code and not on disk at all
$importOrphans = @()   # tracked asset, untracked .import sibling
$uncommitted   = @()   # untracked, nothing tracked reaches it

foreach ($u in ($untracked | Sort-Object)) {
    $why = @()
    $fatal = $false

    if ($refPaths.ContainsKey($u)) {
        $why += ($refPaths[$u] | Sort-Object -Unique)
        if ($preloaded.Contains($u)) { $fatal = $true }
    }
    if ($classRefs.ContainsKey($u)) {
        # A class_name resolves at compile time exactly as preload does.
        $fatal = $true
        $why += ($classRefs[$u].By | Sort-Object -Unique)
    }

    # A .import is REQUIRED metadata Godot writes beside every asset. Commit the
    # .png without it and a clone reimports with a FRESH uid, which breaks every
    # uid reference to that texture - quietly, because the scene still loads.
    $parent = $u -replace '\.import$', ''
    $isImportOf = ($u -ne $parent) -and $tracked.Contains($parent)

    if ($why.Count -gt 0) {
        # ITS .import RIDES ALONG. Godot writes one beside every asset and it is
        # required metadata; reporting the .png as a problem and its .import as
        # "your call" invites somebody to add one and not the other, which gives
        # a clone a texture it must reimport under a fresh uid.
        $sidecar = ""
        if ($untracked.Contains("$u.import")) { $sidecar = "$u.import" }
        $breaksClones += [pscustomobject]@{
            Path = $u
            Sidecar = $sidecar
            By = ($why | Sort-Object -Unique)
            Fatal = $fatal
            Class = $(if ($classRefs.ContainsKey($u)) { $classRefs[$u].Name } else { "" })
        }
    } elseif ($isImportOf) {
        $importOrphans += $u
    } elseif ($u -match '\.import$' -and $untracked.Contains(($u -replace '\.import$', ''))) {
        # Reported on its parent's line above rather than twice.
    } else {
        $uncommitted += $u
    }
}

foreach ($rel in ($preloaded | Sort-Object)) {
    if ($rel -like 'art/pack/*') { continue }   # private submodule, absent by licence
    if (-not (Test-Path -LiteralPath $rel)) {
        $absent += [pscustomobject]@{ Path = $rel; By = ($refPaths[$rel] | Sort-Object -Unique) }
    }
}

# -----------------------------------------------------------------------------
# REPORT
# -----------------------------------------------------------------------------
if (-not $Quiet) {
    Write-Host ""
    Write-Host "orphancheck - what a fresh clone would be missing" -ForegroundColor Cyan
    Write-Host ("  {0} tracked, {1} untracked-and-not-ignored, {2} res:// references from {3} sources" -f `
        $tracked.Count, $untracked.Count, $refPaths.Count, $sources.Count) -ForegroundColor DarkGray
}

if ($absent.Count -gt 0) {
    Write-Host ""
    Write-Host "PRELOADED AND NOT ON DISK" -ForegroundColor Red
    Write-Host "  Broken for you too - Godot should already be refusing to compile these." -ForegroundColor DarkGray
    foreach ($a in $absent) {
        Write-Host ("  {0}" -f $a.Path) -ForegroundColor Red
        foreach ($f in $a.By) { Write-Host ("      preloaded by {0}" -f $f) -ForegroundColor DarkGray }
    }
}

if ($breaksClones.Count -gt 0) {
    Write-Host ""
    Write-Host "ON YOUR DISK AND IN NO COMMIT" -ForegroundColor Red
    Write-Host "  Works here, missing in every clone. Nothing else catches this." -ForegroundColor DarkGray
    foreach ($b in $breaksClones) {
        $tag = ""
        if ($b.Class) { $tag = "   [class_name {0} - COMPILE ERROR in a clone]" -f $b.Class }
        elseif ($b.Fatal) { $tag = "   [preload - COMPILE ERROR, not a missing picture]" }
        Write-Host ("  {0}{1}" -f $b.Path, $tag) -ForegroundColor Red
        if ($b.Sidecar) {
            Write-Host ("  {0}   [add this too - required metadata]" -f $b.Sidecar) -ForegroundColor Red
        }
        $shown = 0
        foreach ($f in $b.By) {
            if ($shown -ge 4) { Write-Host ("      ... and {0} more" -f ($b.By.Count - 4)) -ForegroundColor DarkGray; break }
            Write-Host ("      needed by {0}" -f $f) -ForegroundColor DarkGray
            $shown++
        }
    }
}

if ($importOrphans.Count -gt 0) {
    Write-Host ""
    Write-Host "TRACKED ASSET, UNTRACKED .import" -ForegroundColor Yellow
    Write-Host "  Required metadata. Without it a clone reimports and the uid changes." -ForegroundColor DarkGray
    foreach ($i in ($importOrphans | Sort-Object)) { Write-Host ("  {0}" -f $i) -ForegroundColor Yellow }
}

if ($uncommitted.Count -gt 0 -and -not $Quiet) {
    Write-Host ""
    Write-Host "UNTRACKED, AND NOTHING TRACKED REACHES THEM" -ForegroundColor DarkGray
    Write-Host "  New work not committed yet, or scratch. Your call - listed, not judged." -ForegroundColor DarkGray
    foreach ($u in ($uncommitted | Sort-Object)) { Write-Host ("  {0}" -f $u) -ForegroundColor DarkGray }
}

$problems = $breaksClones.Count + $absent.Count
$warnings = $importOrphans.Count

if (-not $Quiet -or $problems -gt 0 -or $warnings -gt 0) {
    Write-Host ""
    if ($problems -eq 0 -and $warnings -eq 0) {
        Write-Host "  nothing missing - a clone gets everything tracked code asks for" -ForegroundColor Green
    } else {
        Write-Host ("  {0} problem(s), {1} warning(s)" -f $problems, $warnings) -ForegroundColor Yellow
        if ($breaksClones.Count -gt 0) {
            Write-Host "  git add the paths above, then re-run." -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

# WARNINGS DO NOT FAIL THE RUN, PROBLEMS DO. A missing .import is real and is
# not a reason to block a commit; a file tracked code needs and nobody else gets
# is. Two severities, two exit codes, so a hook can gate on the one that matters.
if ($problems -gt 0) { exit 1 }
exit 0
