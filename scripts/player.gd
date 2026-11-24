extends RigidBody3D
## A wobbly wrestler (bökh). Moves with forces, so it slides and tips over in a funny way.
## An upright "spring" pulls it back up, but strong hits can still knock it over.
##
## Buttons: MOVE + PUSH + GRAB
##   PUSH  = shove. Tipping over? PUSH = palms down (PALM SAVE).
##   GRAB  = take a grip (барьц). With a grip, GRAB + a direction = a technique (мэх):
##           toward the rival / away / to the side / no direction. See mekh.gd.
##           Hold the grip 1.2 s = locked grip (лав барьц) = stronger techniques.
##   GRAB while the rival starts a technique on you = COUNTER (хариулт).

@export var player_id := "p1"            ## "p1" or "p2" - which controls to use
@export var body_color := Color(0.8, 0.1, 0.1)
@export var is_cpu := false              ## computer-controlled (press C in game to switch P2)
@export var move_force := 40.0           ## how hard the player pushes itself
@export var max_speed := 6.0
@export var push_strength := 4.0         ## sideways shove (high = rival SLIDES away instead of falling)
@export var push_range := 2.0
@export var push_cooldown := 0.6         ## seconds between pushes
@export var push_tip := 8.0              ## how much a push TIPS the rival over (high = knee/elbow falls)
@export var upright_strength := 20.0     ## higher = less wobbly
@export var upright_damping := 4.0

@export_group("Palm save")
## Real bökh rule: palms MAY touch the ground, knees/elbows/back may NOT.
## Press PUSH while you are tipping over = throw your palms down.
@export var brace_min_tilt := 28.0       ## degrees; below this, PUSH is a normal push
@export var brace_time := 0.8            ## how long the palms hold you
@export var brace_cooldown := 2.2        ## so you can't spam it
@export var brace_upright_boost := 5.0   ## extra "get up!" strength while bracing
@export var brace_lift := 22.0           ## palms push the body up off the grass

@export_group("Grip and techniques (мэх)")
@export var grab_range := 1.6            ## how close you must be to take a grip
@export var grip_distance := 1.0         ## the grip pulls you to this distance
@export var grip_spring := 30.0          ## how hard the grip pulls (also tips the rival!)
@export var grip_move_factor := 0.65     ## you move slower while holding
@export var grip_max_time := 5.0         ## the zasuul breaks a grip held too long
@export var lock_time := 1.2             ## grip held this long = locked grip (лав барьц)
@export var mekh_cooldown := 1.0
@export var dive_speed := 0.55           ## running this fast (0..1) + GRAB toward = leg dive

const CAPSULE_RADIUS := 0.45             ## must match CollisionShape3D in player.tscn
const CAPSULE_HALF_SEGMENT := 0.35       ## (height 1.6 / 2) - radius
const GROUND_Y := 0.0
const FEET_ZONE := 0.57                  ## cos(~55 deg): steeper than this = not feet

var bracing := false
var _brace_left := 0.0
var _brace_cd := 0.0
var _brace_touched := false              ## were we really falling during this brace?
var stats := {"palm_saves": 0, "pushes_landed": 0, "mekh": {}, "counters": 0}

signal palm_save(player)                 ## a brace that turned a fall into a recovery
signal mekh_done(attacker, victim, id, result)   ## result: "clean", "partial", "fail"

var _cooldown := 0.0
var is_out := false                      ## set true when the round is over (no control)
var keep_upright := false                ## winner stays standing while dancing

# grip + techniques
var rival: RigidBody3D
var gripping := false
var grip_time := 0.0
var _lock_said := false
var pending := {}                        ## a technique winding up: {id, t, windup, target, side}
var _mekh_cd := 0.0
# being thrown
var is_thrown := false
var _fly := {}
var _no_brace := 0.0                     ## after a clean throw you land too hard to palm-save
var thrown_by := {}                      ## {id, by, time} - the arena reads this for the title
# CPU
var _bot := {"t": 0.0, "plan": 0.8, "dir": Vector3.ZERO, "dir_t": 0.0, "counter": -1.0}

@onready var anim: Node3D = $Visual      ## character_animator.gd


func _ready() -> void:
	add_to_group("players")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	for mesh in [$Visual/Body, $Visual/ArmL/ArmMesh, $Visual/ArmR/ArmMesh]:
		mesh.material_override = mat
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.93, 0.76, 0.6)
	for mesh in [$Visual/Head/HeadMesh, $Visual/Head/Nose]:
		mesh.material_override = skin
	anim.set_team_color(body_color)       # Blender model: zodog + shuudag in team color
	for p in get_tree().get_nodes_in_group("players"):
		if p != self:
			rival = p
			p.rival = self


func _physics_process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	_brace_cd = max(_brace_cd - delta, 0.0)
	_mekh_cd = max(_mekh_cd - delta, 0.0)
	_no_brace = max(_no_brace - delta, 0.0)
	if is_thrown:
		_update_flight(delta)
		return
	_update_brace(delta)
	if is_out:
		if keep_upright:
			_stay_upright()
		return

	var inp := _read_input()
	var dir: Vector3 = inp.dir

	# 1. Movement (camera looks along -Z, so "up" means -Z). No walking while
	#    winding up a technique.
	var flat_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	var force := move_force * (grip_move_factor if gripping else 1.0)
	if pending.is_empty() and dir != Vector3.ZERO and flat_vel.length() < max_speed:
		apply_central_force(dir * force)

	# 2. Stay (mostly) upright
	_stay_upright()

	# 3. Face where we walk - or face the rival while gripping
	var look := dir
	if (gripping or not pending.is_empty()) and rival:
		look = _flat(rival.global_position - global_position).normalized()
	if look.length() > 0.1:
		var forward := -global_transform.basis.z
		var turn := forward.signed_angle_to(look, Vector3.UP)
		apply_torque(Vector3.UP * turn * 6.0)

	# 4. The grip pulls both wrestlers together (and tips the rival toward you)
	if gripping:
		_update_grip(delta)
	if not pending.is_empty():
		_update_windup(delta)

	# 5. Buttons
	if inp.push:
		_on_push()
	if inp.grab:
		_on_grab(dir)


func _read_input() -> Dictionary:
	if is_cpu:
		return _bot_input()
	var v := Input.get_vector(player_id + "_left", player_id + "_right",
			player_id + "_up", player_id + "_down")
	return {
		"dir": Vector3(v.x, 0, v.y),
		"push": Input.is_action_just_pressed(player_id + "_push"),
		"grab": Input.is_action_just_pressed(player_id + "_grab"),
	}


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func speed_ratio() -> float:
	return clampf(_flat(linear_velocity).length() / max_speed, 0.0, 1.0)


# ---------------------------------------------------------------- push / palm save

func _on_push() -> void:
	if tilt_deg() >= brace_min_tilt:
		start_brace()
		return
	# PUSH while the rival holds you = break his grip (барьц таслах)
	if rival and rival.gripping:
		rival.release_grip()
		Juice.pop_text("GRIP BROKEN!", global_position + Vector3.UP * 1.9, Color.LIGHT_SKY_BLUE, 60)
	if gripping:
		release_grip()
	if _cooldown <= 0.0 and pending.is_empty():
		_cooldown = push_cooldown
		anim.play_push()
		_push_nearby()


# ---------------------------------------------------------------- grip + techniques

func _on_grab(dir: Vector3) -> void:
	if rival == null or bracing or _mekh_cd > 0.0 or not pending.is_empty():
		return
	if rival.is_thrown or rival.is_out:
		return
	# COUNTER: the rival is winding up a technique on me right now
	if not rival.pending.is_empty() and rival.pending.target == self:
		_counter(rival)
		return
	var off := _flat(rival.global_position - global_position)
	var dist := off.length()
	var to := off.normalized()
	if gripping:
		var kind := _dir_kind(dir, to)
		var r := _rival_state(to)
		var id := Mekh.choose(kind, is_locked(), r.lean_to, r.vel_in, r.vel_side)
		var side := 1.0
		if kind == "side":
			side = signf(dir.dot(to.cross(Vector3.UP)))
		elif absf(r.vel_side) > 0.3:
			side = signf(r.vel_side)
		start_mekh(id, side)
	elif dist < 2.2 and dist > 1.25 and speed_ratio() >= dive_speed and dir.dot(to) > 0.6:
		start_mekh("khul_avakh", 1.0)          # no-grip technique: dive for the leg
	elif dist <= grab_range:
		gripping = true
		grip_time = 0.0
		_lock_said = false
		anim.play_grab()
		Juice.pop_text("grip", global_position + Vector3.UP * 1.7, Color(1, 1, 1, 0.8), 36)
	else:
		anim.play_grab()                      # grabbed at air


func _dir_kind(dir: Vector3, to: Vector3) -> String:
	if dir.length() < 0.3:
		return "none"
	var d := dir.normalized().dot(to)
	if d > 0.45:
		return "toward"
	if d < -0.45:
		return "away"
	return "side"


## How the rival stands, seen from me. lean_to > 0 = leaning back (away from me).
func _rival_state(to: Vector3) -> Dictionary:
	var up := rival.global_transform.basis.y
	var lean := Vector3(up.x, 0, up.z)
	var side := to.cross(Vector3.UP)
	return {
		"lean": lean,
		"lean_to": lean.dot(to),
		"vel_in": rival.linear_velocity.dot(-to),
		"vel_side": rival.linear_velocity.dot(side),
	}


func is_locked() -> bool:
	return gripping and grip_time >= lock_time


func release_grip() -> void:
	gripping = false
	grip_time = 0.0


func _update_grip(delta: float) -> void:
	if rival == null or rival.is_thrown or rival.is_out:
		release_grip()
		return
	grip_time += delta
	var off := _flat(rival.global_position - global_position)
	var dist := off.length()
	if dist > 2.4:
		release_grip()
		return
	if grip_time > grip_max_time:
		release_grip()
		Juice.pop_text("ZASUUL: NEW GRIP!", global_position + Vector3.UP * 2.0, Color.WHITE, 50)
		return
	if is_locked() and not _lock_said:
		_lock_said = true
		Juice.pop_text("LOCKED GRIP", global_position + Vector3.UP * 1.9, Color.GOLD, 52)
	# spring at chest height: pulling also TIPS the rival toward you
	var f := off.normalized() * (dist - grip_distance) * grip_spring
	var chest := Vector3.UP * 0.5
	apply_force(f * 0.5, chest)
	rival.apply_force(-f * 0.5, chest)


## Wind up a technique. The rival has `windup` seconds to COUNTER with GRAB.
func start_mekh(id: String, side: float) -> void:
	var d: Dictionary = Mekh.TABLE[id]
	pending = {"id": id, "t": 0.0, "windup": d.windup, "target": rival, "side": side}
	_mekh_cd = mekh_cooldown
	anim.play_mekh(d.clip)
	# telegraph: the rival sees it coming
	Juice.pop_text("!", rival.global_position + Vector3.UP * 2.1, Color.ORANGE, 90)


func _update_windup(delta: float) -> void:
	pending.t += delta
	var target: RigidBody3D = pending.target
	if target == null or target.is_thrown or target.is_out or is_out:
		pending = {}
		return
	if pending.t < pending.windup:
		return
	var id: String = pending.id
	var side: float = pending.side
	pending = {}
	var to := _flat(target.global_position - global_position).normalized()
	if _flat(target.global_position - global_position).length() > 2.6:
		_mekh_failed(id, target)                # he walked away
		return
	var r := _rival_state(to)
	var land_dir := land_direction(id, to, side)
	var off_bal: float = r.lean.dot(land_dir) / 0.4
	var momentum: float = target.linear_velocity.dot(land_dir) / 3.0
	var c := Mekh.chance(id, is_locked(), off_bal, momentum, target.mass > 1.1, target.gripping)
	var result := Mekh.roll(c)
	release_grip()
	if result == "fail":
		_mekh_failed(id, target)
		return
	stats.mekh[id] = stats.mekh.get(id, 0) + 1
	target.begin_thrown(self, id, result, side)
	Juice.pop_text(Mekh.label(id), global_position + Vector3.UP * 2.3, Color.GOLD, 110)
	Juice.pop_text(Mekh.subtitle(id), global_position + Vector3.UP * 1.9, Color.WHITE, 48)
	mekh_done.emit(self, target, id, result)


func _mekh_failed(id: String, target: RigidBody3D) -> void:
	release_grip()
	Juice.pop_text("DODGED! (ЗАЙЛЛАА)", target.global_position + Vector3.UP * 2.0, Color.LIGHT_SKY_BLUE, 64)
	# the failed thrower is off balance now
	var to := _flat(target.global_position - global_position).normalized()
	apply_central_impulse(to * 2.0)
	apply_torque_impulse(to.cross(Vector3.UP) * -4.0)
	anim.play_stumble()
	mekh_done.emit(self, target, id, "fail")


func _counter(attacker: RigidBody3D) -> void:
	var side := signf(randf() - 0.5)
	attacker.pending = {}
	attacker.release_grip()
	release_grip()
	_mekh_cd = mekh_cooldown
	anim.play_mekh(Mekh.TABLE.khariult.clip)
	var result := Mekh.roll(Mekh.TABLE.khariult.chance)
	if result == "fail":
		result = "partial"
	stats.counters += 1
	stats.mekh["khariult"] = stats.mekh.get("khariult", 0) + 1
	attacker.begin_thrown(self, "khariult", result, side)
	Juice.pop_text("ХАРИУЛТ!", global_position + Vector3.UP * 2.3, Color.CYAN, 110)
	Juice.pop_text("COUNTER!", global_position + Vector3.UP * 1.9, Color.WHITE, 56)
	mekh_done.emit(self, attacker, "khariult", result)


## Which way a technique sends the rival (flat world direction).
func land_direction(id: String, to: Vector3, side: float) -> Vector3:
	var s := to.cross(Vector3.UP) * side
	match Mekh.TABLE[id].land:
		"behind_thrower", "beside_thrower":
			return -to
		"swept_side", "twisted_down":
			return (s + to * 0.3).normalized()
		_:
			return to


# ---------------------------------------------------------------- being thrown

func begin_thrown(thrower: RigidBody3D, id: String, result: String, side: float) -> void:
	var d: Dictionary = Mekh.TABLE[id]
	is_thrown = true
	release_grip()
	pending = {}
	bracing = false
	thrown_by = {"id": id, "by": thrower, "time": Time.get_ticks_msec(), "result": result}
	var A := _flat(thrower.global_position)
	var D := global_position
	var to := _flat(D - A).normalized()
	if to.length() < 0.1:
		to = -thrower.global_transform.basis.z
	var s := to.cross(Vector3.UP) * side
	var land: Vector3
	match d.land:
		"behind_thrower":
			land = A - to * 1.2
		"beside_thrower":
			land = A + s * 1.1 - to * 0.3
		"swept_side":
			land = _flat(D) + s * 0.9 + to * 0.2
		"twisted_down":
			land = _flat(D) + s * 0.8 + to * 0.1
		_:
			land = _flat(D) + to * 0.85
	var clean := result == "clean"
	if not clean:
		land = _flat(D).lerp(land, 0.55)
	land.y = 0.52 if clean else 0.8
	var travel := _flat(land - D).normalized()
	if travel.length() < 0.1:
		travel = to
	var q_end := _landing_basis(d.part, travel).get_rotation_quaternion()
	var q0 := global_transform.basis.get_rotation_quaternion()
	if not clean:
		q_end = q0.slerp(q_end, 0.62)         # only tipping: a palm save can still rescue him
	var q_mid := Quaternion()
	if d.spin and clean:
		q_mid = Basis(travel.cross(Vector3.DOWN).normalized(), Vector3.DOWN, -travel).orthonormalized().get_rotation_quaternion()
	_fly = {
		"t": 0.0, "T": float(d.air) * (1.0 if clean else 0.8), "p0": D, "p2": land,
		"p1": (D + land) * 0.5 + Vector3.UP * float(d.height) * (1.0 if clean else 0.5),
		"q0": q0, "q1": q_end, "qm": q_mid, "spin": d.spin and clean, "clean": clean, "by": thrower,
	}
	add_collision_exception_with(thrower)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	anim.play_thrown()
	Juice.hit_stop(0.05)
	Juice.shake(0.2, 0.25)


## Orientation of a wrestler lying with `part` on the grass, head along `travel`.
func _landing_basis(part: String, travel: Vector3) -> Basis:
	var y := travel                       # the head points the way he flies
	var z: Vector3
	match part:
		"back":
			z = Vector3.DOWN              # body faces -Z, so +Z (his back) on the grass
		"knee":
			z = Vector3.UP                # face/knees down
		_:
			# on his side: his +X (a shoulder/elbow) on the grass
			return Basis(Vector3.DOWN, y, Vector3.DOWN.cross(y)).orthonormalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z).orthonormalized()


func _update_flight(delta: float) -> void:
	_fly.t += delta
	var k: float = clampf(_fly.t / _fly.T, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k) * 0.35 + k * 0.65
	var p: Vector3 = _fly.p0.lerp(_fly.p1, e).lerp(_fly.p1.lerp(_fly.p2, e), e)
	var q: Quaternion
	if _fly.spin:
		q = _fly.q0.slerp(_fly.qm, e * 2.0) if e < 0.5 else _fly.qm.slerp(_fly.q1, (e - 0.5) * 2.0)
	else:
		q = _fly.q0.slerp(_fly.q1, e)
	global_transform = Transform3D(Basis(q), p)
	if k >= 1.0:
		_land()


func _land() -> void:
	is_thrown = false
	freeze = false
	var dir := _flat(_fly.p2 - _fly.p1).normalized()
	linear_velocity = dir * (2.5 if _fly.clean else 1.2) + Vector3.DOWN * 1.5
	angular_velocity = Vector3.ZERO
	_no_brace = 0.4 if _fly.clean else 0.0
	var thrower: RigidBody3D = _fly.by
	get_tree().create_timer(0.3).timeout.connect(func():
		if is_instance_valid(thrower):
			remove_collision_exception_with(thrower))
	Juice.dust(global_position + Vector3.DOWN * 0.4, 28)
	Juice.shake(0.3 if _fly.clean else 0.15, 0.3)
	if not _fly.clean:
		anim.play_stumble()
	_fly = {}


# ---------------------------------------------------------------- ground rules

func tilt_deg() -> float:
	return rad_to_deg(global_transform.basis.y.angle_to(Vector3.UP))


## Which part of the body touches the grass right now?
## "" = nothing (or only the feet).  Otherwise "knee", "back", "elbow".
## We find the lowest point of the capsule and ask: is it the feet, the front
## (knees), the back, or the side (elbow)?
func ground_touch() -> String:
	var b := global_transform.basis.orthonormalized()
	var lowest := global_position.y - (CAPSULE_HALF_SEGMENT * absf(b.y.y) + CAPSULE_RADIUS)
	if lowest > GROUND_Y + 0.06:
		return ""
	var d := b.transposed() * Vector3.DOWN   # "down" seen from the body
	if d.y < -FEET_ZONE:
		return ""                            # standing on the feet: fine
	if bracing:
		return ""                            # palms are on the grass: still legal!
	if absf(d.z) >= absf(d.x):
		return "knee" if d.z < 0.0 else "back"   # body faces -Z
	return "elbow"


func start_brace() -> void:
	if bracing or _brace_cd > 0.0 or _no_brace > 0.0 or is_thrown:
		return
	bracing = true
	_brace_left = brace_time
	_brace_cd = brace_cooldown
	_brace_touched = false
	release_grip()
	anim.play_brace()
	Juice.dust(global_position + Vector3.DOWN * 0.5, 10)


func _update_brace(delta: float) -> void:
	if not bracing:
		return
	if is_out:
		bracing = false
		return
	_brace_left -= delta
	var b := global_transform.basis
	var lowest := global_position.y - (CAPSULE_HALF_SEGMENT * absf(b.y.y) + CAPSULE_RADIUS)
	var tilt := tilt_deg()
	if tilt > 50.0:
		_brace_touched = true                # we really were going down
	if tilt > 40.0 and lowest < GROUND_Y + 0.15:
		apply_central_force(Vector3.UP * brace_lift)   # palms push us up
	var tilt_axis := b.y.cross(Vector3.UP)
	apply_torque(tilt_axis * upright_strength * brace_upright_boost)
	if tilt < 22.0 and _brace_touched:
		bracing = false
		stats.palm_saves += 1
		palm_save.emit(self)
		Juice.pop_text("PALM SAVE!", global_position + Vector3.UP * 1.8, Color.GOLD)
		Juice.shake(0.12, 0.2)
	elif _brace_left <= 0.0:
		bracing = false


## Torque that rotates our "up" back to world up.
func _stay_upright() -> void:
	var tilt_axis := global_transform.basis.y.cross(Vector3.UP)
	apply_torque(tilt_axis * upright_strength - angular_velocity * upright_damping)


func _push_nearby() -> void:
	for other in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		var offset: Vector3 = other.global_position - global_position
		if offset.length() <= push_range:
			var away := Vector3(offset.x, 0, offset.z).normalized()
			# a little upward pop makes hits look goofy
			other.apply_central_impulse(away * push_strength + Vector3.UP * push_strength * 0.35)
			other.apply_torque_impulse(away.cross(Vector3.UP) * -push_tip)
			# recoil: we also wobble back a bit
			apply_central_impulse(-away * push_strength * 0.25)
			# effects
			other.anim.play_hit()
			stats.pushes_landed += 1
			Juice.dust(global_position + offset * 0.5 + Vector3.DOWN * 0.7)
			Juice.shake(0.15, 0.2)
			Juice.hit_stop(0.05)


## Called by the arena between rounds.
func reset_state() -> void:
	is_out = false
	keep_upright = false
	bracing = false
	is_thrown = false
	freeze = false
	_fly = {}
	pending = {}
	thrown_by = {}
	release_grip()
	_mekh_cd = 0.5
	_bot.counter = -1.0


# ---------------------------------------------------------------- CPU wrestler

func _bot_input() -> Dictionary:
	var out := {"dir": Vector3.ZERO, "push": false, "grab": false}
	if rival == null:
		return out
	var dt := get_physics_process_delta_time()
	_bot.t += dt
	_bot.dir_t -= dt
	var off := _flat(rival.global_position - global_position)
	var dist := off.length()
	var to := off.normalized()
	# palm save when going down
	if tilt_deg() > 36.0 and _brace_cd <= 0.0 and randf() < 0.1:
		out.push = true
		return out
	# counter a technique (sometimes)
	if not rival.pending.is_empty() and rival.pending.target == self:
		if _bot.counter < 0.0:
			_bot.counter = randf_range(0.06, 0.3) if randf() < 0.3 else 99.0
		if rival.pending.t > _bot.counter:
			out.grab = true
		return out
	_bot.counter = -1.0
	if gripping:
		if grip_time > _bot.plan and _mekh_cd <= 0.0:
			_bot.plan = randf_range(0.4, 2.0)
			var pick := randi() % 4
			out.dir = [to, -to, to.cross(Vector3.UP) * (1 if randf() < 0.5 else -1), Vector3.ZERO][pick]
			out.grab = true
		else:
			if _bot.dir_t <= 0.0:
				_bot.dir_t = randf_range(0.3, 0.8)
				_bot.dir = [to * 0.8, -to * 0.8, Vector3.ZERO, to.cross(Vector3.UP) * 0.7].pick_random()
			out.dir = _bot.dir
		return out
	# no grip: walk in, sometimes circle, then grab (or push, or dive for the leg)
	if _bot.dir_t <= 0.0:
		_bot.dir_t = randf_range(0.4, 1.0)
		_bot.dir = (to + to.cross(Vector3.UP) * randf_range(-0.6, 0.6)).normalized()
	out.dir = _bot.dir * (1.0 if dist > 2.4 else 0.35) if dist > 1.1 else Vector3.ZERO
	# stay near the middle (the zasuul pushes wanderers back anyway)
	if _flat(global_position).length() > 4.5:
		out.dir = (-_flat(global_position).normalized() + to).normalized()
	if _mekh_cd <= 0.0 and dist < grab_range - 0.1 and randf() < 0.05:
		out.grab = true
	elif dist < 2.2 and dist > 1.4 and speed_ratio() > dive_speed and randf() < 0.03:
		out.dir = to
		out.grab = true
	elif dist < push_range * 0.9 and _cooldown <= 0.0 and randf() < 0.008:
		out.push = true
	return out
