# Naadam Chaos – Creative Direction

The goal: someone who has played 100 party games plays ours and says "I've never seen *that* before."

---

## 1. The big discovery

**The real Naadam rules are already jokes. We don't need to invent random chaos. We need to make the real traditions playable.**

Look at what actually happens at Naadam:

| Real tradition | Why it's already a game mechanic |
|---|---|
| In bökh you lose if your **knee, elbow or back** touches the ground, but **palms are allowed**. | A wrestler crawling on hands and feet is still alive. That's a desperate, funny "save" move no other party game has. |
| The **last horse** in the two-year-old race is called **Bayan Khodood** ("full stomach"). It gets a song, is told it will win next year, and stands next to the winner **acting arrogant**. | A built-in reason to laugh at the loser *with* them, plus a comeback mechanic. |
| Archery **judges stand right next to the targets** and sing **"uukhai"** with arm signals when an arrow hits. For a miss, they show the gap with their arms. | A second player can be the judge. Arrows fly at the judge's feet. Every hit gets a song. |
| People rush to touch the **winning horse's sweat** and dust for luck. | A post-race stampede is a free chaos moment. |
| Each wrestler has a **zasuul** (herald/coach) who slaps his back and sings his praise. Champions collect **very long titles**. | A role for a 3rd/4th player, and an announcer that makes every win feel huge. |
| The **eagle dance** before and after each match. | Victory celebration that players will copy in real life. |

Most "cultural" games put culture in the background (costumes, music). Ours puts it **in the rules**. That is our identity.

---

## 2. What the research says makes party games work

| Principle | Example | What it means for us |
|---|---|---|
| **Clumsy controls + physics = comedy.** Unpredictability is funny. | Human: Fall Flat, Gang Beasts, QWOP | Keep the wobble. Never make movement "clean". |
| **Falling down is funny when it doesn't hurt.** | Gang Beasts, Fall Guys | Big fall = big effects, never punishment-feeling. |
| **The group laughing matters more than winning.** | Jackbox | Celebrate losers (Bayan Khodood!). |
| **Few buttons.** Overcooked has move + 2 buttons. | Overcooked | Max 2 buttons per player. One button can change meaning by situation (push vs palm save). |
| **Different roles create stories.** | Overcooked, It Takes Two, Among Us | Wrestler + zasuul, archer + judge, jockey + horse. |
| **Clutch moments get shared.** | Rocket League saves | Palm Save is our "clutch save" button. |

---

## 3. The ideas, ranked

Each idea was checked against: Is it fun? Funny? Replayable? Only-in-our-game? Cheap enough?

### ✅ A. Real bökh rule + PALM SAVE — **BUILT**
- Knee, elbow or back on the grass = lose. The game shouts which one: "KNEE!", "ELBOW!", "BACK!"
- Tipping over? Press push = palms slam down. If you recover, **"PALM SAVE!"** pops up.
- Same button as push, so no new controls. Cooldown 2.2 s, so it needs timing.
- **Why it's special:** players learn the real bökh rule without reading anything.
- **Test result:** a falling wrestler who braced survived the fall and lasted almost **2x longer** in the round.

### ✅ B. BAYAN KHODOOD — **BUILT (wrestling + archery)**, extend to every event
- Match loser stands up next to the champion and does an **arrogant strut** while the winner does the eagle dance.
- Wrestling rematch: the Bayan Khodood gets a **FULL STOMACH**: rounder belly, 35% heavier, harder to push.
- Archery rematch: the Bayan Khodood gets a **5th arrow**.
- **Later:** in horse racing it's the real tradition.

### ✅ C. ZASUUL TITLES — **BUILT (basic)** → + MongoDB "Hall of Titles"
- After each round the zasuul announces a title built from *how* you won:
  "ARSLAN (LION), THE GER-TOPPLER, BELOVED BY MARMOTS!"
- Uses the real ranks: Nachin (Falcon) → Khartsaga (Hawk) → Zaan (Elephant) → Arslan (Lion) → Avarga (Titan).
- Archery wins add archery words: "MERGEN (MARKSMAN) …, WHOSE ARROWS ALWAYS FIND THE SUR".
- **This is where your teacher's MongoDB + Express requirement fits perfectly:**
  save every player's titles on the server, so titles grow longer **forever**, across sessions.
  Show a "Hall of Titles" wall. That's a backend that actually adds fun, not a boring leaderboard.

### ✅ D. ARCHERY: "THE UUKHAI JUDGE" — **BUILT (web version)**
- Player 1 = archer. Player 2 = the **surchid judge**, standing next to the sur targets.
- Judge earns points for: **standing close** to the targets (bravery), and doing the **right signal fast** after each shot
  (hold the button = "uukhaaai" with arms up; tap = arms spread to show "this close" for a miss).
- Archer earns points for hits, **loses points for hitting the judge**.
- Funny moments: arrow pins the judge's hat; judge sings uukhai for a miss and the crowd boos; judge dives away mid-song.
- Swap roles each round.

### 🔜 E. HORSE RACE: "THE HORSE HAS OPINIONS"
- Real Naadam races test the **horse**, not the jockey. So our horse has a mood.
- Jockey steers and holds the **"giingoo" sing button** in rhythm to keep the horse happy.
  Stop singing → horse slows down, stops to eat grass, or chases a marmot.
- After the finish: **lucky sweat stampede.** Everyone rushes to touch the winning horse.
  Whoever touches it gets "luck" for the next event (e.g. one free palm save).
- Last place = Bayan Khodood ceremony (the real one).
- **Keep jockeys cartoony and not tiny kids.** Child jockey safety is a real debate in Mongolia; don't make it the joke.

### ⭐ F. NORTH STAR: "ONE FIELD NAADAM" (build ONLY if A–E are fun)
- At real Naadam, many bouts happen at the same time on the same field.
- Big idea: all three events happen **at once** on one steppe. The horse race track goes **through** the wrestling field.
  Archers shoot across it. Every 60 s, players rotate roles.
- A horse stampede through your wrestling match = the story players will tell.
- **Warning:** this is big. It only works if each event is already fun alone.

---

## 4. Ideas I threw away (and why)

| Idea | Why not |
|---|---|
| Random power-ups (speed boots, bombs) | Every party game has them. Says nothing about Naadam. |
| Fall Guys-style obstacle course | We'd be a worse copy of Fall Guys. |
| Random weather events | Generic. The real traditions are funnier. |
| XP, levels, achievements, skins | Not gameplay. Titles (idea C) give progression *with* culture. |
| Online multiplayer | Huge work, kills the deadline. Couch play is enough for a hackathon demo. |
| More than 2 buttons | Party guests won't learn it. |

---

## 5. Playtest findings (from automated tests)

1. **Ring-outs ate the game.** With the old push (strength 7, tip 3), *every* round ended by ring-out.
   Players slid like ice cubes and never fell. The bökh rule never happened.
   New defaults: `push_strength 4`, `push_tip 8`, `upright_strength 20`. Now falls (elbow) happen.
2. Bots always attack from the side, so tests only show "ELBOW". Real people will make knee and back falls too.
3. **A bot can't tell you if it's fun.** Play 10 rounds with real friends before changing anything else.
   Watch their faces. Write down every moment someone laughs or yells.

---

## 6. Build order

1. **Playtest wrestling with real people** and tune (this week). Does PALM SAVE feel good? Is the strut funny?
2. Replace placeholder with the Blender model + `palm_brace` and `bayan_khodood_strut` clips. ✅ (Godot)
3. Archery: The Uukhai Judge (D). ✅ (web version) → playtest, then port to Godot.
4. Horse race (E).
5. Express + MongoDB: Hall of Titles (C).
6. Only then: One Field Naadam (F).

Finish one thing fully before starting the next. Three half-finished games lose to one fun finished game.

---

## 7. Web prototype (2026-11-19) — playable link for playtests

A 2D browser version, so friends can playtest from any phone or laptop with no install:
https://claude.ai/artifact/Ss3dEwUsSUYCyyryeBeGgQ (private until shared). The same file is in the repo at `web/index.html`.

- Has: bökh fall rule (KNEE/ELBOW/BACK), Palm Save, eagle dance intro, zasuul round titles, Bayan Khodood strut + Full Stomach rematch, Hall of Titles (saved in the browser for now), 1P vs CPU and 2P on one keyboard, touch buttons.
- **New mechanic: DODGE.** Step back just as the rival pushes → they stumble forward (KNEE/ELBOW falls). Same controls, gives forward falls a cause.
- **New rule of thumb:** a velocity kick (from a push) must not also create a "feet moved under you" tilt torque, or it cancels the push. Fix: change velocity and previous velocity together.
- Bot vs bot tuning result: rounds ≈13 s, ~0.3 palm saves per round, falls mostly BACK (pushes), ~10% KNEE/ELBOW. Real players should dodge more → more forward falls. Check this in human playtests.
- Tuning values (`TUNE`): push tip 1.4 rad/s, upright 20, gravity 9, miss lunge 2.0, dodge 3.8, palm cooldown 2.2 s.

---

## 8. Archery in the web version (2026-11-23)

The menu now has two events: **Bökh** and **Sur kharvaa**.

- **Archer:** move keys aim, hold the button to draw (power goes up and down, so release timing matters), let go to shoot. Wind changes every arrow.
- **Judge:** walks freely. Bravery = closeness to the sur wall at the moment the arrow lands (up to +5).
  Standing **in front** of the wall is braver but arrows aimed at the wall fly through you. Standing **behind** is safer, but long misses land there.
- **Signal:** the game does **not** say "hit" until the judge signals. The judge must read the field (a sur flying off = hit).
  Hold 0.6 s = UUKHAI (hit). Tap under 0.35 s = "this close" (miss). Points drop the slower you are. No signal in 2.4 s = "SLEEPY JUDGE".
- Points: hit +10 · bravery up to +5 · right signal up to +5 · wrong signal −3 · bonk: archer −10, judge −5 · pinned hat: archer −5.
- CPU vs CPU (300 matches): CPU archer hits ~70%, judge gets bonked on ~10% of arrows, hat pinned ~5%, CPU judge signals right ~88%, a match takes ~46 s.
- **Check in human playtests:** Is the CPU archer too good? (`AT.botAim`, bigger = worse aim.) Is −10 for a bonk too harsh? Do judges actually stand close, or hide far away? If they hide, raise `AT.brave`.

---

## 9. Wrestling upgrade (2026-11-23): grips, real techniques, new wrestler, Naadam field

**Research:** bökh has **45 base techniques (мэх)** and about **1000 variations** (some sources say 666).
They come in 3 families: **no-grip** (барьцгүй), **grip** (барьцны), **locked grip** (лав барьцны).
There are also combo (угсраа) and counter (хариулт) techniques. Before a bout wrestlers slap their thighs.

**Design decision:** not 200 buttons. 2 buttons + direction, and the game picks the REAL technique
from the situation (direction, rival's lean, rival's movement, grip strength). This keeps the
"max 2 buttons" rule from section 2, and players still learn real technique names.

- New button **GRAB**: take a grip → hold 1.2 s = locked grip → GRAB + direction = technique.
- **10 techniques**: Ачих, Сээрэн дунгуй, Дэгээдэх, Тахимдах, Өсгийдөх, Гуядах, Мушгих, Тонгорох, Хөл авах, Хариулт (counter).
- **Off-balance matters:** the grip spring pulls at chest height, so pushing/pulling makes the rival lean.
  Throwing the way he already leans adds up to +35% chance. Real wrestling idea, works in the game.
- **Counter window:** each technique has a 0.2–0.4 s wind-up with a "!" over the target. GRAB in time = Хариулт.
- **3 results:** clean (hard fall), partial (tipping: PALM SAVE can still save you → clutch moments), fail (зайллаа).
- **CPU wrestler** (press C) for solo testing.
- **New wrestler (Blender v2):** chunky stylized human, real face, open-chest zodog with cord, shuudag, gutal. 23 clips.
- **Naadam field:** trampled grass circle, Nine White Banners (Есөн хөлт цагаан туг), gers, grandstand + crowd that
  jumps on big moments, two zasuul heralds holding the wrestlers' hats, Mongolian flags (no Soyombo yet), mountains, clouds.
  Follow camera that zooms with the distance between wrestlers.

**CPU vs CPU test (170 s, 26 rounds):** 19 of 26 rounds were won by a named technique (7 different ones).
Falls: back 11, knee 6, elbow 4, ring-out 5. Before this update almost every fall was BACK from pushes.

**Check with real people:**
- Is the leg dive (Хөл авах) too strong? CPU tests use it most.
- Do players understand the "!" counter window? 0.2 s might be too short for beginners.
- Anar: check the technique animations against real bökh, fix any that look wrong (see ANIMATIONS.md).
