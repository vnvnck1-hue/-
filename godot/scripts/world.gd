class_name World
extends Node3D
## Builds the forest diorama: lighting, post FX, the 6x8 board, rails and props.

const COLS := 6
const ROWS := 8
const TILE := 1.0
const TILE_A := Color("86cf45")
const TILE_B := Color("74c03a")
const RAIL := Color("f0a040")
const GRASS := Color("6dbe45")
const DIRT := Color("b77b45")
const WATER := Color("63c5ea")

var overlays := {}          # Vector2i -> MeshInstance3D
var overlay_mats := {}      # Vector2i -> StandardMaterial3D
var rng := RandomNumberGenerator.new()
var _t := 0.0
var deploy_glow := 0.0
var env: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D

var dim_cine := 0.0    # ultimate cinematics
var dim_focus := 0.0   # hover / drag focus on a hero (lighter)
var dim_drag := 0.0    # gear drag stage (ultimate-like dark stage around the heroes)

func set_cine_dim(v: float) -> void:
	dim_cine = v
	_apply_dims()

func set_focus_dim(v: float) -> void:
	dim_focus = v
	_apply_dims()

func set_drag_dim(v: float) -> void:
	dim_drag = v
	_apply_dims()

func _apply_dims() -> void:
	set_dim(maxf(maxf(dim_cine, dim_focus), dim_drag))

## Stage dimming: 0 = normal daylight, 1 = dark stage (unshaded VFX stay bright).
func set_dim(k: float) -> void:
	sun.light_energy = lerpf(1.25, 0.12, k)
	fill.light_energy = lerpf(0.28, 0.04, k)
	env.ambient_light_energy = lerpf(0.62, 0.1, k)
	env.background_color = Color("8fd0f0").lerp(Color("141026"), k)
	env.adjustment_saturation = lerpf(1.3, 0.85, k)
	env.glow_intensity = WebLook.glow(lerpf(0.5, 0.65, k))

static func tile_pos(c: int, r: int) -> Vector3:
	return Vector3((c - 2.5) * TILE, 0.0, (3.5 - r) * TILE)

static func pos_to_tile(p: Vector3) -> Vector2i:
	var c := roundi(p.x / TILE + 2.5)
	var r := roundi(3.5 - p.z / TILE)
	return Vector2i(c, r)

static func in_board(t: Vector2i) -> bool:
	return t.x >= 0 and t.x < COLS and t.y >= 0 and t.y < ROWS

func build() -> void:
	rng.seed = 7
	_env()
	_board()
	_terrain()
	_props()

# ---------------------------------------------------------------- env / light
func _env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("8fd0f0")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b3bdff")
	e.ambient_light_energy = 0.62
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.98
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.15
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.ssao_enabled = true
	e.ssao_radius = 0.5
	e.ssao_intensity = 1.6
	e.ssao_power = 1.2
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.3
	e.adjustment_contrast = 1.1
	WebLook.apply(e)
	we.environment = e
	env = e
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color("fff1d6")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.62
	sun.shadow_blur = 1.4
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	sun.position = Vector3(-6, 12, -4)
	sun.look_at(Vector3(1.5, 0, 2.5), Vector3.UP)

	# cool rim/fill from the opposite side
	fill = DirectionalLight3D.new()
	fill.light_color = Color("a8c8ff")
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	add_child(fill)
	fill.position = Vector3(6, 4, 8)
	fill.look_at(Vector3.ZERO, Vector3.UP)

# ---------------------------------------------------------------- helpers
func _box(size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = Mats.prop(color)
	mi.position = pos
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	return mi

func _sphere(r: float, color: Color, pos: Vector3, scl := Vector3.ONE, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 10
	mi.mesh = s
	mi.material_override = Mats.prop(color)
	mi.position = pos
	mi.scale = scl
	(parent if parent else self).add_child(mi)
	return mi

func _cyl(rt: float, rb: float, h: float, color: Color, pos: Vector3, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = rt
	c.bottom_radius = rb
	c.height = h
	c.radial_segments = 20
	mi.mesh = c
	mi.material_override = Mats.prop(color)
	mi.position = pos
	mi.rotation = rot
	(parent if parent else self).add_child(mi)
	return mi

## Rounded "toy block": box body + slightly larger grass lip on top.
func _block(size: Vector3, pos: Vector3, top := GRASS, side := DIRT) -> void:
	_box(size, side, pos + Vector3(0, size.y * 0.5, 0))
	_box(Vector3(size.x + 0.08, 0.14, size.z + 0.08), top, pos + Vector3(0, size.y + 0.02, 0))

# ---------------------------------------------------------------- board
func _board() -> void:
	# slab
	_box(Vector3(COLS * TILE + 0.3, 0.4, ROWS * TILE + 0.3), Color("7a5a3a"), Vector3(0, -0.3, 0))
	for r in ROWS:
		for c in COLS:
			var p := tile_pos(c, r)
			var col := TILE_A if (c + r) % 2 == 0 else TILE_B
			if r >= 6:
				col = col.lerp(Color("e8c060"), 0.22)   # enemy spawn rows: warmer
			elif r >= 4:
				col = col.lerp(Color("c8d860"), 0.08)
			_box(Vector3(TILE * 0.985, 0.2, TILE * 0.985), col, p + Vector3(0, -0.1, 0))
			# overlay for highlights
			var ov := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(TILE * 0.94, TILE * 0.94)
			ov.mesh = pm
			var m := Mats.ground("square", Color(1, 1, 1, 0.0), false)
			ov.material_override = m
			ov.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ov.position = p + Vector3(0, 0.012, 0)
			add_child(ov)
			overlays[Vector2i(c, r)] = ov
			overlay_mats[Vector2i(c, r)] = m
	# midline
	_box(Vector3(COLS * TILE, 0.02, 0.05), Color("f8f2c8"), Vector3(0, 0.005, 0))
	# rails
	var w := COLS * TILE * 0.5 + 0.12
	var h := ROWS * TILE * 0.5 + 0.12
	_box(Vector3(0.24, 0.22, ROWS * TILE + 0.48), RAIL, Vector3(-w, 0.03, 0))
	_box(Vector3(0.24, 0.22, ROWS * TILE + 0.48), RAIL, Vector3(w, 0.03, 0))
	_box(Vector3(COLS * TILE + 0.48, 0.22, 0.24), RAIL, Vector3(0, 0.03, -h))
	_box(Vector3(COLS * TILE + 0.48, 0.22, 0.24), RAIL, Vector3(0, 0.03, h))
	for s in [-1.0, 1.0]:
		for t in [-1.0, 1.0]:
			_box(Vector3(0.36, 0.3, 0.36), RAIL.darkened(0.15), Vector3(w * s, 0.08, h * t))
		# midline posts
		_cyl(0.13, 0.15, 0.4, Color("f5e6c0"), Vector3(w * s, 0.15, 0))
		_sphere(0.12, Color("ffd23f"), Vector3(w * s, 0.4, 0))

func set_tile_highlight(t: Vector2i, color: Color) -> void:
	if overlay_mats.has(t):
		overlay_mats[t].albedo_color = color

func clear_highlights() -> void:
	for k in overlay_mats:
		overlay_mats[k].albedo_color = Color(1, 1, 1, 0)

func _process(delta: float) -> void:
	_t += delta
	# soft pulse on player's half during deploy
	if deploy_glow > 0.001:
		var a := (0.05 + 0.03 * sin(_t * 3.0)) * deploy_glow
		for k in overlay_mats:
			var m: StandardMaterial3D = overlay_mats[k]
			if k.y < 4 and m.albedo_color.a < 0.2:
				m.albedo_color = Color(0.55, 0.85, 1.0, a)

# ---------------------------------------------------------------- terrain & props
func _terrain() -> void:
	# base grass ground
	_box(Vector3(40, 1.0, 40), GRASS, Vector3(0, -0.56, 0))
	# terraces (boxy grass blocks) framing the board
	_block(Vector3(3.0, 0.5, 4.0), Vector3(-5.2, -0.06, -3.5))
	_block(Vector3(3.0, 0.9, 3.0), Vector3(5.1, -0.06, -4.6))
	_block(Vector3(2.6, 0.35, 3.0), Vector3(5.0, -0.06, 1.2))
	_block(Vector3(4.0, 0.7, 2.2), Vector3(0.0, -0.06, -6.3))
	_block(Vector3(2.2, 0.3, 2.0), Vector3(-4.6, -0.06, 3.4))
	# water pond bottom-left
	var water := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.6, 2.0)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = WATER
	wm.roughness = 0.1
	wm.metallic_specular = 0.8
	wm.emission_enabled = true
	wm.emission = WATER * 0.25
	WebLook.unify(wm)
	water.material_override = wm
	water.position = Vector3(-4.3, -0.03, 0.6)
	add_child(water)
	_box(Vector3(2.8, 0.1, 0.2), Color("e8d6a8"), Vector3(-4.3, -0.02, 1.65))

func _tree(pos: Vector3, s := 1.0) -> void:
	_cyl(0.1 * s, 0.14 * s, 0.7 * s, Color("8a5a34"), pos + Vector3(0, 0.35 * s, 0))
	var g := Color("57b53a").lerp(Color("7fd04a"), rng.randf())
	_sphere(0.55 * s, g, pos + Vector3(0, 0.95 * s, 0), Vector3(1, 0.85, 1))
	_sphere(0.38 * s, g.lightened(0.12), pos + Vector3(0.22 * s, 1.35 * s, -0.1 * s))
	_sphere(0.34 * s, g.darkened(0.05), pos + Vector3(-0.3 * s, 1.15 * s, 0.15 * s))

func _bush(pos: Vector3, s := 1.0) -> void:
	var g := Color("5fbf3c").lerp(Color("8ad455"), rng.randf())
	_sphere(0.28 * s, g, pos + Vector3(0, 0.18 * s, 0), Vector3(1, 0.8, 1))
	_sphere(0.2 * s, g.lightened(0.1), pos + Vector3(0.22 * s, 0.14 * s, 0.05))
	_sphere(0.18 * s, g.darkened(0.05), pos + Vector3(-0.2 * s, 0.12 * s, 0.08))

func _rock(pos: Vector3, s := 1.0) -> void:
	_sphere(0.3 * s, Color("b9b4c4"), pos + Vector3(0, 0.12 * s, 0), Vector3(1.2, 0.7, 1.0))
	_sphere(0.18 * s, Color("cfcad8"), pos + Vector3(0.25 * s, 0.08 * s, 0.1), Vector3(1.1, 0.7, 1))

func _barrel(pos: Vector3, tip := false) -> void:
	var n := Node3D.new()
	add_child(n)
	n.position = pos
	if tip:
		n.rotation = Vector3(0, rng.randf() * TAU, PI * 0.5)
	_cyl(0.24, 0.24, 0.5, Color("c8894a"), Vector3(0, 0.25, 0), Vector3.ZERO, n)
	_cyl(0.255, 0.255, 0.06, Color("8a8fa0"), Vector3(0, 0.1, 0), Vector3.ZERO, n)
	_cyl(0.255, 0.255, 0.06, Color("8a8fa0"), Vector3(0, 0.4, 0), Vector3.ZERO, n)
	_cyl(0.2, 0.2, 0.02, Color("7ec8e8"), Vector3(0, 0.5, 0), Vector3.ZERO, n)

func _flower(pos: Vector3) -> void:
	for i in 5:
		var a := TAU * i / 5.0
		_sphere(0.05, Color("ffffff"), pos + Vector3(cos(a) * 0.06, 0.03, sin(a) * 0.06), Vector3(1, 0.4, 1))
	_sphere(0.035, Color("ffd23f"), pos + Vector3(0, 0.05, 0))

func _props() -> void:
	# sides of the board (visible margins)
	for z in [-2.6, -0.4, 2.2]:
		_bush(Vector3(-3.85, 0, z + rng.randf_range(-0.3, 0.3)), rng.randf_range(0.7, 0.9))
		_bush(Vector3(3.85, 0, z + rng.randf_range(-0.3, 0.3)), rng.randf_range(0.7, 0.9))
	_tree(Vector3(-4.8, 0.44, -3.8), 1.2)
	_tree(Vector3(-5.8, 0.44, -2.6), 0.9)
	_tree(Vector3(5.0, 0.84, -4.8), 1.1)
	_tree(Vector3(-4.2, 0, 4.9), 1.0)
	_tree(Vector3(4.6, 0.29, 0.6), 0.9)
	_tree(Vector3(1.8, 0.64, -6.4), 1.0)
	_tree(Vector3(-1.4, 0.64, -6.6), 1.15)
	_rock(Vector3(3.95, 0, 3.3), 1.0)
	_rock(Vector3(-3.95, 0, -1.3), 0.8)
	_rock(Vector3(0.4, 0.64, -5.6), 0.9)
	_barrel(Vector3(-0.8, 0, 4.9))
	_barrel(Vector3(0.2, 0, 4.95), true)
	_barrel(Vector3(3.7, 0.29, 1.6))
	_barrel(Vector3(-3.2, 0, -4.9))
	for i in 26:
		var p := Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(-7.0, 6.0))
		if absf(p.x) < 3.6 and absf(p.z) < 4.4:
			continue
		if p.z > 5.3 and absf(p.x) < 4.0:
			continue
		_flower(p)
	# grass tufts
	for i in 30:
		var p := Vector3(rng.randf_range(-6.0, 6.0), 0, rng.randf_range(-7.0, 6.0))
		if absf(p.x) < 3.6 and absf(p.z) < 4.4:
			continue
		_cyl(0.0, 0.05, 0.22, Color("4ea83a"), p + Vector3(0, 0.1, 0), Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)))
