# Security — Elusion RPG (game client)

**The security model lives with the server, because that is where the decisions
are made:** [`elusion-api` → SECURITY.md](https://github.com/Tunacanman2EZ/elusion-api/blob/main/SECURITY.md)
— the premise, who is trusted with what, the invariants and the honest limits,
each naming the test that holds it.

This repository is the Godot client. Four things are worth knowing about it
before reporting something here.

**The client is not a trust boundary, and it is not meant to be.** It runs on the
player's machine, so anything it computes the player can forge. `Api.role` and
`Api.is_owner` are set from a login response and held in memory; they decide which
buttons are drawn and they refuse nothing. `require_role()` and `require_owner()`
on the server are what actually say no. A patched build setting itself to `owner`
gains exactly nothing.

**The debug keys are a rule, not a defence.** `_staff_debug_allowed()` gates them
on `OS.is_debug_build()` **and** a rank of mod or above — which stops an honest
player holding a Debug-template export, and stops nobody else. Anyone able to edit
the client can grant themselves items with or without that gate; the backpack
ledger is still client-declared, and that is named as an open limit on the
server's page rather than pretended away.

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
