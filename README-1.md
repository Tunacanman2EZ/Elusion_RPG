<!--
  This is your GitHub PROFILE README.
  It shows at the top of github.com/Tunacanman2EZ.

  To publish it:
  1. Create a new PUBLIC repo named EXACTLY  Tunacanman2EZ  (same as your username).
     GitHub will show a note: "You found a secret! ... this special repository."
  2. Add this file as README.md and commit.

  THE BOSS GIF is already in your Elusion_RPG repo at  docs/boss.gif  (placed there
  for you). It just needs to be committed + pushed, and Elusion_RPG must be PUBLIC
  for the image to show to visitors. Branch is confirmed  main , so the link below
  is correct exactly as written — no edit needed.
-->

### Solo game developer — I build the thing, then try to break it.

I'm building **Elusion**, a top-down action RPG in Godot with a Flask backend. I started with **zero coding experience** and set out to ship something *complete* and treat it like real software — which, for a game with a server, means assuming the player is hostile.

![Elusion — the final boss](https://raw.githubusercontent.com/Tunacanman2EZ/Elusion_RPG/main/docs/boss.gif)

*The final boss telegraphs in red, then erupts. Two attack tracks run on separate timers and never sync, so the pattern you're dodging is emergent, not scripted.*

---

🎮 **[Elusion — the game](https://github.com/Tunacanman2EZ/Elusion_RPG)**  ·  Godot 4 · GDScript
A complete run from town to a final boss and back. Four classes, six enemy families in 43 elemental variants, pets, fishing, cooking, and player-to-player trading over a taxed economy.

🔐 **[Elusion API](https://github.com/Tunacanman2EZ/elusion-api)**  ·  Python · Flask
The account & game server. Server-authoritative saves, a double-entry gold economy, and a security self-audit I ran against my own API — **14 findings, 12 closed** — backed by **~1,600 automated tests** and a red-team bot that attacks a live server and checks the money, items and stats can't be forged.

---

**How I work:** I made the architectural calls and used AI as an architect's assistant and reviewer — directed and verified, not handed the wheel. The proof is in the repo: a git history that explains its decisions, diffs I actually read, and tests that are mutation-checked so they can *actually fail*. A rule that shows up all over the codebase — when I reasoned about what a change would do and the running engine disagreed, the engine won, and I wrote down why.

<sub>Godot · GDScript · Python · Flask · SQLite · pytest</sub>
