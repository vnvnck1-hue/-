class_name LobbyCampStage
extends Node3D
## Toy-camp lobby 3D scene: sky + hazy far valley (a painted backdrop card when res://art/lobby/backdrop.png exists,
## otherwise built from soft primitives), a grassy plateau with a big pine on the left, crystals and rocks on the
## right, and up front the trio (warrior / ranger / mage) around the campfire with the reward chest beside it.
## Owns its camera, lights and environment; Lobby only asks it for the chest's screen anchor.
## Lobby-only hero figures (LobbyHero) and every material here are local instances: nothing shared with battle
## models (Mats.shared / Mats.prop caches) is modified.

var cam: Camera3D
var env: Environment
var chest: ChestModel
var chest_anchor: Node3D        # just above the chest lid: the 보상 받기 pill hangs here
var heroes: Array = []
var _t := 0.0
var _rig: Node3D                # the whole camp: a barely-there sway, faces and chest stay put

const BASE_ASPECT := 720.0 / 1280.0
const LOOK := Vector3(0, 0.36, 0)
const FOV := 36.0               # horizontal, at 9:16
const SKY_COMPAT := 0.9         # Compatibility (web) sky energy, matched against Forward+ captures

func _ready() -> void:
	_environment()
	_camera()
	_rig = Node3D.new()
	add_child(_rig)
	_backdrop()
	_plateau()
	_props()
	_camp()
	_trio()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _process(delta: float) -> void:
	_t += delta
	_rig.rotation.y = sin(_t * 0.22) * 0.012

## Where the chest pill should hang, in the given control's coordinates (canvas_items stretch: the 3D viewport and
## the UI share the logical size, so the projection is used as is).
func chest_screen_pos() -> Vector2:
	if cam == null or not cam.is_inside_tree():
		return Vector2(-999, -999)
	return cam.unproject_position(chest_anchor.global_position)

# ---------------------------------------------------------------- environment / camera
func _environment() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color("5cc6f2")
	sm.sky_horizon_color = LobbyStyle.SKY_LOW
	sm.ground_horizon_color = LobbyStyle.SKY_LOW
	sm.ground_bottom_color = Color("9fd9b0")
	sm.sky_curve = 0.2
	sm.sun_angle_max = 0.0
	sm.use_debanding = true
	sky.sky_material = sm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c9e6ff")
	e.ambient_light_energy = 0.78
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_strength = 0.9
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.3
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.ssao_enabled = true
	e.ssao_radius = 0.6
	e.ssao_intensity = 1.1
	e.ssao_power = 1.2
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color("bfe8f8")
	e.fog_depth_begin = 18.0
	e.fog_depth_end = 70.0
	e.fog_depth_curve = 1.6
	e.fog_density = 0.3
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.12
	e.adjustment_contrast = 1.04
	WebLook.apply(e)
	if WebLook.compat():   # its background cut is tuned for a flat colour that glow blows out; this sky stays in range
		e.background_energy_multiplier = SKY_COMPAT
	we.environment = e
	env = e
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1d8")
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.5
	sun.shadow_blur = 1.8
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 22.0
	add_child(sun)
	sun.position = Vector3(-5, 10, 7)
	sun.look_at(Vector3(0.6, 0, -0.4), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("bfe2ff")
	fill.light_energy = 0.32
	add_child(fill)
	fill.position = Vector3(6, 3, 6)
	fill.look_at(Vector3.ZERO, Vector3.UP)

func _camera() -> void:
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = FOV
	cam.near = 0.1
	cam.far = 120.0
	add_child(cam)
	cam.position = Vector3(0, 2.6, 8.35)
	cam.look_at(LOOK, Vector3.UP)
	cam.current = true

## Taller-than-9:16 screens: the extra height opens above the party (sky), so the trio, fire and chest keep their
## distance to the bottom sheet (v_offset shifts the frustum without changing the angle). Wider screens keep the
## 9:16 vertical view instead and show more of the camp at the sides.
func _fit() -> void:
	var vs := get_viewport().get_visible_rect().size
	if vs.x <= 0.0:
		return
	var tall := vs.y / vs.x - 1.0 / BASE_ASPECT   # extra height, in screen widths
	if tall >= 0.0:
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.fov = FOV
		# KEEP_WIDTH: one screen width at the look distance d spans 2 d tan(fov/2)
		var d := cam.position.distance_to(LOOK)
		cam.v_offset = tall * 2.0 * d * tan(deg_to_rad(FOV) * 0.5) * 0.5 * 0.82
	else:
		cam.keep_aspect = Camera3D.KEEP_HEIGHT
		cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV) * 0.5) / BASE_ASPECT))
		cam.v_offset = 0.0

# ---------------------------------------------------------------- materials (lobby-local)
var _mat_cache := {}

func _m(c: Color, rough := 0.8) -> StandardMaterial3D:
	var key := "%s%.2f" % [c.to_html(), rough]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic_specular = 0.25
		m.rim_enabled = true
		m.rim = 0.2
		m.rim_tint = 0.6
		WebLook.unify(m)
		_mat_cache[key] = m
	return _mat_cache[key]

func _unlit(c: Color) -> StandardMaterial3D:
	var key := "u" + c.to_html()
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.disable_receive_shadows = true
		_mat_cache[key] = m
	return _mat_cache[key]

func _mi(p: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	p.add_child(mi)
	return mi

func _rb(p: Node3D, size: Vector3, c: Color, pos: Vector3, rot := Vector3.ZERO, e := 0.3) -> MeshInstance3D:
	return _mi(p, MarchProps.rbox_mesh(Vector3.ONE, e), _m(c), pos, size, rot)

func _ball(p: Node3D, r: float, c: Color, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	return _mi(p, MarchProps._sphere_mesh(1.0), _m(c), pos, scl * r)

func _cone(p: Node3D, rt: float, rb: float, h: float, c: Color, pos: Vector3, rot := Vector3.ZERO, seg := 16) -> MeshInstance3D:
	var r := maxf(rt, rb)
	return _mi(p, MarchProps._cyl_mesh(snappedf(rt / r, 0.01), snappedf(rb / r, 0.01), 1.0, seg), _m(c), pos, Vector3(r, h, r), rot)

# ---------------------------------------------------------------- far valley
func _backdrop() -> void:
	var tex := LobbyStyle.texture("backdrop")
	if tex:   # painted far layer: a big card behind the plateau, unlit and fog-free (its haze is painted in)
		var q := QuadMesh.new()
		var h := 34.0
		q.size = Vector2(h * tex.get_width() / tex.get_height(), h)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tex
		m.disable_fog = true
		m.disable_receive_shadows = true
		var mi := _mi(self, q, m, Vector3(0, 6.5, -30))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return
	var far := Node3D.new()
	add_child(far)
	# clouds: soft white puffs high up
	var cm := _unlit(Color("ffffff"))
	for c in [[Vector3(-9, 13.5, -34), 1.0], [Vector3(-2.5, 15.5, -40), 0.8], [Vector3(8, 12.5, -32), 1.1], [Vector3(13, 16, -40), 0.7]]:
		var n := Node3D.new()
		n.position = c[0]
		n.scale = Vector3.ONE * c[1]
		far.add_child(n)
		for b in [[Vector3(0, 0, 0), 2.0], [Vector3(1.8, -0.3, 0.2), 1.5], [Vector3(-1.9, -0.4, 0.1), 1.4], [Vector3(0.8, 0.9, -0.2), 1.3], [Vector3(-3.2, -0.8, 0), 0.9], [Vector3(3.3, -0.7, 0), 1.0]]:
			var mi := _mi(n, MarchProps._sphere_mesh(1.0), cm, b[0], Vector3(1.0, 0.72, 0.6) * b[1])
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# valley floor + river
	_rb(far, Vector3(80, 2, 40), Color("8fcf73"), Vector3(0, -3.2, -26), Vector3.ZERO, 0.2)
	var water := _mi(far, MarchProps._box_mesh(Vector3.ONE), MarchProps.water_mat(), Vector3(2, -2.15, -19), Vector3(60, 0.1, 5.5), Vector3(0, -0.12, 0))
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# far cliffs: layered plateaus, green tops over warm stone
	var cliffs := [[Vector3(-13, -1.0, -24), Vector3(12, 6.5, 8)], [Vector3(-4, -1.6, -31), Vector3(10, 6.5, 7)], [Vector3(12, -0.8, -27), Vector3(14, 7.5, 9)],
		[Vector3(4, -1.4, -36), Vector3(16, 8, 6)], [Vector3(-16, 0.5, -38), Vector3(14, 9, 7)], [Vector3(18, 0.5, -38), Vector3(12, 9.5, 7)]]
	for c in cliffs:
		var p: Vector3 = c[0]
		var s: Vector3 = c[1]
		_rb(far, s, Color("a59a7c"), p, Vector3(0, randf_range(-0.1, 0.1), 0), 0.22)
		_rb(far, Vector3(s.x * 1.02, 0.9, s.z * 1.02), Color("79c45a"), p + Vector3(0, s.y * 0.5, 0), Vector3.ZERO, 0.3)
		_rb(far, Vector3(s.x * 1.01, s.y * 0.22, s.z * 1.01), Color("6fb455"), p + Vector3(0, s.y * 0.36, 0), Vector3.ZERO, 0.3)
		for i in 7:
			var tp := p + Vector3(randf_range(-s.x, s.x) * 0.45, s.y * 0.5 + 0.6, randf_range(-s.z, s.z) * 0.3)
			_ball(far, randf_range(0.6, 1.0), Color("4fae4a"), tp + Vector3(0, 0.5, 0), Vector3(1, 1.2, 1))
	# waterfall off the left-centre cliff
	var fall := _mi(far, MarchProps._box_mesh(Vector3.ONE), _unlit(Color("bfeaf8")), Vector3(-3.2, 0.4, -27.4), Vector3(0.9, 4.6, 0.2))
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# arch bridge
	for i in 3:
		_rb(far, Vector3(1.4, 2.2, 1.1), Color("d9cdb6"), Vector3(-9.5 + i * 2.2, -0.8, -21), Vector3.ZERO, 0.25)
	_rb(far, Vector3(7.4, 0.6, 1.3), Color("e2d7c2"), Vector3(-7.3, 0.4, -21), Vector3.ZERO, 0.25)
	# castle on the right hill
	var cs := Node3D.new()
	cs.position = Vector3(5.5, 2.7, -36)
	cs.scale = Vector3.ONE * 0.9
	far.add_child(cs)
	_rb(cs, Vector3(4.2, 2.2, 2.0), Color("efe2c8"), Vector3(0, 1.1, 0), Vector3.ZERO, 0.15)
	for t in [[-2.1, 3.6, 0.65, Color("4f78d8")], [2.1, 3.2, 0.6, Color("e0566a")], [0.0, 4.6, 0.8, Color("4f78d8")], [-0.9, 3.0, 0.5, Color("e0566a")], [1.0, 3.9, 0.55, Color("4f78d8")]]:
		_cone(cs, t[2], t[2], t[1], Color("f3e7cf"), Vector3(t[0], t[1] * 0.5, 0.2), Vector3.ZERO, 14)
		_cone(cs, 0.0, t[2] * 1.3, t[2] * 2.4, t[3], Vector3(t[0], t[1] + t[2] * 1.2, 0.2), Vector3.ZERO, 14)

# ---------------------------------------------------------------- plateau
func _plateau() -> void:
	# dirt body + grass cap, front edge falls away under the bottom sheet
	_rb(_rig, Vector3(15, 2.2, 11), Color("b98a5a"), Vector3(0, -1.18, -0.6), Vector3.ZERO, 0.2)
	_rb(_rig, Vector3(15.2, 0.5, 11.2), Color("7fca4e"), Vector3(0, -0.18, -0.6), Vector3.ZERO, 0.35)
	# a lower ledge behind the camp, so the plateau reads as a rise over the valley
	_rb(_rig, Vector3(20, 3.0, 6), Color("b48a5e"), Vector3(-1, -2.6, -8.2), Vector3.ZERO, 0.22)
	_rb(_rig, Vector3(20.2, 0.5, 6.2), Color("86cc56"), Vector3(-1, -1.2, -8.2), Vector3.ZERO, 0.35)
	# soft lighter patch where the trio stands
	var patch := _mi(_rig, MarchProps._cyl_mesh(1.0, 1.0, 1.0, 40), _m(Color("98d860")), Vector3(0.1, 0.075, 0.55), Vector3(3.6, 0.02, 2.2))
	patch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# worn dirt ring around the fire
	var dirt := _mi(_rig, MarchProps._cyl_mesh(1.0, 1.0, 1.0, 32), _m(Color("8fc457")), Vector3(-0.6, 0.08, 1.85), Vector3(0.8, 0.02, 0.62))
	dirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------------------------------------------------------------- props
func _props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	# left: a big tiered pine, bushes behind, stumps in front
	_pine(Vector3(-3.15, 0.07, -0.9), 2.45)
	_pine(Vector3(-5.2, 0.07, -2.6), 1.9)
	_pine(Vector3(4.9, 0.07, -3.6), 1.6)
	for b in [[Vector3(-2.2, 0.07, -1.9), 0.75], [Vector3(-1.2, 0.07, -2.4), 0.6], [Vector3(-4.0, 0.07, 0.3), 0.7], [Vector3(2.7, 0.07, -2.3), 0.65], [Vector3(1.2, 0.07, -2.6), 0.55]]:
		_bush(b[0], b[1])
	_stump(Vector3(-2.75, 0.07, 1.15), 0.95)
	_stump(Vector3(2.95, 0.07, 1.0), 0.8)
	# right: purple / blue crystal cluster and rounded rocks
	_crystal_cluster(Vector3(2.65, 0.07, -0.55), 1.15)
	_crystal_cluster(Vector3(3.55, 0.07, 0.35), 0.7)
	for r in [[Vector3(2.15, 0.07, 0.1), 0.42], [Vector3(3.2, 0.07, -0.1), 0.55], [Vector3(-1.9, 0.07, 0.25), 0.3]]:
		_rock(r[0], r[1])
	# small life: daisies, a few red mushrooms, grass tufts
	for d in [Vector3(-2.2, 0.08, 1.9), Vector3(-1.4, 0.08, 2.6), Vector3(2.0, 0.08, 2.3), Vector3(1.0, 0.08, 2.9), Vector3(-3.4, 0.08, 1.9), Vector3(3.1, 0.08, 1.8), Vector3(-0.9, 0.08, -1.2)]:
		_daisy(d)
	for mm in [Vector3(-2.15, 0.07, 0.75), Vector3(-1.95, 0.07, 0.95), Vector3(3.5, 0.07, 1.25)]:
		_mushroom(mm, rng.randf_range(0.8, 1.1))
	for i in 26:
		var p := Vector3(rng.randf_range(-4.2, 4.2), 0.07, rng.randf_range(-1.6, 3.2))
		if absf(p.x + 0.6) < 1.1 and absf(p.z - 1.85) < 0.8:
			continue
		if absf(p.x) < 1.8 and absf(p.z - 0.35) < 0.6:
			continue
		_tuft(p, rng.randf_range(0.7, 1.2), rng)

func _pine(pos: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * s
	_rig.add_child(n)
	_cone(n, 0.09, 0.13, 0.7, Color("8a5a34"), Vector3(0, 0.35, 0), Vector3.ZERO, 12)
	var cols := [Color("2f8a42"), Color("3a9a48"), Color("47aa4e"), Color("57ba55")]
	for t in 4:
		var r := 0.62 - t * 0.12
		var y := 0.62 + t * 0.34
		var col: Color = cols[t]
		_cone(n, r * 0.22, r, 0.46, col, Vector3(0, y + 0.08, 0), Vector3.ZERO, 18)
		var lobes := 8 - t
		for i in lobes:
			var a := TAU * (i + t * 0.5) / lobes
			_ball(n, r * 0.32, col, Vector3(cos(a) * r * 0.84, y - 0.13, sin(a) * r * 0.84), Vector3(1, 0.62, 1))
	_ball(n, 0.12, cols[3].lightened(0.1), Vector3(0, 1.98, 0), Vector3(1, 1.5, 1))

func _bush(pos: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * s
	_rig.add_child(n)
	_ball(n, 0.5, Color("4aa84a"), Vector3(0, 0.38, 0))
	_ball(n, 0.38, Color("5cb854"), Vector3(0.42, 0.28, 0.12))
	_ball(n, 0.36, Color("3f9a44"), Vector3(-0.42, 0.26, 0.05))

func _stump(pos: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * s
	_rig.add_child(n)
	_cone(n, 0.3, 0.36, 0.42, Color("9a6438"), Vector3(0, 0.21, 0), Vector3.ZERO, 18)
	_cone(n, 0.29, 0.29, 0.03, Color("e2b77a"), Vector3(0, 0.43, 0), Vector3.ZERO, 18)
	_mi(n, MarchProps._torus_mesh(0.6, 1.0), _m(Color("c8955c")), Vector3(0, 0.445, 0), Vector3(0.18, 0.12, 0.18))
	for a in [0.4, 2.3, 4.2]:
		_cone(n, 0.04, 0.09, 0.28, Color("8a5a34"), Vector3(cos(a) * 0.33, 0.06, sin(a) * 0.33), Vector3.ZERO, 8)

func _crystal_cluster(pos: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * s
	_rig.add_child(n)
	_rb(n, Vector3(0.9, 0.3, 0.7), Color("9a97a8"), Vector3(0, 0.1, 0), Vector3.ZERO, 0.4)
	var defs := [[Vector3(0, 0.2, 0), 0.62, 0.0, Color("9a5ef0")], [Vector3(0.24, 0.15, 0.1), 0.4, -0.35, Color("b07cff")],
		[Vector3(-0.22, 0.15, 0.12), 0.36, 0.4, Color("7f8cff")], [Vector3(0.1, 0.12, -0.2), 0.3, -0.2, Color("8a6cf0")]]
	for d in defs:
		var c := Node3D.new()
		c.position = d[0]
		c.rotation = Vector3(0, 0.4, d[2])
		n.add_child(c)
		var h: float = d[1]
		var m := StandardMaterial3D.new()
		m.albedo_color = d[3]
		m.roughness = 0.18
		m.metallic_specular = 0.9
		m.emission_enabled = true
		m.emission = (d[3] as Color) * 0.28
		m.rim_enabled = true
		m.rim = 0.5
		_mi(c, MarchProps._cyl_mesh(1.0, 1.0, 1.0, 6), m, Vector3(0, h * 0.5, 0), Vector3(h * 0.22, h, h * 0.22))
		_mi(c, MarchProps._cyl_mesh(0.0, 1.0, 1.0, 6), m, Vector3(0, h + h * 0.17, 0), Vector3(h * 0.22, h * 0.34, h * 0.22))

func _rock(pos: Vector3, s: float) -> void:
	_rb(_rig, Vector3(1.0, 0.7, 0.85) * s, Color("a9a6b6"), pos + Vector3(0, 0.3 * s, 0), Vector3(0, s * 3.0, 0), 0.55)

func _daisy(pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos
	_rig.add_child(n)
	_cone(n, 0.012, 0.016, 0.14, Color("4fae4a"), Vector3(0, 0.07, 0), Vector3.ZERO, 6)
	for i in 6:
		var a := TAU * i / 6.0
		_ball(n, 0.05, Color("fffdf4"), Vector3(cos(a) * 0.06, 0.15, sin(a) * 0.06), Vector3(1, 0.35, 1))
	_ball(n, 0.035, Color("ffcf2a"), Vector3(0, 0.165, 0))

func _mushroom(pos: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * s
	_rig.add_child(n)
	_cone(n, 0.04, 0.05, 0.14, Color("f6ecd8"), Vector3(0, 0.07, 0), Vector3.ZERO, 10)
	_mi(n, MarchProps._sphere_mesh(1.0), _m(Color("e2412c")), Vector3(0, 0.15, 0), Vector3(0.12, 0.08, 0.12))
	for p in [Vector3(0.05, 0.2, 0.06), Vector3(-0.05, 0.19, 0.05), Vector3(0.0, 0.215, -0.04)]:
		_ball(n, 0.018, Color.WHITE, p)

func _tuft(pos: Vector3, s: float, rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * s
	n.rotation.y = rng.randf() * TAU
	_rig.add_child(n)
	var c := Color("5fb846") if rng.randf() < 0.5 else Color("6cc24a")
	for i in 4:
		var a := TAU * i / 4.0
		var blade := _cone(n, 0.0, 0.035, 0.2, c, Vector3(cos(a) * 0.04, 0.09, sin(a) * 0.04), Vector3(sin(a) * 0.35, 0, -cos(a) * 0.35), 5)
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# ---------------------------------------------------------------- campfire + chest
func _camp() -> void:
	var fire := Node3D.new()
	fire.position = Vector3(-0.6, 0.08, 1.85)
	_rig.add_child(fire)
	for i in 9:
		var a := TAU * i / 9.0
		_rb(fire, Vector3(0.27, 0.19, 0.22), Color("a7a3b2") if i % 2 == 0 else Color("bdb9c6"), Vector3(cos(a) * 0.48, 0.07, sin(a) * 0.4), Vector3(0, -a, 0), 0.45)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		_cone(fire, 0.06, 0.07, 0.62, Color("8a5434"), Vector3(cos(a) * 0.1, 0.12, sin(a) * 0.1), Vector3(1.15, -a, 0), 10)
	var flame := Node3D.new()
	flame.position = Vector3(0, 0.14, 0)
	fire.add_child(flame)
	# three soft teardrop layers (round bottom + pointed top), unlit so the colours stay warm instead of clipping
	for f in [[Vector3(0, 0, 0), 0.2, 0.44, Color("ff7424")], [Vector3(0.02, 0.0, 0.09), 0.14, 0.32, Color("ffa22e")], [Vector3(0.0, 0.0, 0.16), 0.085, 0.2, Color("ffe066")]]:
		var r: float = f[1]
		var col: Color = f[3]
		var b := _mi(flame, MarchProps._sphere_mesh(1.0), _unlit(col), f[0] + Vector3(0, r * 0.75, 0), Vector3(r, r * 0.85, r))
		var t := _mi(flame, MarchProps._cyl_mesh(0.0, 1.0, 1.0, 20), _unlit(col), f[0] + Vector3(0, r * 0.75 + f[2] * 0.5, 0), Vector3(r * 0.98, f[2], r * 0.98))
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := flame.create_tween().set_loops()
	tw.tween_property(flame, "scale", Vector3(1.08, 0.9, 1.08), 0.16).set_trans(Tween.TRANS_SINE)
	tw.tween_property(flame, "scale", Vector3(0.94, 1.1, 0.94), 0.2).set_trans(Tween.TRANS_SINE)
	tw.tween_property(flame, "scale", Vector3(1.02, 0.97, 1.02), 0.14).set_trans(Tween.TRANS_SINE)
	var l := OmniLight3D.new()
	l.light_color = Color("ffa04a")
	l.light_energy = 1.3
	l.omni_range = 3.0
	l.omni_attenuation = 1.3
	l.position = Vector3(0, 0.7, 0.1)
	fire.add_child(l)
	var lt := l.create_tween().set_loops()
	lt.tween_property(l, "light_energy", 1.55, 0.18)
	lt.tween_property(l, "light_energy", 1.15, 0.22)
	var sparks := CPUParticles3D.new()
	sparks.amount = 7
	sparks.lifetime = 1.4
	sparks.position = Vector3(0, 0.5, 0)
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	sparks.emission_sphere_radius = 0.12
	sparks.direction = Vector3.UP
	sparks.spread = 18.0
	sparks.gravity = Vector3(0, 0.25, 0)
	sparks.initial_velocity_min = 0.35
	sparks.initial_velocity_max = 0.6
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.0
	var sm := SphereMesh.new()
	sm.radius = 0.022
	sm.height = 0.044
	sm.radial_segments = 6
	sm.rings = 3
	sparks.mesh = sm
	sparks.material_override = MarchProps.glow_mat(Color("ffc24a"), 1.8)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	sparks.color_ramp = g
	fire.add_child(sparks)

	# reward chest: brown wood, grey bands, a gold lock (recoloured on its own per-instance materials)
	chest = ChestModel.new(0)
	chest.position = Vector3(1.55, 0.08, 1.8)
	chest.rotation.y = -0.32
	chest.scale = Vector3.ONE * 0.86
	_rig.add_child(chest)
	chest._mats["body"].albedo_color = Color("a3612f")
	chest._mats["lid"].albedo_color = Color("b46c35")
	chest._mats["trim"].albedo_color = Color("8f939e")
	chest._mats["gem"].albedo_color = Color("e9ad35")
	chest._mats["gem"].roughness = 0.45
	chest._mats["dark"].albedo_color = Color("5e3518")
	chest._gem_light.light_energy = 0.0
	chest_anchor = Node3D.new()
	chest_anchor.position = Vector3(0, 0.98, 0)
	chest.add_child(chest_anchor)

# ---------------------------------------------------------------- the trio
func _trio() -> void:
	var spots := {"warrior": [Vector3(-1.4, 0.08, 0.3), 0.3], "ranger": [Vector3(0.0, 0.08, 0.6), 0.0], "mage": [Vector3(1.38, 0.08, 0.25), -0.28]}
	for cls in ["warrior", "ranger", "mage"]:
		var m := LobbyHero.new()
		m.build_lobby(cls)
		_rig.add_child(m)
		m.position = spots[cls][0]
		m.rotation.y = PI + spots[cls][1]
		m.scale = Vector3.ONE * 1.78
		heroes.append(m)

## Lobby-only hero figure: the battle UnitModel's skeleton, motion and per-instance toy materials, with a bigger
## round head, a face (eyes with catch-lights, cheeks, brows) and each hero's signature kit from the concept.
class LobbyHero extends UnitModel:
	var _idle := 0.0

	func build_lobby(cls: String) -> LobbyHero:
		kind = cls
		team = Defs.TEAM_HERO
		_phase = randf() * TAU
		squash = _node(self, Vector3.ZERO)
		torso = _node(squash, Vector3.ZERO)
		match cls:
			"warrior": _warrior()
			"ranger": _ranger()
			"mage": _mage()
		_arm_busy = true   # arms hold their pose; _process adds a small idle sway of its own
		_wiggle(head, Vector3.UP, 0.06, 0.8)
		return self

	func _process(delta: float) -> void:
		super(delta)
		_idle += delta
		arm_l.rotation.z = _arm_l_base.z + sin(_idle * 1.6 + _phase) * 0.03
		arm_r.rotation.z = _arm_r_base.z - sin(_idle * 1.6 + _phase + 0.6) * 0.03

	var _arm_l_base := Vector3.ZERO
	var _arm_r_base := Vector3.ZERO

	## Big-head chibi: boots, short legs, round body, belt with buckle, head ~0.3, stubby arms. Faces -Z.
	func _toy(body: Color, legs: Color, boots: Color, gloves: Color, sleeve: Color, head_r := 0.29, body_r := 0.205) -> void:
		leg_l = _node(torso, Vector3(-0.085, 0.15, 0))
		leg_r = _node(torso, Vector3(0.085, 0.15, 0))
		for lg in [leg_l, leg_r]:
			_capsule(lg, 0.062, 0.18, legs, Vector3(0, -0.04, 0))
			_sphere(lg, 0.085, boots, Vector3(0, -0.11, -0.025), Vector3(1.0, 0.75, 1.3))
			_cyl(lg, 0.078, 0.07, 0.07, boots.lightened(0.08), Vector3(0, -0.04, 0))
		_sphere(torso, body_r, body, Vector3(0, 0.31, 0), Vector3(1.0, 0.96, 0.86))
		_torus(torso, body_r * 0.84, body_r * 1.03, Color("6b4428"), Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1, 1.4, 0.88))
		_box(torso, Vector3(0.075, 0.06, 0.03), Color("f2c14a"), Vector3(0, 0.24, -body_r * 0.9))
		head = _node(torso, Vector3(0, 0.31 + body_r * 0.72 + head_r * 0.78, 0))
		_sphere(head, head_r, SKIN, Vector3.ZERO, Vector3(1.04, 0.97, 1.0))
		_ears(head_r)
		_face(head_r)
		arm_l = _node(torso, Vector3(-body_r * 0.98, 0.4, 0))
		arm_r = _node(torso, Vector3(body_r * 0.98, 0.4, 0))
		_capsule(arm_l, 0.056, 0.19, sleeve, Vector3(-0.025, -0.075, 0), Vector3(0, 0, -0.38))
		_capsule(arm_r, 0.056, 0.19, sleeve, Vector3(0.025, -0.075, 0), Vector3(0, 0, 0.38))
		_sphere(arm_l, 0.07, gloves, Vector3(-0.065, -0.16, 0))
		_sphere(arm_r, 0.07, gloves, Vector3(0.065, -0.16, 0))
		weapon = _node(arm_r, Vector3(0.065, -0.16, 0))

	func _ears(hr: float) -> void:
		_sphere(head, hr * 0.2, SKIN.darkened(0.04), Vector3(-hr * 0.98, -hr * 0.05, 0.0), Vector3(0.6, 1, 0.8))
		_sphere(head, hr * 0.2, SKIN.darkened(0.04), Vector3(hr * 0.98, -hr * 0.05, 0.0), Vector3(0.6, 1, 0.8))

	func _face(hr: float) -> void:
		var eye := Color("231816")
		for sx in [-1.0, 1.0]:
			_sphere(head, hr * 0.16, eye, Vector3(sx * hr * 0.37, -hr * 0.04, -hr * 0.89), Vector3(0.82, 1.2, 0.5))
			var hl := _sphere(head, hr * 0.055, Color.WHITE, Vector3(sx * hr * 0.37 + hr * 0.045, hr * 0.07, -hr * 0.99))
			hl.material_override = _glow_mat(Color.WHITE, 1.0)
			var ck := _sphere(head, hr * 0.12, Color("f58c86"), Vector3(sx * hr * 0.56, -hr * 0.3, -hr * 0.76), Vector3(1.2, 0.7, 0.4))
			(ck.material_override as StandardMaterial3D).albedo_color = Color("f7978c")
		_sphere(head, hr * 0.085, SKIN.darkened(0.08), Vector3(0, -hr * 0.2, -hr * 0.98), Vector3(1.1, 0.8, 0.7))

	func _lobby_brows(hr: float, col: Color, tilt := 0.0) -> void:
		for sx in [-1.0, 1.0]:
			_capsule(head, hr * 0.045, hr * 0.32, col, Vector3(sx * hr * 0.34, hr * 0.22, -hr * 0.9), Vector3(0, 0, PI * 0.5 + sx * tilt))

	# -------------------------------------------------------------- warrior
	func _warrior() -> void:
		var hr := 0.29
		_toy(Color("ee8a2e"), Color("6b4a2f"), Color("7a4a2a"), Color("8a5a34"), Color("4e6a8a"), hr, 0.215)
		_sphere(torso, 0.13, Color("d06f20"), Vector3(0, 0.15, 0), Vector3(1.55, 0.6, 1.25))   # tunic hem
		_sphere(torso, 0.08, Color("9aa3b4"), Vector3(-0.2, 0.44, 0), Vector3(1.1, 0.8, 1.1))  # shoulder plates
		_sphere(torso, 0.08, Color("9aa3b4"), Vector3(0.2, 0.44, 0), Vector3(1.1, 0.8, 1.1))
		# white beard + mustache and bushy brows
		var white := Color("f6f2ea")
		_sphere(head, hr * 0.72, white, Vector3(0, -hr * 0.52, -hr * 0.46), Vector3(1.18, 0.95, 0.72))
		_sphere(head, hr * 0.5, white, Vector3(0, -hr * 0.9, -hr * 0.3), Vector3(1.0, 0.9, 0.7))
		_capsule(head, hr * 0.13, hr * 0.62, white, Vector3(-hr * 0.2, -hr * 0.28, -hr * 0.9), Vector3(0, 0, PI * 0.5 + 0.35))
		_capsule(head, hr * 0.13, hr * 0.62, white, Vector3(hr * 0.2, -hr * 0.28, -hr * 0.9), Vector3(0, 0, PI * 0.5 - 0.35))
		_sphere(head, hr * 0.1, SKIN.darkened(0.06), Vector3(0, -hr * 0.16, -hr * 1.02))
		_lobby_brows(hr, white, 0.15)
		# horned steel helmet
		var steel := Color("b8c0cc")
		_hemi(head, hr * 1.08, steel, Vector3(0, hr * 0.12, 0), Vector3(1.0, 1.0, 1.0))
		_torus(head, hr * 0.98, hr * 1.14, Color("9aa3b2"), Vector3(0, hr * 0.14, 0), Vector3.ZERO, Vector3(1, 1.5, 1))
		for sx in [-1.0, 1.0]:
			var horn := _node(head, Vector3(sx * hr * 0.92, hr * 0.52, 0))
			horn.rotation = Vector3(0, 0, -sx * 0.95)
			_cyl(horn, hr * 0.13, hr * 0.17, hr * 0.42, Color("fff3dc"), Vector3(0, hr * 0.2, 0))
			_cyl(horn, 0.0, hr * 0.13, hr * 0.5, Color("fff3dc"), Vector3(-sx * hr * 0.1, hr * 0.62, 0), Vector3(0, 0, sx * 0.55))
		# short broad sword raised in the right hand
		arm_r.rotation = Vector3(-0.55, 0, 0.75)
		var sw := _node(weapon, Vector3.ZERO)
		sw.rotation = Vector3(0.55, 0, -0.55)
		_capsule(sw, 0.03, 0.12, Color("6b4a2f"), Vector3(0, 0.0, 0))
		_box(sw, Vector3(0.2, 0.05, 0.06), Color("f2b632"), Vector3(0, 0.07, 0))
		_box(sw, Vector3(0.12, 0.42, 0.035), Color("e6edf5"), Vector3(0, 0.3, 0))
		_box(sw, Vector3(0.04, 0.4, 0.04), Color("c9d2de"), Vector3(0, 0.3, 0))
		_cyl(sw, 0.0, 0.085, 0.12, Color("e6edf5"), Vector3(0, 0.57, 0), Vector3.ZERO, Vector3(1, 1, 0.3))
		# round wooden shield on the left arm, facing out
		arm_l.rotation = Vector3(-0.5, 0, -0.15)
		var sh := _node(arm_l, Vector3(-0.06, -0.15, -0.09))
		sh.rotation = Vector3(PI * 0.5 + 0.5, 0, 0)
		_cyl(sh, 0.2, 0.2, 0.05, Color("a8693a"), Vector3.ZERO)
		_torus(sh, 0.18, 0.225, Color("9aa3b2"), Vector3(0, 0.0, 0), Vector3.ZERO, Vector3(1, 1.6, 1))
		_sphere(sh, 0.07, Color("c8cfd8"), Vector3(0, -0.035, 0), Vector3(1, 0.6, 1))
		for a in 6:
			var ang := TAU * a / 6.0
			_sphere(sh, 0.018, Color("c8cfd8"), Vector3(cos(ang) * 0.15, -0.03, sin(ang) * 0.15))
		_arm_l_base = arm_l.rotation
		_arm_r_base = arm_r.rotation

	# -------------------------------------------------------------- ranger
	func _ranger() -> void:
		var hr := 0.3
		var pink := Color("ff74b0")
		_toy(Color("5bb04c"), Color("7a5a3a"), Color("8a5a34"), Color("8a5a34"), Color("5bb04c").darkened(0.06), hr, 0.19)
		_sphere(torso, 0.12, Color("4c9a40"), Vector3(0, 0.15, 0), Vector3(1.55, 0.6, 1.25))   # tunic skirt
		_capsule(torso, 0.022, 0.5, Color("6b4428"), Vector3(0, 0.33, -0.01), Vector3(0, 0, 0.75), Vector3(1, 1, 1))   # quiver strap
		# pink hair: cap, side locks, swept bangs, top bun + ponytail
		_sphere(head, hr * 1.06, pink, Vector3(0, hr * 0.12, hr * 0.1), Vector3(1.03, 0.98, 1.0))
		_sphere(head, hr * 0.42, pink, Vector3(-hr * 0.82, -hr * 0.2, -hr * 0.18), Vector3(0.7, 1.1, 0.8))
		_sphere(head, hr * 0.42, pink, Vector3(hr * 0.82, -hr * 0.2, -hr * 0.18), Vector3(0.7, 1.1, 0.8))
		_sphere(head, hr * 0.55, pink.lightened(0.06), Vector3(-hr * 0.28, hr * 0.5, -hr * 0.62), Vector3(1.25, 0.6, 0.7))
		_sphere(head, hr * 0.42, pink.lightened(0.06), Vector3(hr * 0.38, hr * 0.56, -hr * 0.6), Vector3(1.1, 0.55, 0.7))
		_sphere(head, hr * 0.42, pink.darkened(0.04), Vector3(0, hr * 1.02, hr * 0.15))
		var tail := _node(head, Vector3(0, hr * 0.9, hr * 0.55))
		_capsule(tail, hr * 0.24, hr * 0.9, pink.darkened(0.05), Vector3(0, -hr * 0.2, hr * 0.12), Vector3(0.6, 0, 0))
		_wiggle(tail, Vector3(1, 0, 0), 0.08, 2.0)
		_lobby_brows(hr, pink.darkened(0.25), 0.08)
		# quiver on the back with green fletching
		var q := _node(torso, Vector3(0.1, 0.42, 0.2))
		q.rotation = Vector3(0.25, 0, -0.45)
		_cyl(q, 0.065, 0.055, 0.34, Color("8a5a2b"), Vector3.ZERO)
		_torus(q, 0.05, 0.075, Color("6b4428"), Vector3(0, 0.15, 0), Vector3.ZERO, Vector3(1, 1.2, 1))
		for i in 3:
			var off := Vector3((i - 1) * 0.03, 0.22, (i % 2) * 0.02)
			_capsule(q, 0.008, 0.16, Color("d9c3a0"), off)
			_cyl(q, 0.0, 0.03, 0.08, Color("3fa84a"), off + Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 1, 0.35))
		# bow held across the body (left hand), an arrow nocked
		arm_l.rotation = Vector3(-0.7, 0.2, -0.2)
		arm_r.rotation = Vector3(-0.8, -0.3, 0.3)
		# the bow sits on the torso at the left hand (so the arm sway doesn't swing it): an arc in the bow's XY
		# plane (faces the camera), bellied outwards (-x), an arrow nocked across it
		var bow := _node(torso, Vector3(-0.2, 0.3, -0.2))
		bow.rotation = Vector3(0, 0, -0.35)
		var pts: Array = []
		for i in 7:
			var a := lerpf(-1.15, 1.15, i / 6.0)
			pts.append(Vector3(0.2 - cos(a) * 0.27, sin(a) * 0.27, 0))
		for i in 6:
			_seg(bow, pts[i], pts[i + 1], 0.022 if i in [0, 5] else 0.03, Color("a0662f"))
		_seg(bow, pts[0], pts[6], 0.006, Color("f6ecd8"))   # string
		_capsule(bow, 0.038, 0.1, Color("6b4428"), Vector3(-0.07, 0, 0))   # grip
		_seg(bow, Vector3(0.12, 0.0, -0.02), Vector3(-0.2, 0.0, -0.02), 0.011, Color("d9c3a0"))   # arrow
		_cyl(bow, 0.0, 0.03, 0.07, Color("c9ced8"), Vector3(-0.23, 0, -0.02), Vector3(0, 0, PI * 0.5))
		_arm_l_base = arm_l.rotation
		_arm_r_base = arm_r.rotation

	# -------------------------------------------------------------- mage
	func _mage() -> void:
		var hr := 0.28
		var robe := Color("3f6fe0")
		_toy(robe, robe.darkened(0.3), Color("6b4428"), SKIN, robe.lightened(0.04), hr, 0.205)
		_cyl(torso, 0.16, 0.27, 0.32, robe, Vector3(0, 0.2, 0))   # robe skirt
		_torus(torso, 0.14, 0.2, robe.darkened(0.12), Vector3(0, 0.47, 0), Vector3.ZERO, Vector3(1, 1.4, 1))   # hood collar
		_box(torso, Vector3(0.1, 0.11, 0.06), Color("8a5a34"), Vector3(0.17, 0.2, -0.13), Vector3(0, 0.6, 0))   # satchel
		# brown hair under the brim
		var hair := Color("7a4a2a")
		_sphere(head, hr * 1.02, hair, Vector3(0, hr * 0.08, hr * 0.14), Vector3(1.04, 0.95, 1.0))
		_sphere(head, hr * 0.5, hair, Vector3(0, hr * 0.42, -hr * 0.62), Vector3(1.6, 0.55, 0.7))
		_lobby_brows(hr, hair.darkened(0.15), 0.0)
		# wide purple witch hat with a gold band, its tip bent back
		var purple := Color("7d42d6")
		_cyl(head, hr * 1.55, hr * 1.6, hr * 0.12, purple.darkened(0.08), Vector3(0, hr * 0.62, 0))
		_cyl(head, hr * 0.58, hr * 0.92, hr * 0.85, purple, Vector3(0, hr * 1.1, hr * 0.02))
		_cyl(head, hr * 0.93, hr * 0.96, hr * 0.2, Color("f2b632"), Vector3(0, hr * 0.8, hr * 0.02))
		var tip := _node(head, Vector3(0, hr * 1.5, hr * 0.06))
		tip.rotation = Vector3(0.5, 0, 0.12)
		_cyl(tip, 0.0, hr * 0.6, hr * 1.0, purple.lightened(0.05), Vector3(0, hr * 0.45, 0))
		_wiggle(tip, Vector3(0, 0, 1), 0.05, 1.4)
		# crystal staff in the left hand (screen right)
		arm_l.rotation = Vector3(-0.3, 0, -0.55)
		arm_r.rotation = Vector3(-0.2, 0, 0.3)
		var st := _node(arm_l, Vector3(-0.065, -0.16, 0))
		st.rotation = Vector3(0.3, 0, 0.5)
		_capsule(st, 0.026, 0.95, Color("8a5434"), Vector3(0, 0.18, 0))
		_torus(st, 0.03, 0.06, Color("f2b632"), Vector3(0, 0.62, 0))
		var gem := MeshInstance3D.new()
		gem.mesh = _sphere_mesh(0.09, 8, 4)
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color("8fe3ff")
		gm.roughness = 0.1
		gm.metallic_specular = 1.0
		gm.emission_enabled = true
		gm.emission = Color("5ec8ff") * 0.55
		gm.rim_enabled = true
		gm.rim = 0.6
		gem.material_override = gm
		gem.position = Vector3(0, 0.76, 0)
		gem.scale = Vector3(0.85, 1.55, 0.85)
		st.add_child(gem)
		_spin(gem, 0.8)
		_arm_l_base = arm_l.rotation
		_arm_r_base = arm_r.rotation
