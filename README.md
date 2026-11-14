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

**R** = restart. You lose a round if you **fall over** (like real bökh) or **leave the ring**. First to 3 wins is the *avarga*.

## Project structure
```
scenes/
  main.tscn        - wrestling arena (ground, ring, camera, UI)
  player.tscn      - one wobbly wrestler (RigidBody3D)
scripts/
  input_setup.gd   - keyboard controls for both players (change keys here)
  player.gd        - movement, wobble, push
  arena.gd         - round rules, score, win screen
assets/
  models/          - Blender models go here (export as .glb)
  sounds/          - sound effects and music
```

## Tuning the fun
Click `Player1` / `Player2` in `main.tscn` and change values in the **Inspector**:
`move_force`, `push_strength`, `upright_strength` (lower = more wobbly), etc.

## Adding Blender models
1. In Blender: **File → Export → glTF 2.0 (.glb)**.
2. Put the file in `assets/models/`.
3. In `player.tscn`, hide the `Body` and `Head` meshes and drag your `.glb` in as a child.
   Keep the `CollisionShape3D` capsule so physics still works.

## Roadmap
- [x] Bökh prototype (2 players, push, fall = lose)
- [ ] Make wrestling feel fun (playtest + tune!)
- [ ] Real character models (Blender)
- [ ] Main menu
- [ ] Sur kharvaa (archery) mini-game
- [ ] Morin uraldaan (horse racing) mini-game
- [ ] Bonus: shagai

## Team rules
- Pull before you start: `git pull`
- Don't edit the same `.tscn` scene at the same time as someone else (scene merges break easily).
- Finish one mini-game fully before starting the next.
