# Naadam Chaos 🏹🐎🤼

A goofy party game about Mongolian **Naadam**, made with **Godot 4.7** (GDScript).

## How to run
1. Install **Godot 4.7.2** (standard version, not .NET) from https://godotengine.org/download
   - Everyone on the team must use the **same version**.
2. Open Godot → **Import** → choose the `project.godot` file in this folder.
3. Press **F5** (or the ▶ button) to play.

## Controls (Bökh / wrestling)
| | Move | Push | Grab |
|---|---|---|---|
| Player 1 (red) | W A S D | Space | Left Shift |
| Player 2 (blue) | Arrow keys | Enter | Right Shift |
| Gamepad 1 / 2 | Left stick | A | X |

**C** = Player 2 human / computer. **R** = restart.

**Real bökh rule:** you lose if your **knee, elbow or back** touches the grass, or if you leave the ring.
Your **palms are allowed** on the grass: when you are tipping over, press PUSH to
throw your palms down = **PALM SAVE**. It has a cooldown, so time it well.

### Grips and techniques (мэх)
1. **GRAB** when close = take a grip (барьц). Hold it **1.2 s** = **locked grip** (лав барьц), every technique gets stronger.
2. With a grip, **GRAB + a direction** = a real technique. The game picks the one that fits:

| Direction | Rival is... | Technique |
|---|---|---|
| toward him | leaning back | **Тахимдах** – knee-back pick |
| toward him | standing | **Дэгээдэх** – inside leg hook |
| away (pull) | coming in / leaning forward | **Ачих** – shoulder load throw |
| away (pull) | standing | **Сээрэн дунгуй** – hip roll |
| sideways | stepping sideways | **Өсгийдөх** – heel sweep |
| sideways | – (locked grip) | **Гуядах** – thigh lift |
| sideways / none | – | **Мушгих** – twist down |
| none | – (locked grip) | **Тонгорох** – lift and flip back |
| run at him + GRAB (no grip) | – | **Хөл авах** – leg grab dive |

3. When the rival starts a technique, a **!** appears over your head. Press **GRAB** fast = **Хариулт (counter)**: you throw *him*.
4. Tip: push and pull with the grip to make him lean, **then** throw the way he leans. Off-balance rivals fall much easier.
5. **PUSH** while he holds you = break his grip.

Each technique can land **clean** (hard fall), **partial** (you're tipping: PALM SAVE can still rescue you!) or **fail** (he dodges, зайллаа).

First to 3 wins becomes **Arslan (Lion)**. The loser becomes **Bayan Khodood** ("full stomach"),
like the last horse at Naadam: celebrated, arrogant, and starts the rematch heavier.

## Project structure
```
scenes/
  main.tscn        - wrestling arena (field, camera, UI)
  player.tscn      - one wobbly wrestler (RigidBody3D)
scripts/
  input_setup.gd   - keyboard controls for both players (change keys here)
  player.gd        - movement, wobble, push, grip, techniques, being thrown, CPU wrestler
  mekh.gd          - the techniques (мэх) table: names, chances, how each one throws
  field_builder.gd - the Naadam field: places terrain, grass, banners, gers, crowd, flags, trees, eagles
  camera_rig.gd    - camera that follows the wrestlers and zooms
  arena.gd         - round rules (knee/elbow/back), score, Bayan Khodood ending
  title_forge.gd   - zasuul announcer: builds grand champion titles
  character_animator.gd - picks animations (placeholder or Blender model)
  juice.gd         - effects: camera shake, hit-stop, squash, dust, confetti
shaders/           - terrain, grass, sky, crowd, flag, horsehair, foliage, eagle (+ common.gdshaderinc)
tests/
  sim_cpu.gd       - CPU vs CPU balance test (headless)
assets/
  env/             - terrain.glb, naadam_props.glb, scatter.json, textures/ (made by the Blender scripts)
  models/          - Blender models go here (export as .glb)
  sounds/          - sound effects and music
```

## Tuning the fun
Click `Player1` / `Player2` in `main.tscn` and change values in the **Inspector**:
`move_force`, `push_strength`, `push_tip`, `upright_strength` (lower = more wobbly), etc.

**Important:** `push_strength` makes the rival SLIDE (ring-outs). `push_tip` makes the rival
TIP OVER (knee/elbow/back falls). With the old value (push 7, tip 3) every test round ended
by ring-out, so the bökh rule never happened. New defaults: push 4, tip 8, upright 20.

Techniques: chances and throw shapes are in `scripts/mekh.gd` (`TABLE`). Grip feel is in the
**Grip and techniques** group on the player (`grip_spring`, `lock_time`, `grab_range`...).
Balance test: `godot --headless --fixed-fps 60 -s res://tests/sim_cpu.gd`.

## The Naadam field (environment)
Everything around the wrestlers is made in Blender by scripts, then brought to life by shaders:

| File | What it makes |
|---|---|
| `art/blender/make_textures.py` | felt, ger door ornaments (өлзий, үүлэн хээ), horsehair, Mongolian flag with Soyombo, grass, dirt, rock |
| `art/blender/build_environment.py` | `assets/env/terrain.glb` (steppe, hills, mountains), `assets/env/naadam_props.glb` (ger, banner, flag, grandstand, 8 crowd people, larch, rocks, eagle), `assets/env/scatter.json` |
| `scripts/field_builder.gd` | places it all when the game starts |
| `shaders/` | wind on grass, trees and horsehair; waving flags; moving clouds + cloud shadows; cheering crowd; eagles |

Rebuild after changing a script: `python3 art/blender/make_textures.py`, then
`blender -b -P art/blender/build_environment.py` (or run it from Blender's Scripting tab).

**Slow computer?** Click `Field` in `main.tscn` and lower `grass_density` / `crowd_density`.

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
- [x] Grips + 10 real techniques (мэх) + counters, CPU opponent
- [x] Naadam field v2: Blender terrain + mountains, 95k wind-blown grass blades, detailed gers, horsehair banners, cloth flags, 600+ animated crowd, larch forests, sky with clouds, eagles, smoke
- [x] Animation system (placeholder animations, eagle dance, effects)
- [x] Real character model v2 (chunky human, detailed costume) + 23 clips – see ANIMATIONS.md
- [ ] Main menu
- [x] Sur kharvaa (archery) – web version (`web/`), Godot port still to do
- [ ] Morin uraldaan (horse racing) mini-game
- [ ] Bonus: shagai

## Team rules
- Pull before you start: `git pull`
- Don't edit the same `.tscn` scene at the same time as someone else (scene merges break easily).
- Finish one mini-game fully before starting the next.
