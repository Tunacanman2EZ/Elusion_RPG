# Story scenes

Characters talk in speech bubbles, from the scripts in these folders
(src/shared/talk.gd). One folder a scene, one file a hero:

    data/story/<scene>/warrior.txt
    data/story/<scene>/mage.txt
    data/story/<scene>/tank.txt
    data/story/<scene>/healer.txt
    data/story/<scene>/all.txt     <- any hero without a file of its own

A hero with no file (and no all.txt) says nothing in that scene.

## Writing a script

Each line is a speaker, a colon, and what they say. Each line is one
bubble; the next comes when it is gone. Interact or Enter hurries a line.

    shopkeeper: Are you lost?
    hero: I was dead. I know I was.

`hero` is whoever is playing. Lines starting with # are notes, never said.
Blank lines are skipped.

## Many lines: parts

A script can be in parts, with a line of just `---` between them. The first
time the scene happens the hero says part 1, the next time part 2, and so on.
After the last part it says nothing, until you write more.

    hero: This is not the crypt...
    ---
    hero: Back again. Did I die... again?
    ---
    hero: Every time I wake up here, I remember a little more.

## Choices: the player picks what to say

    shopkeeper: Are you lost?
    ? Lost? I was dead. = dead
    ? Trade = @shop

    [dead]
    hero: Lost? I was dead.
    shopkeeper: Another one through the portal...

- `? words = branch` is an answer the player can pick (a click, a tap, or
  its number key). Answers in a row are offered together, under the hero.
- `[branch]` starts what an answer leads to. A branch ends where the next
  `[branch]` begins.
- `> branch` goes on in another branch.
- `= @shop` opens the shop instead of leading to a branch; `= @end` just
  ends the conversation.
- The game keeps each character's pick, for scenes to come.
- Walking away ends the conversation.

The suite reads every script here and fails, naming the line, on anything it
cannot play (a line with no `speaker:`, an answer leading to a branch that is
not there, an `@` it does not know).

**Replay story**, on the GM panel's Testing tab, makes your character forget
every scene and pick, so you can hear them all again.

## The scenes

| folder | when | who can speak |
|---|---|---|
| meet_shopkeeper | the first time this character walks up to the shopkeeper (part 1 only) | shopkeeper, hero |
| visit_shopkeeper | EVERY later visit, after his greeting: the menu (a file each hero) - the next part each visit, round again | shopkeeper, hero |
| arrive_elusion | part 1 the first time this character is in town; each later part the next time they come into town by a portal, ladder or minigame (signing in never says a later part) | hero |
| arrive_bigfield | each time in the Big Field (after its story screen): the next part | hero |
| after_death | each time this character arrives after dying: the next part (else the arrival's own) | hero |

Parts are counted for each character, on this computer.

**Arriving anywhere else** is a new folder named `arrive_` and the area's
scene file name, no code: `arrive_field`, `arrive_descent`,
`arrive_endless`, `arrive_forge` (every area built on field.gd).
