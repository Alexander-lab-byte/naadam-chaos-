extends RigidBody3D
## A wobbly wrestler (bökh). Moves with forces, so it slides and tips over in a funny way.
## An upright "spring" pulls it back up, but strong hits can still knock it over.

@export var player_id := "p1"            ## "p1" or "p2" - which controls to use
@export var body_color := Color(0.8, 0.1, 0.1)
@export var move_force := 40.0           ## how hard the player pushes itself
@export var max_speed := 6.0
@export var push_strength := 7.0         ## impulse given to the other player
@export var push_range := 2.0
@export var push_cooldown := 0.6         ## seconds between pushes
@export var upright_strength := 25.0     ## higher = less wobbly
@export var upright_damping := 4.0

var _cooldown := 0.0
var is_out := false                      ## set true when the player leaves the ring


func _ready() -> void:
	add_to_group("players")
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	for mesh in [$Body, $Head]:
		mesh.material_override = mat


func _physics_process(delta: float) -> void:
	_cooldown = max(_cooldown - delta, 0.0)
	if is_out:
		return

	# 1. Movement (camera looks along -Z, so "up" means -Z)
	var input := Input.get_vector(player_id + "_left", player_id + "_right",
			player_id + "_up", player_id + "_down")
	var dir := Vector3(input.x, 0, input.y)
	var flat_vel := Vector3(linear_velocity.x, 0, linear_velocity.z)
	if dir != Vector3.ZERO and flat_vel.length() < max_speed:
		apply_central_force(dir * move_force)

	# 2. Stay (mostly) upright: torque that rotates our "up" back to world up
	var tilt_axis := global_transform.basis.y.cross(Vector3.UP)
	apply_torque(tilt_axis * upright_strength - angular_velocity * upright_damping)

	# 3. Face where we walk (only turn around the Y axis)
	if dir.length() > 0.1:
		var forward := -global_transform.basis.z
		var turn := forward.signed_angle_to(dir, Vector3.UP)
		apply_torque(Vector3.UP * turn * 6.0)

	# 4. Push
	if Input.is_action_just_pressed(player_id + "_push") and _cooldown <= 0.0:
		_cooldown = push_cooldown
		_push_nearby()


func _push_nearby() -> void:
	for other in get_tree().get_nodes_in_group("players"):
		if other == self:
			continue
		var offset: Vector3 = other.global_position - global_position
		if offset.length() <= push_range:
			var away := Vector3(offset.x, 0, offset.z).normalized()
			# a little upward pop makes hits look goofy
			other.apply_central_impulse(away * push_strength + Vector3.UP * push_strength * 0.35)
			other.apply_torque_impulse(away.cross(Vector3.UP) * -3.0)
			# recoil: we also wobble back a bit
			apply_central_impulse(-away * push_strength * 0.25)
