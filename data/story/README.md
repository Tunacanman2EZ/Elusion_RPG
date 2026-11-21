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

## The scenes

| folder | when | who can speak |
|---|---|---|
| meet_shopkeeper | the first time this character walks up to the shopkeeper (part 1 only) | shopkeeper, hero |
| arrive_elusion | each time this character arrives in town: the next part | hero |
| arrive_bigfield | each time in the Big Field (after its story screen): the next part | hero |
| after_death | each time this character arrives after dying: the next part (else the arrival's own) | hero |

Parts are counted for each character, on this computer.

**Arriving anywhere else** is a new folder named `arrive_` and the area's
scene file name, no code: `arrive_field`, `arrive_descent`,
`arrive_endless`, `arrive_forge` (every area built on field.gd).
