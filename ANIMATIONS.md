# Naadam Chaos – Animation Plan

How animation works in this project, and the list of clips to make in Blender.

## 4 kinds of animation

| Kind | Where it lives | Used for |
|---|---|---|
| **Skeletal clips** (Blender) | `.glb` file → `AnimationPlayer` | Body moves: walk, push, eagle dance |
| **Physics** | `player.gd` (RigidBody3D) | Wobbling, tipping over, flying out of the ring. **Already done.** |
| **Code / Tween** | `juice.gd`, `character_animator.gd` | Squash & stretch, camera shake, hit-stop, UI pop. **Already done.** |
| **Particles** | `juice.gd` (`Juice.dust()`, `Juice.confetti()`) | Dust, confetti. **Already done.** |

No real ragdoll is needed: the whole wrestler is already one wobbly physics body.

## How a character is built

```
Player (RigidBody3D, player.gd)       <- physics: moving, wobbling, falling
├── CollisionShape3D (capsule)
└── Visual (character_animator.gd)    <- picks which animation to play
    ├── Body, Head, ArmL, ArmR        <- placeholder shapes (animated by code)
    └── Model                         <- ADD YOUR .glb HERE (name it exactly "Model")
```

When a `Model` with an `AnimationPlayer` is found, the placeholders hide and
the Blender clips play instead. Nothing else needs to change.

## Clip list (names must match exactly, lowercase)

### Shared – one skeleton for ALL human characters
Make these once. Every wrestler, jockey and archer reuses them.

| Clip | Loop? | Notes |
|---|---|---|
| `idle` | yes | wrestler stance, knees bent, arms a bit out |
| `walk` | yes | waddly, goofy. Speed is changed by code |
| `push` | no | ~0.3 s, both arms shoot forward |
| `hit` | no | ~0.4 s, arms flail, lean back |
| `eagle_dance` | yes | **devekh**: slow eagle wing flaps, small hops. Most important cultural clip! |
| `lose` | yes | sad slump, head down |
| `palm_brace` | no | ~0.8 s, palms slam down to the grass to stop a fall, panicked face |
| `bayan_khodood_strut` | yes | the loser's ARROGANT swagger: chest out, hands on hips, nose up. Funnier = better |
| `stumble` | no | ~0.8 s, trip + windmill arms. Plays instead of `hit` when you get hit while running fast |
| `thigh_slap` | no | ~1 s, slap the thighs before the bout: "ready!" (real bökh custom) |
| `grab` | no | ~0.27 s, lunge in and take the grip (барьц) |
| `grip_idle` | yes | bent forward, holding the rival's zodog, pulling and leaning |
| `thrown` | yes | flailing in the air after a throw. The physics body does the flying |

### Techniques (мэх) – one clip per technique, played by the thrower
The thrown wrestler is moved by code (`player.gd → begin_thrown()`), then physics takes over for the landing.

| Clip | Technique | What the thrower does |
|---|---|---|
| `achikh` | Ачих | turns his back in, loads the rival on his back, throws him over the shoulder |
| `seeren_dungui` | Сээрэн дунгуй | turns side-on and rolls the rival over his hip |
| `degeedekh` | Дэгээдэх | hooks the rival's leg from the inside and drives forward |
| `takhimdakh` | Тахимдах | drops low, catches behind the knee, pushes the rival over backwards |
| `usgiidukh` | Өсгийдөх | sweeps the rival's heel from behind |
| `guyadakh` | Гуядах | steps in and lifts the rival with his thigh, twisting |
| `mushgikh` | Мушгих | twists the rival's upper body down to the side |
| `tongorokh` | Тонгорох | lifts the rival off the grass and arches back |
| `khul_avakh` | Хөл авах | dives for the leg (no grip needed) and lifts it |
| `khariult` | Хариулт | counter: slips to the side and pulls the attacker past |

**Anar, please check these against real bökh.** The names come from the list of 45 base
techniques, but the moves were animated from the meaning of each word. Fix any that look wrong.

Looping is set by code (`looping_clips` on the `Visual` node), so you don't need to tick Loop in the import dialog.

Other names? Change `clip_names` on the `Visual` node in the Inspector.

### Horse racing (later)
| Clip | Notes |
|---|---|
| horse `gallop` | loop. Cartoony horse. Or fake it with a Tween bob, no rig |
| jockey `ride` | loop, bouncing on the saddle |
| jockey `urge` | one-shot, "chuu!" arm wave |
| jockey `fall_off` | switch to physics instead of animating it |

### Archery (later)
| Clip | Notes |
|---|---|
| `bow_draw` | one-shot, ends holding the pose |
| `bow_release` | one-shot |
| judge `uukhai` | loop, arms up and swaying while singing "uukhai" |

Arrows are physics objects (`RigidBody3D`), **not** animations.

## The wrestler (already in the game)

| File | What it is |
|---|---|
| `assets/models/bokh_wrestler.glb` | what Godot uses. Already placed as `Model` in `scenes/player.tscn` |
| `art/blender/bokh_wrestler.blend` | the Blender file. **Edit this one** |
| `art/blender/build_wrestler.py` | script that builds the whole character from zero (Blender 4.2+) |

`art/blender` has a `.gdignore` file, so Godot ignores the .blend.

**v2 (Nov 2026): chunky stylized human** (was a bean). ~46k triangles.
- **Body**: big round belly, broad shoulders, thick neck, short strong legs. Made from simple
  shapes, merged into one smooth skin (voxel remesh + smooth).
- **Face**: eyes, thick brows, round nose, thick wrestler's ears, red wind-burned cheeks, buzz cut.
- **Zodog**: short sleeves, OPEN chest and belly (like the real one), gold trim, cord tied around the belly.
- **Shuudag**: tight briefs with gold trim. **Gutal**: curled-up toes, red appliqué stripes, sole.
- **Rig**: same 14 bones as v1: `root`, `hips`, `chest`, `head`, `upper_arm/forearm/hand.L/R`, `thigh/shin.L/R`
- **Material `Team`** = zodog + shuudag. Godot paints it with `body_color` (red P1, blue P2)
- **Shape key `full_stomach`**: the Bayan Khodood rematch belly. Set by `arena.gd`

Change the look: edit the numbers in `build_wrestler.py` (sizes at the top, `build_body()`,
`build_face()`, costume regions `zodog_region()` / `shuudag_region()`) and run it again.

### Change an animation
1. Open `art/blender/bokh_wrestler.blend`. Click the **Rig**, switch to **Pose Mode** (Ctrl+Tab).
2. Bottom panel: **Dope Sheet → Action Editor**. Pick a clip in the action menu (e.g. `eagle_dance`).
3. Move to a frame, rotate a bone (R), press **I** to insert a key. Space = play.
4. Save the .blend, then export (below). Godot reloads it by itself.

### Export to Godot
**File → Export → glTF 2.0** →
- Format: **glTF Binary (.glb)**
- Include: tick **Limit to → Selected Objects** and select **Rig + Wrestler** first
- Animation: **Mode = Actions**, Shape Keys ON
- Save over `assets/models/bokh_wrestler.glb`

New clip? Make a new Action, give it a name, and add it to `clip_names` in `character_animator.gd`.

## Blender → Godot steps (for NEW characters)
1. Model the character normally, facing Blender's Front view (-Y).
2. Rig it. Fastest: auto-rig + base moves (idle, walk) from a free animation library like Mixamo.
   Hand-make only the Naadam moves: `eagle_dance`, `uukhai`, `bow_draw`.
3. Name each Action exactly like the table. Tick **"Cyclic"** / loop for looping clips.
4. **File → Export → glTF 2.0 (.glb)**, with Animations ticked. Save to `assets/models/`.
5. In Godot: double-click the `.glb` → for looping clips set **Loop Mode = Linear** → Reimport.
6. Open `scenes/player.tscn`, drag the `.glb` under `Visual`, rename it to **`Model`**.
7. Scale/move `Model` so the feet are at the bottom of the capsule (y ≈ -0.8).
   Rotate it **180° on Y** so it faces the same way as the placeholder's nose (-Z). Press F5.

## Juice functions (use them in every mini-game)
```gdscript
Juice.shake(0.2)                 # camera shake
Juice.hit_stop(0.05)             # tiny freeze on big hits
Juice.squash($Visual, 0.3)       # cartoon boing
Juice.pop($UI/Message)           # UI text pops in
Juice.dust(position)             # dust cloud
Juice.confetti(position)         # winner confetti
```
