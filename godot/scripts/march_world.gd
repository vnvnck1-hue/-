class_name MarchWorld
extends World
## Endless March stage: one continuous, gently winding battle field that runs up the screen forever.
## No board, no tiles — units fight in real time anywhere on the field.
## The field scrolls toward the camera (treadmill): battle logic keeps local coordinates, and the track
## node is shifted by (-center_x(D), 0, D) for travelled distance D.
##
## Track space: a point at distance s along the road and lateral x sits at (x, y, -s).
## Enemy groups wait at a fixed rhythm (encounter k at arena_s(k)); around every 10th (mid-boss) the
## field widens. The road crosses the world map's regions (Regions.LIST, 10 groups each, looping forever):
## each region has its own ground / light / prop theme. A region ends halfway between its mid-boss and the
## next group; ground colours and lighting cross-fade over BLEND_GROUND and props mix over BLEND_PROPS.

const FIRST := 11.0
const GAP := 11.5
const GAP_BOSS := 14.5
const FIELD_W := 3.4      # field half width
const BOSS_W := 5.0       # field half width at a mid-boss
const BOSS_EVERY := 10
const CHUNK := 8.0
const AHEAD := 38.0
const BEHIND := 14.0
const GROUND_W := 16.0
const BLEND_GROUND := 6.0
const BLEND_PROPS := 9.0

var seed_v := 1
var dist := 0.0
var track: Node3D
var chunks := {}     # chunk index -> Node3D
var _span := Vector2i(1, 0)      # chunk index window [x, y] currently built (empty until the first set_dist)
var view_mix := Vector3.ZERO   # (region a, region b, blend a->b) at the view centre
var _dim_k := 0.0
var _as: Array[float] = [0.0]    # encounter k: distance where the trio meets group k (k = 0 is the start)
var _ph := Vector3.ZERO          # curve phases
var _noise := FastNoiseLite.new()
var _gmat: StandardMaterial3D

func build() -> void:
	_env()
	env.fog_enabled = true
	env.set("fog_mode", 1)            # depth fog: only the far end of the road fades
	env.set("fog_depth_begin", 24.0)
	env.set("fog_depth_end", 46.0)
	env.fog_density = 0.7
	env.fog_sky_affect = 0.0
	_gmat = StandardMaterial3D.new()
	_gmat.vertex_color_use_as_albedo = true
	_gmat.vertex_color_is_srgb = true
	_gmat.roughness = 0.95
	_gmat.metallic_specular = 0.2
	_gmat.rim_enabled = true
	_gmat.rim = 0.15
	WebLook.unify(_gmat)
	track = Node3D.new()
	track.name = "Track"
	add_child(track)
	reset(seed_v)

## New layout for a new run.
func reset(p_seed: int) -> void:
	seed_v = p_seed
	for n in track.get_children():
		n.queue_free()
	chunks.clear()
	_span = Vector2i(1, 0)
	_as = [0.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	_ph = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	_noise.seed = seed_v
	_noise.frequency = 0.12
	set_dist(0.0)

# ---------------------------------------------------------------- layout
static func is_boss(k: int) -> bool:
	return k > 0 and k % BOSS_EVERY == 0

func _extend(k: int) -> void:
	while _as.size() <= k:
		var i := _as.size()
		var gap := FIRST if i == 1 else (GAP_BOSS if is_boss(i) or is_boss(i - 1) else GAP)
		_as.append(_as[i - 1] + gap)

func arena_s(k: int) -> float:
	_extend(maxi(k, 0))
	return _as[maxi(k, 0)]

## Encounter index k with s_k <= s < s_k+1.
func _seg(s: float) -> int:
	while _as[_as.size() - 1] < s + 1.0:
		_extend(_as.size())
	return maxi(0, _as.bsearch(s, false) - 1)

## Gently winding centreline (two slow sine waves, flattened at the start).
func center_x(s: float) -> float:
	var x := 1.5 * sin(s * 0.105 + _ph.x) + 0.9 * sin(s * 0.043 + _ph.y)
	var x0 := 1.5 * sin(_ph.x) + 0.9 * sin(_ph.y)
	return x - x0 * (1.0 - smoothstep(0.0, 12.0, s))

## 0..1: how much the field is widened for a nearby mid-boss.
func boss_k(s: float) -> float:
	var k := _seg(s)
	var b := 0.0
	for j in [k, k + 1]:
		if is_boss(j):
			b = maxf(b, 1.0 - smoothstep(5.5, 10.0, absf(s - _as[j])))
	return b

func half_w(s: float) -> float:
	return lerpf(FIELD_W, BOSS_W, boss_k(s))

func _height(x: float, s: float, d: float) -> float:
	if d <= 0.2:
		return -0.08
	var hill := 0.55 + 0.45 * _noise.get_noise_2d(x * 0.6, s * 0.6)
	return -0.08 + smoothstep(0.2, 6.5, d) * hill * 1.35

# ---------------------------------------------------------------- regions
## Distance where region r (>= 1) begins: halfway between its predecessor's mid-boss and its first group.
func region_start(r: int) -> float:
	if r <= 0:
		return -INF
	var k := r * Regions.PER_REGION
	return (arena_s(k) + arena_s(k + 1)) * 0.5

## Region index (unbounded, laps keep counting) at road distance s.
func region_at(s: float) -> int:
	var r := int(_seg(maxf(s, 0.0)) / Regions.PER_REGION)
	if r > 0 and s < region_start(r):
		r -= 1
	return r

## (region a, region b, t): the theme at s is a blended toward b by t (a == b away from borders).
func mix_at(s: float, blend: float) -> Vector3:
	var r := region_at(s)
	if r > 0 and s - region_start(r) < blend:
		return Vector3(r - 1, r, smoothstep(-blend, blend, s - region_start(r)))
	var nb := region_start(r + 1)
	if nb - s < blend:
		return Vector3(r, r + 1, smoothstep(-blend, blend, s - nb))
	return Vector3(r, r, 0.0)

static func _th(m: Vector3, pick_b: bool) -> Dictionary:
	return Regions.theme(int(m.y) if pick_b else int(m.x))

## Blended theme colour; f mixes the two tones of a two-tone entry.
static func tcol(m: Vector3, key: String, f := 0.0) -> Color:
	var ca: Variant = Regions.theme(int(m.x))[key]
	var cb: Variant = Regions.theme(int(m.y))[key]
	var a: Color = (ca[0] as Color).lerp(ca[1], f) if ca is Array else ca
	var b: Color = (cb[0] as Color).lerp(cb[1], f) if cb is Array else cb
	return a.lerp(b, m.z)

static func tnum(m: Vector3, key: String) -> float:
	return lerpf(Regions.theme(int(m.x))[key], Regions.theme(int(m.y))[key], m.z)

## Stone colour for a campfire ring at road distance s.
func camp_stone(s: float) -> Color:
	return tcol(mix_at(s, BLEND_GROUND), "camp")

## Keep a local-space point on the field (used as Actor.clamp_fn while marching mode runs).
func clamp_local(p: Vector3, margin: float, z_min := -6.6, z_max := 4.7) -> Vector3:
	var z := clampf(p.z, z_min + margin, z_max - margin)
	var s := dist - z
	var c := center_x(s) - center_x(dist)
	var w := half_w(s) - 0.35 - margin
	return Vector3(clampf(p.x, c - w, c + w), p.y, z)

## Lateral offset of the field centre at local z (relative to the view centre).
func local_center(z: float) -> float:
	return center_x(dist - z) - center_x(dist)

# ---------------------------------------------------------------- streaming
func set_dist(d: float) -> void:
	dist = d
	track.position = Vector3(-center_x(d), 0, d)
	var span := Vector2i(int(floorf((d - BEHIND) / CHUNK)), int(floorf((d + AHEAD) / CHUNK)))
	if span != _span:   # the chunk window only moves every CHUNK metres: skip the scan on all other frames
		_span = span
		for i in range(span.x, span.y + 1):
			if not chunks.has(i):
				chunks[i] = _build_chunk(i)
		for i in chunks.keys():
			if i < span.x or i > span.y:
				chunks[i].queue_free()
				chunks.erase(i)
	view_mix = mix_at(d + 4.0, BLEND_GROUND)
	_apply_light()

# ---------------------------------------------------------------- lighting
## World map transition: while the camera pulls up into the sky, the fog closes in and takes the sky colour,
## so the far end of the generated road melts into the sky instead of showing its edge.
var sky_fade := 0.0
func set_sky_fade(k: float) -> void:
	sky_fade = k
	env.set("fog_depth_begin", lerpf(24.0, 7.0, k))
	env.set("fog_depth_end", lerpf(46.0, 21.0, k))
	env.fog_density = lerpf(0.7, 1.0, k)
	_apply_light()

func set_dim(k: float) -> void:
	_dim_k = k
	_apply_light()

func _apply_light() -> void:
	if sun == null:
		return
	var m := view_mix
	var k := _dim_k
	WebLook.light_color(sun, tcol(m, "sun"))
	sun.light_energy = lerpf(tnum(m, "sun_e"), 0.12, k)
	WebLook.light_color(fill, tcol(m, "fill"))
	fill.light_energy = lerpf(tnum(m, "fill_e"), 0.04, k)
	env.ambient_light_color = WebLook.ambient(tcol(m, "amb"))
	env.ambient_light_energy = lerpf(tnum(m, "amb_e"), 0.1, k)
	env.background_color = tcol(m, "sky").lerp(Color("141026"), k)
	env.fog_light_color = tcol(m, "fog").lerp(Color("141026"), k).lerp(env.background_color, sky_fade)
	env.adjustment_saturation = lerpf(tnum(m, "sat"), 0.85, k)
	env.glow_intensity = WebLook.glow(lerpf(tnum(m, "glow"), 0.65, k))

# ---------------------------------------------------------------- ground chunk
func _build_chunk(i: int) -> Node3D:
	var node := Node3D.new()
	track.add_child(node)
	var s0 := i * CHUNK
	_ground_mesh(node, s0)
	_field_mesh(node, s0)
	_field_decor(node, s0, i)
	_scatter_props(node, s0, i)
	WebBatch.batch(node)
	return node

func _quad_indices(st: SurfaceTool, rows: int, cols: int) -> void:
	for r in rows - 1:
		for c in cols - 1:
			var a := r * cols + c
			var b := a + cols
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)

func _commit(node: Node3D, st: SurfaceTool) -> void:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _gmat
	node.add_child(mi)

## Surrounding terrain: flat next to the field, rolling hills further out.
func _ground_mesh(node: Node3D, s0: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ds := 0.5
	var rows := int(CHUNK / ds) + 1
	var cols := 47
	for r in rows:
		var s := s0 + r * ds
		var cx := center_x(s)
		var hw := half_w(s) + 0.25
		var m := mix_at(s, BLEND_GROUND)
		for c in cols:
			var off := -GROUND_W + 2.0 * GROUND_W * c / (cols - 1)
			var x := cx + off
			var d := absf(off) - hw
			var n := _noise.get_noise_2d(x * 1.6 + 100.0, s * 1.6)
			var col := tcol(m, "grass", clampf(0.5 + n * 1.3, 0.0, 1.0))
			st.set_color(col)
			st.add_vertex(Vector3(x, _height(x, s, d), -s))
	_quad_indices(st, rows, cols)
	_commit(node, st)

## The battle field: a slightly raised band with a worn trail down the middle and a darker skirt.
func _field_mesh(node: Node3D, s0: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ds := 0.5
	var rows := int(CHUNK / ds) + 1
	var fr := [-1.04, -1.0, -0.8, -0.45, -0.3, -0.15, 0.0, 0.15, 0.3, 0.45, 0.8, 1.0, 1.04]
	var n := fr.size()
	for r in rows:
		var s := s0 + r * ds
		var cx := center_x(s)
		var hw := half_w(s)
		var m := mix_at(s, BLEND_GROUND)
		var field := tcol(m, "field", 0.0)
		var field2 := tcol(m, "field", 1.0)
		var trail := tcol(m, "trail")
		for c in n:
			var f: float = fr[c]
			var x := cx + f * hw
			var nz := clampf(0.5 + _noise.get_noise_2d(x * 1.3, s * 1.3) * 1.2, 0.0, 1.0)
			var col := field.lerp(field2, nz)
			var tw := 0.3 + 0.05 * _noise.get_noise_2d(s * 0.7, 3.0)
			col = col.lerp(trail, 1.0 - smoothstep(tw * 0.55, tw, absf(f)))
			if absf(f) >= 1.0:
				col = field.darkened(0.32)
			st.set_color(col)
			st.add_vertex(Vector3(x, -0.15 if absf(f) > 1.0 else -0.01, -s))
	_quad_indices(st, rows, n)
	_commit(node, st)

## Field details: soft border bumps along both edges (hedge lips / stone curbs / sand / snow) with small edge
## accents, and trail details per theme (stepping stones, mine rails with sleepers, glowing lava cracks, ice slabs).
func _field_decor(node: Node3D, s0: float, i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(seed_v, i, 7))
	var s := s0 + 0.35
	while s < s0 + CHUNK:
		var cx := center_x(s)
		var hw := half_w(s)
		var slope := (center_x(s + 0.3) - center_x(s - 0.3)) / 0.6
		var yaw := atan(slope)
		var m := mix_at(s, BLEND_GROUND)
		var th := _th(m, rng.randf() < m.z)
		var deco: String = th["deco"]
		var dc: Color = th["deco_col"]
		# trail
		match deco:
			"rails":
				MarchProps._box(node, Vector3(1.5, 0.04, 0.16), Color("6b4a3a"), Vector3(cx, -0.005, -s), Vector3(0, yaw, 0))
				for side in [-0.5, 0.5]:
					MarchProps._box(node, Vector3(0.07, 0.05, 0.72), dc, Vector3(cx + side, 0.025, -s), Vector3(0, yaw, 0))
			"embers":
				if rng.randf() < 0.45:
					var p0 := Vector3(cx + rng.randf_range(-0.6, 0.6), -0.005, -s + rng.randf_range(-0.2, 0.2))
					MarchProps._mi(node, MarchProps._box_mesh(Vector3.ONE), Color.WHITE, p0, Vector3(rng.randf_range(0.3, 0.6), 0.02, 0.05), Vector3(0, rng.randf() * PI, 0), MarchProps.glow_mat(dc, 1.7))
			_:
				if rng.randf() < (0.5 if deco == "ice" else 0.4):
					var p := Vector3(cx + rng.randf_range(-0.7, 0.7), -0.01, -s + rng.randf_range(-0.2, 0.2))
					MarchProps._rb(node, Vector3(rng.randf_range(0.3, 0.45), 0.04 if deco == "ice" else 0.05, rng.randf_range(0.25, 0.38)), dc, p, Vector3(0, rng.randf() * TAU, 0), 0.4)
		# border bumps on both edges
		for side in [-1.0, 1.0]:
			var tb := _th(m, rng.randf() < m.z)
			var p2 := Vector3(cx + side * (hw + 0.12), -0.04, -s)
			var sz := Vector3(rng.randf_range(0.45, 0.7), rng.randf_range(0.18, 0.3), rng.randf_range(0.6, 0.8))
			var rnd: float = tb["round"]
			if rnd > 0.5:
				sz.y *= 1.25
			MarchProps._rb(node, sz, (tb["bump"][0] as Color).lerp(tb["bump"][1], rng.randf()), p2, Vector3(0, yaw + rng.randf_range(-0.2, 0.2), 0), rnd)
			if rng.randf() < 0.12:
				_spawn_prop(node, tb["edge"], p2 + Vector3(side * 0.35, 0.0, 0), rng, 0.9, 99)
		s += 0.7

# ---------------------------------------------------------------- props
func _pick(rng: RandomNumberGenerator, table: Array) -> String:
	var total := 0.0
	for e in table:
		total += e[1]
	var r := rng.randf() * total
	for e in table:
		r -= e[1]
		if r <= 0.0:
			return e[0]
	return table[0][0]

func _scatter_props(node: Node3D, s0: float, i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(seed_v, i, 1))
	var lights := 0
	for n in 44:
		var s := s0 + rng.randf() * CHUNK
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var d := 0.55 + pow(rng.randf(), 1.35) * 9.0
		var x := center_x(s) + side * (half_w(s) + 0.25 + d)
		var p := Vector3(x, _height(x, s, d), -s)
		var m := mix_at(s, BLEND_PROPS)
		var th := _th(m, rng.randf() < m.z)
		var table: Array = th["near"] if d < 1.3 else (th["mid"] if d < 3.6 else th["far"])
		var kind := _pick(rng, table)
		if _spawn_prop(node, kind, p, rng, rng.randf_range(0.85, 1.2), lights, d):
			lights += 1

## Builds one prop by name; returns true when it used up a real light (capped at 2 per chunk).
func _spawn_prop(node: Node3D, kind: String, p: Vector3, rng: RandomNumberGenerator, sc: float, lights: int, d := 0.0) -> bool:
	match kind:
		"daisies": MarchProps.daisies(node, p, rng, sc)
		"lily": MarchProps.lily(node, p, rng, sc * 1.2)
		"mushrooms": MarchProps.mushrooms(node, p, rng, sc)
		"rock": MarchProps.rock(node, p, rng, sc)
		"stump": MarchProps.stump(node, p, rng, sc)
		"blob_y": MarchProps.blob_bush(node, p, rng, sc, true)
		"blob_g": MarchProps.blob_bush(node, p, rng, sc, false)
		"pine": MarchProps.pine(node, p, rng, sc * (0.8 if d < 3.6 else 1.25))
		"cube": MarchProps.cube_tree(node, p, rng, sc * 1.1)
		"egg": MarchProps.egg_trees(node, p, rng, sc * 1.1)
		"puff": MarchProps.puff_tree(node, p, rng, sc * 1.2)
		"terrace": MarchProps.terrace(node, p, rng, sc)
		"pond": MarchProps.pond(node, p, rng, sc)
		# forest
		"ferns": MarchProps.ferns(node, p, rng, sc * 1.2)
		"mossrock": MarchProps.moss_rock(node, p, rng, sc)
		"log": MarchProps.log_prop(node, p, rng, sc)
		"spirit": MarchProps.spirit(node, p, rng, sc * 1.2)
		"giant": MarchProps.giant_tree(node, p, rng, sc * 1.1)
		# desert
		"cactus": MarchProps.cactus(node, p, rng, sc)
		"cactus_s": MarchProps.cactus(node, p, rng, sc, true)
		"sandrock": MarchProps.sand_rock(node, p, rng, sc)
		"drybush": MarchProps.dry_bush(node, p, rng, sc)
		"bones": MarchProps.bones(node, p, rng, sc)
		"palm": MarchProps.palm(node, p, rng, sc * 1.15)
		"mesa": MarchProps.mesa(node, p, rng, sc)
		"dune": MarchProps.dune(node, p, rng, sc)
		# volcano
		"obsidian": MarchProps.obsidian(node, p, rng, sc)
		"embers": MarchProps.embers(node, p, rng, sc)
		"vent": MarchProps.vent(node, p, rng, sc)
		"deadtree": MarchProps.dead_tree(node, p, rng, sc * 1.1)
		"lavapool": MarchProps.lava_pool(node, p, rng, sc)
		"basalt": MarchProps.basalt(node, p, rng, sc)
		"cone": MarchProps.cone(node, p, rng, sc)
		"ledge_v": MarchProps.ledge(node, p, rng, sc, Color("3d3238"), Color("5a4048"), MarchProps.LAVA)
		# mine
		"shrooms": MarchProps.glow_shrooms(node, p, rng, sc * 1.3)
		"crystals": MarchProps.crystals(node, p, rng, sc)
		"crock": MarchProps.cave_rock(node, p, rng, sc)
		"lantern":
			MarchProps.lantern(node, p, rng, sc, lights < 2)
			return true
		"cart": MarchProps.cart(node, p, rng, sc)
		"pillar": MarchProps.pillar(node, p, rng, sc)
		"bigshroom": MarchProps.big_mushroom(node, p, rng, sc * 1.1)
		"scaffold": MarchProps.scaffold(node, p, rng, sc)
		"pulley": MarchProps.pulley(node, p, rng, sc)
		"ledge": MarchProps.ledge(node, p, rng, sc)
		# frost
		"snowrock": MarchProps.snow_rock(node, p, rng, sc)
		"mound": MarchProps.snow_mound(node, p, rng, sc)
		"icebits": MarchProps.ice_bits(node, p, rng, sc)
		"icespike": MarchProps.ice_spike(node, p, rng, sc)
		"snowman": MarchProps.snowman(node, p, rng, sc)
		"snowpine": MarchProps.pine(node, p, rng, sc * (0.85 if d < 3.6 else 1.25), Color("3f8a6a"), true)
		"peak": MarchProps.peak(node, p, rng, sc)
		"icecliff": MarchProps.ledge(node, p, rng, sc, Color("8a9ab4"), Color("f4f9ff"), MarchProps.ICE)
	return false
