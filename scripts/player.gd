extends RigidBody3D
## A wobbly wrestler (bökh). Moves with forces, so it slides and tips over in a funny way.
## An upright "spring" pulls it back up, but strong hits can still knock it over.

@export var player_id := "p1"            ## "p1" or "p2" - which controls to use
@export var body_color := Color(0.8, 0.1, 0.1)
@export var move_force := 40.0           ## how hard the player pushes itself
@export var max_speed := 6.0
@export var push_strength := 4.0         ## sideways shove (high = rival SLIDES out of the ring)
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

const CAPSULE_RADIUS := 0.45             ## must match CollisionShape3D in player.tscn
const CAPSULE_HALF_SEGMENT := 0.35       ## (height 1.6 / 2) - radius
const GROUND_Y := 0.0
const FEET_ZONE := 0.57                  ## cos(~55 deg): steeper than this = not feet

var bracing := false
var _brace_left := 0.0
var _brace_cd := 0.0
var _brace_touched := false              ## were we really falling during this brace?
var stats := {"palm_saves": 0, "pushes_landed": 0}

signal palm_save(player)                 ## a brace that turned a fall into a recovery

var _cooldown := 0.0
var is_out := false                      ## set true when the round is over (no control)
var keep_upright := false                ## winner stays standing while dancing

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


func _physics_process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	_brace_cd = max(_brace_cd - delta, 0.0)
	_update_brace(delta)
	if is_out:
		if keep_upright:
			_stay_upright()
		return

	# 1. Movement (camera looks along -Z, so "up" means -Z)
	var input := Input.get_vector(player_id + "_left", player_id + "_right",
			player_id + "_up", player_id + "_down")
	var dir := Vector3(input.x, 0, input.y)
	var flat_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if dir != Vector3.ZERO and flat_vel.length() < max_speed:
		apply_central_force(dir * move_force)

	# 2. Stay (mostly) upright
	_stay_upright()

	# 3. Face where we walk (only turn around the Y axis)
	if dir.length() > 0.1:
		var forward := -global_transform.basis.z
		var turn := forward.signed_angle_to(dir, Vector3.UP)
		apply_torque(Vector3.UP * turn * 6.0)

	# 4. Push - or, if we are tipping over, throw the palms down (brace)
	if Input.is_action_just_pressed(player_id + "_push"):
		if tilt_deg() >= brace_min_tilt:
			start_brace()
		elif _cooldown <= 0.0:
			_cooldown = push_cooldown
			anim.play_push()
			_push_nearby()


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
	if bracing or _brace_cd > 0.0:
		return
	bracing = true
	_brace_left = brace_time
	_brace_cd = brace_cooldown
	_brace_touched = false
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
