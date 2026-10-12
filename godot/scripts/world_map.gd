class_name WorldMap
extends Node3D
## World map diorama for the Endless March: a painted sea map in a carved wooden frame lying on a dark
## desk, lit by candles (ref: fantasy war-table map). Every region of Regions.LIST is a raised toy island
## with its landmark; unexplored regions hide under clouds with a little lock tower, glowing arcs link the
## islands in marching order, and the trio stands where the march currently is.
## View: orthographic camera (isometric feel) zoomed in on the current region, draggable across the sheet.
## Regions not reached yet are shown in greyscale; a newly reached region "unlocks" with a puff burst
## (grey -> colour), ref: Ttukkapet Survival world map.
## Everything is procedural (primitive meshes, SurfaceTool islands, one sea shader), like the rest of the game.

const HALF := Vector2(5.0, 7.5)          # map sheet half size (x, z)
const FRAME_W := 0.78
const HEIGHT := [0.6, 0.52, 0.44, 0.55, 0.68, 0.46]
const FLOAT_Y := [0.0, 0.0, 0.0, 0.0, 0.0, 1.0]   # frost floats above the sea

const BIOME := {
	"meadow": {"top": [Color("7cc443"), Color("94d455")], "rim": Color("a6d85a"), "beach": Color("f0d9a0"),
		"cliff": [Color("e0a865"), Color("c4844a"), Color("a2663a"), Color("7f4c2e")]},
	"forest": {"top": [Color("3c9446"), Color("52ad4e")], "rim": Color("66b85a"), "beach": Color("e6d29a"),
		"cliff": [Color("d39a5a"), Color("b47a44"), Color("935b34"), Color("6e4228")]},
	"desert": {"top": [Color("efcc84"), Color("f6dc9c")], "rim": Color("fbe6b4"), "beach": Color("f6e2ae"),
		"cliff": [Color("eab274"), Color("d8985a"), Color("bf7c46"), Color("9a5e36")]},
	"volcano": {"top": [Color("7a5852"), Color("644644")], "rim": Color("9a7268"), "beach": Color("5a4440"),
		"cliff": [Color("8a5e4e"), Color("6e4a40"), Color("563832"), Color("3e2826")]},
	"mine": {"top": [Color("54498a"), Color("41706c")], "rim": Color("7468a8"), "beach": Color("5a5080"),
		"cliff": [Color("6a6190"), Color("564e7c"), Color("453e68"), Color("332d50")]},
	"frost": {"top": [Color("eef5fc"), Color("d9e7f6")], "rim": Color("ffffff"), "beach": Color("cfe8ff"),
		"cliff": [Color("c4d2e6"), Color("a6b8d0"), Color("8a9cb8"), Color("6a7c98")]},
}

const SEA_SHADER := """
shader_type spatial;
render_mode specular_schlick_ggx;
uniform vec4 isl[6];
uniform vec2 half_size = vec2(5.0, 7.5);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
float h21(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}
float rr(vec4 d, float a) {
	float p = d.w;
	return d.z * (1.0 + 0.12 * sin(2.0 * a + p) + 0.08 * sin(3.0 * a + p * 2.1) + 0.05 * sin(5.0 * a + p * 0.7) + 0.03 * sin(7.0 * a + p * 3.3));
}
void fragment() {
	vec2 p = wp.xz;
	float e = 99.0;
	for (int i = 0; i < 6; i++) {
		vec2 v = p - isl[i].xy;
		e = min(e, length(v) - rr(isl[i], atan(v.y, v.x)));
	}
	vec2 q = half_size - abs(p);
	float edge = min(q.x, q.y);
	float n = vn(p * 1.3) * 0.6 + vn(p * 3.1) * 0.4;
	vec3 deep = vec3(0.05, 0.30, 0.40);
	vec3 mid = vec3(0.12, 0.55, 0.62);
	vec3 shal = vec3(0.42, 0.84, 0.80);
	vec3 col = mix(deep, mid, smoothstep(0.1, 3.0, edge) * (0.72 + 0.28 * n));
	col = mix(col, shal, (1.0 - smoothstep(0.0, 1.0 + n * 0.35, e)) * 0.9);
	// painted wave strokes drifting in patches
	float wv = sin(p.y * 8.0 + sin(p.x * 2.1 + p.y * 0.4) * 1.8 + TIME * 0.7);
	float patch = smoothstep(0.55, 0.78, vn(p * 0.8 + vec2(TIME * 0.04, 0.0)));
	col = mix(col, vec3(0.78, 0.96, 0.95), smoothstep(0.92, 0.99, wv) * patch * 0.45 * smoothstep(0.35, 1.2, e));
	// foam around the coasts
	float f1 = 1.0 - smoothstep(0.0, 0.045, abs(e - 0.07 - 0.025 * sin(TIME * 1.6 + n * 6.0)));
	float f2 = 1.0 - smoothstep(0.0, 0.035, abs(e - 0.3 - 0.05 * sin(TIME * 1.1 + n * 5.0)));
	col = mix(col, vec3(0.95, 1.0, 1.0), max(f1 * 0.85, f2 * 0.28));
	// engraved compass rose (lower left)
	vec2 cc = p - vec2(-3.25, 5.75);
	float r = length(cc);
	float ang = atan(cc.y, cc.x);
	float R = max(0.12 + 0.95 * pow(abs(cos(2.0 * ang)), 10.0), 0.12 + 0.55 * pow(abs(sin(2.0 * ang)), 10.0));
	float star = 1.0 - smoothstep(R - 0.02, R + 0.02, r);
	float ring = (1.0 - smoothstep(0.0, 0.025, abs(r - 0.82))) + (1.0 - smoothstep(0.0, 0.015, abs(r - 0.94)));
	float half_star = step(0.0, sin(ang * 4.0 + 0.785));
	vec3 ink = mix(vec3(0.86, 0.76, 0.5), vec3(0.7, 0.58, 0.36), half_star);
	col = mix(col, ink, clamp(star * 0.42 + ring * 0.4, 0.0, 0.62));
	// faint latitude / longitude lines
	vec2 g = abs(fract(p / 2.5) - 0.5);
	float gl = 1.0 - smoothstep(0.0, 0.007, min(g.x, g.y));
	col = mix(col, deep * 0.7, gl * 0.22 * smoothstep(0.3, 1.0, e));
	// parchment margin under the frame
	float m = 1.0 - smoothstep(0.14, 0.2 + n * 0.07, edge);
	col = mix(col, mix(vec3(0.92, 0.82, 0.6), vec3(0.5, 0.36, 0.22), 1.0 - smoothstep(0.0, 0.12, edge)), m);
	ALBEDO = col;
	ROUGHNESS = 0.32;
	SPECULAR = 0.45;
	EMISSION = col * 0.12;
}
"""

var cur := 0                 # current region (unbounded, laps keep counting)
var u := 0.0                 # progress through the current region 0..1
var camps_u: Array = []      # 10 camp positions (0..1) in the current region
var cleared := 0             # camps already beaten in the current region
var cam: Camera3D
var anchors: Array = []      # per island: label anchor (world)
var marker: Node3D
var _t := 0.0
var _bob: Array = []         # [node, base Vector3, phase, amp]
var _flow: Array = []        # [node, Array path points]
var _flames: Array = []
var _lights: Array = []
var _ring: MeshInstance3D
var _noise := FastNoiseLite.new()
var _gold: StandardMaterial3D
var unlock := false          # play the unlock of the current region (grey until play_unlock())
var focus := Vector3.ZERO     # orthographic camera target on the map sheet
var _here_fx: Node3D          # path dots + camps of the current region (shown after an unlock)
var _gray_nodes := {}         # island index -> greyscale island node
var _color_nodes := {}        # island index -> colour island node
var _gray_mats := {}
var _vm: StandardMaterial3D   # shared island material (see _vmat)

const PITCH := 0.84           # ~48 deg looking down
const ZOOM := 7.6             # visible map width (units)

static func cur_mod(r: int) -> int:
	return posmod(r, Regions.count())

func build(p_cur: int, p_u: float, p_camps: Array, p_cleared: int, p_unlock := false) -> void:
	cur = p_cur
	unlock = p_unlock
	u = clampf(p_u, 0.0, 1.0)
	camps_u = p_camps
	cleared = p_cleared
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise.seed = 5
	_noise.frequency = 0.9
	_gold = StandardMaterial3D.new()
	_gold.albedo_color = Color("f2c255")
	_gold.metallic = 0.35
	_gold.roughness = 0.3
	_gold.metallic_specular = 0.8
	_gold.emission_enabled = true
	_gold.emission = Color("6a4a10")
	_gold.rim_enabled = true
	_gold.rim = 0.3
	_env()
	_table()
	_frame()
	_sea()
	for i in Regions.count():
		var c := center(i)
		anchors.append(Vector3(c.x, top_y(i) + 0.05, c.y + Regions.shape_r(i, PI * 0.5) * 0.55))
	for i in Regions.count():
		var st := island_state(i)
		if unlock and st == "here":
			_gray_nodes[i] = _island(i, true)
			_color_nodes[i] = _island(i, false)
			_color_nodes[i].visible = false
		else:
			_island(i, st == "locked")
	_sea_clouds()
	_here_fx = Node3D.new()
	_here_fx.visible = not unlock
	add_child(_here_fx)
	_routes()
	_make_marker()
	_boats()
	_desk_props()
	_camera()

# ---------------------------------------------------------------- state helpers
func _lap() -> int:
	return Regions.lap(cur)

## "done" (already marched through), "here", "next" (seen on an earlier lap) or "locked" (not reached yet: greyscale).
func island_state(i: int) -> String:
	var c := cur_mod(cur)
	if i == c:
		return "here"
	if i < c:
		return "done"
	return "next" if _lap() > 0 else "locked"

static func center(i: int) -> Vector2:
	return Regions.LIST[i]["map"]

func top_y(i: int) -> float:
	return FLOAT_Y[i] + HEIGHT[i]

func _outline(i: int, a: float, k := 1.0) -> Vector2:
	return center(i) + Vector2(cos(a), sin(a)) * Regions.shape_r(i, a) * k

## Point on island i's march path (entry -> centre -> exit), t in 0..1.
func path_point(i: int, t: float) -> Vector3:
	var n := Regions.count()
	var c := center(i)
	var prev := center(posmod(i - 1, n))
	var nxt := center(posmod(i + 1, n))
	var a_in := (prev - c).angle()
	var a_out := (nxt - c).angle()
	var p0 := _outline(i, a_in, 0.72)
	var p2 := _outline(i, a_out, 0.72)
	var p1 := c * 2.0 - (p0 + p2) * 0.5
	var q := p0.lerp(p1, t).lerp(p1.lerp(p2, t), t)
	return Vector3(q.x, top_y(i) + 0.035, q.y)

# ---------------------------------------------------------------- environment
func _env() -> void:
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("140f22")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("8a96d0")
	e.ambient_light_energy = 0.58
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_strength = 1.0
	e.glow_hdr_threshold = 1.05
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	e.ssao_enabled = true
	e.ssao_radius = 0.6
	e.ssao_intensity = 1.8
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.22
	e.adjustment_contrast = 1.08
	we.environment = e
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("ffe6c0")
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.7
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
	sun.position = Vector3(6, 12, -6)
	sun.look_at(Vector3(-1, 0, 2), Vector3.UP)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color("7f9cff")
	fill.light_energy = 0.32
	add_child(fill)
	fill.position = Vector3(-8, 5, 8)
	fill.look_at(Vector3.ZERO, Vector3.UP)

func _camera() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.near = 0.5
	cam.far = 120.0
	add_child(cam)
	var c := center(cur_mod(cur))
	focus = clamp_focus(Vector3(c.x, 0.0, c.y + 1.7))
	cam.size = ZOOM * 1.22
	_apply_cam()
	cam.current = true
	cam.create_tween().tween_property(cam, "size", ZOOM, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _apply_cam() -> void:
	cam.position = focus + Vector3(0, sin(PITCH), cos(PITCH)) * 40.0
	cam.look_at(focus, Vector3.UP)

func clamp_focus(f: Vector3) -> Vector3:
	return Vector3(clampf(f.x, -1.6, 1.6), 0.0, clampf(f.z, -4.0, 5.4))

## Drag the map: rel in screen pixels of a view vp_w pixels wide.
func pan(rel: Vector2, vp_w: float) -> void:
	var k := cam.size / vp_w
	focus = clamp_focus(focus - Vector3(rel.x * k, 0.0, rel.y * k / sin(PITCH)))
	_apply_cam()

# ---------------------------------------------------------------- mesh helpers
## Vertex-coloured island material, shared by every island mesh (_grayify leaves vertex-colour materials alone).
func _vmat() -> StandardMaterial3D:
	if _vm == null:
		_vm = StandardMaterial3D.new()
		_vm.vertex_color_use_as_albedo = true
		_vm.vertex_color_is_srgb = true
		_vm.roughness = 0.9
		_vm.metallic_specular = 0.2
		_vm.rim_enabled = true
		_vm.rim = 0.2
	return _vm

func _commit(st: SurfaceTool, parent: Node3D) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _vmat()
	parent.add_child(mi)
	return mi

func _bobber(n: Node3D, amp: float, phase := -1.0) -> void:
	_bob.append([n, n.position, phase if phase >= 0.0 else randf() * TAU, amp])

# ---------------------------------------------------------------- desk + frame
func _table() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var z := -16.0
	while z < 16.0:
		var w := rng.randf_range(1.1, 1.6)
		MarchProps._box(self, Vector3(40, 0.6, w - 0.04), Color("3a2822").lerp(Color("4a3229"), rng.randf()), Vector3(0, -0.36, z + w * 0.5))
		z += w
	# deep blue cloth draped along both long sides
	for side in [-1.0, 1.0]:
		MarchProps._rb(self, Vector3(4.6, 0.3, 30.0), Color("1c285e"), Vector3(side * 8.6, -0.12, -2.0), Vector3(0, 0, side * 0.03), 0.3)
		for k in 2:
			MarchProps._rb(self, Vector3(0.7, 0.22, 12.0), Color("22306c"), Vector3(side * (7.2 + k * 1.1), 0.02, -4.0 + k * 2.0), Vector3(0, 0.04 * side, 0), 0.6)

func _frame() -> void:
	var wood := Color("b07636")
	var dark := Color("6a4122")
	var lip := Color("4a2c18")
	var w := FRAME_W
	for side in [-1.0, 1.0]:
		# long bars (left / right)
		var x: float = side * (HALF.x + w * 0.5)
		var L := HALF.y * 2.0 + w * 2.0
		MarchProps._rb(self, Vector3(w + 0.14, 0.24, L + 0.14), dark, Vector3(x, 0.05, 0), Vector3.ZERO, 0.25)
		MarchProps._rb(self, Vector3(w * 0.8, 0.3, L), wood, Vector3(x, 0.16, 0), Vector3.ZERO, 0.3)
		MarchProps._rb(self, Vector3(w * 0.36, 0.12, L - 0.3), wood.lightened(0.12), Vector3(x + side * 0.05, 0.3, 0), Vector3.ZERO, 0.5)
		MarchProps._mi(self, MarchProps._box_mesh(Vector3(0.07, 0.06, HALF.y * 2.0)), Color.WHITE, Vector3(side * (HALF.x + 0.06), 0.24, 0), Vector3.ONE, Vector3.ZERO, _gold)
		MarchProps._box(self, Vector3(0.14, 0.1, HALF.y * 2.0), lip, Vector3(side * (HALF.x + 0.02), 0.03, 0))
		# short bars (top / bottom)
		var z: float = side * (HALF.y + w * 0.5)
		var W := HALF.x * 2.0 + w * 2.0
		MarchProps._rb(self, Vector3(W + 0.14, 0.24, w + 0.14), dark, Vector3(0, 0.05, z), Vector3.ZERO, 0.25)
		MarchProps._rb(self, Vector3(W, 0.3, w * 0.8), wood, Vector3(0, 0.16, z), Vector3.ZERO, 0.3)
		MarchProps._rb(self, Vector3(W - 0.3, 0.12, w * 0.36), wood.lightened(0.12), Vector3(0, 0.3, z + side * 0.05), Vector3.ZERO, 0.5)
		MarchProps._mi(self, MarchProps._box_mesh(Vector3(HALF.x * 2.0, 0.06, 0.07)), Color.WHITE, Vector3(0, 0.24, side * (HALF.y + 0.06)), Vector3.ONE, Vector3.ZERO, _gold)
		MarchProps._box(self, Vector3(HALF.x * 2.0, 0.1, 0.14), lip, Vector3(0, 0.03, side * (HALF.y + 0.02)))
	# carved corner blocks with brass knobs
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * (HALF.x + w * 0.5), 0.0, sz * (HALF.y + w * 0.5))
			MarchProps._rb(self, Vector3(w + 0.36, 0.44, w + 0.36), dark.lightened(0.08), p + Vector3(0, 0.2, 0), Vector3.ZERO, 0.3)
			MarchProps._rb(self, Vector3(w + 0.1, 0.16, w + 0.1), wood, p + Vector3(0, 0.46, 0), Vector3.ZERO, 0.4)
			MarchProps._mi(self, MarchProps._sphere_mesh(0.2), Color.WHITE, p + Vector3(0, 0.6, 0), Vector3(1, 0.8, 1), Vector3.ZERO, _gold)
	# arched crest over the top edge with a glowing gem
	var crest := Node3D.new()
	crest.position = Vector3(0, 0.1, -(HALF.y + w * 0.5))
	add_child(crest)
	MarchProps._mi(crest, MarchProps._torus_mesh(1.25, 1.7), dark.lightened(0.05), Vector3.ZERO, Vector3(1, 1.0, 0.7), Vector3(PI * 0.5, 0, 0))
	MarchProps._mi(crest, MarchProps._torus_mesh(1.34, 1.6), wood, Vector3(0, 0, 0.06), Vector3(1, 1.0, 0.8), Vector3(PI * 0.5, 0, 0))
	MarchProps._mi(crest, MarchProps._torus_mesh(1.44, 1.5), Color.WHITE, Vector3(0, 0, 0.14), Vector3(1, 1.0, 0.6), Vector3(PI * 0.5, 0, 0), _gold)
	MarchProps._rb(crest, Vector3(0.7, 0.62, 0.36), dark, Vector3(0, 1.56, 0), Vector3.ZERO, 0.35)
	MarchProps._mi(crest, MarchProps._sphere_mesh(0.2), Color.WHITE, Vector3(0, 1.58, 0.18), Vector3(1, 1.2, 0.6), Vector3.ZERO, MarchProps.glow_mat(Color("5fd8ff"), 1.6))
	MarchProps._mi(crest, MarchProps._torus_mesh(0.2, 0.27), Color.WHITE, Vector3(0, 1.58, 0.18), Vector3.ONE, Vector3(PI * 0.5, 0, 0), _gold)

func _sea() -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = HALF * 2.0
	mi.mesh = pm
	var sm := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SEA_SHADER
	sm.shader = sh
	var arr := PackedVector4Array()
	for i in Regions.count():
		var d: Dictionary = Regions.LIST[i]
		var c: Vector2 = d["map"]
		arr.append(Vector4(c.x, c.y, d["size"] * (0.92 if FLOAT_Y[i] > 0.0 else 1.0), d["seed"] * 1.37))
	sm.set_shader_parameter("isl", arr)
	sm.set_shader_parameter("half_size", HALF)
	mi.material_override = sm
	add_child(mi)

# ---------------------------------------------------------------- islands
func _island(i: int, gray := false) -> Node3D:
	var d: Dictionary = Regions.LIST[i]
	var b: Dictionary = BIOME[d["theme"]]
	var node := Node3D.new()
	node.name = "Island%d%s" % [i, "g" if gray else ""]
	add_child(node)
	var c := center(i)
	var y0: float = FLOAT_Y[i]
	var h: float = HEIGHT[i]
	var top := y0 + h
	var N := 72
	# top cap: rings from the centre out to a light rim lip, gently domed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fr := [0.0, 0.25, 0.5, 0.7, 0.85, 0.94, 1.0]
	for f in fr:
		for j in N + 1:
			var a := TAU * j / N
			var p := _outline(i, a, f)
			var nz := clampf(0.5 + _noise.get_noise_2d(p.x * 1.4, p.y * 1.4) * 0.9, 0.0, 1.0)
			var col: Color = (b["top"][0] as Color).lerp(b["top"][1], nz)
			if f >= 0.94:
				col = col.lerp(b["rim"], 0.65 if f >= 1.0 else 0.3)
			st.set_color(_g(col) if gray else col)
			st.add_vertex(Vector3(p.x, top + 0.07 * (1.0 - f * f), p.y))
	_grid(st, fr.size(), N + 1)
	_commit(st, node)
	# cliffs: strata bands flaring slightly outward to the sea (or a rocky cone under a floating island)
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lv: Array
	if y0 > 0.0:
		lv = [[1.0, top, 0], [1.015, top - 0.08, 0], [1.0, y0 + 0.02, 1], [0.86, y0 - 0.3, 2], [0.62, y0 - 0.6, 2], [0.34, y0 - 0.88, 3], [0.06, y0 - 1.08, 3]]
	else:
		lv = [[1.0, top, 0], [1.015, top - 0.07, 0], [1.022, top * 0.66, 1], [1.034, top * 0.4, 2], [1.05, top * 0.16, 3], [1.06, -0.01, 3]]
	for l in lv:
		for j in N + 1:
			var a := TAU * j / N
			var jag := 1.0 + 0.025 * _noise.get_noise_2d(a * 6.0, l[1] * 9.0)
			var p := _outline(i, a, l[0] * jag)
			var col2: Color = b["cliff"][l[2]]
			col2 = col2.lerp(col2.darkened(0.12), clampf(0.5 + _noise.get_noise_2d(a * 12.0, l[1] * 4.0), 0.0, 1.0))
			st2.set_color(_g(col2) if gray else col2)
			st2.add_vertex(Vector3(p.x, l[1], p.y))
	_grid(st2, lv.size(), N + 1, true)
	_commit(st2, node)
	# beach / shelf at sea level
	if y0 <= 0.0:
		var st3 := SurfaceTool.new()
		st3.begin(Mesh.PRIMITIVE_TRIANGLES)
		for f in [1.03, 1.1, 1.14]:
			for j in N + 1:
				var a := TAU * j / N
				var p := _outline(i, a, f)
				var bc := (b["beach"] as Color).lerp(Color("7fd6cc"), 0.0 if f < 1.12 else 0.55)
				st3.set_color(_g(bc) if gray else bc)
				st3.add_vertex(Vector3(p.x, 0.012 if f < 1.12 else 0.004, p.y))
		_grid(st3, 3, N + 1)
		_commit(st3, node)
	else:
		_float_clouds(node, i)
	_landmark(node, i)
	var state := island_state(i)
	if not gray and (state == "done" or state == "next"):
		_flag(node, path_point(i, 1.0), state == "done")
	if gray:
		_grayify(node)
	return node

## Greyscale tone used for regions not reached yet.
static func _g(c: Color) -> Color:
	var l := 0.3 * c.r + 0.59 * c.g + 0.11 * c.b
	var v := clampf(0.3 + l * 0.66, 0.0, 0.92)
	return Color(v, v, v * 1.03, c.a)

func _grayify(n: Node) -> void:
	for ch in n.get_children():
		if ch is MeshInstance3D:
			var m = ch.material_override
			if m is StandardMaterial3D and not m.vertex_color_use_as_albedo:
				var key: int = m.get_instance_id()
				if not _gray_mats.has(key):
					var gm: StandardMaterial3D = m.duplicate()
					gm.albedo_color = _g(Color(minf(m.albedo_color.r, 1.0), minf(m.albedo_color.g, 1.0), minf(m.albedo_color.b, 1.0), m.albedo_color.a))
					if gm.emission_enabled:
						gm.emission = _g(gm.emission) * 0.3
					_gray_mats[key] = gm
				ch.material_override = _gray_mats[key]
		elif ch is Light3D:
			ch.visible = false
		_grayify(ch)

func _grid(st: SurfaceTool, rows: int, cols: int, flip := false) -> void:
	for r in rows - 1:
		for cc in cols - 1:
			var a := r * cols + cc
			var b := a + cols
			if flip:
				st.add_index(a)
				st.add_index(a + 1)
				st.add_index(b)
				st.add_index(a + 1)
				st.add_index(b + 1)
				st.add_index(b)
			else:
				st.add_index(a)
				st.add_index(b)
				st.add_index(a + 1)
				st.add_index(a + 1)
				st.add_index(b)
				st.add_index(b + 1)

## Random spot on island i away from its march path and its landmark.
func _spot(i: int, rng: RandomNumberGenerator, keep_from: Array, k := 0.8) -> Vector3:
	var c := center(i)
	for tries in 30:
		var a := rng.randf() * TAU
		var p := _outline(i, a, sqrt(rng.randf()) * k)
		var ok := true
		for t in 9:
			var pp := path_point(i, t / 8.0)
			if p.distance_to(Vector2(pp.x, pp.z)) < 0.3:
				ok = false
				break
		for q in keep_from:
			if p.distance_to(q[0]) < q[1]:
				ok = false
		if ok:
			return Vector3(p.x, top_y(i) + 0.03, p.y)
	return Vector3(c.x, top_y(i) + 0.03, c.y)

## Landmark spot: beside the path, on the side away from the route bend.
func _landmark_pos(i: int) -> Vector2:
	var c := center(i)
	var p0 := path_point(i, 0.0)
	var p2 := path_point(i, 1.0)
	var dir := Vector2(p2.x - p0.x, p2.z - p0.z).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var mid := path_point(i, 0.5)
	var side := signf(perp.dot(c - Vector2(mid.x, mid.z)))
	if side == 0.0:
		side = 1.0
	return c + perp * side * Regions.LIST[i]["size"] * 0.42

func _landmark(node: Node3D, i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + i
	var lp := _landmark_pos(i)
	var top := top_y(i)
	var L := Vector3(lp.x, top + 0.03, lp.y)
	var keep := [[lp, 0.62]]
	if Regions.LIST[i]["theme"] != "volcano":
		_terraces(node, i, rng, keep)
	match Regions.LIST[i]["theme"]:
		"meadow":
			_castle(node, L, 0.62)
			for k in 4:
				_house(node, _spot(i, rng, keep, 0.75), rng)
			for k in 16:
				var p := _spot(i, rng, keep)
				if rng.randf() < 0.55:
					MarchProps.pine(node, p, rng, rng.randf_range(0.16, 0.22))
				else:
					MarchProps.puff_tree(node, p, rng, rng.randf_range(0.18, 0.24))
		"forest":
			MarchProps.giant_tree(node, L, rng, 0.56)
			var l := OmniLight3D.new()
			l.light_color = Color("5fd8ff")
			l.light_energy = 1.4
			l.omni_range = 1.6
			l.position = L + Vector3(0, 0.4, 0.3)
			node.add_child(l)
			for k in 26:
				var p := _spot(i, rng, keep, 0.86)
				if rng.randf() < 0.7:
					MarchProps.pine(node, p, rng, rng.randf_range(0.15, 0.23), Color("2f7f3e"))
				else:
					MarchProps.egg_trees(node, p, rng, rng.randf_range(0.18, 0.24))
		"desert":
			MarchProps._cyl(node, 0.0, 0.62, 0.62, Color("e3a862"), L + Vector3(0, 0.31, 0), Vector3(0, PI * 0.25, 0), 4)
			MarchProps._cyl(node, 0.0, 0.1, 0.1, Color("ffd23f"), L + Vector3(0, 0.62, 0), Vector3(0, PI * 0.25, 0), 4)
			for k in 3:
				MarchProps.mesa(node, _spot(i, rng, keep, 0.8), rng, rng.randf_range(0.22, 0.3))
			for k in 10:
				var p := _spot(i, rng, keep)
				if rng.randf() < 0.5:
					MarchProps.cactus(node, p, rng, rng.randf_range(0.2, 0.28))
				else:
					MarchProps.palm(node, p, rng, rng.randf_range(0.2, 0.26))
		"volcano":
			var vol := Node3D.new()
			vol.position = L
			node.add_child(vol)
			var H := 1.15
			MarchProps._cyl(vol, 0.3, 0.95, H, Color("4a3a42"), Vector3(0, H * 0.5, 0), Vector3.ZERO, 14)
			MarchProps._cyl(vol, 0.22, 0.36, 0.14, Color("2c2228"), Vector3(0, H + 0.02, 0), Vector3.ZERO, 14)
			MarchProps._mi(vol, MarchProps._cyl_mesh(0.24, 0.24, 0.03, 14), Color.WHITE, Vector3(0, H + 0.06, 0), Vector3.ONE, Vector3.ZERO, MarchProps.glow_mat(MarchProps.LAVA, 2.2))
			for k in 4:
				var a := TAU * k / 4.0 + 0.4
				var rv := Node3D.new()
				rv.rotation.y = -a
				vol.add_child(rv)
				MarchProps._mi(rv, MarchProps._box_mesh(Vector3(0.07, 0.025, 0.92)), Color.WHITE, Vector3(0, H * 0.5, 0.42), Vector3.ONE, Vector3(-atan(H / 0.7), 0, 0), MarchProps.glow_mat(MarchProps.LAVA, 1.6))
				MarchProps._mi(rv, MarchProps._box_mesh(Vector3(0.09, 0.02, 0.7)), Color.WHITE, Vector3(0, 0.02, 1.2), Vector3.ONE, Vector3(0, 0.3 * (k % 2 - 0.5), 0), MarchProps.glow_mat(MarchProps.LAVA, 1.4))
			var l2 := OmniLight3D.new()
			l2.light_color = Color("ff7a2a")
			l2.light_energy = 2.4 if island_state(i) != "locked" else 0.9
			l2.omni_range = 2.4
			l2.position = Vector3(0, H + 0.4, 0)
			vol.add_child(l2)
			_lights.append(l2)
			for k in 3:
				var sm := MarchProps._mi(vol, MarchProps._sphere_mesh(0.16), Color.WHITE, Vector3(0, H + 0.3 + k * 0.28, 0), Vector3.ONE, Vector3.ZERO, Mats.puff(Color(0.42, 0.38, 0.44, 0.6)))
				_bobber(sm, 0.06)
			for k in 8:
				var p := _spot(i, rng, [[lp, 1.1]])
				match k % 3:
					0: MarchProps.basalt(node, p, rng, rng.randf_range(0.2, 0.28))
					1: MarchProps.dead_tree(node, p, rng, rng.randf_range(0.24, 0.3))
					_: MarchProps.lava_pool(node, p, rng, rng.randf_range(0.25, 0.32))
		"mine":
			MarchProps.scaffold(node, L, rng, 0.3)
			MarchProps.pulley(node, L + Vector3(0.45, 0, 0.2), rng, 0.3)
			for k in 10:
				var p := _spot(i, rng, keep)
				match k % 3:
					0: MarchProps.big_mushroom(node, p, rng, rng.randf_range(0.24, 0.3))
					1: MarchProps.crystals(node, p, rng, rng.randf_range(0.4, 0.55))
					_: MarchProps.pillar(node, p, rng, rng.randf_range(0.22, 0.3))
		"frost":
			for k in 3:
				MarchProps.peak(node, L + Vector3((k - 1) * 0.42, 0, (k % 2) * 0.25), rng, 0.5 - (k % 2) * 0.12)
			for k in 14:
				var p := _spot(i, rng, [[lp, 0.75]])
				if rng.randf() < 0.75:
					MarchProps.pine(node, p, rng, rng.randf_range(0.15, 0.21), Color("3f8a6a"), true)
				else:
					MarchProps.ice_spike(node, p, rng, rng.randf_range(0.25, 0.32))

## Raised grassy (sandy / snowy / mossy) terraces and soft hills: the layered relief of a toy map.
func _terraces(node: Node3D, i: int, rng: RandomNumberGenerator, keep: Array) -> void:
	var b: Dictionary = BIOME[Regions.LIST[i]["theme"]]
	var top: Color = b["top"][0]
	for k in 2:
		var p := _spot(i, rng, keep, 0.62)
		var w := rng.randf_range(0.55, 0.8)
		var d := rng.randf_range(0.45, 0.65)
		var h := rng.randf_range(0.14, 0.22)
		var t := Node3D.new()
		t.position = p
		t.rotation.y = rng.randf() * TAU
		node.add_child(t)
		MarchProps._rb(t, Vector3(w, h, d), b["cliff"][1], Vector3(0, h * 0.5 - 0.03, 0), Vector3.ZERO, 0.22)
		MarchProps._rb(t, Vector3(w + 0.06, 0.07, d + 0.06), (top as Color).lightened(0.06), Vector3(0, h - 0.01, 0), Vector3.ZERO, 0.3)
		keep.append([Vector2(p.x, p.z), maxf(w, d) * 0.6])
	for k in 3:
		var p2 := _spot(i, rng, keep, 0.8)
		var r := rng.randf_range(0.22, 0.34)
		MarchProps._sph(node, r, (top as Color).darkened(0.05), p2 + Vector3(0, -0.02, 0), Vector3(1.3, 0.42, 1.0))

## Royal castle: corner towers with blue cone roofs, crenellated walls, a tall keep, gate and gold flags.
func _castle(parent: Node3D, pos: Vector3, s: float) -> void:
	var n := Node3D.new()
	n.position = pos
	n.scale = Vector3.ONE * s
	n.rotation.y = 0.35
	parent.add_child(n)
	var wall := Color("f2e8d4")
	var roof := Color("4a6fe0")
	MarchProps._rb(n, Vector3(1.5, 0.16, 1.3), Color("b9b2c4"), Vector3(0, 0.05, 0), Vector3.ZERO, 0.3)
	for sx in [-1.0, 1.0]:
		MarchProps._box(n, Vector3(0.1, 0.42, 1.0), wall, Vector3(sx * 0.6, 0.33, 0))
		MarchProps._box(n, Vector3(1.2, 0.42, 0.1), wall, Vector3(0, 0.33, sx * 0.5))
		for k in 4:
			MarchProps._box(n, Vector3(0.12, 0.08, 0.12), wall.darkened(0.06), Vector3(sx * 0.6, 0.58, -0.36 + k * 0.24))
			MarchProps._box(n, Vector3(0.12, 0.08, 0.12), wall.darkened(0.06), Vector3(-0.42 + k * 0.28, 0.58, sx * 0.5))
	MarchProps._box(n, Vector3(0.24, 0.28, 0.04), Color("4a3428"), Vector3(0, 0.25, 0.53))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var p := Vector3(sx * 0.6, 0, sz * 0.5)
			MarchProps._cyl(n, 0.15, 0.17, 0.82, wall, p + Vector3(0, 0.45, 0))
			MarchProps._cyl(n, 0.0, 0.22, 0.38, roof, p + Vector3(0, 1.05, 0))
			_pennant(n, p + Vector3(0, 1.24, 0), 0.22, Color("ffd23f"))
	MarchProps._box(n, Vector3(0.5, 0.95, 0.46), wall, Vector3(0, 0.58, -0.05))
	MarchProps._cyl(n, 0.0, 0.42, 0.5, roof, Vector3(0, 1.3, -0.05), Vector3(0, PI * 0.25, 0), 4)
	MarchProps._cyl(n, 0.17, 0.19, 1.45, wall, Vector3(0.12, 0.8, -0.32))
	MarchProps._cyl(n, 0.0, 0.25, 0.55, roof.lightened(0.08), Vector3(0.12, 1.8, -0.32))
	_pennant(n, Vector3(0.12, 2.06, -0.32), 0.34, Color("e2412c"))
	for k in 3:
		MarchProps._mi(n, MarchProps._box_mesh(Vector3(0.07, 0.1, 0.02)), Color.WHITE, Vector3(-0.12 + k * 0.12, 0.8, 0.19), Vector3.ONE, Vector3.ZERO, MarchProps.glow_mat(Color("ffd27a"), 1.4))

func _pennant(parent: Node3D, base: Vector3, h: float, col: Color) -> void:
	MarchProps._cyl(parent, 0.012, 0.012, h, Color("8a6a4a"), base + Vector3(0, h * 0.5, 0), Vector3.ZERO, 6)
	var f := MarchProps._box(parent, Vector3(0.16, 0.09, 0.012), col, base + Vector3(0.08, h - 0.05, 0))
	_bobber(f, 0.0)

func _house(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rng.randf() * TAU
	n.scale = Vector3.ONE * rng.randf_range(0.8, 1.0)
	parent.add_child(n)
	MarchProps._box(n, Vector3(0.24, 0.16, 0.19), Color("f6ecd8"), Vector3(0, 0.08, 0))
	var roof := MarchProps._cyl(n, 0.0, 0.17, 0.27, Color("d0573a"), Vector3(0, 0.22, 0), Vector3(PI * 0.5, 0, 0), 3)
	roof.scale.z *= 0.7   # flattened roof (multiplied: the scale holds the size)
	MarchProps._box(n, Vector3(0.05, 0.08, 0.01), Color("6a4a30"), Vector3(0, 0.04, 0.1))

## Cleared region: a planted gold banner at its exit.
func _flag(parent: Node3D, p: Vector3, gold: bool) -> void:
	MarchProps._cyl(parent, 0.018, 0.022, 0.6, Color("6a4a30"), p + Vector3(0, 0.3, 0), Vector3.ZERO, 6)
	var f := MarchProps._rb(parent, Vector3(0.28, 0.18, 0.025), Color("ffcf40") if gold else Color("c8c0d8"), p + Vector3(0.15, 0.5, 0), Vector3.ZERO, 0.25)
	_bobber(f, 0.0)
	MarchProps._mi(parent, MarchProps._sphere_mesh(0.035), Color.WHITE, p + Vector3(0, 0.62, 0), Vector3.ONE, Vector3.ZERO, _gold)

# ---------------------------------------------------------------- clouds + locks
func _cloud_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("fff8e4")
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.rim_enabled = true
	m.rim = 0.45
	m.rim_tint = 0.1
	m.emission_enabled = true
	m.emission = Color("a8c8d8") * 0.2
	return m

func _cloud(parent: Node3D, pos: Vector3, s: float, rng: RandomNumberGenerator, mat: StandardMaterial3D) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	var cnt := rng.randi_range(4, 6)
	for k in cnt:
		var r := s * rng.randf_range(0.32, 0.5) * (1.25 if k == 0 else 1.0)
		var off := Vector3(rng.randf_range(-0.55, 0.55) * s, rng.randf_range(0.0, 0.14) * s, rng.randf_range(-0.35, 0.35) * s)
		if k == 0:
			off = Vector3(0, 0.12 * s, 0)
		MarchProps._mi(n, MarchProps._sphere_mesh(1.0), Color.WHITE, off, Vector3(r, r * 0.72, r), Vector3.ZERO, mat)
	_bobber(n, 0.05)
	return n

## Soft cream clouds resting on the sheet around the map edges (ref: clouds drawn over the map).
func _sea_clouds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mat := _cloud_mat()
	for p in [Vector2(-4.3, -6.6), Vector2(4.2, -6.2), Vector2(-4.5, 4.9), Vector2(4.4, 3.6), Vector2(4.4, -1.6),
			Vector2(-4.6, -0.6), Vector2(2.3, 7.0), Vector2(-2.0, 7.1)]:
		_cloud(self, Vector3(p.x, rng.randf_range(0.25, 0.5), p.y), rng.randf_range(0.9, 1.25), rng, mat)

## Clouds drifting under the floating island.
func _float_clouds(parent: Node3D, i: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 500 + i
	var mat := _cloud_mat()
	for k in 9:
		var a := TAU * k / 9.0 + rng.randf() * 0.4
		var p := _outline(i, a, rng.randf_range(0.75, 1.15))
		_cloud(parent, Vector3(p.x, rng.randf_range(0.1, 0.45), p.y), rng.randf_range(0.8, 1.15), rng, mat)

# ---------------------------------------------------------------- routes + marker
## Glowing tube along a polyline (ref: the bright blue route arcs).
func _tube(pts: Array, r: float, mat: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var seg := 6
	for k in pts.size():
		var p: Vector3 = pts[k]
		var fwd: Vector3 = (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
		var side := fwd.cross(Vector3.UP).normalized()
		if side.length() < 0.01:
			side = Vector3.RIGHT
		var upv := side.cross(fwd).normalized()
		for j in seg + 1:
			var a := TAU * j / seg
			st.add_vertex(p + (side * cos(a) + upv * sin(a)) * r)
	_grid(st, pts.size(), seg + 1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi

func _arc(i: int) -> Array:
	var n := Regions.count()
	var j := posmod(i + 1, n)
	var a := path_point(i, 1.0)
	var b := path_point(j, 0.0)
	var mid := (a + b) * 0.5 + Vector3(0, 0.18 + a.distance_to(b) * 0.03, 0)
	var pts: Array = []
	for k in 33:
		var t := k / 32.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return pts

func _routes() -> void:
	var n := Regions.count()
	var c := cur_mod(cur)
	var bright := MarchProps.glow_mat(Color("6fe6ff"), 1.9)
	var dim := Mats.fx(Color(0.75, 0.92, 1.0, 0.28))
	for i in n:
		var pts := _arc(i)
		var walked := i < c or (_lap() > 0 and i == n - 1)
		if walked:
			_tube(pts, 0.045, bright)
			_tube(pts, 0.1, Mats.fx(Color(0.4, 0.85, 1.0, 0.22), true))
		else:
			# dashed, faint: the road still ahead
			for k in range(0, pts.size() - 2, 3):
				_tube([pts[k], pts[k + 1], pts[k + 2]], 0.03, dim)
		if i == c:
			# sparks flowing toward the next region
			for k in 4:
				var dot := MarchProps._mi(self, MarchProps._sphere_mesh(0.06), Color.WHITE, pts[0], Vector3.ONE, Vector3.ZERO, MarchProps.glow_mat(Color("bff6ff"), 2.0))
				_flow.append([dot, pts, k / 4.0])
	# dotted marching path across each visible island
	for i in n:
		var st := island_state(i)
		if st == "locked":
			continue
		var par: Node3D = _here_fx if st == "here" else self
		for k in 25:
			var t := k / 24.0
			var walked2 := st == "done" or (st == "here" and t <= u)
			var col := Color("ffe9a8") if walked2 else Color("fff8ee")
			var mat: Material = MarchProps.glow_mat(col, 1.25) if walked2 else Mats.prop(col)
			MarchProps._mi(par, MarchProps._cyl_mesh(0.035, 0.035, 0.012, 10), Color.WHITE, path_point(i, t), Vector3.ONE, Vector3.ZERO, mat)
	# camps of the current region: beaten ones gold, waiting ones red, the mid-boss a big skull plate
	var ci := cur_mod(cur)
	for k in camps_u.size():
		var p := path_point(ci, camps_u[k])
		var boss: bool = k == camps_u.size() - 1
		var done := k < cleared
		var col := Color("ffcf40") if done else (Color("ff4f5e") if boss else Color("ff8a6a"))
		var r := 0.15 if boss else 0.085
		MarchProps._cyl(_here_fx, r + 0.02, r + 0.02, 0.03, Color("2a1c30"), p + Vector3(0, 0.01, 0), Vector3.ZERO, 16)
		MarchProps._mi(_here_fx, MarchProps._cyl_mesh(r, r, 0.04, 16), Color.WHITE, p + Vector3(0, 0.02, 0), Vector3.ONE, Vector3.ZERO, MarchProps.glow_mat(col, 1.3) if not done else _gold)
		if boss and not done:
			var sk := Node3D.new()
			sk.position = p + Vector3(0, 0.12, 0)
			_here_fx.add_child(sk)
			MarchProps._sph(sk, 0.08, Color("f6ecd8"), Vector3.ZERO, Vector3(1, 0.9, 0.9))
			for x in [-0.03, 0.03]:
				MarchProps._sph(sk, 0.02, Color("2a1c30"), Vector3(x, 0.0, 0.065))
			for x in [-1.0, 1.0]:
				MarchProps._cyl(sk, 0.0, 0.025, 0.08, Color("ff4f5e"), Vector3(x * 0.07, 0.07, 0), Vector3(0, 0, -x * 0.5), 6)
			_bobber(sk, 0.03)

## The trio standing at the current march position, a pulsing gold ring and a bobbing map pin.
func _make_marker() -> void:
	var ci := cur_mod(cur)
	marker = Node3D.new()
	marker.position = path_point(ci, u)
	marker.visible = not unlock
	add_child(marker)
	_ring = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.0, 1.0)
	_ring.mesh = pm
	_ring.material_override = Mats.ground("ring_soft", Color(1.0, 0.85, 0.3, 0.9), true)
	_ring.position.y = 0.02
	marker.add_child(_ring)
	var p0 := path_point(ci, maxf(u - 0.05, 0.0))
	var p1 := path_point(ci, minf(u + 0.05, 1.0))
	var fwd := p1 - p0
	var yaw := atan2(fwd.x, fwd.z) if fwd.length() > 0.001 else 0.0
	var offs := {"warrior": Vector3(-0.2, 0, 0.06), "ranger": Vector3(0.0, 0, -0.12), "mage": Vector3(0.2, 0, 0.06)}
	var trio := Node3D.new()
	trio.rotation.y = yaw
	marker.add_child(trio)
	for cls in Defs.HERO_ORDER:
		var m := UnitModel.new().build(cls, Defs.TEAM_HERO)
		trio.add_child(m)
		m.position = offs[cls]
		m.scale = Vector3.ONE * Defs.HEROES[cls]["scale"] * Actor.MODEL_SCALE * 0.3
		m.walk = 1.0
	var pin := Node3D.new()
	pin.position = Vector3(0, 1.05, 0)
	pin.scale = Vector3.ONE * 1.4
	marker.add_child(pin)
	MarchProps._mi(pin, MarchProps._cyl_mesh(0.13, 0.0, 0.3, 16), Color.WHITE, Vector3(0, -0.12, 0), Vector3.ONE, Vector3.ZERO, _gold)
	MarchProps._mi(pin, MarchProps._sphere_mesh(0.15), Color.WHITE, Vector3(0, 0.07, 0), Vector3.ONE, Vector3.ZERO, _gold)
	MarchProps._mi(pin, MarchProps._sphere_mesh(0.085), Color.WHITE, Vector3(0, 0.08, 0.08), Vector3(1, 1, 0.6), Vector3.ZERO, MarchProps.glow_mat(Color("ff5f6e"), 1.5))
	_bobber(pin, 0.07, 0.0)

# ---------------------------------------------------------------- unlock
## New region reached: a puff burst hides the swap from the greyscale island to the coloured one, which pops
## up out of the sheet; then the route, camps and the trio appear.
func play_unlock() -> void:
	var i := cur_mod(cur)
	if not _color_nodes.has(i):
		return
	var c := center(i)
	_burst(Vector3(c.x, top_y(i) + 0.25, c.y), Regions.LIST[i]["size"])
	await get_tree().create_timer(0.14, true, false, true).timeout
	var col_n: Node3D = _color_nodes[i]
	_gray_nodes[i].visible = false
	col_n.visible = true
	col_n.position.y = -0.35
	col_n.create_tween().tween_property(col_n, "position:y", 0.0, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.3, true, false, true).timeout
	_here_fx.visible = true
	marker.visible = true
	marker.scale = Vector3.ONE * 0.01
	marker.create_tween().tween_property(marker, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## White puffs bursting outward + a bright flash.
func _burst(p: Vector3, size: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var flash := MarchProps._mi(self, MarchProps._sphere_mesh(1.0), Color.WHITE, p, Vector3.ONE * 0.3, Vector3.ZERO, Mats.fx(Color(1.0, 0.97, 0.85, 0.9), true))
	var ft := flash.create_tween().set_parallel(true)
	ft.tween_property(flash, "scale", Vector3.ONE * size * 1.3, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ft.tween_property(flash.material_override, "albedo_color:a", 0.0, 0.4)
	ft.chain().tween_callback(flash.queue_free)
	for k in 18:
		var a := TAU * k / 18.0 + rng.randf() * 0.3
		var dir := Vector3(cos(a), rng.randf_range(0.1, 0.6), sin(a))
		var m := Mats.puff(Color(1.0, 0.99, 0.94, 0.95))
		var pf := MarchProps._mi(self, MarchProps._sphere_mesh(1.0), Color.WHITE, p + dir * 0.2, Vector3.ONE * rng.randf_range(0.18, 0.3), Vector3.ZERO, m)
		var dur := rng.randf_range(0.6, 0.9)
		var tw := pf.create_tween().set_parallel(true)
		tw.tween_property(pf, "position", p + dir * size * rng.randf_range(0.7, 1.05), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(pf, "scale", Vector3.ONE * rng.randf_range(0.35, 0.55), dur * 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "albedo_color:a", 0.0, dur * 0.45).set_delay(dur * 0.55)
		tw.chain().tween_callback(pf.queue_free)
	for k in 10:
		var a2 := rng.randf() * TAU
		var sp := MarchProps._mi(self, MarchProps._sphere_mesh(0.05), Color.WHITE, p, Vector3.ONE, Vector3.ZERO, MarchProps.glow_mat(Color("fff1a8"), 2.2))
		var tw2 := sp.create_tween().set_parallel(true)
		tw2.tween_property(sp, "position", p + Vector3(cos(a2), rng.randf_range(0.4, 1.2), sin(a2)) * size * 0.9, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw2.tween_property(sp, "scale", Vector3.ONE * 0.01, 0.7).set_ease(Tween.EASE_IN)
		tw2.chain().tween_callback(sp.queue_free)

# ---------------------------------------------------------------- sea + desk dressing
func _boats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for p in [Vector2(4.1, -3.7), Vector2(-4.25, -0.1), Vector2(3.85, 5.7), Vector2(-1.2, 6.55)]:
		var n := Node3D.new()
		n.position = Vector3(p.x, 0.02, p.y)
		n.rotation.y = rng.randf() * TAU
		add_child(n)
		MarchProps._rb(n, Vector3(0.42, 0.13, 0.17), Color("8a5432"), Vector3(0, 0.05, 0), Vector3.ZERO, 0.4)
		MarchProps._box(n, Vector3(0.34, 0.02, 0.12), Color("c8945a"), Vector3(0, 0.11, 0))
		MarchProps._cyl(n, 0.012, 0.012, 0.42, Color("6a4a30"), Vector3(0, 0.3, 0), Vector3.ZERO, 6)
		var sail := MarchProps._rb(n, Vector3(0.03, 0.26, 0.22), Color("fbf4e4"), Vector3(0.03, 0.33, 0), Vector3(0, 0, 0.06), 0.45)
		sail.rotation.y = PI * 0.5
		MarchProps._box(n, Vector3(0.06, 0.04, 0.012), Color("e2412c"), Vector3(0.03, 0.52, 0))
		MarchProps._mi(n, MarchProps._torus_mesh(0.18, 0.26), Color.WHITE, Vector3(-0.05, 0.0, 0), Vector3(1.6, 0.2, 0.8), Vector3.ZERO, Mats.fx(Color(1, 1, 1, 0.45)))
		_bobber(n, 0.025)

func _desk_props() -> void:
	# candles (top right): warm light pooling over that corner of the map
	var cbase := Vector3(4.75, -0.05, -9.15)
	var hs := [1.7, 1.2, 0.8]
	var offs := [Vector3(0, 0, 0), Vector3(0.62, 0, 0.42), Vector3(-0.32, 0, 0.62)]
	for k in 3:
		var p: Vector3 = cbase + offs[k]
		var h: float = hs[k]
		MarchProps._cyl(self, 0.32, 0.36, 0.06, Color("b88a3a"), p + Vector3(0, 0.03, 0), Vector3.ZERO, 18)
		MarchProps._cyl(self, 0.24, 0.25, h, Color("f6e9cc"), p + Vector3(0, h * 0.5 + 0.05, 0), Vector3.ZERO, 18)
		for d in 3:
			var a := TAU * d / 3.0 + k
			MarchProps._sph(self, 0.06, Color("fbf1da"), p + Vector3(cos(a) * 0.24, h - 0.1 - d * 0.12, sin(a) * 0.24), Vector3(0.7, 1.6, 0.7))
		MarchProps._cyl(self, 0.012, 0.012, 0.08, Color("2a1c18"), p + Vector3(0, h + 0.09, 0), Vector3.ZERO, 6)
		var fl := Node3D.new()
		fl.position = p + Vector3(0, h + 0.2, 0)
		add_child(fl)
		MarchProps._mi(fl, MarchProps._sphere_mesh(0.07), Color.WHITE, Vector3.ZERO, Vector3(1, 1.9, 1), Vector3.ZERO, MarchProps.glow_mat(Color("ffe08a"), 2.6))
		MarchProps._mi(fl, MarchProps._sphere_mesh(0.11), Color.WHITE, Vector3(0, -0.02, 0), Vector3(1, 1.7, 1), Vector3.ZERO, Mats.fx(Color(1.0, 0.6, 0.2, 0.45), true))
		var halo := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(1.3, 1.3)
		halo.mesh = qm
		halo.material_override = Mats.sprite("soft", Color(1.0, 0.65, 0.25, 0.4), true)
		fl.add_child(halo)
		_flames.append(fl)
	var l := OmniLight3D.new()
	l.light_color = Color("ffb062")
	l.light_energy = 3.2
	l.omni_range = 8.5
	l.omni_attenuation = 1.3
	l.shadow_enabled = true
	l.position = cbase + Vector3(0.1, 1.9, 0.3)
	add_child(l)
	_lights.append(l)
	# ink pot + quill
	var ink := Vector3(2.75, -0.05, -9.55)
	MarchProps._rb(self, Vector3(0.62, 0.42, 0.62), Color("1c2846"), ink + Vector3(0, 0.21, 0), Vector3.ZERO, 0.45)
	MarchProps._cyl(self, 0.14, 0.17, 0.14, Color("1c2846"), ink + Vector3(0, 0.48, 0), Vector3.ZERO, 14)
	MarchProps._mi(self, MarchProps._torus_mesh(0.13, 0.19), Color.WHITE, ink + Vector3(0, 0.56, 0), Vector3.ONE, Vector3.ZERO, _gold)
	var q := Node3D.new()
	q.position = ink + Vector3(0, 0.5, 0)
	q.rotation = Vector3(0.55, 0.6, 0.0)
	add_child(q)
	MarchProps._cyl(q, 0.012, 0.02, 1.9, Color("e8dcc6"), Vector3(0, 0.95, 0), Vector3.ZERO, 6)
	MarchProps._mi(q, MarchProps._sphere_mesh(1.0), Color("f8f4ee"), Vector3(0.07, 1.25, 0), Vector3(0.14, 0.7, 0.025), Vector3(0, 0, -0.08))
	MarchProps._mi(q, MarchProps._sphere_mesh(1.0), Color("dcd4ca"), Vector3(-0.03, 1.2, 0), Vector3(0.07, 0.62, 0.02), Vector3(0, 0, 0.06))
	# brass compass (top left)
	var cp := Vector3(-4.35, 0.0, -9.35)
	MarchProps._cyl(self, 0.72, 0.75, 0.16, Color("6a4a2a"), cp + Vector3(0, 0.03, 0), Vector3.ZERO, 32)
	MarchProps._mi(self, MarchProps._torus_mesh(0.62, 0.76), Color.WHITE, cp + Vector3(0, 0.12, 0), Vector3(1, 1.4, 1), Vector3.ZERO, _gold)
	MarchProps._cyl(self, 0.62, 0.62, 0.02, Color("f2e4c4"), cp + Vector3(0, 0.12, 0), Vector3.ZERO, 32)
	for k in 8:
		var a := TAU * k / 8.0
		MarchProps._box(self, Vector3(0.03, 0.01, 0.12 if k % 2 == 0 else 0.07), Color("6a4a2a"), cp + Vector3(cos(a) * 0.5, 0.135, sin(a) * 0.5), Vector3(0, -a + PI * 0.5, 0))
	var needle := Node3D.new()
	needle.position = cp + Vector3(0, 0.15, 0)
	needle.rotation.y = 0.5
	add_child(needle)
	MarchProps._cyl(needle, 0.0, 0.05, 0.42, Color("e2412c"), Vector3(0, 0, -0.21), Vector3(-PI * 0.5, 0, 0), 4)
	MarchProps._cyl(needle, 0.0, 0.05, 0.42, Color("f4f0e8"), Vector3(0, 0, 0.21), Vector3(PI * 0.5, 0, 0), 4)
	MarchProps._mi(needle, MarchProps._sphere_mesh(0.045), Color.WHITE, Vector3.ZERO, Vector3.ONE, Vector3.ZERO, _gold)
	_bobber(needle, 0.0)
	# rolled scroll (bottom left) and a closed book (bottom right)
	var sc := Node3D.new()
	sc.position = Vector3(-4.7, 0.18, 8.75)
	sc.rotation.y = 0.35
	add_child(sc)
	MarchProps._cyl(sc, 0.22, 0.22, 2.4, Color("eedcb2"), Vector3.ZERO, Vector3(0, 0, PI * 0.5), 18)
	for x in [-1.21, 1.21]:
		MarchProps._cyl(sc, 0.12, 0.12, 0.04, Color("c8a878"), Vector3(x, 0, 0), Vector3(0, 0, PI * 0.5), 14)
	MarchProps._mi(sc, MarchProps._torus_mesh(0.21, 0.26), Color("b8323a"), Vector3(0.3, 0, 0), Vector3.ONE, Vector3(0, 0, PI * 0.5))
	var bk := Node3D.new()
	bk.position = Vector3(4.6, 0.0, 8.95)
	bk.rotation.y = -0.25
	add_child(bk)
	MarchProps._rb(bk, Vector3(1.9, 0.34, 1.4), Color("7a2e34"), Vector3(0, 0.17, 0), Vector3.ZERO, 0.2)
	MarchProps._box(bk, Vector3(1.78, 0.26, 1.3), Color("f2e6c8"), Vector3(0.06, 0.17, 0))
	MarchProps._mi(bk, MarchProps._box_mesh(Vector3(0.5, 0.02, 0.5)), Color.WHITE, Vector3(0, 0.35, 0), Vector3.ONE, Vector3(0, PI * 0.25, 0), _gold)

# ---------------------------------------------------------------- animation
func _process(delta: float) -> void:
	_t += delta
	for b in _bob:
		var n: Node3D = b[0]
		if not is_instance_valid(n):
			continue
		var base: Vector3 = b[1]
		var ph: float = b[2]
		var amp: float = b[3]
		if amp > 0.0:
			n.position = base + Vector3(0, sin(_t * 1.6 + ph) * amp, 0)
		else:
			n.rotation.y = sin(_t * 3.0 + ph) * 0.35   # flags / needle flutter
	for f in _flow:
		var dot: Node3D = f[0]
		var pts: Array = f[1]
		var k := fmod(f[2] + _t * 0.28, 1.0)
		var fi := k * (pts.size() - 1)
		var i0 := int(fi)
		dot.position = (pts[i0] as Vector3).lerp(pts[mini(i0 + 1, pts.size() - 1)], fi - i0)
		dot.scale = Vector3.ONE * (0.6 + 0.6 * sin(k * PI))
	for fl in _flames:
		fl.scale = Vector3(1.0 + sin(_t * 13.0 + fl.position.x) * 0.06, 1.0 + sin(_t * 9.0 + fl.position.z * 3.0) * 0.12, 1.0)
	for l in _lights:
		if not l.has_meta("e0"):
			l.set_meta("e0", l.light_energy)
		l.light_energy = (l.get_meta("e0") as float) * (0.9 + 0.1 * sin(_t * 11.0) + 0.05 * sin(_t * 23.0))
	if _ring:
		var k2 := fmod(_t * 0.8, 1.0)
		_ring.scale = Vector3.ONE * (0.8 + k2 * 0.7)
		(_ring.material_override as StandardMaterial3D).albedo_color.a = 0.9 * (1.0 - k2)
