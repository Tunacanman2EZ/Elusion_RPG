# Asset License

**The MIT licence in `LICENSE` covers the source code in this repository and
nothing else.** It does not cover the artwork or the audio. This file does, and
if you are here to work out what you may do with the files under `art/` or
`assets/`, this file is the answer and `LICENSE` is not.

`LICENSE` is kept as the unmodified MIT text on purpose. Licence scanners —
GitHub's included — match it by comparing it word for word against the
canonical text, so a carve-out paragraph added to it drops the similarity below
the match threshold and the repository stops being reported as MIT-licensed at
all. Measured on this repository: the canonical text scores 100%, the same text
with a single extra sentence scores 93%, and the threshold is 98%. So the
carve-out lives here instead. Adding it back to `LICENSE` would make the code's
licence *less* clear, not more.

This repository contains art from three sources under three different licences.
They are not interchangeable, and the distinction matters if you are reading
this to work out what you may do with these files.

## Original art — © 2026 Elusion Studios

Everything under `/art` and `/assets` **except** the two sections below. This
includes characters, enemies, tilesets, buildings, interiors, doors, teleporters
and menu art.

Commissioned from Ahvassa (https://ahvassa.itch.io/) with rights assigned to
Elusion Studios, plus original work by Robert Ashley Clear.

Provided here for demonstration and development purposes as part of this game
project. It may **not** be used, copied, redistributed, or incorporated into
other projects — commercial or non-commercial — without express written
permission from Robert Ashley Clear.

After the official launch of the game, selected assets may be made available
for purchase or reuse under separate terms.

Asset licensing enquiries: elusionrpg@gmail.com

## Purchased pack art — © Clockwork Raven Studios

**`/art/pack/` is the authoritative location** for Clockwork Raven's art. It is a
private submodule and it is where any file of Caio's belongs. Its subfolders are
currently `amulets`, `armour`, `consumables`, `currency`, `fishing`, `icons`,
`tiles` and `weapons`.

**One known exception, in the other direction.**
`/art/pack/icons/behemothcrown.png` is **not** Caio's. It was cut and edited from
the behemoth boss art, which was commissioned from Ahvassa with rights assigned,
so the crown is Elusion Studios' under the section above. It is misfiled, not
reclassified.

**Which is the only boundary in this file that actually matters.** There are two
artists here and only one of them transferred rights. Ahvassa's work is Elusion
Studios' to edit, derive from, ship and relicense — crediting him is courtesy,
and gladly given. Caio's is not: the IP stays with Clockwork Raven Studios, and
crediting him is a condition, not a courtesy. So "Ahvassa's or Robert's own" is
not a distinction this file needs to police; the line between either of those and
Clockwork Raven's is the whole job.

**Fixed, and the file now lives at `art/enemy/behemothcrown.png`** — public,
beside the boss art it was cut from. The pack no longer carries it, and the three
constants that name it point at the new path: `player.gd`'s
`NAMEPLATE_CROWN_PATH`, `friendspanel.gd`'s `CROWN_PATH`, and `chatpanel.gd`'s
`CROWN_TAG`.

The cost while it was misfiled is worth recording, because it is the kind of
breakage that never announces itself. All three of those constants are in public
code, and the file they named was in the private submodule — so a clone of this
public repository, which by design cannot have the pack, rendered no crown on the
nameplate and no crown in chat. A missing `[img]` in a RichTextLabel fails
silently. Elusion Studios' own art was unreachable from Elusion Studios' own
public repository, and nothing said so.

`_test_staff_panel()` is why the move was safe to make: it asserts that all three
sites name the same path as `NAMEPLATE_CROWN_PATH`, that the art loads, and that
it is 26x15 — the size both the chat tag and the nameplate assume. Change the
path in two places out of three and the suite says so.

One thing this did **not** fix, and it is the larger version of the same problem:
the other 133 files the public code loads out of `art/pack/` are legitimately
Caio's and legitimately private, so a fresh public clone still cannot draw any
item, weapon or piece of armour. That is a correct boundary rather than a bug, but
the test suite currently reports it as failures rather than as skips, which reads
like a broken project to anybody who clones and runs it.

This used to be written as a rule about *categories* — "all item and icon
artwork", with the note that the category governs rather than the folder list.
That was too narrow, and the narrowness was not theoretical. The pack is a
general fantasy asset pack: it contains **environment and tileset art as well as
items and icons**. So a tile of Caio's sitting in `/art/tiles/` was covered by no
rule in this file at all — not by the item-and-icon category, and not by the
catch-all in the section above, which claimed it for Elusion Studios instead.

Two such files were found and removed. The rule is now about **location**, which
is checkable: anything of Caio's outside `/art/pack/` is a file the split
missed, not a file that has been reclassified. `split_art.ps1` is the tool that
did that split, and its job is to leave nothing of his behind.

Art by **Caio Carlos** of **Clockwork Raven Studios**.

- Website: https://www.clockworkravenstudios.com/
- Asset store: https://clockworkraven.itch.io/
- Patreon: https://www.patreon.com/clockworkravenstudios

### What the licence permits

These assets were purchased from Clockwork Raven Studios under their standard
asset licence. Under it, Elusion Studios **may**:

- use the art in this game, commercially and non-commercially
- modify it for use within this project

and **may not**:

- claim ownership of the artwork — the intellectual property remains with
  Clockwork Raven Studios, who created it. Elusion Studios did not.
- sell or distribute the assets as a separate product, asset pack, or
  standalone download
- use the assets to train any machine learning or AI system that produces
  derivative or visually similar work

Those terms apply to anyone reading this repository, not only to Elusion
Studios. This art is here because it is part of this game; it is not offered
for reuse, and a copy taken from this repository is not a licensed copy. If
you want these assets for your own project, buy them from the store link
above — that is what supports the artist who made them.

### Permission for this repository

This source repository is public with the artist's written consent. Asked
directly whether publishing it counted as redistribution, Caio Carlos replied
in September 2026:

> Hey Robert, congrats on the project and thanks for acquiring my assets. If
> you clearly state the license usage and my website, that is enough for me.

This section is that statement.

## Art of unconfirmed origin — none, and that took two passes

There is no third source in this repository any more. There was.

`/art/thirdparty/` existed to hold tilesets that arrived as "ready to use" files
whose origin was never established — `split_art.ps1` separated them out and its
own comment is the plainest statement of the problem: *tilesets of unconfirmed
origin*, with "their own licence terms". Most were removed months ago when the
Clockwork Raven pack was bought to replace them.

One survived: `houses read to use.png`. It looked live, because
`scene/walls/shop.tscn` drew a shop out of it — but that scene was the **old**
shop, and nothing referenced it, by path or by UID. The shop the game actually
builds is `scene/walls/shophouse.tscn`, on `art/shophouses/`. So the file was
reachable only from a scene that nothing could reach. Both are deleted.

The removal was therefore already done and had missed one thing, in the one place
that looks alive from a search and is dead from the root. That is the general
shape of it: art gets replaced by editing the scenes that use it, and a scene
that stopped being used stops being edited, so it keeps its old references
forever and keeps the files behind them alive with it.

If you are an artist and you recognise anything here as yours, please write to
elusionrpg@gmail.com.

## Source code — MIT

The source code in this repository is licensed separately under the MIT
License. See `LICENSE`.

## How this file goes stale, which is the actual failure mode

`LICENSE` used to carry a note of its own, claiming that *"all original artwork,
music, and paid/commissioned assets in this repository are the exclusive
property of Robert Ashley Clear."*

**That was true when it was written.** At the time there was one source of art in
this project: work commissioned from Ahvassa with rights assigned, plus original
work. Every word of it was accurate.

It stopped being accurate the day the Clockwork Raven pack arrived, and nothing
went back to look at it. That is the failure worth recording, because it is not
carelessness and it will happen again: a licence file is a claim about a *set of
files*, the set changes every time art arrives, and adding art does not feel like
touching licensing. By the time the pack was in and working, the sentence about
"paid/commissioned assets" had quietly grown to cover somebody else's copyright —
the precise thing the Clockwork Raven section says may not be claimed, and the
opposite of the one condition the artist set for this repository being public.

`/art/thirdparty/` above is the same failure caught a second time, in the middle
of writing this. The catch-all "everything under `/art` except the item art" was
silently claiming files the project's own tooling describes as unconfirmed.

So the rule this file now runs on: **every top-level folder under `/art` and
`/assets` must be classified by name, and adding one is a licensing decision.**
`_test_art_folders_are_licensed()` in `src/tools/testrunner.gd` enforces it. A new
folder fails the suite until somebody says whose it is, which means the next time
art arrives from a new source, the thing that notices is the test run and not a
stranger reading this file.
