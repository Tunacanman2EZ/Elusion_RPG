# Elusion — TODO & backlog

Two lists: things to **do next** (to get it in front of the school), and
engineering worth doing **someday** if the project grows.

---

## ✅ To show the school — do these next

- [ ] **Commit & push your recent changes** so they're actually live on GitHub.
      The must-have is **`docs/boss.gif`** — both the game README *and* the profile
      README point at it, so it shows as a broken image in two places until it's
      pushed. Also in this batch: the `settings.gd` warning fix, the README art
      credit line, and this `TODO.md`. (A few prepared commit messages are still on
      your Desktop — `commit_game.txt`, `commitmsg4.txt`, `commitmsg5.txt` — if
      those describe work you haven't committed yet, do those too.)
- [ ] **Record a short gameplay video** (1–2 min: a fight, the boss, maybe fishing
      or trading) and add it to the game README and your submission. This is the
      thing that lets the school *see* it run without setting up the server.
- [ ] **Create your profile repo** — a new **public** repo named exactly
      `Tunacanman2EZ` — and add the profile README.
- [ ] **Pin** `Elusion_RPG` and `elusion-api` to your profile.
- [ ] **Send the school** the write-up + your three links (game, API, profile).

---

## Known open engineering — someday, named not hidden

These are already named in the README / `SECURITY_NOTES.md`. Listing them is a
strength, not a confession.

- [ ] **E-3 — server-side combat / kill verification.** The one deep open finding:
      the server rate-limits and caps kills but doesn't *watch the fight*. A real
      fix needs server-side encounter state. (This is also the trigger for the JWT
      note below.)
- [ ] **Server-side XP grants for the last 3 skills.** Fishing, cooking and attack
      grant XP server-side; the other three don't yet.
- [ ] **Audio.** Many sound effects still map to empty strings (including
      `"teleport"` — used by the new victory teleporter).
- [ ] **Endgame loop polish.**

---

## Auth: add short-lived JWTs — but only once there's a second service

**Today: do nothing.** I use server-side session tokens (random token stored in
the `sessions` table, looked up per request). They're revocable — banning/kicking
deletes the row and the token dies instantly. That's the right call for one server
+ one database, and it's what the whole moderation system depends on. Do **not**
switch to JWTs: a JWT can't be revoked before it expires, which would break
instant bans.

**The one future case where JWTs help me:** the day Elusion becomes *more than one
service*. The most likely trigger is **E-3** (server-side combat / kill
verification) moving into its own service. That service would need to trust "this
request really is player #42" without sharing access to the accounts database.
That's the textbook JWT use:

- The main server mints a **short-lived** JWT (~60s) carrying the player id + an
  expiry.
- The combat service verifies it **by signature** — no lookup into my `sessions`
  table.
- Sessions stay the revocable source of truth; the JWT is just a short-lived pass
  between my *own* services.

That's a legitimate hybrid — sessions **plus** short-lived JWTs — not a
replacement.

**Signal to start:** the first time there's a second server/service, a companion
app, or a third-party integration that needs to verify identity. Not before —
until then, one clean mechanism beats two.

**Note to self:** I'll have already built JWT auth in Recipe Box for the course,
so the mechanics (PyJWT, signing secret, encode identity + expiry, verify) will be
familiar when this day comes.
