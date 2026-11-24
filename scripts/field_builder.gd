extends Node3D
## Builds the Naadam wrestling field when the scene starts.
##
## Everything here comes from Blender (art/blender/build_environment.py):
##   assets/env/terrain.glb      - the steppe, hills and mountains
##   assets/env/naadam_props.glb - Ger, Tug, Flag, StandSegment, Person_*, Larch, Rock_*, Eagle
##   assets/env/scatter.json     - where trees, rocks and far gers stand on the hills
## and the shaders in res://shaders/ make it move: grass + trees + horsehair in the wind,
## waving flags, drifting clouds and their shadows, a cheering crowd, eagles, chimney smoke.
##
## Call cheer(1.0) (arena.gd does) to make the crowd jump and throw their arms up.
## Slow computer? Lower grass_density / crowd_density in the Inspector.

@export var ring_radius := 6.0
@export_range(0.1, 2.0) var grass_density := 1.0
@export_range(0.1, 1.0) var crowd_density := 1.0
@export var seed_value := 7

const PROPS_PATH := "res://assets/env/naadam_props.glb"
const TERRAIN_PATH := "res://assets/env/terrain.glb"
const SCATTER_PATH := "res://assets/env/scatter.json"
const TEX := "res://assets/env/textures/"

var _mesh := {}                       ## Blender object name -> Mesh
var _crowd_mat: ShaderMaterial
var _hype := 0.15
var _rng := RandomNumberGenerator.new()
var _eagles: Array[Node3D] = []
var _crowd := {}                      ## mesh name -> Array of [Transform3D, Color custom]


func _ready() -> void:
	_rng.seed = seed_value
	add_to_group("field")
	_load_props()
	_build_terrain()
	_build_grass()
	_build_flowers()
	_build_banners()
	_build_stands()
	_build_side_crowd()
	_build_zasuuls()
	_spawn_crowd()
	_build_gers()
	_build_flags()
	_build_scatter()
	_build_eagles()
	_build_pollen()


func _process(delta: float) -> void:
	_hype = maxf(0.15, _hype - delta * 0.45)
	if _crowd_mat:
		_crowd_mat.set_shader_parameter("hype", _hype)
	var t := Time.get_ticks_msec() / 1000.0
	for i in _eagles.size():
		var e: Node3D = _eagles[i]
		var r: float = e.get_meta("r")
		var a: float = e.get_meta("a") + t * e.get_meta("speed")
		var c: Vector3 = e.get_meta("c")
		var p := c + Vector3(cos(a) * r, sin(t * 0.3 + i) * 3.0, sin(a) * r)
		var dir := Vector3(-sin(a), 0, cos(a)) * signf(e.get_meta("speed"))
		e.global_position = p
		e.basis = Basis.looking_at(-dir, Vector3.UP).rotated(dir, -0.35 * signf(e.get_meta("speed")))


## Make the crowd jump and cheer (0..1).
func cheer(amount := 1.0) -> void:
	_hype = maxf(_hype, amount)


# ---------------------------------------------------------------- loading

func _load_props() -> void:
	var scene: PackedScene = load(PROPS_PATH)
	var root := scene.instantiate()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		_mesh[String(mi.name)] = mi.mesh
	root.free()


func _shader(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	return m


func _tex(name: String) -> Texture2D:
	return load(TEX + name)


func _place(mesh_name: String, t: Transform3D, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh.get(mesh_name)
	mi.transform = t
	parent.add_child(mi)
	return mi


## Swap one material of a mesh instance (found by its Blender material name).
func _override(mi: MeshInstance3D, mat_name: String, mat: Material) -> void:
	for i in mi.mesh.get_surface_count():
		var m := mi.mesh.surface_get_material(i)
		if m and m.resource_name == mat_name:
			mi.set_surface_override_material(i, mat)


func _multimesh(mesh: Mesh, items: Array, mat: Material, shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true                      # white = keep the mesh's own vertex colors
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_custom_data(i, items[i][1] if items[i].size() > 1 else Color(0, 0, 0, 0))
		mm.set_instance_color(i, Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi


# ---------------------------------------------------------------- terrain + grass

func _build_terrain() -> void:
	var root: Node3D = (load(TERRAIN_PATH) as PackedScene).instantiate()
	add_child(root)
	var mat := _shader("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("grass_tex", _tex("ground_grass.png"))
	mat.set_shader_parameter("dirt_tex", _tex("ground_dirt.png"))
	mat.set_shader_parameter("rock_tex", _tex("rock.png"))
	mat.set_shader_parameter("ring_radius", ring_radius)
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One grass blade: 4 segments, tapered, curved forward. UV.y = 0 at the root, 1 at the tip.
func _blade_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 4
	var pts := []
	for i in segs + 1:
		var t := float(i) / segs
		var w := 0.022 * pow(1.0 - t, 0.7) + 0.001
		var p := Vector3(0, t * 0.36, -0.1 * t * t)
		pts.append([p + Vector3(-w, 0, 0), p + Vector3(w, 0, 0), t])
	for i in segs:
		var a: Array = pts[i]
		var b: Array = pts[i + 1]
		for v in [[a[0], a[2]], [a[1], a[2]], [b[1], b[2]], [a[0], a[2]], [b[1], b[2]], [b[0], b[2]]]:
			st.set_normal(Vector3(0, 0.4, 1).normalized())
			st.set_uv(Vector2(0.5, v[1]))
			st.add_vertex(v[0])
	return st.commit()


func _build_grass() -> void:
	var blade := _blade_mesh()
	var mat := _shader("res://shaders/grass.gdshader")
	mat.set_shader_parameter("grass_tex", _tex("ground_grass.png"))
	mat.set_shader_parameter("ring_radius", ring_radius)
	var chunks := {}
	var count := int(95000 * grass_density)
	for i in count:
		var r := sqrt(_rng.randf()) * 37.5
		if r < ring_radius - 0.3 and _rng.randf() > 0.3:
			continue                          # trampled: fewer blades in the circle
		var a := _rng.randf() * TAU
		var pos := Vector3(cos(a) * r, -0.02, sin(a) * r)
		var s := _rng.randf_range(0.7, 1.3)
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.6, 1.5), s))
		var key := Vector2i(floori(pos.x / 12.5), floori(pos.z / 12.5))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append([Transform3D(b, pos), Color(_rng.randf(), _rng.randf(), 0, 0)])
	for key in chunks:
		var mmi := _multimesh(blade, chunks[key], mat, false)
		mmi.custom_aabb = AABB(Vector3(key.x * 12.5 - 1, -1, key.y * 12.5 - 1), Vector3(14.5, 3, 14.5))
		mmi.visibility_range_end = 70.0


## Little steppe flowers: white (edelweiss), yellow, purple.
func _flower_mesh(petal: Color) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem := Color(0.25, 0.45, 0.15)
	var h := 0.22
	for v in [Vector3(-0.006, 0, 0), Vector3(0.006, 0, 0), Vector3(0, h, 0)]:
		st.set_color(stem); st.set_normal(Vector3.UP); st.add_vertex(v)
	for k in 6:
		var a := TAU * k / 6.0
		var d := Vector3(cos(a), 0.25, sin(a)) * 0.035
		var s := Vector3(-sin(a), 0, cos(a)) * 0.014
		for v in [Vector3(0, h, 0), Vector3(0, h, 0) + d + s, Vector3(0, h, 0) + d - s]:
			st.set_color(petal); st.set_normal(Vector3.UP); st.add_vertex(v)
	st.set_color(Color(0.95, 0.8, 0.2))
	return st.commit()


func _build_flowers() -> void:
	var mat := _shader("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("sway", 0.6)
	for c in [Color(0.95, 0.95, 0.9), Color(0.95, 0.8, 0.15), Color(0.55, 0.35, 0.8)]:
		var items := []
		for i in int(900 * grass_density):
			var r := _rng.randf_range(ring_radius + 2.5, 37.0)
			var a := _rng.randf() * TAU
			# flowers grow in small patches
			var p := Vector3(cos(a) * r, -0.02, sin(a) * r)
			if sin(p.x * 0.4) * sin(p.z * 0.37) < 0.2:
				continue
			items.append([Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.8, 1.3)), p)])
		_multimesh(_flower_mesh(c), items, mat, false).visibility_range_end = 60.0


# ---------------------------------------------------------------- Nine White Banners

## Есөн хөлт цагаан туг. They stand in a row behind the field.
func _build_banners() -> void:
	var hair := _shader("res://shaders/hair.gdshader")
	hair.set_shader_parameter("hair_tex", _tex("horsehair.png"))
	for i in 9:
		var k := i - 4
		var s := 1.18 if k == 0 else 1.0           # the main banner in the middle is bigger
		var t := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(k * 2.4, 0, -13.5 + absf(k) * 0.3))
		var mi := _place("Tug", t)
		_override(mi, "Horsehair", hair)


# ---------------------------------------------------------------- grandstand + crowd

func _crowd_add(mesh_name: String, t: Transform3D, shoulder: float, zasuul := false) -> void:
	if not _crowd.has(mesh_name):
		_crowd[mesh_name] = []
	var color_idx := 0.0
	if zasuul:
		color_idx = 0.45 if t.origin.x < 0 else 0.15
	else:
		color_idx = _rng.randf()
	_crowd[mesh_name].append([t, Color(_rng.randf(), color_idx, shoulder, 1.0 if zasuul else 0.0)])


const HATS := ["mongol", "mongol", "cap", "scarf", "scarf", "bare"]


func _build_stands() -> void:
	var r := 24.0
	for i in 9:
		var th := (i - 4) * 0.25
		var pos := Vector3(sin(th) * r, 0, -cos(th) * r)
		var seg := Transform3D(Basis(Vector3.UP, -th), pos)
		_place("StandSegment", seg)
		# seated people on the 4 benches
		for tier in 4:
			var y := 0.45 * (tier + 1) + 0.11
			var z := -(tier * 0.9 + 0.55)
			var x := -2.6
			while x <= 2.65:
				if _rng.randf() < 0.88 * crowd_density:
					var local := Transform3D(Basis(Vector3.UP, _rng.randf_range(-0.15, 0.15)), Vector3(x + _rng.randf_range(-0.06, 0.06), y, z))
					_crowd_add("Person_sit_" + HATS[_rng.randi() % HATS.size()], seg * local, 1.0)
				x += 0.62


func _build_side_crowd() -> void:
	for side: int in [-1, 1]:
		for i in int(170 * crowd_density):
			var th: float = deg_to_rad(_rng.randf_range(66, 118)) * side
			var r := _rng.randf_range(13.0, 17.5)
			var pos := Vector3(sin(th) * r, 0, -cos(th) * r)
			var look := Basis(Vector3.UP, atan2(-pos.x, -pos.z))   # face the field
			var sc := _rng.randf_range(0.9, 1.08)
			_crowd_add("Person_stand_" + HATS[_rng.randi() % HATS.size()], Transform3D(look.scaled(Vector3.ONE * sc), pos), 1.36)


## Two zasuul heralds standing at the edge of the circle.
func _build_zasuuls() -> void:
	for side: int in [-1, 1]:
		var pos := Vector3(side * (ring_radius + 1.6), 0, -1.8)
		var look := Basis(Vector3.UP, atan2(-pos.x, -pos.z))
		_crowd_add("Person_stand_mongol", Transform3D(look.scaled(Vector3.ONE * 1.12), pos), 1.36, true)


func _spawn_crowd() -> void:
	_crowd_mat = _shader("res://shaders/crowd.gdshader")
	for name in _crowd:
		if _mesh.has(name):
			_multimesh(_mesh[name], _crowd[name], _crowd_mat, true)


# ---------------------------------------------------------------- gers, flags, nature

func _build_gers() -> void:
	var spots := [[78, 35.0], [-78, 35.5], [97, 36.0], [-99, 34.5], [122, 35.0], [-121, 36.0], [146, 35.5], [-148, 35.0]]
	for s in spots:
		var th: float = deg_to_rad(s[0])
		var pos := Vector3(sin(th) * s[1], -0.03, -cos(th) * s[1])
		# door (Blender -Y = Godot +Z) faces the field
		var t := Transform3D(Basis(Vector3.UP, atan2(-pos.x, -pos.z)).scaled(Vector3.ONE * _rng.randf_range(0.92, 1.08)), pos)
		var mi := _place("Ger", t)
		_add_smoke(mi)


func _add_smoke(ger: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.amount = 18
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.position = Vector3(0.3, 3.95, -0.18)
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.35
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.22, 0.05, 0.12)
	pm.scale_min = 0.35
	pm.scale_max = 0.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 2.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.85, 0.85, 0.0))
	g.add_point(0.15, Color(0.82, 0.82, 0.82, 0.38))
	g.set_color(g.get_point_count() - 1, Color(0.9, 0.9, 0.92, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = _soft_dot()
	q.material = m
	p.draw_pass_1 = q
	ger.add_child(p)


func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func _build_flags() -> void:
	var cloth := _shader("res://shaders/flag.gdshader")
	cloth.set_shader_parameter("flag_tex", _tex("flag_mongolia.png"))
	for i in 7:
		var th := deg_to_rad(-60 + i * 20)
		var pos := Vector3(sin(th) * 30.5, -0.03, -cos(th) * 30.5)
		# the cloth points with the wind (WIND_DIR in common.gdshaderinc)
		var t := Transform3D(Basis(Vector3.UP, -0.55 + _rng.randf_range(-0.1, 0.1)), pos)
		var mi := _place("Flag", t)
		_override(mi, "FlagCloth", cloth)


func _build_scatter() -> void:
	if not FileAccess.file_exists(SCATTER_PATH):
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SCATTER_PATH))
	var tree_mat := _shader("res://shaders/foliage.gdshader")
	tree_mat.set_shader_parameter("sway", 0.08)
	var near := []
	var far := []
	for t in data.trees:
		var tr := Transform3D(Basis(Vector3.UP, t[4]).scaled(Vector3.ONE * t[3]), Vector3(t[0], t[1] - 0.2, t[2]))
		(near if Vector2(t[0], t[2]).length() < 320.0 else far).append([tr])
	_multimesh(_mesh["Larch"], near, tree_mat, true)
	_multimesh(_mesh["Larch_Far"], far, tree_mat, false)
	var rock_mat := _shader("res://shaders/foliage.gdshader")
	var rocks := {1: [], 2: [], 3: []}
	for r in data.rocks:
		var tr := Transform3D(Basis(Vector3.UP, r[4]).scaled(Vector3.ONE * r[3]), Vector3(r[0], r[1] - r[3] * 0.15, r[2]))
		rocks[int(r[5])].append([tr])
	for k in rocks:
		_multimesh(_mesh["Rock_%d" % k], rocks[k], rock_mat, true)
	var gers := []
	for g in data.gers:
		gers.append([Transform3D(Basis(Vector3.UP, g[4]).scaled(Vector3.ONE * g[3]), Vector3(g[0], g[1] - 0.05, g[2]))])
	_multimesh(_mesh["Ger"], gers, null, true)


func _build_eagles() -> void:
	for i in 3:
		var mat := _shader("res://shaders/eagle.gdshader")
		mat.set_shader_parameter("phase", i * 2.3)
		var e := MeshInstance3D.new()
		e.mesh = _mesh["Eagle"]
		e.material_override = mat
		e.scale = Vector3.ONE * 1.3
		e.set_meta("c", Vector3(_rng.randf_range(-40, 40), _rng.randf_range(38, 60), _rng.randf_range(-90, -40)))
		e.set_meta("r", _rng.randf_range(18, 35))
		e.set_meta("a", _rng.randf() * TAU)
		e.set_meta("speed", _rng.randf_range(0.08, 0.14) * (1 if i % 2 == 0 else -1))
		add_child(e)
		_eagles.append(e)


## Floating seeds / pollen catching the sunlight.
func _build_pollen() -> void:
	var p := GPUParticles3D.new()
	p.amount = 220
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.visibility_aabb = AABB(Vector3(-40, -2, -40), Vector3(80, 14, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 4, 30)
	pm.gravity = Vector3(0.25, -0.02, 0.15)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	p.process_material = pm
	p.position = Vector3(0, 3, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 0.95, 0.7)
	m.albedo_texture = _soft_dot()
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
