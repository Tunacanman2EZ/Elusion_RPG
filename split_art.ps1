# split_art.ps1 - separate licensed pack art from your own work.
#
# RUN WITH GODOT CLOSED, from the Elusion_RPG folder.
#
#     .\split_art.ps1 -WhatIf     # print the plan, change nothing
#     .\split_art.ps1             # do it
#
# Result:
#     art/           your own work - characters, enemies, menus, doors, tiles
#     art/pack/      Caio Carlos / Raven Fantasy - every file verified
#                    pixel-identical to his spritesheets
#     art/thirdparty/  "ready to use" tilesets of unconfirmed origin
#
# NOTE, Sept 2026: art/thirdparty/ no longer exists in the project. Its files
# were replaced by the purchased Clockwork Raven pack, and the last one went
# with the orphaned old shop scene that was the only thing still drawing it.
# The $ThirdPartyFiles list below is kept as the record of what was separated
# out and why. Re-running this script would recreate the folder, so do not,
# unless a new batch of unverified art actually needs the same treatment.
#
# art/pack/ is the folder that becomes the private submodule. Keeping it INSIDE
# art/ rather than beside it means res://art/... still names everything, and a
# clone without submodule access is missing one subfolder rather than all art.
#
#
# WHY THE .import FILES MOVE TOO, AND WHY THAT MATTERS MOST
# --------------------------------------------------------
# A .png.import carries the texture's uid. Every .tres and .tscn refers to art
# by uid first and path second. Delete the .import and Godot regenerates it with
# a NEW uid - and every reference silently resolves to nothing.
#
# So each .import moves with its .png and has its source_file line rewritten.
# dest_files is left alone on purpose: it is a hash of the old path, so Godot
# notices it is stale and re-imports, which is correct. The uid survives, which
# is the part that cannot be allowed to change.
#
# ASCII ONLY. Windows PowerShell 5.1 reads a BOM-less .ps1 as CP1252, where the
# last byte of a UTF-8 em dash decodes to a right double quote and silently ends
# whatever string it is sitting in. See CLAUDE.md.

[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = "Stop"

if (-not (Test-Path ".\project.godot" -PathType Leaf)) {
    throw "Run this from the Elusion_RPG folder (no project.godot here)."
}
if (-not (Test-Path ".\.git" -PathType Container)) {
    throw "No .git here. This script uses git mv so the move stays reviewable."
}

$dirty = git status --porcelain
if ($dirty -and -not $WhatIfPreference) {
    Write-Host "Working tree is not clean:" -ForegroundColor Yellow
    Write-Host ($dirty | Out-String)
    throw "Commit or stash first. A move this wide must be its own revertable commit."
}

if ($WhatIfPreference) {
    Write-Host "`n-WhatIf: printing the plan. Nothing will be moved or rewritten.`n" -ForegroundColor Cyan
}


# =============================================================================
# 1. WHAT GOES WHERE
# =============================================================================
# Whole folders, because every file in each was verified pixel-identical to a
# cell in 16x16.png or 32x32.png of the Raven Fantasy pack. Adjust freely - the
# rest of the script derives everything from these two lists.

$PackFolders = @(
    "consumables",   # the a15xx/a16xx potion block, and the potions named from it
    "armour",        # every piece extracted today
    "weapons",       # swords, mauls, staves, scepters, and the original a5425
    "currency",      # a371, largeamountofgold, lusions
    "amulets",       # bushamulet - sheet row 501, col 0
    "icons",         # EVERY stat icon: attack, defence, agility, magic, hp,
                     # mana, stamina, fishing, cooking, inventorygold
    "lootbag"        # unused - lootbag.tscn uses your artist's floorwalls.png
)

# Individual files rather than whole folders.
$PackFiles = @(
    "tiles/lootbag2.png"   # sheet row 2 col 0; unused, same story as above
)

# NOT Caio's, but named like a purchased set rather than something you would
# name yourself. Parked here until you confirm the origin; they may carry their
# own licence terms. Move any of these back into the main list if they are
# actually yours.
$ThirdPartyFiles = @(
    "tiles/houses read to use.png",
    "tiles/trees read to use.png",
    "tiles/tile set perfect.png",
    "tiles/Tiles set ready to use.png",
    "tiles/furniture assests-Recovered.png",
    "tiles/flower bush grass stones rocks bloulder.png"
)


# =============================================================================
# 1b. RENAMES - your own art, named by whatever tool exported it
# =============================================================================
# Only files whose contents I actually looked at. Everything else keeps its
# name, however ugly, because renaming art you cannot identify is how a sheet
# ends up called the wrong thing forever.
#
# THE gate/spike NAMES ARE SWAPPED IN THE CURRENT PROJECT, which is the one
# worth fixing now rather than later: gate1/2/3 are the three frames of SPIKES
# retracting into the floor, and the two files Piskel named for you are the
# actual barred gate, open and closed.

$Renames = [ordered]@{
    # spikes: fully raised -> half -> just the tips. Used by spikedoor.tscn.
    "art/doors/gate1.png"                   = "art/doors/spikesup.png"
    "art/doors/gate2.png"                   = "art/doors/spikeshalf.png"
    "art/doors/gate3.png"                   = "art/doors/spikesdown.png"

    # the barred gate the spikes were misnamed after
    "art/doors/New Piskel-1 copy.png.png"   = "art/doors/gateclosed.png"
    "art/doors/New Piskel-2.png (1).png"    = "art/doors/gateopen.png"

    # ladder, chest, firepit, lever, then water and lava tiles. Yours, and the
    # sheet lever.tscn reads its three lever frames out of.
    "tiles/ladderchestlevertiles.png"       = "tiles/propsandterrain.png"

    # double extensions and an export timestamp
    "art/tiles/middle brick wall-1.png.png" = "art/tiles/brickwallmiddle.png"
    "art/tiles/flowers_tile-1.png.png"      = "art/tiles/flowerstile.png"
    "art/tiles/lava_tile_2-1.png (1).png"   = "art/tiles/lavatile.png"
    "art/tiles/animated cyclops wall.png 17-21-48-422.png" = "art/tiles/cyclopswallanimated.png"
}

# The two tiles/ entries above are written without the art/ prefix by mistake-
# proofing below, so normalise them here rather than relying on me typing 40
# paths correctly.
$normalised = [ordered]@{}
foreach ($k in $Renames.Keys) {
    $from = if ($k.StartsWith("art/")) { $k } else { "art/$k" }
    $to   = if ($Renames[$k].StartsWith("art/")) { $Renames[$k] } else { "art/$($Renames[$k])" }
    $normalised[$from] = $to
}
$Renames = $normalised


# =============================================================================
# 2. BUILD THE MOVE LIST
# =============================================================================

function Add-Move([string]$From, [string]$To, [System.Collections.ArrayList]$Into) {
    if (-not (Test-Path $From -PathType Leaf)) { return }
    [void]$Into.Add([pscustomobject]@{ From = $From; To = $To })
    # The .import travels with its source or the uid is lost. See the header.
    if (Test-Path "$From.import" -PathType Leaf) {
        [void]$Into.Add([pscustomobject]@{ From = "$From.import"; To = "$To.import" })
    }
}

$moves = New-Object System.Collections.ArrayList

foreach ($folder in $PackFolders) {
    $src = Join-Path "art" $folder
    if (-not (Test-Path $src -PathType Container)) {
        Write-Host "   . art/$folder (not present, skipping)" -ForegroundColor DarkGray
        continue
    }
    foreach ($file in Get-ChildItem $src -File | Where-Object { $_.Extension -ne ".import" }) {
        Add-Move "art/$folder/$($file.Name)" "art/pack/$folder/$($file.Name)" $moves
    }
}
foreach ($rel in $PackFiles)       { Add-Move "art/$rel" "art/pack/$rel" $moves }
foreach ($rel in $ThirdPartyFiles) { Add-Move "art/$rel" "art/thirdparty/$($rel -replace '^tiles/', '')" $moves }

# Renames ride the same machinery: same git mv, same .import handling, same
# reference rewrite. A rename IS a move that happens to stay in its folder.
foreach ($from in $Renames.Keys) {
    if (Test-Path $Renames[$from] -PathType Leaf) {
        throw "$($Renames[$from]) already exists. Refusing to overwrite it."
    }
    Add-Move $from $Renames[$from] $moves
}

Write-Host "1. Moving $($moves.Count) files ($([math]::Round($moves.Count / 2)) assets plus their .import)" -ForegroundColor Cyan

$pathFixes = [ordered]@{}
foreach ($mv in $moves) {
    if ($mv.From -like "*.import") { continue }
    $pathFixes["res://$($mv.From)"] = "res://$($mv.To)"
}

foreach ($mv in $moves) {
    $dir = Split-Path $mv.To -Parent
    if (-not (Test-Path $dir)) {
        if ($PSCmdlet.ShouldProcess($dir, "create folder")) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
    if ($PSCmdlet.ShouldProcess($mv.From, "git mv -> $($mv.To)")) {
        git mv -- $mv.From $mv.To
    }
}
Write-Host "   done" -ForegroundColor Green


# =============================================================================
# 3. REWRITE EVERY REFERENCE
# =============================================================================
# Generic on purpose. Art is referenced from .tres, .tscn, .gd preloads and
# project.godot - the whole point is not to depend on my having guessed where.

Write-Host "`n2. Rewriting references" -ForegroundColor Cyan

$textExt = @(".tscn", ".tres", ".gd", ".godot", ".cfg", ".json", ".md", ".import")
$files = Get-ChildItem -Recurse -File | Where-Object {
    $textExt -contains $_.Extension -and
    $_.FullName -notmatch '\\\.godot\\' -and
    $_.FullName -notmatch '\\\.git\\'   -and
    $_.FullName -notmatch '\\builds\\'
}

$rewritten = 0
foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText($file.FullName)
    $original = $text
    foreach ($old in $pathFixes.Keys) {
        if ($text.Contains($old)) { $text = $text.Replace($old, $pathFixes[$old]) }
    }
    if ($text -ne $original) {
        $relative = Resolve-Path -Relative $file.FullName
        if ($PSCmdlet.ShouldProcess($relative, "rewrite art paths")) {
            # UTF-8 WITHOUT A BOM. Set-Content adds one on Windows PowerShell,
            # and Godot will not load a .tscn or .tres that starts with it.
            [System.IO.File]::WriteAllText($file.FullName, $text, [System.Text.UTF8Encoding]::new($false))
        }
        Write-Host "   - $relative" -ForegroundColor Green
        $rewritten++
    }
}
Write-Host "   $rewritten file(s) touched" -ForegroundColor Green


# =============================================================================
# 4. VERIFY
# =============================================================================
# The check that matters: after the move, does every res://art/ path in the
# project still point at a file that exists?

Write-Host "`n3. Verifying every res://art/ path resolves" -ForegroundColor Cyan

if ($WhatIfPreference) {
    # Nothing moved, so this can only re-describe the state we started in.
    # Reporting it as a result would be worse than saying nothing.
    Write-Host "   skipped under -WhatIf (nothing was moved, so there is nothing to verify)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Re-run without -WhatIf to perform the move." -ForegroundColor Cyan
    exit 0
}

$broken = @()
foreach ($file in $files) {
    if (-not (Test-Path $file.FullName -PathType Leaf)) { continue }
    $text = [System.IO.File]::ReadAllText($file.FullName)
    # GREEDY, not lazy. Several of your filenames contain ".png" in the MIDDLE
    # - "New Piskel-1 copy.png.png", "lava_tile_2-1.png (1).png" - and a lazy
    # quantifier stops at the first one, truncating the path and then reporting
    # the truncation as a broken reference. Greedy backtracks to the last valid
    # extension instead. The [^"'] class keeps it inside one quoted string.
    foreach ($match in [regex]::Matches($text, 'res://art/[^"'']+\.(png|tres|ogg|wav)')) {
        $target = $match.Value.Substring("res://".Length)
        if (-not (Test-Path $target -PathType Leaf)) {
            $broken += [pscustomobject]@{
                File = (Resolve-Path -Relative $file.FullName)
                Path = $match.Value
            }
        }
    }
}

if ($broken.Count -gt 0) {
    Write-Host ""
    Write-Host "   BROKEN REFERENCES - do not commit this:" -ForegroundColor Red
    $broken | Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "   Undo with: git reset --hard" -ForegroundColor Yellow
    if (-not $WhatIfPreference) { exit 1 }
} else {
    Write-Host "   OK - every res://art/ path points at a file that exists." -ForegroundColor Green
}


# =============================================================================
# 5. INVALIDATE GODOT'S CACHES
# =============================================================================
# uid_cache.bin maps every uid to the path it was last seen at, and moving a
# file does not update it. Rebuilt by the EDITOR's filesystem scan, which is why
# step 1 below says to open the editor before anything headless.

Write-Host "`n4. Invalidating Godot's caches" -ForegroundColor Cyan
foreach ($cache in @(".godot/uid_cache.bin", ".godot/global_script_class_cache.cfg")) {
    if (Test-Path $cache -PathType Leaf) {
        if ($PSCmdlet.ShouldProcess($cache, "delete (Godot rebuilds it on next editor scan)")) {
            Remove-Item $cache -Force
        }
        Write-Host "   - $cache" -ForegroundColor DarkRed
    } else {
        Write-Host "   . $cache (not present)" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Next, in order:" -ForegroundColor Cyan
Write-Host "  1. Open the Godot EDITOR and let it finish scanning and re-importing."
Write-Host "     Read the Errors tab before anything else. DO NOT SAVE A SCENE"
Write-Host "     until the scan finishes - saving while the uid cache is rebuilding"
Write-Host "     is what corrupted loginmenu.tscn and characterhud.tscn before."
Write-Host "  2. Check the boot log: scanned N, loaded N, with N matching."
Write-Host "  3. git status, review, commit on its own."
Write-Host "  4. Only THEN split art/pack/ out into the private submodule."
Write-Host ""
Write-Host "Undo at any point before committing: git reset --hard" -ForegroundColor DarkGray
