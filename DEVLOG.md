# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
- Porting the multiplayer spike into Elusion, in this order:
  1. connect to the game server at `characterselect.gd:149`
  2. spawn the player server-side
  3. rewrite `SceneTransition.change_scene()` for areas
  4. give `baseenemy.gd` server authority
- Poison slime: `small_attack*` and large `hitflash*` animations still unwired (art exists), `acidpuddle.tscn` not built, `poisonslime.gd` not written

## [2026-09-08]

### Decision: persistent online world, served by headless Godot
- The target is a persistent online world, not a lobby game — one world
  that keeps running whether or not any particular player is connected.
- The server is **Godot running headless**, not Python. The alternative was
  rewriting movement, collision, and enemy AI in Python so the backend could
  own them. That means maintaining the same game twice and keeping the two
  copies agreeing about physics forever. Running the real game code headless
  means there is exactly one implementation of the rules.
- Flask stays, but only for what it is good at: accounts, tokens, and
  persistence. It never simulates the world.
- Cost target for a rented VPS: ~$10/mo.

### Backend (Flask) — done
- `register` / `login` / `session` / `logout`, SQLite, salted password
  hashing via `werkzeug.security`, 30-day bearer tokens.
- Login and "no such user" return an **identical 401** on purpose, so the
  endpoint can't be used to discover which usernames exist. The client
  can't tell them apart either, which is why `loginmenu.gd` tries login
  first and falls back to register on a 401.
- `is_admin` is a database column now, not a hardcoded username compare
  running on the player's own machine. `make_admin.py` is the only way to
  set it.
- No `/health` endpoint and no user profile fields — this backend exists
  for the game, nothing else.

### Client
- `api.gd` (autoload `Api`) — every call is awaitable and returns
  `{ok, status, data, error}`. A **fresh HTTPRequest per call**, freed
  after: one shared node breaks the moment two systems call at once.
- `loginmenu.gd` rewritten as a coroutine. Local `users.cfg` accounts are
  gone and do not migrate.
- Auto-resume from a cached token. **Gotcha:** this made the login form
  unreachable until `_on_logout_pressed` also called `await Api.logout()` —
  clearing the local session is not enough if the token is still valid.

### Fixed: save thrashing
- `characterdata.gd` was writing the whole save file on every change —
  roughly 20 disk writes a second in normal play.
- Now debounced (`SAVE_DEBOUNCE_SECONDS := 2.0`): `save_data()` queues,
  `_process` counts down, `flush_save()` forces a write. Flushed on
  `NOTIFICATION_WM_CLOSE_REQUEST` / `NOTIFICATION_EXIT_TREE` and before
  `clear_current_user()`, so nothing is lost on quit or logout.

### Multiplayer spike (separate project) — proved out
Two clients, a Flask-authenticated game server, and a server-authoritative
enemy. Three things worth remembering:

- **`spawn = true` does not deliver spawn state.** Client copies arrived
  with `position = (0,0)` and an empty name, then replicated that (0,0)
  back at the server. Use `spawner.spawn_function` and build the node from
  a data dictionary instead.
- **Replicated positions are teleports.** `MultiplayerSynchronizer`
  *assigns* `position`; assignment does not sweep, so collision shapes
  cannot block it. This is why the enemy sat on top of the player and why
  collision layers were a red herring. Separation has to be
  **behavioural** — a flee band in the AI. `baseenemy.gd` already had
  exactly that as `flee_range = 40`.
- **Peer IDs are random in Godot 4.** Only the server is guaranteed to be
  `1`. Never assume the first client is `2`.
- Token handshake: client RPCs its Flask token to the server, the server
  validates it against Flask, then accepts. Capture
  `multiplayer.get_remote_sender_id()` **before** the `await` — it is not
  the same value after.

### Established: `SceneTransition.change_scene()` is the single seam
Area transitions in the whole game go through exactly two call sites:

- `src/world/ladder.gd:59`
- `src/world/leavetown.gd:51`

Both call `SceneTransition.change_scene(destination_scene)`. Everything
else (`characterselect.gd:149`, `characterhud.gd:326/351`,
`loginmenu.gd:145`, `player.gd:676`) is a menu transition, not a world
transition.

That is the whole reason areas are **step 3** and not step 1. In a
persistent world an area change is not "load a new scene locally" — it is
"tell the server I'm moving, and let it decide where I end up." Rewriting
that now would mean rewriting working single-player code against a server
that does not exist yet, with nothing to test it against. Connection first,
so there is something real to talk to; then server-side spawn, so a player
exists on it; then this seam, which is a small, contained change precisely
because there are only two call sites.

## [2026-04-27]
- Initial project setup
- Added MIT LICENSE
- Created ASSET_LICENSE.md
- Organized folders: assets, docs, src, builds, scenes
- Added project vision statement
