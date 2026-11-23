class_name Mekh
extends RefCounted
## МЭХ - the real techniques of Mongolian wrestling (bökh).
##
## Real bökh has 45 base techniques and about 1000 variations. They come in
## 3 families: no-grip (барьцгүй), grip (барьцны) and locked-grip (лав барьцны).
## There are also combos (угсраа мэх) and counters (хариулт мэх).
##
## In the game the player never picks a technique from a menu. They press GRAB
## with a direction, and the game finds the REAL technique that fits:
##   - which way you pull or push (toward the rival, away, to the side, nothing)
##   - how the rival is standing (leaning back? leaning forward? stepping sideways?)
##   - your grip (no grip / grip / locked grip held a long time)
## So every throw has a real name, and players learn them by playing.
##
## To add a technique: add an entry to TABLE, add its clip in Blender
## (art/blender/build_wrestler.py), and add a rule in choose().

## Where the thrown wrestler lands, relative to the thrower (A) and the
## thrown one (D). "to" = direction from A to D, "side" = to the side.
##   land: where D lands   part: which body part lands first
##   spin: flips over the top (big throws)   height: how high D flies
const TABLE := {
	"achikh": {"mn": "АЧИХ", "en": "shoulder load throw", "clip": "achikh", "family": "grip",
		"chance": 0.45, "windup": 0.33, "air": 0.6, "height": 1.7, "land": "behind_thrower", "part": "back", "spin": true},
	"seeren_dungui": {"mn": "СЭЭРЭН ДУНГУЙ", "en": "hip roll", "clip": "seeren_dungui", "family": "grip",
		"chance": 0.55, "windup": 0.3, "air": 0.5, "height": 1.1, "land": "beside_thrower", "part": "back", "spin": false},
	"degeedekh": {"mn": "ДЭГЭЭДЭХ", "en": "inside leg hook", "clip": "degeedekh", "family": "grip",
		"chance": 0.6, "windup": 0.24, "air": 0.42, "height": 0.4, "land": "pushed_back", "part": "back", "spin": false},
	"takhimdakh": {"mn": "ТАХИМДАХ", "en": "knee-back pick", "clip": "takhimdakh", "family": "grip",
		"chance": 0.55, "windup": 0.26, "air": 0.45, "height": 0.5, "land": "pushed_back", "part": "back", "spin": false},
	"usgiidukh": {"mn": "ӨСГИЙДӨХ", "en": "heel sweep", "clip": "usgiidukh", "family": "grip",
		"chance": 0.55, "windup": 0.22, "air": 0.42, "height": 0.45, "land": "swept_side", "part": "elbow", "spin": false},
	"guyadakh": {"mn": "ГУЯДАХ", "en": "thigh lift", "clip": "guyadakh", "family": "grip",
		"chance": 0.5, "windup": 0.28, "air": 0.55, "height": 1.2, "land": "swept_side", "part": "elbow", "spin": false},
	"mushgikh": {"mn": "МУШГИХ", "en": "twist down", "clip": "mushgikh", "family": "grip",
		"chance": 0.6, "windup": 0.24, "air": 0.45, "height": 0.5, "land": "twisted_down", "part": "knee", "spin": false},
	"tongorokh": {"mn": "ТОНГОРОХ", "en": "lift and flip back", "clip": "tongorokh", "family": "locked",
		"chance": 0.3, "windup": 0.4, "air": 0.65, "height": 1.9, "land": "behind_thrower", "part": "back", "spin": true},
	"khul_avakh": {"mn": "ХӨЛ АВАХ", "en": "leg grab dive", "clip": "khul_avakh", "family": "no_grip",
		"chance": 0.5, "windup": 0.22, "air": 0.45, "height": 0.6, "land": "pushed_back", "part": "back", "spin": false},
	"khariult": {"mn": "ХАРИУЛТ", "en": "counter!", "clip": "khariult", "family": "counter",
		"chance": 0.8, "windup": 0.12, "air": 0.45, "height": 0.6, "land": "twisted_down", "part": "knee", "spin": false},
}

const LOCK_BONUS := 0.25          ## locked grip (лав барьц) makes every throw stronger
const OFF_BALANCE_BONUS := 0.35   ## rival already leaning the way you throw
const MOMENTUM_BONUS := 0.15      ## rival walking into the throw
const FULL_STOMACH_PENALTY := 0.15  ## Bayan Khodood is heavy!
const MUTUAL_GRIP_PENALTY := 0.1  ## rival holds you too: harder


## dir_kind: "toward", "away", "side", "none"
## lean_to: rival's lean along the line between you (+ = leaning back, away from you)
## vel_in: rival's speed toward you (+ = coming in)
## vel_side: rival's sideways speed
static func choose(dir_kind: String, locked: bool, lean_to: float, vel_in: float, vel_side: float) -> String:
	match dir_kind:
		"toward":
			return "takhimdakh" if lean_to > 0.12 else "degeedekh"
		"away":
			return "achikh" if (vel_in > 0.8 or lean_to < -0.12) else "seeren_dungui"
		"side":
			if absf(vel_side) > 1.0:
				return "usgiidukh"
			return "guyadakh" if locked else "mushgikh"
		_:
			return "tongorokh" if locked else "mushgikh"


## How likely the technique works (0..1). off_balance: 0..1 how much the
## rival already leans the way this technique throws him.
static func chance(id: String, locked: bool, off_balance: float, momentum: float,
		rival_full: bool, mutual: bool) -> float:
	var c: float = TABLE[id].chance
	if locked:
		c += LOCK_BONUS
	c += OFF_BALANCE_BONUS * clampf(off_balance, 0.0, 1.0)
	c += MOMENTUM_BONUS * clampf(momentum, 0.0, 1.0)
	if rival_full:
		c -= FULL_STOMACH_PENALTY
	if mutual:
		c -= MUTUAL_GRIP_PENALTY
	return clampf(c, 0.05, 0.95)


## "clean" = full throw, rival lands hard.  "partial" = rival lands tipping,
## a PALM SAVE can still rescue him.  "fail" = rival slips out (зайлах).
static func roll(c: float) -> String:
	var r := randf()
	if r < c - 0.15:
		return "clean"
	if r < c + 0.1:
		return "partial"
	return "fail"


static func label(id: String) -> String:
	return "%s!" % TABLE[id].mn


static func subtitle(id: String) -> String:
	return "%s · %s" % [id.capitalize().replace(" ", " "), TABLE[id].en]
