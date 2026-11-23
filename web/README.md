# Naadam Chaos — web version

A 2D browser version of Naadam Chaos for quick playtests. One file, no install, no build step.
Open `index.html` in any browser (laptop or phone).

## Events

| Event | Status | The real rule we turned into a game |
|---|---|---|
| **Bökh** (wrestling) | playable | Knee, elbow or back on the grass = you lose. Palms are allowed → **Palm Save**. |
| **Sur kharvaa** (archery) | playable | The judge (surchid) stands next to the targets and sings **"uukhai!"** for a hit → second player is the judge. |
| Horse race | not yet | The last horse is honored as **Bayan Khodood**. |

## Controls

| | Move | Button |
|---|---|---|
| Red | `A` `D` | `W` (push / palm save · draw bow / judge signal) |
| Blue | `←` `→` | `↑` |

`Esc` = menu, `M` = mute. On phones, touch buttons appear.

## Archery: "The Uukhai Judge"

- One player shoots 4 arrows, the other is the judge. Then swap.
- **Archer:** aim with move keys, hold the button to draw, let go to shoot. Watch the wind. Hit = +10.
- **Judge:** walk with move keys. Standing close to the targets = bravery points (up to +5 per arrow).
  Getting hit = BONK (archer −10, judge −5). Pinned hat = archer −5.
- After each arrow the judge signals: **hold** = "UUKHAI!" (hit), **tap** = "this close" (miss).
  Fast and right = up to +5. Wrong = −3.
- Loser = Bayan Khodood → 5th arrow in the rematch.
- Tuning values are in the `AT` object at the top of the archery section.

## Hall of Titles

Every win (wrestling or archery) adds words to your title. Saved in the browser (localStorage) for now.
Next step: move it to Express + MongoDB so titles are shared across devices.

## Testing

Open the browser console:

- `__sim(200)` — 200 CPU vs CPU wrestling rounds (fall types, round length, palm saves)
- `__simA(200)` — 200 CPU vs CPU archery matches (hit rate, judge bonks, signal accuracy)
