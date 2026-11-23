extends Node
## "Juice" = small effects that make hits feel strong and funny.
## Autoload: call from any script, e.g.  Juice.shake(0.3)  or  Juice.dust(pos)
##
## Everything here is made in code (Tweens + particles), so it works
## with the placeholder capsules AND with real Blender models later.

var _shake_strength := 0.0
var _shake_time := 0.0
var _camera: Camera3D


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	# shake with h_offset / v_offset, so a moving camera rig still works
	if _shake_time > 0.0:
		_shake_time -= delta
		var s := _shake_strength * clampf(_shake_time / 0.25, 0.0, 1.0)
		_camera.h_offset = randf_range(-s, s)
		_camera.v_offset = randf_range(-s, s)
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		_camera = null


## Shake the current camera. strength ~0.1 (small) to 0.5 (huge).
func shake(strength := 0.2, time := 0.25) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_camera = cam
	_shake_strength = maxf(_shake_strength if _shake_time > 0.0 else 0.0, strength)
	_shake_time = maxf(_shake_time, time)


## Freeze the game for a tiny moment. Makes a big hit feel heavy.
func hit_stop(time := 0.06, slow := 0.05) -> void:
	Engine.time_scale = slow
	# ignore_time_scale = true, so the timer runs in real time
	await get_tree().create_timer(time, true, false, true).timeout
	Engine.time_scale = 1.0


## Squash and stretch a node (cartoon "boing"). amount 0.3 = strong.
func squash(node: Node3D, amount := 0.25, time := 0.3) -> void:
	if node == null:
		return
	var base := Vector3.ONE
	var t := node.create_tween()
	t.tween_property(node, "scale", Vector3(1.0 + amount, 1.0 - amount, 1.0 + amount), time * 0.25)
	t.tween_property(node, "scale", Vector3(1.0 - amount * 0.5, 1.0 + amount * 0.5, 1.0 - amount * 0.5), time * 0.25)
	t.tween_property(node, "scale", base, time * 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## Make a UI element (Label, Button...) pop in.
func pop(control: Control, time := 0.35) -> void:
	if control == null:
		return
	control.pivot_offset = control.size / 2.0
	control.scale = Vector2(0.3, 0.3)
	var t := control.create_tween()
	t.tween_property(control, "scale", Vector2.ONE, time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Floating 3D text that rises and fades ("PALM SAVE!", "UUKHAI!").
func pop_text(text: String, pos: Vector3, color := Color.WHITE, size := 96) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 18
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.006
	scene_root.add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 0.3
	var t := l.create_tween()
	t.tween_property(l, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "global_position", pos + Vector3.UP * 1.2, 1.2)
	t.tween_property(l, "modulate:a", 0.0, 0.4)
	t.tween_callback(l.queue_free)


## Dust cloud (pushes, falls, horse hooves).
func dust(pos: Vector3, amount := 16, color := Color(0.75, 0.65, 0.45)) -> void:
	_burst(pos, amount, color, 0.12, 2.5, 0.6, Vector3(0, 0.5, 0), 70.0, -2.0)


## Confetti (winner, arrow hits the target).
func confetti(pos: Vector3, amount := 40) -> void:
	var colors := [Color.RED, Color.GOLD, Color.DODGER_BLUE, Color.WHITE, Color.LIME_GREEN]
	for c in colors:
		_burst(pos, int(amount / float(colors.size())), c, 0.07, 6.0, 1.6, Vector3.UP, 35.0, -6.0)


## Builds a one-shot GPUParticles3D, plays it, and deletes it after.
func _burst(pos: Vector3, amount: int, color: Color, size: float, speed: float,
		life: float, dir: Vector3, spread: float, gravity_y: float) -> void:
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = maxi(amount, 1)
	p.lifetime = life

	var mat := ParticleProcessMaterial.new()
	mat.direction = dir
	mat.spread = spread
	mat.initial_velocity_min = speed * 0.5
	mat.initial_velocity_max = speed
	mat.gravity = Vector3(0, gravity_y, 0)
	mat.scale_min = 0.6
	mat.scale_max = 1.2
	mat.damping_min = 1.0
	mat.damping_max = 2.0
	# fade out: scale goes from 1 to 0 over the lifetime
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	mat.scale_curve = ct
	p.process_material = mat

	var mesh := SphereMesh.new()
	mesh.radius = size
	mesh.height = size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = m
	p.draw_pass_1 = mesh

	scene_root.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)
