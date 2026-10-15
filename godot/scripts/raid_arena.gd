class_name RaidArena
extends Node3D
## Boss raid arena: a sealed, gloomy canyon instead of the march road (MarchWorld.use_arena).
##   floor   — an oval of cracked teal flagstones with faint glowing seams, a rune circle in the middle and pale
##             green glow pools, rimmed by a broken ring of dark blocks.
##   walls   — jagged violet rock cliffs all the way round: towering at the back, tall at the sides, low in front
##             (the camera looks over them), a second taller ridge behind the first to close the horizon.
##   dressing — violet / ice-blue crystal clusters at the cliff feet, leaning carved monoliths, fallen planks,
##             rubble, drifting violet motes and a cold mist; dim purple / teal light (MarchWorld.ARENA_LIGHT).
## Units stand inside the oval: clamp() is the raid's Actor.clamp_fn.

const C := Vector3(0, 0, -1.0)     # arena centre (the trio stands on the near half, the boss on the far one)
const FLOOR_R := 5.7
const MOVE_R := Vector2(4.9, 5.4)  # walkable oval (x, z radii)
const STONE := Color("4fa8a0")
const STONE_B := Color("3a8786")
const SEAM := Color("22424c")
const RIM := Color("3b4256")
const ROCK := [Color("3a2c58"), Color("46366c"), Color("2f2448"), Color("524078")]
const ROCK_TOP := Color("6c5aa0")
const CRYSTAL := [Color("a07aff"), Color("7fa8ff"), Color("c9a8ff")]

var rng := RandomNumberGenerator.new()

func build() -> void:
	rng.seed = 4242
	_floor()
	_rim()
	_walls()
	_crystals()
	_monoliths()
	_debris()
	_motes()

## Nearest walkable point (oval around C; z also capped by the near edge MarchMain keeps above the bag).
static func clamp_local(p: Vector3, margin: float, z_max: float) -> Vector3:
	var d := Vector2(p.x - C.x, p.z - C.z)
	var r := Vector2(MOVE_R.x - margin, MOVE_R.y - margin)
	var k := (d.x * d.x) / (r.x * r.x) + (d.y * d.y) / (r.y * r.y)
	if k > 1.0:
		d /= sqrt(k)
	return Vector3(C.x + d.x, p.y, minf(C.z + d.y, z_max - margin))

# ---------------------------------------------------------------- floor
## The arena floor as ONE plate: a disc mesh with a slightly wavy outline, brighter teal in the middle fading to a
## deep teal rim, with soft painterly blotches (noise in the vertex colours) instead of separate stones.
func _plate() -> MeshInstance3D:
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.35
	var rings := 22
	var segs := 96
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Color("63bdb2")
	var edge := Color("2e7377")
	var pts := []   # [ring][seg] -> [pos, col]
	for i in rings + 1:
		var row := []
		var t := float(i) / rings
		for j in segs:
			var a := TAU * j / segs
			var wob := 1.0 + 0.05 * noise.get_noise_2d(cos(a) * 3.0, sin(a) * 3.0) * t   # wavy outline only near the rim
			var r := FLOOR_R * t * wob
			var p := Vector3(cos(a) * r, 0.02 - 0.06 * pow(t, 6.0), sin(a) * r)   # the rim rolls down a touch
			var blot := noise.get_noise_2d(p.x * 1.0, p.z * 1.0) * 0.5 + noise.get_noise_2d(p.x * 2.6 + 9.0, p.z * 2.6) * 0.25
			var c := center.lerp(edge, pow(t, 1.6)).lightened(maxf(0.0, blot) * 0.18).darkened(maxf(0.0, -blot) * 0.2)
			row.append([p, c])
		pts.append(row)
	for i in rings:
		for j in segs:
			var j2 := (j + 1) % segs
			var quad := [pts[i][j], pts[i + 1][j], pts[i + 1][j2], pts[i][j2]]
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(quad[k][1])
				st.set_normal(Vector3.UP)
				st.add_vertex(quad[k][0])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	WebLook.unify(m)
	mi.material_override = m
	mi.position = C
	return mi

func _floor() -> void:
	var n := Node3D.new()
	add_child(n)
	var glow := OmniLight3D.new()   # the floor glows from the middle out (the canyon stays dark)
	glow.light_color = Color("6ff0e0")
	glow.light_energy = 1.8
	glow.omni_range = 9.0
	glow.omni_attenuation = 1.4
	glow.position = C + Vector3(0, 2.6, 0)
	add_child(glow)
	MarchProps._cyl(n, FLOOR_R + 0.4, FLOOR_R + 0.6, 0.3, SEAM, C + Vector3(0, -0.16, 0), Vector3.ZERO, 48)   # dark lip under the plate's edge
	n.add_child(_plate())
	# rune circle, glow seams and pale green glow pools (unlit, faint)
	var g := Node3D.new()
	add_child(g)
	MarchProps._torus_mi(g, 1.55, 1.68, Color.WHITE, C + Vector3(0, 0.07, 0), Vector3(1, 0.2, 1), Vector3.ZERO, MarchProps.glow_mat(Color(0.35, 0.95, 0.9), 0.7))
	MarchProps._torus_mi(g, 2.35, 2.42, Color.WHITE, C + Vector3(0, 0.07, 0), Vector3(1, 0.2, 1), Vector3.ZERO, MarchProps.glow_mat(Color(0.3, 0.8, 0.85), 0.5))
	for i in 8:
		var a := TAU * i / 8.0
		MarchProps._box(g, Vector3(0.14, 0.02, 0.5), Color.WHITE, C + Vector3(cos(a) * 1.95, 0.07, sin(a) * 1.95), Vector3(0, -a, 0)).material_override = MarchProps.glow_mat(Color(0.45, 1.0, 0.9), 0.8)
	for i in 9:   # a few faint cracks
		var a := rng.randf() * TAU
		var r := rng.randf_range(1.0, FLOOR_R - 0.6)
		MarchProps._box(g, Vector3(0.035, 0.015, rng.randf_range(0.5, 1.4)), Color.WHITE, C + Vector3(cos(a) * r, 0.065, sin(a) * r),
			Vector3(0, rng.randf() * TAU, 0)).material_override = MarchProps.glow_mat(Color(0.3, 0.75, 0.8), 0.4)
	for p in [Vector2(-2.6, 1.8), Vector2(2.9, -1.6), Vector2(-1.2, -3.6), Vector2(3.4, 2.6)]:
		var pool := MarchProps._cyl_mi(g, 0.75, 0.75, 0.01, 24, Color.WHITE, C + Vector3(p.x, 0.06, p.y), Vector3(1, 1, 0.8), Vector3.ZERO,
			Mats.fx(Color(0.7, 1.0, 0.6, 0.12), true))
		pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Broken ring of dark blocks round the floor (gaps where it crumbled).
func _rim() -> void:
	var n := Node3D.new()
	add_child(n)
	var count := 34
	for i in count:
		if rng.randf() < 0.14:
			continue
		var a := TAU * i / count
		var r := FLOOR_R + 0.15
		var h := rng.randf_range(0.18, 0.42)
		MarchProps._rb(n, Vector3(0.95, h, 0.55), RIM.lerp(Color("2a3046"), rng.randf()), C + Vector3(cos(a) * r, h * 0.5 - 0.05, sin(a) * r),
			Vector3(rng.randf_range(-0.1, 0.1), -a + PI * 0.5, rng.randf_range(-0.12, 0.12)), 0.2)
	# a dark rubble band between the rim and the cliffs
	MarchProps._cyl(n, FLOOR_R + 7.0, FLOOR_R + 7.5, 0.2, Color("241b38"), C + Vector3(0, -0.2, 0), Vector3.ZERO, 48)
	for i in 70:
		var a := rng.randf() * TAU
		var r := rng.randf_range(FLOOR_R + 0.7, FLOOR_R + 2.2)
		var s := rng.randf_range(0.2, 0.55)
		MarchProps._rb(n, Vector3(s, s * 0.6, s * 0.9), (ROCK[rng.randi() % ROCK.size()] as Color).darkened(0.1),
			C + Vector3(cos(a) * r, s * 0.2, sin(a) * r), Vector3(rng.randf() * 0.5, rng.randf() * TAU, rng.randf() * 0.5), 0.25)
	WebBatch.batch(n)

# ---------------------------------------------------------------- canyon walls
## Wall height around the oval: towering at the back (far z), tall at the sides, low in front of the camera.
func _wall_h(a: float, far := false) -> float:
	var back := clampf(-sin(a), 0.0, 1.0)      # 1 straight back
	var front := clampf(sin(a), 0.0, 1.0)      # 1 straight in front
	var h := lerpf(4.5, 10.5, back) * lerpf(1.0, 0.18, pow(front, 0.6))
	return h * (1.5 if far else 1.0)

func _walls() -> void:
	var n := Node3D.new()
	add_child(n)
	for ring in 2:
		var far := ring == 1
		var a := 0.0
		while a < TAU:
			var r := FLOOR_R + (1.5 if not far else 4.6) + rng.randf_range(-0.3, 0.5)
			var h := _wall_h(a, far) * rng.randf_range(0.8, 1.2)
			if not (far and sin(a) > 0.3):   # no far ridge in front of the camera
				_spire(n, C + Vector3(cos(a) * r * 1.02, 0, sin(a) * r), h, rng.randf_range(1.5, 2.6) * (1.3 if far else 1.0), -a + PI * 0.5)
			a += rng.randf_range(0.2, 0.32) * (0.8 if far else 1.0)
	WebBatch.batch(n)

## One jagged rock spire: stacked blocks narrowing upward, leaning a little, with a pale violet ledge on top.
func _spire(parent: Node3D, pos: Vector3, h: float, w: float, yaw: float) -> void:
	var y := 0.0
	var col: Color = ROCK[rng.randi() % ROCK.size()]
	var lean := Vector2(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.1, 0.1))
	var parts := maxi(1, int(h / 2.2))
	for i in parts:
		var ph := h / parts * rng.randf_range(0.9, 1.15)
		var off := Vector3(lean.x, 0, lean.y) * y
		MarchProps._rb(parent, Vector3(w, ph, w * rng.randf_range(0.7, 1.0)), MarchProps._vary(col, rng, 0.03), pos + off + Vector3(0, y + ph * 0.5, 0),
			Vector3(lean.y + rng.randf_range(-0.06, 0.06), yaw + rng.randf_range(-0.4, 0.4), lean.x + rng.randf_range(-0.06, 0.06)), 0.15)
		y += ph * 0.92
		w *= rng.randf_range(0.72, 0.88)
	MarchProps._rb(parent, Vector3(w * 1.15, 0.16, w), ROCK_TOP, pos + Vector3(lean.x, 0, lean.y) * y + Vector3(0, y, 0), Vector3(0, yaw, 0), 0.3)

# ---------------------------------------------------------------- dressing
func _crystals() -> void:
	var lights := 0
	for i in 16:
		var a := TAU * i / 16.0 + rng.randf_range(-0.12, 0.12)
		if sin(a) > 0.75:   # keep the near edge clear (the bag panel covers it anyway)
			continue
		var r := FLOOR_R + rng.randf_range(0.6, 1.3)
		var p := C + Vector3(cos(a) * r, 0, sin(a) * r)
		var big := clampf(-sin(a), 0.0, 1.0) * 0.8 + rng.randf_range(0.6, 1.0)
		_cluster(p, big, a)
		if lights < 4 and i % 4 == 1:
			lights += 1
			var l := OmniLight3D.new()
			l.light_color = Color("b48cff")
			l.light_energy = 1.6
			l.omni_range = 5.0
			l.position = p + Vector3(0, 1.4, 0)
			add_child(l)

## A crystal cluster: glowing shards fanning out of a rock base (violet / ice blue).
func _cluster(pos: Vector3, s: float, a: float) -> void:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	MarchProps._rb(n, Vector3(1.1, 0.4, 0.9) * s, ROCK[0], Vector3(0, 0.12 * s, 0), Vector3(0, rng.randf() * TAU, 0), 0.3)
	var col: Color = CRYSTAL[rng.randi() % CRYSTAL.size()]
	for k in rng.randi_range(4, 7):
		var h := rng.randf_range(0.8, 2.4) * s
		var b := rng.randf() * TAU
		var tilt := rng.randf_range(0.1, 0.5)
		var out := Vector3(cos(a), 0, sin(a)) * 0.35   # lean away from the arena
		var shard := MarchProps._cyl_mi(n, 0.0, rng.randf_range(0.14, 0.3) * s, h, 6, Color.WHITE,
			Vector3(cos(b) * 0.3 * s, h * 0.42, sin(b) * 0.3 * s),
			Vector3.ONE, Vector3(sin(b) * tilt + out.z, 0, -cos(b) * tilt - out.x), MarchProps.glow_mat(col.lightened(rng.randf() * 0.25), 1.15))
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

## Leaning carved monoliths (like broken gate pillars) at the back corners and one fallen across the side.
func _monoliths() -> void:
	for d in [[Vector3(-4.9, 0, -5.6), 0.32, 5.2], [Vector3(5.1, 0, -5.3), -0.28, 4.6], [Vector3(-6.4, 0, -1.6), 0.5, 3.8], [Vector3(6.3, 0, 0.6), -0.22, 3.4]]:
		var n := Node3D.new()
		n.position = C + d[0]
		n.rotation = Vector3(0, rng.randf_range(-0.4, 0.4), d[1])
		add_child(n)
		var h: float = d[2]
		MarchProps._rb(n, Vector3(1.0, h, 0.7), Color("4a3d66"), Vector3(0, h * 0.5, 0), Vector3.ZERO, 0.12)
		MarchProps._rb(n, Vector3(0.5, h * 0.55, 0.12), Color("2c2244"), Vector3(0, h * 0.55, -0.32), Vector3.ZERO, 0.1)   # carved slot
		MarchProps._box(n, Vector3(0.12, 0.3, 0.04), Color.WHITE, Vector3(0, h * 0.62, -0.38)).material_override = MarchProps.glow_mat(Color(0.7, 0.5, 1.0), 1.4)   # rune
		MarchProps._rb(n, Vector3(1.2, 0.35, 0.85), Color("5a4a7e"), Vector3(0, h, 0), Vector3.ZERO, 0.2)
	# a broken pillar or two on the floor's edge
	for p in [Vector3(-4.1, 0, -4.0), Vector3(4.3, 0, -3.7)]:
		MarchProps.pillar(self, C + p, rng, 1.2, Color("4a4466"), Color("6a5a96"))

func _debris() -> void:
	var n := Node3D.new()
	add_child(n)
	for i in 4:   # fallen planks on the near left
		MarchProps._rb(n, Vector3(0.35, 0.08, 1.9), Color("5a4636").lerp(Color("3e3028"), rng.randf()), C + Vector3(-5.2 + i * 0.45, 0.06 + i * 0.03, 3.6 + rng.randf_range(-0.3, 0.3)),
			Vector3(rng.randf_range(-0.08, 0.08), 0.9 + rng.randf_range(-0.2, 0.2), rng.randf_range(-0.1, 0.1)), 0.1)
	for i in 3:   # dark stone slabs tipped over at the rim
		var a := rng.randf_range(0.0, TAU)
		MarchProps._rb(n, Vector3(1.1, 0.35, 0.8), Color("3a3a52"), C + Vector3(cos(a) * (FLOOR_R + 0.6), 0.15, sin(a) * (FLOOR_R + 0.6)),
			Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3)), 0.15)
	WebBatch.batch(n)

## Violet motes drifting up out of the floor (the "gloom").
func _motes() -> void:
	var p := CPUParticles3D.new()
	p.amount = 60
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(7.5, 0.2, 6.5)
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, 0.12, 0)
	p.initial_velocity_min = 0.15
	p.initial_velocity_max = 0.45
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.75, 0.55, 1.0, 0.8)
	q.material = m
	p.mesh = q
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	p.color_ramp = ramp
	p.position = C + Vector3(0, 0.3, 0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
