extends Node3D
## Builds the Naadam wrestling field when the scene starts:
## grass with a trampled wrestling circle, the Nine White Banners
## (Есөн хөлт цагаан туг), gers, grandstands with a cheering crowd,
## two zasuul heralds, Mongolian flags, mountains and clouds.
##
## Everything is made in code from simple shapes, so it's light and easy to
## change: tweak the numbers in the @export vars or in each build_ function.
## Call Field.cheer(1.0) (from arena.gd) to make the crowd jump.

@export var ring_radius := 6.0
@export var crowd_count := 1400
@export var grass_tufts := 9000
@export var seed_value := 7

var _crowd_mats: Array[ShaderMaterial] = []
var _hype := 0.0
var _rng := RandomNumberGenerator.new()

const DEEL_COLORS := [Color(0.66, 0.14, 0.14), Color(0.16, 0.3, 0.62), Color(0.85, 0.65, 0.2),
	Color(0.2, 0.45, 0.35), Color(0.42, 0.24, 0.48), Color(0.86, 0.84, 0.78), Color(0.78, 0.42, 0.18),
	Color(0.3, 0.5, 0.7), Color(0.55, 0.2, 0.3), Color(0.35, 0.3, 0.28)]


func _ready() -> void:
	_rng.seed = seed_value
	add_to_group("field")
	_build_ground()
	_build_grass_tufts()
	_build_banners()
	_build_gers()
	_build_stands()
	_build_zasuuls()
	_build_flags()
	_build_mountains()
	_build_clouds()


func _process(delta: float) -> void:
	_hype = maxf(0.15, _hype - delta * 0.6)
	for m in _crowd_mats:
		m.set_shader_parameter("hype", _hype)


## Make the crowd jump and cheer (0..1).
func cheer(amount := 1.0) -> void:
	_hype = maxf(_hype, amount)


# ---------------------------------------------------------------- helpers

func _mat(color: Color, rough := 0.8) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


func _cyl(top: float, bottom: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _sphere(r: float, h := -1.0, segs := 16) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0 if h < 0.0 else h
	s.radial_segments = segs
	s.rings = maxi(4, segs / 2)
	return s


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## Material that sways in the wind (tassels, flags, grass).
func _wind_mat(color: Color, strength: float, stripes := 0.0) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
uniform vec4 color : source_color;
uniform float strength = 0.1;
uniform float stripes = 0.0;
varying float h;
void vertex() {
	h = clamp(-VERTEX.y + 0.5, 0.0, 1.0);
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(TIME * 2.3 + wp.x * 0.7 + wp.z * 0.5) + 0.5 * sin(TIME * 4.1 + wp.y * 3.0);
	VERTEX.x += w * strength * h;
	VERTEX.z += cos(TIME * 1.7 + wp.x) * strength * 0.5 * h;
}
void fragment() {
	float s = stripes > 0.0 ? 0.9 + 0.1 * sin(UV.x * stripes * 6.283) : 1.0;
	ALBEDO = color.rgb * s;
	ROUGHNESS = 0.9;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("stripes", stripes)
	return m


# ---------------------------------------------------------------- ground

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(300, 300)
	plane.subdivide_width = 2
	plane.subdivide_depth = 2
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform float ring_radius = 6.0;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { return noise(p) * 0.5 + noise(p * 2.1) * 0.3 + noise(p * 4.3) * 0.2; }
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wp.xz;
	float n = fbm(p * 0.35);
	float fine = noise(p * 6.0);
	vec3 g1 = vec3(0.30, 0.55, 0.20);
	vec3 g2 = vec3(0.45, 0.62, 0.24);
	vec3 dry = vec3(0.62, 0.62, 0.32);
	vec3 col = mix(g1, g2, n);
	col = mix(col, dry, smoothstep(0.62, 0.8, fbm(p * 0.08 + 3.0)) * 0.6);
	col *= 0.88 + fine * 0.2;
	// the wrestling circle: grass trampled flat, dusty patches
	float r = length(p);
	float inside = 1.0 - smoothstep(ring_radius - 0.6, ring_radius + 0.3, r);
	vec3 trampled = mix(vec3(0.47, 0.55, 0.27), vec3(0.6, 0.52, 0.34), smoothstep(0.35, 0.75, fbm(p * 0.9)));
	col = mix(col, trampled * (0.92 + fine * 0.12), inside * 0.75);
	// faint chalk-free edge: a ring of darker, longer grass
	float edge = smoothstep(0.5, 0.0, abs(r - ring_radius - 0.2));
	col = mix(col, g1 * 0.8, edge * 0.5);
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = 0.95;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("ring_radius", ring_radius)
	_mesh(plane, m, Vector3(0, 0.002, 0))


func _build_grass_tufts() -> void:
	# a tuft = 3 crossed blades
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := PI * i / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.035
		var lean := Vector3(sin(a * 3.0), 0, cos(a * 2.0)) * 0.05
		st.set_uv(Vector2(0, 1)); st.add_vertex(-d)
		st.set_uv(Vector2(1, 1)); st.add_vertex(d)
		st.set_uv(Vector2(0.5, 0)); st.add_vertex(lean + Vector3(0, 0.2, 0))
	st.generate_normals()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = st.commit()
	mm.instance_count = grass_tufts
	for i in grass_tufts:
		var r := _rng.randf_range(ring_radius + 0.6, 28.0)
		var a := _rng.randf() * TAU
		var t := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * _rng.randf_range(0.6, 1.2)),
				Vector3(cos(a) * r, 0, sin(a) * r))
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, Color(0.36, 0.6, 0.22).lerp(Color(0.6, 0.7, 0.3), _rng.randf()))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled;
varying vec3 c;
void vertex() {
	c = COLOR.rgb;
	float h = VERTEX.y;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.x += sin(TIME * 2.0 + wp.x * 0.6 + wp.z * 0.4) * h * 0.25;
}
void fragment() { ALBEDO = pow(c * (0.85 + 0.3 * (1.0 - UV.y)), vec3(2.2)); ROUGHNESS = 0.95; }
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	mmi.material_override = m
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


# ---------------------------------------------------------------- Nine White Banners

## Есөн хөлт цагаан туг: white horsehair banners on tall poles with a
## trident top. They stand at the stadium during Naadam.
func _build_banners() -> void:
	var pole_mat := _mat(Color(0.45, 0.12, 0.08), 0.5)
	var gold := _mat(Color(0.95, 0.75, 0.25), 0.3)
	gold.metallic = 0.7
	var silver := _mat(Color(0.85, 0.85, 0.9), 0.25)
	silver.metallic = 0.8
	var hair := _wind_mat(Color(0.97, 0.96, 0.93), 0.12, 24.0)
	var base_mat := _mat(Color(0.9, 0.88, 0.82))
	for i in 9:
		var k := i - 4
		var x := k * 2.3
		var main := k == 0
		var h := 5.6 if main else 4.6
		var root := Node3D.new()
		root.position = Vector3(x, 0, -13.5 + absf(k) * 0.35)
		add_child(root)
		_mesh(_cyl(0.45, 0.55, 0.3, 12), base_mat, Vector3(0, 0.15, 0), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_cyl(0.055, 0.07, h, 10), pole_mat, Vector3(0, h * 0.5, 0), Vector3.ZERO, Vector3.ONE, root)
		var top := h
		# white horsehair tassel (the "sülde")
		var tassel := _cyl(0.09, 0.62 if main else 0.5, 1.5, 24)
		_mesh(tassel, hair, Vector3(0, top - 0.55, 0), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_cyl(0.12, 0.12, 0.08, 16), gold, Vector3(0, top + 0.22, 0), Vector3.ZERO, Vector3.ONE, root)
		var disk := TorusMesh.new()
		disk.inner_radius = 0.16
		disk.outer_radius = 0.22
		_mesh(disk, gold, Vector3(0, top + 0.42, 0), Vector3(PI / 2, 0, 0), Vector3.ONE, root)
		# trident (three-pronged spear top)
		_mesh(_cyl(0.0, 0.05, 0.42, 8), silver, Vector3(0, top + 0.78, 0), Vector3.ZERO, Vector3.ONE, root)
		for sx in [-1, 1]:
			_mesh(_cyl(0.0, 0.035, 0.3, 8), silver, Vector3(sx * 0.12, top + 0.68, 0), Vector3(0, 0, -sx * 0.25), Vector3.ONE, root)
		_mesh(_box(Vector3(0.28, 0.04, 0.04)), silver, Vector3(0, top + 0.52, 0), Vector3.ZERO, Vector3.ONE, root)


# ---------------------------------------------------------------- gers

func _build_gers() -> void:
	var felt := _mat(Color(0.95, 0.93, 0.88), 0.95)
	var orange := _mat(Color(0.88, 0.42, 0.12), 0.6)
	var blue := _mat(Color(0.15, 0.35, 0.75), 0.6)
	var rope := _mat(Color(0.35, 0.22, 0.12), 0.9)
	var spots := [Vector3(-24, 0, -22), Vector3(-31, 0, -9), Vector3(-29, 0, 6), Vector3(26, 0, -21),
		Vector3(32, 0, -7), Vector3(30, 0, 8), Vector3(-15, 0, -30), Vector3(14, 0, -31), Vector3(0, 0, -36)]
	for p in spots:
		var root := Node3D.new()
		root.position = p
		root.rotation.y = atan2(-p.x, -p.z) + PI        # door faces the field
		root.scale = Vector3.ONE * _rng.randf_range(0.9, 1.15)
		add_child(root)
		_mesh(_cyl(2.4, 2.4, 1.5, 28), felt, Vector3(0, 0.75, 0), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_cyl(0.4, 2.6, 1.15, 28), felt, Vector3(0, 2.07, 0), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_cyl(0.42, 0.42, 0.14, 16), orange, Vector3(0, 2.68, 0), Vector3.ZERO, Vector3.ONE, root)  # toono
		_mesh(_cyl(2.62, 2.62, 0.18, 28), blue, Vector3(0, 1.52, 0), Vector3.ZERO, Vector3.ONE, root)   # roof edge band
		for y in [0.35, 0.8, 1.25]:
			_mesh(_cyl(2.43, 2.43, 0.05, 28), rope, Vector3(0, y, 0), Vector3.ZERO, Vector3.ONE, root)
		# orange painted door with a frame
		_mesh(_box(Vector3(0.95, 1.25, 0.12)), orange, Vector3(0, 0.63, 2.38), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_box(Vector3(0.6, 0.06, 0.13)), blue, Vector3(0, 0.95, 2.43), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_box(Vector3(0.6, 0.06, 0.13)), blue, Vector3(0, 0.35, 2.43), Vector3.ZERO, Vector3.ONE, root)


# ---------------------------------------------------------------- stands + crowd

func _build_stands() -> void:
	var wood := _mat(Color(0.55, 0.38, 0.22), 0.9)
	var paint := _mat(Color(0.12, 0.3, 0.7), 0.7)
	var seats: Array[Transform3D] = []
	# grandstand: an arc behind the banners
	var tiers := 3
	for t in tiers:
		var r := 26.0 + t * 1.5
		var y := 0.35 + t * 0.45
		var segs := 26
		for s in segs:
			var a := lerpf(deg_to_rad(-62), deg_to_rad(62), (s + 0.5) / segs) - PI / 2
			var p := Vector3(cos(a) * r, y * 0.5, sin(a) * r)
			var seg_len := r * deg_to_rad(124) / segs + 0.05
			var bm := _mesh(_box(Vector3(seg_len, y, 1.3)), wood if t % 2 == 0 else paint, p)
			bm.rotation.y = -a - PI / 2
			for n in 3:
				var off := (n - 1) * seg_len / 3.0
				var tan := Vector3(-sin(a), 0, cos(a))
				var sp := Vector3(cos(a) * r, y, sin(a) * r) + tan * off
				seats.append(Transform3D(Basis(Vector3.UP, -a - PI / 2 + PI), sp))
	# people standing around the sides of the field
	for side in [-1, 1]:
		for i in 140:
			var a := _rng.randf_range(deg_to_rad(52), deg_to_rad(110))
			var r := _rng.randf_range(12.5, 16.5)
			var p := Vector3(side * sin(a) * r, 0, -cos(a) * r - 1.0)
			seats.append(Transform3D(Basis(Vector3.UP, atan2(p.x, p.z) + PI), p))
	seats.shuffle()
	_spawn_crowd(seats.slice(0, mini(crowd_count, seats.size())))


func _spawn_crowd(spots: Array) -> void:
	var count := spots.size()
	var body := _cyl(0.22, 0.3, 0.62, 8)
	var head := _sphere(0.16, -1.0, 10)
	var hat := _cyl(0.04, 0.2, 0.12, 8)
	var parts := [[body, 0.31, true], [head, 0.78, false], [hat, 0.95, true]]
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = part[0]
		mm.instance_count = count
		for i in count:
			var t: Transform3D = spots[i]
			var rng := RandomNumberGenerator.new()
			rng.seed = i * 7919
			var scl := rng.randf_range(0.85, 1.1)
			t = t.scaled_local(Vector3.ONE * scl)
			t.origin += Vector3.UP * float(part[1]) * scl
			mm.set_instance_transform(i, t)
			var c: Color = DEEL_COLORS[rng.randi() % DEEL_COLORS.size()]
			if part[0] == head:
				c = Color(0.82, 0.6, 0.42).lerp(Color(0.6, 0.4, 0.27), rng.randf())
			elif part[0] == hat:
				c = [Color(0.15, 0.12, 0.1), Color(0.8, 0.15, 0.1), Color(0.95, 0.8, 0.2), Color(0.2, 0.2, 0.45)][rng.randi() % 4]
				if rng.randf() < 0.45:
					t.origin.y -= 50.0                  # no hat
					mm.set_instance_transform(i, t)
			mm.set_instance_color(i, c)
			mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		var sh := Shader.new()
		sh.code = """
shader_type spatial;
uniform float hype = 0.15;
varying vec3 c;
void vertex() {
	c = COLOR.rgb;
	float ph = INSTANCE_CUSTOM.r * 6.283;
	float jump = max(0.0, sin(TIME * (6.0 + INSTANCE_CUSTOM.r * 4.0) + ph));
	VERTEX.y += jump * hype * 0.35 + sin(TIME * 1.3 + ph) * 0.02;
}
void fragment() { ALBEDO = pow(c, vec3(2.2)); ROUGHNESS = 0.85; }
"""
		var m := ShaderMaterial.new()
		m.shader = sh
		_crowd_mats.append(m)
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


# ---------------------------------------------------------------- zasuul heralds

## Each wrestler has a zasuul: in a long deel and a tall hat, he holds the
## wrestler's hat during the bout and sings his titles.
func _build_zasuuls() -> void:
	var colors := [Color(0.55, 0.12, 0.12), Color(0.15, 0.22, 0.55)]
	var skin := _mat(Color(0.78, 0.55, 0.38))
	var gold := _mat(Color(0.95, 0.75, 0.25), 0.4)
	var dark := _mat(Color(0.12, 0.1, 0.08))
	for i in 2:
		var side := -1 if i == 0 else 1
		var root := Node3D.new()
		root.position = Vector3(side * (ring_radius + 1.3), 0, -2.0)
		root.rotation.y = -side * PI / 2.5
		root.add_to_group("zasuul")
		add_child(root)
		var deel := _mat(colors[i], 0.6)
		_mesh(_cyl(0.24, 0.42, 1.35, 16), deel, Vector3(0, 0.68, 0), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_cyl(0.3, 0.3, 0.1, 16), gold, Vector3(0, 0.95, 0), Vector3.ZERO, Vector3.ONE, root)   # sash
		_mesh(_sphere(0.17), skin, Vector3(0, 1.55, 0), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_cyl(0.0, 0.2, 0.32, 12), deel, Vector3(0, 1.82, 0), Vector3.ZERO, Vector3.ONE, root)  # tall hat
		_mesh(_cyl(0.22, 0.22, 0.06, 12), dark, Vector3(0, 1.68, 0), Vector3.ZERO, Vector3.ONE, root)
		_mesh(_sphere(0.04), gold, Vector3(0, 2.0, 0), Vector3.ZERO, Vector3.ONE, root)
		# arm holding the wrestler's hat (шовгор малгай)
		_mesh(_cyl(0.07, 0.08, 0.55, 8), deel, Vector3(0.0, 1.15, -0.25), Vector3(PI / 2.6, 0, 0), Vector3.ONE, root)
		_mesh(_cyl(0.02, 0.16, 0.22, 10), _mat(Color(0.75, 0.1, 0.1) if i == 0 else Color(0.1, 0.25, 0.7)),
				Vector3(0.0, 1.32, -0.5), Vector3.ZERO, Vector3.ONE, root)


# ---------------------------------------------------------------- flags

func _build_flags() -> void:
	var pole := _mat(Color(0.85, 0.85, 0.85), 0.4)
	var red := _wind_mat(Color(0.77, 0.1, 0.14), 0.18)
	var blue := _wind_mat(Color(0.0, 0.3, 0.6), 0.18)
	for i in 7:
		var a := lerpf(deg_to_rad(-55), deg_to_rad(55), i / 6.0) - PI / 2
		var r := 30.5
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		_mesh(_cyl(0.05, 0.06, 7.0, 8), pole, p + Vector3(0, 3.5, 0))
		# Mongolian flag: red - blue - red (simplified, no Soyombo symbol)
		for k in 3:
			var stripe := _mesh(_box(Vector3(0.6, 1.2, 0.03)), red if k != 1 else blue, p + Vector3(0.36 + k * 0.6, 6.3, 0))
			stripe.rotation.y = 0.0


# ---------------------------------------------------------------- mountains + clouds

func _build_mountains() -> void:
	var rock := _mat(Color(0.42, 0.52, 0.5), 1.0)
	var green := _mat(Color(0.36, 0.52, 0.3), 1.0)
	var snow := _mat(Color(0.96, 0.97, 1.0), 0.6)
	# rolling green hills
	for i in 14:
		var a := TAU * i / 14.0 + _rng.randf() * 0.2
		var r := _rng.randf_range(55, 70)
		var h := _rng.randf_range(4, 9)
		_mesh(_sphere(1.0, -1.0, 20), green, Vector3(cos(a) * r, -h * 0.3, sin(a) * r), Vector3.ZERO,
				Vector3(_rng.randf_range(16, 26), h, _rng.randf_range(12, 18)))
	# mountains (like Bogd Khan mountain behind Ulaanbaatar)
	for i in 18:
		var a := TAU * i / 18.0 + _rng.randf() * 0.15
		var r := _rng.randf_range(95, 130)
		var h := _rng.randf_range(16, 38)
		var w := _rng.randf_range(22, 36)
		var p := Vector3(cos(a) * r, h * 0.5 - 1.0, sin(a) * r)
		_mesh(_cyl(0.0, w, h, 7), rock, p, Vector3(0, _rng.randf() * TAU, 0))
		if h > 26:
			var cap := h * 0.28
			_mesh(_cyl(0.0, w * 0.28 + 0.5, cap, 7), snow, Vector3(p.x, h - 1.0 - cap * 0.5 + 0.2, p.z), Vector3(0, _rng.randf() * TAU, 0))


func _build_clouds() -> void:
	var m := _mat(Color(1, 1, 1), 1.0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 1, 1)
	for i in 12:
		var a := _rng.randf_range(-PI, 0.2)
		var r := _rng.randf_range(80, 150)
		var c := Vector3(cos(a) * r, _rng.randf_range(38, 60), sin(a) * r)
		for k in 5:
			var s := _rng.randf_range(5, 10)
			_mesh(_sphere(1.0, -1.0, 12), m, c + Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-1, 2), _rng.randf_range(-4, 4)),
					Vector3.ZERO, Vector3(s * 1.6, s * 0.6, s))
