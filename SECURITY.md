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

**The debug keys are a rule, not a defence.** `_staff_debug_allowed()` gates them
on `OS.is_debug_build()` **and** a rank of mod or above — which stops an honest
player holding a Debug-template export, and stops nobody else. That is all right
because the keys grant nothing by themselves: they ask `POST /api/staff/grant`,
which refuses anyone below mod. And an edited client cannot write its own bag
either - the backpack and the bank are the server's, every drag and bin is a
request it carries out, and a player's whole-bag write is ignored.

The same is true of **god mode** (`Ctrl+G`, or the owner panel's switch; dev and
owner), which turns damage off so the people who test the game can do it without
dying repeatedly. The key works in a release build, unlike the debug item keys
beside it, because testing means the real build against the real server — and
unlike those keys, this one hands out nothing. It grants nothing: the
guard returns before the hit is applied *and* before the defense XP that
`/api/skill/train` would otherwise bank, so an invincible character earns exactly
as much as a stationary one. `hp` is client-written in any case, so a modified
client could always refuse to die — the gate keeps an honest build honest.

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
