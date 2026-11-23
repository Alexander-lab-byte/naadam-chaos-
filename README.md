# Naadam Chaos 🏹🐎🤼

A goofy party game about Mongolian **Naadam**, made with **Godot 4.7** (GDScript).

## How to run
1. Install **Godot 4.7.2** (standard version, not .NET) from https://godotengine.org/download
   - Everyone on the team must use the **same version**.
2. Open Godot → **Import** → choose the `project.godot` file in this folder.
3. Press **F5** (or the ▶ button) to play.

## Controls (Bökh / wrestling prototype)
| | Move | Push |
|---|---|---|
| Player 1 (red) | W A S D | Space |
| Player 2 (blue) | Arrow keys | Enter |

**R** = restart.

**Real bökh rule:** you lose if your **knee, elbow or back** touches the grass, or if you leave the ring.
Your **palms are allowed** on the grass: when you are tipping over, press your push button to
throw your palms down = **PALM SAVE**. It has a cooldown, so time it well.

First to 3 wins becomes **Arslan (Lion)**. The loser becomes **Bayan Khodood** ("full stomach"),
like the last horse at Naadam: celebrated, arrogant, and starts the rematch heavier.

## Project structure
```
scenes/
  main.tscn        - wrestling arena (ground, ring, camera, UI)
  player.tscn      - one wobbly wrestler (RigidBody3D)
scripts/
  input_setup.gd   - keyboard controls for both players (change keys here)
  player.gd        - movement, wobble, push
  arena.gd         - round rules (knee/elbow/back), score, Bayan Khodood ending
  title_forge.gd   - zasuul announcer: builds grand champion titles
  character_animator.gd - picks animations (placeholder or Blender model)
  juice.gd         - effects: camera shake, hit-stop, squash, dust, confetti
assets/
  models/          - Blender models go here (export as .glb)
  sounds/          - sound effects and music
```

## Tuning the fun
Click `Player1` / `Player2` in `main.tscn` and change values in the **Inspector**:
`move_force`, `push_strength`, `push_tip`, `upright_strength` (lower = more wobbly), etc.

**Important:** `push_strength` makes the rival SLIDE (ring-outs). `push_tip` makes the rival
TIP OVER (knee/elbow/back falls). With the old value (push 7, tip 3) every test round ended
by ring-out, so the bökh rule never happened. New defaults: push 4, tip 8, upright 20.

## Adding Blender models + animations
See **[ANIMATIONS.md](ANIMATIONS.md)** – clip names, export steps, and how the
`Model` node replaces the placeholder shapes automatically.

## Web version (playtest build)
Open `web/index.html` in any browser (laptop or phone). It has **Bökh** and **Sur kharvaa (archery)**,
1P vs CPU or 2P on one keyboard. See `web/README.md`.

## Creative direction
See **[CREATIVE_DIRECTION.md](CREATIVE_DIRECTION.md)** for the research, the big ideas, and the build order.

## Roadmap
- [x] Bökh prototype (2 players, push, fall = lose)
- [x] Real bökh rule (knee/elbow/back) + palm save
- [x] Bayan Khodood ending + zasuul titles
- [ ] Make wrestling feel fun (playtest with REAL people + tune!)
- [x] Animation system (placeholder animations, eagle dance, effects)
- [ ] Real character models + clips (Blender) – see ANIMATIONS.md
- [ ] Main menu
- [x] Sur kharvaa (archery) – web version (`web/`), Godot port still to do
- [ ] Morin uraldaan (horse racing) mini-game
- [ ] Bonus: shagai

## Team rules
- Pull before you start: `git pull`
- Don't edit the same `.tscn` scene at the same time as someone else (scene merges break easily).
- Finish one mini-game fully before starting the next.
