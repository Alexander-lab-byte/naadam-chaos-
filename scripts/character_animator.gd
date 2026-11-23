extends Node3D
## Animates one character. Put this script on the "Visual" node of a player.
##
## Two modes (chosen automatically):
##  1. PLACEHOLDER mode - no Blender model yet. Moves the capsule body,
##     head and arms with code, so we can playtest the feel right now.
##  2. MODEL mode - a child node named "Model" (your .glb from Blender) with an
##     AnimationPlayer inside. Then it plays the clips listed in `clip_names`
##     and hides the placeholder meshes.
##
## Other scripts only call these functions:
##   play_push()  play_hit()  play_win()  play_lose()  play_brace()
##   play_strut()  play_stumble()  reset()
##   set_team_color(color)  set_full_stomach(0..1)   (MODEL mode only)
## Walk / idle is chosen automatically from the body's speed.

enum State { LOCOMOTION, PUSH, HIT, WIN, LOSE, BRACE, STRUT, STUMBLE }

## Animation names inside the Blender file. Change the right side if the
## artist used other names. See ANIMATIONS.md for the full list.
@export var clip_names := {
	"idle": "idle",
	"walk": "walk",
	"push": "push",
	"hit": "hit",
	"win": "eagle_dance",
	"lose": "lose",
	"brace": "palm_brace",
	"strut": "bayan_khodood_strut",
	"stumble": "stumble",
}
## Clips that repeat forever. Set here so you don't have to tick
## "Loop" in the import dialog every time you re-export from Blender.
@export var looping_clips := ["idle", "walk", "eagle_dance", "lose", "bayan_khodood_strut"]
## When hit while running at least this fast (0..1), play the big stumble instead of hit.
@export var stumble_speed := 0.45
@export var blend_time := 0.15           ## crossfade between clips (seconds)
@export var walk_bob := 0.08             ## placeholder: how much the body bounces
@export var arm_swing := 0.7             ## placeholder: walking arm swing (radians)

var state := State.LOCOMOTION
var _state_time := 0.0                   ## seconds since the state started
var _cycle := 0.0                        ## walk / dance cycle phase
var _hit_dir := 1.0

var _body: RigidBody3D
var _anim: AnimationPlayer               ## only in MODEL mode
var _current_clip := ""
var _mesh: MeshInstance3D                ## the model's mesh (MODEL mode)

@onready var _head: Node3D = get_node_or_null("Head")
@onready var _arm_l: Node3D = get_node_or_null("ArmL")
@onready var _arm_r: Node3D = get_node_or_null("ArmR")


func _ready() -> void:
	_body = get_parent() as RigidBody3D
	var model := get_node_or_null("Model")
	if model:
		_anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for clip in looping_clips:
			if _anim.has_animation(clip):
				_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		var meshes := model.find_children("*", "MeshInstance3D", true, false)
		if meshes.size() > 0:
			_mesh = meshes[0] as MeshInstance3D
		for n in ["Body", "Head", "ArmL", "ArmR"]:
			var placeholder := get_node_or_null(n) as Node3D
			if placeholder:
				placeholder.visible = false


# ---------------------------------------------------------------- public API

func play_push() -> void:
	if state in [State.WIN, State.LOSE]:
		return
	_set_state(State.PUSH)
	Juice.squash(self, 0.15, 0.25)


func play_hit() -> void:
	if state in [State.WIN, State.LOSE]:
		return
	_hit_dir = -1.0 if randf() < 0.5 else 1.0
	if _anim and _speed_ratio() >= stumble_speed and _anim.has_animation(clip_names.get("stumble", "stumble")):
		play_stumble()
		return
	_set_state(State.HIT)
	Juice.squash(self, 0.3, 0.35)


## Trip forward and windmill the arms (party-game classic).
func play_stumble() -> void:
	if state in [State.WIN, State.LOSE, State.STRUT]:
		return
	_set_state(State.STUMBLE)
	Juice.squash(self, 0.2, 0.3)


## Paint the zodog + shuudag (material "Team" in Blender) in the player's color.
func set_team_color(color: Color) -> void:
	if _mesh == null or _mesh.mesh == null:
		return
	for i in _mesh.mesh.get_surface_count():
		var mat := _mesh.mesh.surface_get_material(i)
		if mat and mat.resource_name == "Team":
			var m := mat.duplicate() as BaseMaterial3D
			m.albedo_color = color
			_mesh.set_surface_override_material(i, m)


## Bayan Khodood blessing: 0 = normal belly, 1 = big round "full stomach".
func set_full_stomach(amount: float) -> void:
	if _mesh and _mesh.find_blend_shape_by_name("full_stomach") >= 0:
		_mesh.set_blend_shape_value(_mesh.find_blend_shape_by_name("full_stomach"), amount)


## Winner: the bökh "eagle dance" (devekh) - flap the arms like an eagle.
func play_win() -> void:
	_set_state(State.WIN)


func play_lose() -> void:
	_set_state(State.LOSE)


## Palms slam down to the grass (legal in bökh) to stop a fall.
func play_brace() -> void:
	if state in [State.WIN, State.LOSE, State.STRUT]:
		return
	_set_state(State.BRACE)
	Juice.squash(self, 0.2, 0.3)


## Bayan Khodood ("full stomach"): the last-place horse is celebrated and
## stands next to the winner acting arrogant. Our loser does the same.
func play_strut() -> void:
	_set_state(State.STRUT)


func reset() -> void:
	_set_state(State.LOCOMOTION)
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	scale = Vector3.ONE


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	_state_time += delta
	# one-shot states end by themselves
	if state == State.PUSH and _state_time > 0.3:
		_set_state(State.LOCOMOTION)
	elif state == State.HIT and _state_time > 0.45:
		_set_state(State.LOCOMOTION)
	elif state == State.BRACE and _state_time > 0.8:
		_set_state(State.LOCOMOTION)
	elif state == State.STUMBLE and _state_time > 0.8:
		_set_state(State.LOCOMOTION)

	var speed := _speed_ratio()
	if _anim:
		_update_model(speed)
	else:
		_update_placeholder(speed, delta)


func _speed_ratio() -> float:
	if _body == null:
		return 0.0
	var v := _body.linear_velocity
	var max_speed: float = _body.get("max_speed") if _body.get("max_speed") != null else 6.0
	return clampf(Vector2(v.x, v.z).length() / max_speed, 0.0, 1.0)


func _set_state(s: State) -> void:
	state = s
	_state_time = 0.0


# ---------------------------------------------------------------- MODEL mode

func _update_model(speed: float) -> void:
	var key := "idle"
	match state:
		State.LOCOMOTION:
			key = "walk" if speed > 0.1 else "idle"
		State.PUSH:
			key = "push"
		State.HIT:
			key = "hit"
		State.WIN:
			key = "win"
		State.LOSE:
			key = "lose"
		State.BRACE:
			key = "brace"
		State.STRUT:
			key = "strut"
		State.STUMBLE:
			key = "stumble"
	var clip: String = clip_names.get(key, key)
	if not _anim.has_animation(clip):
		clip = clip_names.get("idle", "idle")
		if not _anim.has_animation(clip):
			return
	if clip != _current_clip:
		_current_clip = clip
		_anim.play(clip, blend_time)
	# walk faster = play walk clip faster
	_anim.speed_scale = lerpf(0.6, 1.4, speed) if key == "walk" else 1.0


# ---------------------------------------------------------------- PLACEHOLDER mode

func _update_placeholder(speed: float, delta: float) -> void:
	# targets for this frame (radians / meters); smoothed at the end
	var arm_l := Vector3.ZERO                # ArmL rotation
	var arm_r := Vector3.ZERO                # ArmR rotation
	var lean := 0.0                          # body lean forward (+) / back (-)
	var y := 0.0                             # body height offset
	var head_tilt := 0.0

	match state:
		State.LOCOMOTION:
			_cycle += delta * lerpf(2.0, 12.0, speed)
			if speed > 0.1:
				var s := sin(_cycle)
				arm_l.x = s * arm_swing * speed
				arm_r.x = -s * arm_swing * speed
				y = absf(sin(_cycle)) * walk_bob * speed
				lean = 0.15 * speed
			else:
				# idle: slow breathing, arms a bit out (wrestler stance)
				y = sin(_cycle * 0.5) * 0.015
				arm_l.z = -0.25
				arm_r.z = 0.25
				arm_l.x = 0.4
				arm_r.x = 0.4

		State.PUSH:
			# both arms shoot forward, body leans in
			var k := clampf(_state_time / 0.08, 0.0, 1.0)
			arm_l.x = PI * 0.5 * k
			arm_r.x = PI * 0.5 * k
			lean = 0.35 * k

		State.HIT, State.STUMBLE:
			# arms flail, body bends back, head wobbles
			var w := sin(_state_time * 40.0)
			arm_l.z = -1.6 + w * 0.5
			arm_r.z = 1.6 - w * 0.5
			lean = -0.4
			head_tilt = w * 0.4 * _hit_dir

		State.WIN:
			# EAGLE DANCE (devekh): slow, proud wing flaps + small hops,
			# turning around like the wrestler circles the flag
			_cycle += delta * 3.0
			var flap := (sin(_cycle) + 1.0) * 0.5          # 0..1
			arm_l.z = -lerpf(0.6, 1.9, flap)
			arm_r.z = lerpf(0.6, 1.9, flap)
			arm_l.x = 0.2
			arm_r.x = 0.2
			y = absf(sin(_cycle)) * 0.12
			lean = 0.25
			rotation.y += delta * 1.2

		State.LOSE:
			# sad slump: arms hang, body and head drop forward
			lean = 0.5
			y = -0.12
			head_tilt = 0.0
			arm_l.x = -0.2
			arm_r.x = -0.2

		State.BRACE:
			# both arms shoot DOWN and out to catch the grass, head up in panic
			arm_l.x = 1.1
			arm_r.x = 1.1
			arm_l.z = -0.5
			arm_r.z = 0.5
			lean = 0.3
			head_tilt = sin(_state_time * 30.0) * 0.25

		State.STRUT:
			# arrogant swagger: chest out, hands on hips, slow side-to-side sway,
			# nose in the air. Like he won, even though he came LAST.
			_cycle += delta * 2.2
			arm_l.z = -0.7
			arm_r.z = 0.7
			arm_l.x = -0.5
			arm_r.x = -0.5
			lean = -0.22
			y = absf(sin(_cycle)) * 0.05
			head_tilt = sin(_cycle) * 0.15
			rotation.y = lerp_angle(rotation.y, sin(_cycle * 0.5) * 0.6, clampf(delta * 3.0, 0.0, 1.0))

	var k_smooth := clampf(delta * 14.0, 0.0, 1.0)
	position.y = lerpf(position.y, y, k_smooth)
	rotation.x = lerp_angle(rotation.x, -lean, k_smooth)
	if _arm_l:
		_arm_l.rotation = _arm_l.rotation.lerp(arm_l, k_smooth)
	if _arm_r:
		_arm_r.rotation = _arm_r.rotation.lerp(arm_r, k_smooth)
	if _head:
		_head.rotation.z = lerp_angle(_head.rotation.z, head_tilt, k_smooth)
		var nod := 0.6 if state == State.LOSE else (-0.35 if state == State.STRUT else 0.0)
		_head.rotation.x = lerp_angle(_head.rotation.x, -nod, k_smooth)
