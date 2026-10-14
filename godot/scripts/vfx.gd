class_name Vfx
extends RefCounted
## VFX factory. Grammar (from reference research): white core + saturated rim,
## chunky cartoon puffs, star sparks, ring shockwaves, peak on the emit frame.

static var root: Node3D
static var cam: CameraRig

const WHITE := Color(1, 1, 1)
const DUST := Color("f4ead6")

## Parents a fresh effect node under the VFX layer. With no live layer (its scene is gone) the node is
## dropped right away instead of leaking as an orphan.
static func _add(n: Node3D, pos: Vector3) -> Node3D:
	if not is_instance_valid(root) or not root.is_inside_tree():
		n.position = pos
		n.queue_free()
		return n
	root.add_child(n)
	n.global_position = pos
	return n

static func _free_later(n: Node, t: float) -> void:
	if not n.is_inside_tree():
		return   # never parented (see _add): already queued for deletion
	n.get_tree().create_timer(t, false).timeout.connect(n.queue_free)

static func _shake(trauma: float) -> void:
	if is_instance_valid(cam):
		cam.add_trauma(trauma)

# ---------------------------------------------------------------- shared meshes
## Unit primitives shared by every effect (the instances scale them); built once.
static func _unit_sphere() -> Mesh:
	return Mats.shared("vfx/sphere", func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = 0.5
		s.height = 1.0
		s.radial_segments = 12
		s.rings = 6
		return s)

static func _unit_plane() -> Mesh:
	return Mats.shared("vfx/plane", func() -> Mesh:
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		return q)

static func _unit_quad() -> Mesh:
	return Mats.shared("vfx/quad", func() -> Mesh:
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		return q)

static func _unit_box() -> Mesh:
	return Mats.shared("vfx/box", func() -> Mesh: return BoxMesh.new())

## Fixed-size box / sphere (sizes are code constants, so the cache stays small).
static func _box_mesh(size: Vector3) -> Mesh:
	return Mats.shared("vfx/box%s" % size, func() -> Mesh:
		var b := BoxMesh.new()
		b.size = size
		return b)

static func _sphere_mesh(r: float) -> Mesh:
	return Mats.shared("vfx/sph%.3f" % r, func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		return s)

## Particle quad (size x size) carrying its shared billboard material.
static func _particle_quad(shape: String, additive: bool, size := Vector2(1, 1)) -> Mesh:
	return Mats.shared("vfx/pq%s%s%s" % [shape, additive, size], func() -> Mesh:
		var q := QuadMesh.new()
		q.size = size
		q.material = Mats.particle(shape, additive)
		return q)

## Spark size-over-life curve (same for every burst).
static func _spark_curve() -> Curve:
	return Mats.shared("vfx/spark_curve", func() -> Curve:
		var curve := Curve.new()
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(0.6, 0.8))
		curve.add_point(Vector2(1, 0))
		return curve)

## White-hot -> colour -> transparent ramp per spark colour. Colours are mostly constants, but the cache
## is capped so computed colours can't grow it without bound.
static var _ramps := {}
static func _spark_ramp(color: Color) -> Gradient:
	var key := str(color)   # not to_html(): that clamps HDR colours
	var g: Gradient = _ramps.get(key)
	if g == null:
		if _ramps.size() >= 128:
			_ramps.clear()
		g = Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(color.r, color.g, color.b, 0))
		g.add_point(0.25, color)
		_ramps[key] = g
	return g

# ---------------------------------------------------------------- primitives
static func puff(pos: Vector3, color: Color, size: float, drift: Vector3, life := 0.5, delay := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_sphere()
	var m := Mats.puff(color)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos)
	mi.scale = Vector3.ONE * 0.01
	var tw := mi.create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "global_position", pos + drift, life).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.45).set_delay(life * 0.55)
	tw.tween_property(mi, "scale", Vector3.ONE * size * 0.4, life * 0.45).set_delay(life * 0.55)
	tw.chain().tween_callback(mi.queue_free)

static func ground_ring(pos: Vector3, color: Color, from_s: float, to_s: float, life := 0.35, shape := "ring", additive := true) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_plane()
	var m := Mats.ground(shape, color, additive)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos + Vector3(0, 0.03, 0))
	mi.scale = Vector3.ONE * from_s
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * to_s, life).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.6).set_delay(life * 0.4)
	tw.chain().tween_callback(mi.queue_free)

static func pop_sprite(pos: Vector3, shape: String, color: Color, size: float, life := 0.18, spin := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_quad()
	var m := Mats.sprite(shape, color, true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos)
	mi.scale = Vector3.ONE * size * 0.3
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * size, life * 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, life * 0.5).set_delay(life * 0.5)
	if spin != 0.0:
		tw.tween_property(mi, "rotation:z", spin, life)
	tw.chain().tween_callback(mi.queue_free)

static func sparks(pos: Vector3, color: Color, amount := 8, speed := 3.0, life := 0.4, shape := "star", size := 0.14, gravity := -6.0, dir := Vector3.UP, spread := 80.0) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _particle_quad(shape, true)
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.5
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.damping_min = 2.0
	p.damping_max = 4.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	p.scale_amount_curve = _spark_curve()
	p.color_ramp = _spark_ramp(color)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(p, pos)
	p.emitting = true
	_free_later(p, life + 0.3)

# ---------------------------------------------------------------- composites
static func dust_ring(pos: Vector3, size := 1.0) -> void:
	var n := 9
	for i in n:
		var a := TAU * i / n + randf() * 0.3
		var d := Vector3(cos(a), 0, sin(a))
		puff(pos + d * 0.15 * size + Vector3(0, 0.06, 0), DUST, randf_range(0.16, 0.24) * size, d * 0.55 * size + Vector3(0, 0.1, 0), 0.45)
	ground_ring(pos, Color(1, 1, 1, 0.7), 0.3 * size, 1.5 * size, 0.3, "ring_soft")

static func hit_spark(pos: Vector3, color: Color, big := false) -> void:
	var s := 0.75 if big else 0.5
	pop_sprite(pos, "star", Color(1.3, 1.3, 1.2, 0.9), s, 0.16, randf_range(-0.6, 0.6))
	pop_sprite(pos, "soft", Color(color.r, color.g, color.b, 0.45), s * 1.1, 0.18)
	sparks(pos, color, 10 if big else 6, 3.5, 0.35, "star", 0.14)
	puff(pos, WHITE, 0.14, Vector3(0, 0.2, 0), 0.3)

static func death_poof(pos: Vector3) -> void:
	for i in 9:
		var a := TAU * i / 9.0
		var d := Vector3(cos(a), randf_range(0.2, 0.9), sin(a))
		puff(pos + Vector3(0, 0.3, 0) + d * 0.1, Color(1, 1, 1), randf_range(0.22, 0.34), d * 0.45, 0.55, randf() * 0.05)
	sparks(pos + Vector3(0, 0.35, 0), Defs.COL_GOLD, 6, 3.0, 0.6, "star5", 0.2, -5.0)
	pop_sprite(pos + Vector3(0, 0.35, 0), "soft", Color(1.0, 1.0, 1.0, 0.45), 0.9, 0.18)

static func explosion(pos: Vector3, color := Color("ff8a2a"), size := 1.0) -> void:
	pop_sprite(pos + Vector3(0, 0.25, 0), "soft", Color(1.6, 1.3, 0.8, 0.8), 1.3 * size, 0.16)
	pop_sprite(pos + Vector3(0, 0.25, 0), "star", Color(1.8, 1.2, 0.5), 1.2 * size, 0.2, 0.8)
	ground_ring(pos, Color(color.r * 1.5, color.g * 1.5, color.b, 1.0), 0.3, 2.2 * size, 0.35)
	ground_ring(pos, Color(0.25, 0.15, 0.1, 0.45), 1.3 * size, 1.4 * size, 1.4, "blob", false)  # scorch
	for i in 7:
		var a := TAU * i / 7.0
		var d := Vector3(cos(a), randf_range(0.3, 1.0), sin(a))
		puff(pos + Vector3(0, 0.2, 0), Color("fff0d0"), randf_range(0.25, 0.38) * size, d * 0.6 * size, 0.6)
	puff(pos + Vector3(0, 0.25, 0), Color("ffb13b"), 0.55 * size, Vector3(0, 0.35, 0), 0.35)
	sparks(pos + Vector3(0, 0.2, 0), color, 14, 5.0, 0.5, "star", 0.16, -8.0)
	_shake(0.25)

static func slam(pos: Vector3, radius: float) -> void:
	pop_sprite(pos + Vector3(0, 0.2, 0), "soft", Color(2.0, 1.9, 1.5), 2.2, 0.16)
	ground_ring(pos, Color(1.6, 1.4, 0.8, 1.0), 0.4, radius * 2.4, 0.4)
	ground_ring(pos, Color(1.0, 1.0, 1.0, 0.8), 0.2, radius * 1.7, 0.3, "ring_soft")
	ground_ring(pos, Color(0.3, 0.2, 0.12, 0.5), radius * 1.6, radius * 1.7, 1.2, "blob", false)
	for i in 12:
		var a := TAU * i / 12.0
		var d := Vector3(cos(a), 0, sin(a))
		puff(pos + d * 0.3, DUST, randf_range(0.26, 0.4), d * radius * 0.9 + Vector3(0, 0.15, 0), 0.6)
	debris(pos, 10, Color("9a6a3a"))
	sparks(pos + Vector3(0, 0.2, 0), Defs.COL_GOLD, 16, 6.0, 0.55, "star", 0.18, -10.0)
	if is_instance_valid(cam):
		cam.add_trauma(0.6)
		cam.hitstop(0.09)

static func debris(pos: Vector3, count: int, color: Color) -> void:
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = _unit_box()
		mi.scale = Vector3.ONE * randf_range(0.06, 0.12)
		# 5 shade steps: Mats.prop caches per colour, a random lightening would mint a new material per chip
		mi.material_override = Mats.prop(color.lightened(randi_range(0, 4) * 0.05))
		_add(mi, pos + Vector3(0, 0.1, 0))
		var a := randf() * TAU
		var v := Vector3(cos(a) * randf_range(1.0, 2.5), randf_range(2.5, 4.5), sin(a) * randf_range(1.0, 2.5))
		var t := randf_range(0.5, 0.75)
		var fly := func(k: float) -> void:
			var tt := k * t
			mi.global_position = pos + Vector3(v.x * tt, maxf(0.05, 0.1 + v.y * tt - 6.0 * tt * tt), v.z * tt)
		var tw := mi.create_tween().set_parallel(true)
		tw.tween_method(fly, 0.0, 1.0, t)
		tw.tween_property(mi, "rotation", Vector3(randf() * 8, randf() * 8, randf() * 8), t)
		tw.chain().tween_property(mi, "scale", Vector3.ZERO, 0.25)
		tw.chain().tween_callback(mi.queue_free)

static func upgrade_pillar(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.42
	c.bottom_radius = 0.42
	c.height = 3.0
	c.cap_top = false
	c.cap_bottom = false
	mi.mesh = c
	var m := Mats.fx(Color(1.6, 1.3, 0.4, 0.55), true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos + Vector3(0, 1.5, 0))
	mi.scale = Vector3(0.1, 1, 0.1)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1, 1, 1), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3(0.05, 1.3, 0.05), 0.35).set_delay(0.3)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3).set_delay(0.35)
	tw.chain().tween_callback(mi.queue_free)
	sparks(pos + Vector3(0, 0.2, 0), Defs.COL_GOLD, 16, 3.0, 0.9, "star5", 0.18, 2.5, Vector3.UP, 30.0)
	ground_ring(pos, Color(1.6, 1.3, 0.4, 1.0), 0.4, 2.0, 0.4)

static func spin_slash(pos: Vector3, radius: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_plane()
	var m := Mats.ground("ring_soft", Color(1.4, 1.4, 1.4, 0.9), true)
	mi.material_override = m
	_add(mi, pos + Vector3(0, 0.3, 0))
	mi.scale = Vector3.ONE * radius * 1.2
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius * 2.3, 0.25).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "rotation:y", -TAU, 0.25)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.18).set_delay(0.08)
	tw.chain().tween_callback(mi.queue_free)
	sparks(pos + Vector3(0, 0.3, 0), color, 10, 4.0, 0.3, "soft", 0.12, 0.0, Vector3.UP, 180.0)

static func speed_puffs(pos: Vector3, color: Color) -> void:
	puff(pos + Vector3(randf_range(-0.1, 0.1), 0.08, randf_range(-0.1, 0.1)), color, randf_range(0.1, 0.16), Vector3(0, 0.15, 0), 0.35)

static func clash_flash(center: Vector3) -> void:
	ground_ring(center, Color(1.2, 1.2, 1.0, 0.6), 0.5, 9.0, 0.45, "ring_soft")
	sparks(center + Vector3(0, 0.2, 0), Color(1, 1, 0.6), 30, 7.0, 0.6, "star", 0.2, -4.0, Vector3.UP, 90.0)

static func confetti(pos: Vector3) -> void:
	var cols := [Color("ff5f7e"), Color("ffd23f"), Color("3fa9f5"), Color("8fd14f"), Color("c56cf0")]
	for c in cols:
		var p := CPUParticles3D.new()
		p.mesh = _particle_quad("square", false, Vector2(0.16, 0.1))
		p.amount = 24
		p.lifetime = 2.4
		p.one_shot = true
		p.explosiveness = 0.9
		p.direction = Vector3.UP
		p.spread = 50.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 5.0
		p.gravity = Vector3(0, -4, 0)
		p.damping_min = 2.0
		p.damping_max = 3.0
		p.angular_velocity_min = -400
		p.angular_velocity_max = 400
		p.scale_amount_min = 0.7
		p.scale_amount_max = 1.2
		p.color = c * 1.3
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(2.4, 0.1, 3.5)
		_add(p, pos)
		p.emitting = true
		_free_later(p, 3.0)

# ---------------------------------------------------------------- trio chess additions
static func bolt_hit(pos: Vector3) -> void:
	pop_sprite(pos, "star", Color(1.4, 1.1, 1.9), 0.6, 0.16, randf_range(-0.6, 0.6))
	pop_sprite(pos, "soft", Color(0.75, 0.45, 1.0, 0.55), 0.7, 0.2)
	sparks(pos, Color("c08aff"), 7, 3.2, 0.35, "star5", 0.13)
	puff(pos, Color("efe0ff"), 0.15, Vector3(0, 0.2, 0), 0.3)

static func frost_hit(pos: Vector3) -> void:
	var p := pos + Vector3(0, 0.4, 0)
	pop_sprite(p, "star", Color(0.9, 1.4, 1.8), 0.7, 0.2, 0.4)
	sparks(p, Color("9fe8ff"), 8, 2.4, 0.5, "star5", 0.13, -2.0)
	ground_ring(pos, Color(0.6, 1.1, 1.6, 0.9), 0.3, 1.3, 0.35, "ring_soft")

## Big cold wave for the mage skill (radial ring + snowflakes everywhere).
static func frost_wave(center: Vector3, radius: float) -> void:
	ground_ring(center, Color(0.7, 1.3, 1.9, 1.0), 0.4, radius * 2.2, 0.5)
	ground_ring(center, Color(1, 1, 1, 0.8), 0.3, radius * 1.6, 0.4, "ring_soft")
	sparks(center + Vector3(0, 0.3, 0), Color("bff2ff"), 30, 6.0, 0.8, "star5", 0.2, -1.5, Vector3.UP, 90.0)
	_shake(0.3)

## Zig-zag lightning bolt between two points (white core + cyan rim), fades fast.
static func lightning(a: Vector3, b: Vector3, width := 0.09) -> void:
	var n := Node3D.new()
	root.add_child(n)
	var segs := 7
	var pts: Array[Vector3] = [a]
	var side := (b - a).cross(Vector3.UP).normalized()
	for i in range(1, segs):
		var k := float(i) / segs
		pts.append(a.lerp(b, k) + side * randf_range(-0.22, 0.22) + Vector3(0, randf_range(-0.12, 0.12), 0))
	pts.append(b)
	var mats: Array[StandardMaterial3D] = []
	for layer in 2:
		var w := width * (2.6 if layer == 0 else 1.0)
		var col := Color(0.35, 0.85, 1.6, 0.7) if layer == 0 else Color(1.6, 1.6, 1.8, 1.0)
		var m := Mats.fx(col, true)
		mats.append(m)
		for i in segs:
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var mi := MeshInstance3D.new()
			var bx := BoxMesh.new()
			bx.size = Vector3(w, w, p0.distance_to(p1) + w)
			mi.mesh = bx
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(mi)
			mi.global_position = (p0 + p1) * 0.5
			if (p1 - p0).length() > 0.001:
				mi.look_at(p1, Vector3.UP if absf((p1 - p0).normalized().y) < 0.95 else Vector3.RIGHT)
	pop_sprite(b, "star", Color(1.2, 1.6, 2.0), 0.8, 0.18, 0.5)
	sparks(b, Color("9fe8ff"), 8, 3.5, 0.3, "star", 0.12)
	var tw := n.create_tween().set_parallel(true)
	for m in mats:
		tw.tween_property(m, "albedo_color:a", 0.0, 0.22).set_delay(0.06)
	tw.chain().tween_callback(n.queue_free)

## Gold coin that pops out of a defeated enemy and waits on the board (collected at wave end).
static func coin(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.mesh = Mats.shared("vfx/coin", func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = 0.13
		c.bottom_radius = 0.13
		c.height = 0.04
		c.radial_segments = 18
		return c)
	mi.material_override = Mats.shared("vfx/coin_mat", func() -> Material: return Mats.glow(Color("ffd23f"), 1.15))
	mi.rotation.x = PI * 0.5
	n.add_child(mi)
	var rim := MeshInstance3D.new()
	rim.mesh = Mats.shared("vfx/coin_rim", func() -> Mesh:
		var t := TorusMesh.new()
		t.inner_radius = 0.11
		t.outer_radius = 0.145
		return t)
	rim.material_override = Mats.prop(Color("e09a1a"))
	rim.rotation.x = PI * 0.5
	n.add_child(rim)
	_add(n, pos + Vector3(0, 0.3, 0))
	var a := randf() * TAU
	var land := pos + Vector3(cos(a), 0, sin(a)) * randf_range(0.15, 0.4)
	land.x = clampf(land.x, -Actor.BOARD_X + 0.05, Actor.BOARD_X - 0.05)
	land.z = clampf(land.z, -Actor.BOARD_Z + 0.05, Actor.BOARD_Z - 0.05)
	var start := n.global_position
	var rest := land + Vector3(0, 0.17, 0)   # coin stands on its rim, resting on the board surface
	var fly := func(k: float) -> void:
		n.global_position = start.lerp(rest, k) + Vector3(0, sin(k * PI) * 0.7, 0)
	var tw := n.create_tween()
	tw.tween_method(fly, 0.0, 1.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): Sfx.play("tick", -12.0, 1.6))
	tw.tween_property(n, "global_position:y", rest.y + 0.12, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "global_position:y", rest.y, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var spin := n.create_tween().set_loops()
	spin.tween_property(n, "rotation:y", TAU, 1.2).from(0.0)
	return n

## Diablo-style field loot: a little treasure box pops out of the enemy, flips through the air,
## bounces twice and rests on the board under a rarity-coloured light beam. Returns the loot node.
static func loot_drop(pos: Vector3, col: Color, tier: int) -> Node3D:
	var n := Node3D.new()
	var body := Node3D.new()
	n.add_child(body)
	var box := MeshInstance3D.new()
	box.mesh = _box_mesh(Vector3(0.3, 0.2, 0.22))
	box.material_override = Mats.prop(col.lightened(0.05), 0.5)
	box.position.y = 0.1
	body.add_child(box)
	var lid := MeshInstance3D.new()
	lid.mesh = _box_mesh(Vector3(0.32, 0.07, 0.24))
	lid.material_override = Mats.prop(col.darkened(0.15), 0.5)
	lid.position.y = 0.23
	body.add_child(lid)
	for x in [-0.1, 0.1]:
		var band := MeshInstance3D.new()
		band.mesh = _box_mesh(Vector3(0.04, 0.29, 0.25))
		band.material_override = Mats.prop(Color("ffd23f"), 0.4)
		band.position = Vector3(x, 0.13, 0)
		body.add_child(band)
	var gem := MeshInstance3D.new()
	gem.mesh = _sphere_mesh(0.04)
	gem.material_override = Mats.glow(col.lightened(0.4), 1.8)
	gem.position = Vector3(0, 0.15, -0.115)
	body.add_child(gem)
	# light beam (taller / brighter for higher tiers): a soft halo column around a thin white-hot core,
	# both fading out upward with faint streaks drifting up + ground glow
	var h := 1.6 + 0.4 * mini(tier, 6)
	var beam := Node3D.new()
	beam.name = "Beam"
	n.add_child(beam)
	var bmats: Array[ShaderMaterial] = []
	for layer in [[0.22, 0.3, col, 0.6], [0.06, 0.08, col.lerp(WHITE, 0.45), 0.7]]:
		var mi := MeshInstance3D.new()
		var c := CylinderMesh.new()
		c.bottom_radius = layer[0]
		c.top_radius = layer[1]
		c.height = h
		c.radial_segments = 20
		c.rings = 1
		c.cap_top = false
		c.cap_bottom = false
		mi.mesh = c
		var m := _beam_mat(layer[2], layer[3] * (0.75 + 0.06 * mini(tier, 6)), h)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position.y = h * 0.5
		beam.add_child(mi)
		bmats.append(m)
	var glow := MeshInstance3D.new()
	glow.mesh = _unit_plane()
	var gmat := Mats.ground("soft", Color(col.r, col.g, col.b, 0.0), true)
	glow.material_override = gmat
	glow.position.y = 0.02
	glow.scale = Vector3.ONE * 0.9
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(glow)
	_add(n, pos + Vector3(0, 0.5, 0))
	var a := randf() * TAU
	var land := pos + Vector3(cos(a), 0, sin(a)) * randf_range(0.45, 0.85)
	land.x = clampf(land.x, -Actor.BOARD_X + 0.15, Actor.BOARD_X - 0.15)
	land.z = clampf(land.z, -Actor.BOARD_Z + 0.15, Actor.BOARD_Z - 0.15)
	var start := n.global_position
	var spin_axis := randf_range(-1.0, 1.0)
	var fly := func(k: float) -> void:
		n.global_position = start.lerp(land, k) + Vector3(0, sin(k * PI) * 1.3 * (1.0 - k * 0.4), 0)
		body.rotation = Vector3(k * TAU * 1.5, k * PI * spin_axis, 0)
	var tw := n.create_tween()
	tw.tween_method(fly, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func():
		body.rotation = Vector3(0, randf() * TAU, 0)
		dust_ring(land, 0.5)
		Sfx.play("thud", -12.0, 1.5))
	for b in 2:
		var hb := 0.28 / (b + 1)
		tw.tween_property(body, "position:y", hb, 0.11 / (b + 1) + 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(body, "position:y", 0.0, 0.11 / (b + 1) + 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		sparks(land + Vector3(0, 0.3, 0), col, 8 + tier * 2, 2.4, 0.7, "star5", 0.15, 1.0, Vector3.UP, 30.0)
		Sfx.play("chime", -10.0, 1.2 + tier * 0.08))
	# the beam rises out of the box (no pop), the glow spreads under it; the shader handles the idle shimmer
	for m in bmats:
		tw.parallel().tween_method(func(v: float): m.set_shader_parameter("grow", v), 0.0, 1.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(gmat, "albedo_color:a", 0.5, 0.5)
	return n

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform float strength = 0.6;
uniform float height = 2.0;
uniform float grow = 0.0;   // 0..1: how far up the column has risen
uniform float seed = 0.0;
varying float t;            // 0 at the ground .. 1 at the top
void vertex() {
	t = VERTEX.y / height + 0.5;
}
void fragment() {
	// soft sides: brightest where the column faces the camera, nothing at the silhouette
	float facing = abs(dot(normalize(NORMAL), VIEW));
	float side = facing * facing;
	// fades in just above the ground, then dies off smoothly toward the top
	float vert = smoothstep(0.0, 0.05, t) * pow(1.0 - t, 1.7);
	vert *= 1.0 + 0.8 * exp(-t * 9.0);   // hot spot where it leaves the box
	// faint wisps drifting up, and a slow breathing of the whole column
	float w = sin(UV.x * 18.85 + seed) * 0.5 + 0.5;
	float drift = sin(t * 9.0 - TIME * 2.2 + w * 3.0 + seed) * 0.5 + 0.5;
	float shimmer = 0.82 + 0.18 * drift;
	float breathe = 0.88 + 0.12 * sin(TIME * 1.7 + seed);
	float reveal = 1.0 - smoothstep(grow * 1.25 - 0.25, grow * 1.25, t);
	ALBEDO = tint.rgb;
	ALPHA = clamp(strength * side * vert * shimmer * breathe * reveal, 0.0, 1.0);
}
"""
static var _beam_shader: Shader

static func _beam_mat(col: Color, strength: float, h: float) -> ShaderMaterial:
	if _beam_shader == null:
		_beam_shader = Shader.new()
		_beam_shader.code = BEAM_SHADER
	var m := ShaderMaterial.new()
	m.shader = _beam_shader
	m.set_shader_parameter("tint", col)
	m.set_shader_parameter("strength", strength)
	m.set_shader_parameter("height", h)
	m.set_shader_parameter("seed", randf() * TAU)
	return m

## Loot beam + rarity-coloured sparkle when an item drops.
static func item_drop(pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.22
	c.bottom_radius = 0.3
	c.height = 2.4
	c.cap_top = false
	c.cap_bottom = false
	mi.mesh = c
	var m := Mats.fx(Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.5), true)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(mi, pos + Vector3(0, 1.2, 0))
	mi.scale = Vector3(0.1, 1, 0.1)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.5).set_delay(0.4)
	tw.chain().tween_callback(mi.queue_free)
	sparks(pos + Vector3(0, 0.4, 0), col, 10, 2.5, 0.8, "star5", 0.16, 1.5, Vector3.UP, 25.0)
	Sfx.play("chime", -12.0, 1.6)

## Fan-shaped ground decal for the ranger's cone ultimate (aim preview & channel). The fan mesh is shared
## per shape (the aim preview rebuilds on every pointer move); the material is the caller's to fade.
static func cone_mesh(length: float, half_angle: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Mats.shared("vfx/cone%.3f/%.3f" % [length, half_angle], func() -> Mesh:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var n := 20
		for i in n:
			var a0 := -half_angle + 2.0 * half_angle * i / n
			var a1 := -half_angle + 2.0 * half_angle * (i + 1) / n
			st.add_vertex(Vector3.ZERO)
			st.add_vertex(Vector3(sin(a1), 0, -cos(a1)) * length)
			st.add_vertex(Vector3(sin(a0), 0, -cos(a0)) * length)
		return st.commit())
	mi.material_override = Mats.fx(col, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

static func arrow_rain(pos: Vector3) -> void:
	var from := pos + Vector3(randf_range(-0.3, 0.3), 2.6, randf_range(-0.3, 0.3) + 0.6)
	var dummy := Node3D.new()
	_add(dummy, pos + Vector3(0, -0.35, 0))
	var done := func(_p: Vector3) -> void:
		hit_spark(pos + Vector3(0, 0.3, 0), Color("ffe08a"))
		if is_instance_valid(dummy):
			dummy.queue_free()
	projectile("arrow", from, dummy, done, 0.0, 0.18)

# ---------------------------------------------------------------- projectiles
## speed in units/sec; when dur > 0 the flight time is fixed instead.
static func projectile(kind: String, from: Vector3, target: Node3D, on_hit: Callable, speed := 9.0, dur := 0.0) -> void:
	var pr := Projectile.new()
	pr.kind = kind
	pr.target = target
	pr.on_hit = on_hit
	pr.speed = speed
	pr.fixed_dur = dur
	pr.start = from
	_add(pr, from)
	pr.setup()

class Projectile extends Node3D:
	var kind := "arrow"
	var target: Node3D
	var on_hit: Callable
	var speed := 9.0
	var fixed_dur := 0.0
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var t := 0.0
	var dur := 0.4
	var arc := 0.6
	var _trail_acc := 0.0
	var body: Node3D

	func setup() -> void:
		end = _aim()
		var dist := start.distance_to(end)
		dur = fixed_dur if fixed_dur > 0.0 else clampf(dist / speed, 0.18, 0.8)
		body = Node3D.new()
		add_child(body)
		# meshes / materials are shared by every projectile of a kind (none of them is animated)
		if kind == "bolt":
			# homing arcane bolt: white core + violet shell, curving arc
			arc = 0.5 + dist * 0.1
			_part(Vfx._sphere_mesh(0.08), Mats.shared("vfx/bolt_core", func() -> Material: return Mats.glow(Color(1.0, 0.95, 1.0), 2.4)))
			_part(Vfx._sphere_mesh(0.15), Mats.shared("vfx/bolt_shell", func() -> Material: return Mats.fx(Color(0.9, 0.5, 2.0, 0.7), true)))
		elif kind == "fireball":
			arc = 0.9 + dist * 0.12
			_part(Vfx._sphere_mesh(0.1), Mats.shared("vfx/fire_core", func() -> Material: return Mats.glow(Color(1.0, 0.95, 0.8), 2.5)))
			_part(Vfx._sphere_mesh(0.17), Mats.shared("vfx/fire_shell", func() -> Material: return Mats.fx(Color(2.0, 0.9, 0.2, 0.7), true)))
		elif kind == "rock":
			# slinger stone: lobbed high
			arc = 0.7 + dist * 0.14
			_part(Vfx._sphere_mesh(0.085), Mats.shared("vfx/rock", func() -> Material: return Mats.prop(Color("8f8478"))))
		elif kind == "hex":
			# shaman fire hex: violet core in a magenta-orange flame shell
			arc = 0.6 + dist * 0.1
			_part(Vfx._sphere_mesh(0.08), Mats.shared("vfx/hex_core", func() -> Material: return Mats.glow(Color(1.0, 0.85, 1.0), 2.4)))
			_part(Vfx._sphere_mesh(0.16), Mats.shared("vfx/hex_shell", func() -> Material: return Mats.fx(Color(1.8, 0.45, 1.6, 0.7), true)))
		elif kind == "bubble":
			# murloc water orb: pale core in a sea-blue shell, wobbling arc
			arc = 0.5 + dist * 0.1
			_part(Vfx._sphere_mesh(0.07), Mats.shared("vfx/bubble_core", func() -> Material: return Mats.glow(Color(0.85, 1.0, 1.0), 2.2)))
			_part(Vfx._sphere_mesh(0.15), Mats.shared("vfx/bubble_shell", func() -> Material: return Mats.fx(Color(0.3, 0.9, 2.0, 0.6), true)))
		elif kind == "seed" or kind == "web" or kind == "hook":
			# flytrap spiked seed (lobbed high), spider web blob, murloc hook
			arc = (1.8 + dist * 0.2) if kind == "seed" else (0.25 + dist * 0.05)
			var col: Color = {"seed": Color("6cbf52"), "web": Color("eef2f8"), "hook": Color("b8bcc8")}[kind]
			var r := 0.13 if kind == "seed" else (0.12 if kind == "web" else 0.07)
			_part(Vfx._sphere_mesh(r), Mats.shared("vfx/" + kind, func() -> Material: return Mats.prop(col)))
			if kind == "seed":
				for i in 6:
					var sp := _part(Vfx._box_mesh(Vector3(0.05, 0.05, 0.05)), Mats.shared("vfx/seed_spike", func() -> Material: return Mats.prop(Color("e8dcb0"))))
					var a := TAU * i / 6.0
					sp.position = Vector3(cos(a), (i % 2) * 0.6 - 0.3, sin(a)) * 0.13
				_part(Vfx._sphere_mesh(0.06), Mats.shared("vfx/seed_glow", func() -> Material: return Mats.glow(Color(0.7, 1.0, 0.35), 2.0)))
		elif kind == "quarrel":
			# crossbow bolt: short, heavy, flat and fast
			arc = 0.08 + dist * 0.02
			var q := _part(Mats.shared("vfx/quarrel_shaft", func() -> Mesh:
				var c := CylinderMesh.new()
				c.top_radius = 0.022
				c.bottom_radius = 0.022
				c.height = 0.32
				return c), Mats.prop(Color("4a3a30")))
			q.rotation.x = PI * 0.5
			var qt := _part(Mats.shared("vfx/arrow_tip", func() -> Mesh:
				var c2 := CylinderMesh.new()
				c2.top_radius = 0.0
				c2.bottom_radius = 0.045
				c2.height = 0.1
				return c2), Mats.prop(Color("dfe6ee")))
			qt.rotation.x = -PI * 0.5
			qt.position.z = -0.2
			var qf := _part(Vfx._box_mesh(Vector3(0.11, 0.01, 0.08)), Mats.prop(Defs.COL_ENEMY))
			qf.position.z = 0.13
		else:
			arc = 0.35 + dist * 0.08
			var shaft := _part(Mats.shared("vfx/arrow_shaft", func() -> Mesh:
				var c := CylinderMesh.new()
				c.top_radius = 0.018
				c.bottom_radius = 0.018
				c.height = 0.42
				return c), Mats.prop(Color("8a5a2b")))
			shaft.rotation.x = PI * 0.5
			var tip := _part(Mats.shared("vfx/arrow_tip", func() -> Mesh:
				var c2 := CylinderMesh.new()
				c2.top_radius = 0.0
				c2.bottom_radius = 0.045
				c2.height = 0.1
				return c2), Mats.prop(Color("dfe6ee")))
			tip.rotation.x = -PI * 0.5
			tip.position.z = -0.24
			var fl := _part(Vfx._box_mesh(Vector3(0.12, 0.01, 0.1)), Mats.prop(Color("ff6fae")))
			fl.position.z = 0.18

	func _part(mesh: Mesh, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		body.add_child(mi)
		return mi

	func _aim() -> Vector3:
		if is_instance_valid(target):
			return target.global_position + Vector3(0, 0.35, 0)
		return end

	func _process(delta: float) -> void:
		t += delta / dur
		if is_instance_valid(target):
			end = _aim()
		var k := minf(t, 1.0)
		var p := start.lerp(end, k) + Vector3(0, sin(k * PI) * arc, 0)
		var prev := global_position
		global_position = p
		var move := p - prev
		if move.length() > 0.0001:
			# straight up / down flight (arrow rain): look_at needs an up axis that isn't the travel axis
			body.look_at(p + move, Vector3.UP if absf(move.normalized().y) < 0.99 else Vector3.FORWARD)
		_trail_acc += delta
		var step := 0.025 if kind != "arrow" else 0.04
		while _trail_acc > step:
			_trail_acc -= step
			if kind == "fireball":
				Vfx.puff(p, Color(1, 0.97, 0.92), randf_range(0.14, 0.2), Vector3(0, 0.12, 0), 0.55)
			elif kind == "bolt":
				Vfx.puff(p, Color(0.93, 0.85, 1.0), randf_range(0.09, 0.13), Vector3(0, 0.08, 0), 0.4)
			elif kind == "hex":
				Vfx.puff(p, Color(1.0, 0.8, 0.98), randf_range(0.11, 0.16), Vector3(0, 0.1, 0), 0.45)
			elif kind == "rock":
				Vfx.puff(p, Color(0.85, 0.8, 0.72), 0.05, Vector3.ZERO, 0.2)
			elif kind == "bubble":
				Vfx.puff(p, Color(0.75, 0.95, 1.0), randf_range(0.08, 0.12), Vector3(0, 0.1, 0), 0.4)
			elif kind == "seed":
				Vfx.puff(p, Color(0.75, 1.0, 0.55), 0.09, Vector3.ZERO, 0.35)
			elif kind == "web" or kind == "hook":
				Vfx.puff(p, Color(0.95, 0.97, 1.0), 0.04, Vector3.ZERO, 0.5)
			else:
				Vfx.puff(p, Color(1, 1, 1), 0.06, Vector3.ZERO, 0.22)
		if t >= 1.0:
			if on_hit.is_valid():
				on_hit.call(end)
			queue_free()
