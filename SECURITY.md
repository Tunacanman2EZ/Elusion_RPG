# Security — Elusion RPG (game client)

**The security model lives with the server, because that is where the decisions
are made:** [`elusion-api` → SECURITY.md](https://github.com/Tunacanman2EZ/elusion-api/blob/main/SECURITY.md)
— the premise, who is trusted with what, the invariants and the honest limits,
each naming the test that holds it.

This repository is the Godot client. A few things are worth knowing about it
before reporting something here.

**The client is not a trust boundary, and it is not meant to be.** It runs on the
player's machine, so anything it computes the player can forge. `Api.role` and
`Api.is_owner` are set from a login response and held in memory; they decide which
buttons are drawn and they refuse nothing. `require_role()` and `require_owner()`
on the server are what actually say no. A patched build setting itself to `owner`
gains exactly nothing.

**A co-owner's buttons follow the owner's switch; the server does not wait for
them** (0.21.0). Since a co-owner exists, `Api.is_owner` means "has the owner's
powers" - the owner always, a co-owner while the owner's **Co-owners in** switch
is on - and `Api.own_rank()` says which. Who may be a co-owner is named only in
the server's environment, and only the owner can move the switch. The HUD takes
the owner's buttons away on the next heartbeat after the switch goes off, but
that is for an honest build: the server reads the switch on every request, so a
patched build that keeps drawing the buttons gets the same 404 as anyone else
from the moment it moved.

**There are no debug keys.** Until 0.7.1 keyboard shortcuts granted items, pets
and lusions in a debug build, and Ctrl+G switched god mode. They are gone: the
owner panel does that work, and the panel only asks. `POST /api/staff/grant`
refuses everyone but the owner (and a co-owner while the owner lets him in), so a
patched build that opens the panel gains nothing. An edited client cannot write
its own bag either - the backpack and the bank are the server's, every drag and
bin is a request it carries out, and a player's whole-bag write is ignored.

**Give item to a player, Set level and the Save history** (0.7.5 and 0.21.0,
for the owner and a co-owner, on the GM panel's Account tab and in the item
catalogue) are requests like everything else on it. The server decides which
character a gift or a level goes into - the one the player is playing, never a
slot the game names - and hands that player's game the new bag. A level change
and a rollback are carried out entirely on the server, after a snapshot that
can undo them, and the player is signed out so their game loads what the server
holds. Each is a line on the player's record, and every gift is a row in the
gifts ledger (0.20.0) with what it was worth and who gave it; the ledger is read
back from the server, never added up by the game. A patched build that draws
the buttons gets the same 404 as a route that does not exist, and a co-owner
cannot use any of them on the owner's own account.

**God mode** (a switch on the owner panel, for the owner and a co-owner) turns
damage off so the game can be tested without dying repeatedly. It grants nothing:
the guard returns before the hit is applied *and* before the defense XP that
`/api/skill/train` would otherwise bank, so an invincible character earns exactly
as much as a stationary one. `hp` is client-written in any case, so a modified
client could always refuse to die — the gate keeps an honest build honest.

**The always-roll switches** (0.18.1 and 0.18.2, the same two ranks) make every
mythic attack take its one-in-a-hundred or its one-in-ten roll, so the rare ones
can be seen on demand. The character asks for the flag *and* the rank on every
roll, so a flag left on does nothing for anyone else, and both are off after
every restart. They are client dice, like every roll an attack makes: a
modified client could always roll its own, and nothing the switches can do is
outside what the server's books already allow a throw.

**No secrets are in this repository**, and none should ever be. No keys, no
tokens, no database. The session token lives in `user://session.cfg` on the
player's own machine and is a bearer credential — anyone with that file can act as
that account until it expires, the same as a browser cookie. That is the accepted
trade for not retyping a password, and no password is ever written to disk.

**In a browser, a remembered login lives in the browser's storage for the
game's address.** Godot keeps `user://` in the browser's IndexedDB, so with
"Remember me" ticked the session token sits where any script running on that
address could read it. That is why the game is served from an address that serves
nothing but the export and `/api/` (the `play` site block in the API's
`DEPLOY.md`), over https. Nothing else, the website included, should ever be
hosted there. With "Remember me" off the token lives in memory and is not
stored. (A staff account's device file, `user://devices.cfg`, is kept either way;
it opens nothing without the password. So is `user://install.cfg`, a random id
for this copy of the game, sent with every login so that a ban follows the
computer and not only the connection. It is not a credential and opens nothing;
the server keeps only its hash.)

**A desktop build sends the password to whatever server it is pointed at.**
`--server=`, the `ELUSION_SERVER` variable and a one-line `user://server.cfg` all
override the address, which is how a build is moved to a new host without a
rebuild. It also means a build, a shortcut or a `server.cfg` from someone else can
point the game at their server and collect the password typed into it. Only run a
build you exported yourself. A public server must be `https://`: plain `http://`
is accepted, because the local development server is, and would carry the password
across the network unencrypted.

**An export can be read by anyone who has it.** The pack inside a Windows `.exe`
or a browser export holds the scripts compiled but not encrypted
(`encrypt_pck=false`). That changes nothing above: the client was never a secret
and never a trust boundary.

**Other players on your screen are pictures, and where they stand is what their
game said.** `Presence` draws everybody the presence server names in your area,
from its own messages only: their name, rank, colour, guild and the pets they may
show come from the server's rows, and the socket is opened with a two-minute
ticket rather than the login token. A modified game can stand anywhere on other
people's screens; it cannot be someone else, and nothing on that socket deals
damage or moves an item. A drawn player has no hitbox and is never "the player".

**Their attacks are pictures too** (0.19.0). A meteor, a thrown axe, a stick of
Dynamite, a slash wave or a healer's orb from another player is the class's own
scene with everything that hits switched off: no damage, no XP, no wound, no
pull, no camera shake. The server checks each one's shape before passing it on -
a kind it knows, and a start near where that player last said they stood - so a
modified game can draw an attack that never happened, and hurt nobody with it.
Only the attacker's own game lands hits, and those go where they always went.

**A lever pulled is pulled for the whole area** (0.19.0), and the server
remembers it for whoever walks in later. The game only ever matches the name it
is told to a real lever in its own copy of the scene - looked for among the
levers, never fetched by path - so a message cannot reach any other node. A
modified game can throw any lever in its area from anywhere in it, opening or
shutting that gate for everyone there: a gate is a door, not a lock, and moving
one changes nobody's health, bag or gold.

**The monsters you share an area with are run by one player's game** (0.7.0),
the area's leader, and every other game draws them from what it says. A
modified leader can move, heal or kill those monsters on everyone's screen. It
cannot reach anyone's health, bag, gold or kills: each game builds every attack
from its own copy of the monster and caps the few numbers the leader sends, and
the server keeps its own count of every fight (0.10.0). The server's page has
the detail under *Honest limits*.

**Most of what looks like a client-side vulnerability is a server question.** "I
can edit my save", "I can spawn items", "I can claim a kill" — all true, all
expected, and all bounded server-side. The interesting version of those reports is
always *what the server accepted*, so they belong in the API repo.

## Reporting

**Something exploitable — please do not open a public issue.** Use the **Security**
tab on this repository → *Report a vulnerability*. It reaches the maintainer
privately and stays invisible until it is fixed. If it concerns the server rather
than the client, the [API repository](https://github.com/Tunacanman2EZ/elusion-api)
has the same button and is the better home for it.

Ordinary bugs, crashes and questions: a normal issue is perfect.
