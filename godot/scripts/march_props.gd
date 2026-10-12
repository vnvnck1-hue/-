class_name MarchProps
extends RefCounted
## Procedural toy props for the Endless March road, in two themes:
##   meadow  - sunny chunky toy nature (lumpy pines, yellow blob bushes, orange lilies, red mushrooms,
##             stumps, rounded-cube / egg / puff trees, ponds with foam, grass terraces)
##   mine    - twilight purple mining ruins (wooden scaffolds, pulley wheels, mine carts, glowing lanterns,
##             giant pink mushrooms, crystals, stone pillars)
## Everything is built from cached primitive meshes + a superellipsoid "rounded box" for the soft toy look.
## The mesh / material caches are static and live for the whole session, so cache keys must stay bounded:
## random sizes go into the instance scale (see _rb), never into a cache key.

static var _meshes := {}
static var _glow_mats := {}
static var _water_mat: StandardMaterial3D

# ---------------------------------------------------------------- mesh / material helpers
static func _q(c: Color) -> Color:
	# quantize so Mats.prop's per-color cache stays small (1/24 steps: _vary's random tints otherwise keep
	# adding materials to that session-long cache on the endless road)
	return Color(snappedf(c.r, 1.0 / 24.0), snappedf(c.g, 1.0 / 24.0), snappedf(c.b, 1.0 / 24.0), 1.0)

static func _sp(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)

## Superellipsoid: e≈0.25 = rounded cube, e=1 = ellipsoid. Analytic normals, cached per size.
static func rbox_mesh(size: Vector3, e := 0.3) -> ArrayMesh:
	var key := "rb%.2f_%.2f_%.2f_%.2f" % [size.x, size.y, size.z, e]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var R := 12
	var S := 16
	var h := size * 0.5
	for i in R + 1:
		var v := -PI * 0.5 + PI * i / R
		for j in S + 1:
			var u := -PI + TAU * j / S
			var cv := _sp(cos(v), e)
			var p := Vector3(cv * _sp(cos(u), e) * h.x, _sp(sin(v), e) * h.y, cv * _sp(sin(u), e) * h.z)
			var nc := _sp(cos(v), 2.0 - e)
			var n := Vector3(nc * _sp(cos(u), 2.0 - e) / h.x, _sp(sin(v), 2.0 - e) / h.y, nc * _sp(sin(u), 2.0 - e) / h.z)
			st.set_normal(n.normalized() if n.length() > 0.0001 else Vector3(0, signf(v), 0))
			st.add_vertex(p)
	for i in R:
		for j in S:
			var a := i * (S + 1) + j
			var b := a + S + 1
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(b + 1)
			st.add_index(b)
	var m := st.commit()
	_meshes[key] = m
	return m

static func _sphere_mesh(r: float) -> SphereMesh:
	var key := "s%.3f" % r
	if not _meshes.has(key):
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = 16
		s.rings = 8
		_meshes[key] = s
	return _meshes[key]

static func _cyl_mesh(rt: float, rb: float, h: float, seg := 14) -> CylinderMesh:
	var key := "c%.3f_%.3f_%.3f_%d" % [rt, rb, h, seg]
	if not _meshes.has(key):
		var c := CylinderMesh.new()
		c.top_radius = rt
		c.bottom_radius = rb
		c.height = h
		c.radial_segments = seg
		c.rings = 1
		_meshes[key] = c
	return _meshes[key]

static func _box_mesh(size: Vector3) -> BoxMesh:
	var key := "b%.3f_%.3f_%.3f" % [size.x, size.y, size.z]
	if not _meshes.has(key):
		var b := BoxMesh.new()
		b.size = size
		_meshes[key] = b
	return _meshes[key]

static func _torus_mesh(ri: float, ro: float) -> TorusMesh:
	var key := "t%.3f_%.3f" % [ri, ro]
	if not _meshes.has(key):
		var t := TorusMesh.new()
		t.inner_radius = ri
		t.outer_radius = ro
		t.rings = 20
		t.ring_segments = 8
		_meshes[key] = t
	return _meshes[key]

static func glow_mat(c: Color, energy := 1.6) -> StandardMaterial3D:
	var key := "%s%.2f" % [c.to_html(), energy]
	if not _glow_mats.has(key):
		_glow_mats[key] = Mats.glow(c, energy)
	return _glow_mats[key]

static func water_mat() -> StandardMaterial3D:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = Color("46bfcf")
		_water_mat.roughness = 0.08
		_water_mat.metallic_specular = 0.9
		_water_mat.emission_enabled = true
		_water_mat.emission = Color("46bfcf") * 0.3
	return _water_mat

static func _mi(parent: Node3D, mesh: Mesh, col: Color, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat if mat else Mats.prop(_q(col))
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi

## The shape helpers below build from unit meshes and put the size into the node scale (exact for these linear
## shapes: the renderer transforms normals with the inverse scale), so the static mesh cache stays a few dozen
## entries no matter how many randomly sized props the endless road spawns. The returned node's scale holds the
## size: multiply it, never overwrite it.
static func _sph(p: Node3D, r: float, col: Color, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	return _mi(p, _sphere_mesh(1.0), col, pos, scl * r)

static func _cyl(p: Node3D, rt: float, rb: float, h: float, col: Color, pos: Vector3, rot := Vector3.ZERO, seg := 14) -> MeshInstance3D:
	return _cyl_mi(p, rt, rb, h, seg, col, pos, Vector3.ONE, rot)

static func _box(p: Node3D, size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return _mi(p, _box_mesh(Vector3.ONE), col, pos, size, rot)

## Cylinder / cone from a unit-height mesh keyed only by the radius ratio (1% steps) and segment count,
## scaled to (r, h, r) on top of `scl`.
static func _cyl_mi(p: Node3D, rt: float, rb: float, h: float, seg: int, col: Color, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO, mat: Material = null) -> MeshInstance3D:
	var r := maxf(rt, rb)
	if r <= 0.0 or h <= 0.0:
		return _mi(p, _cyl_mesh(rt, rb, h, seg), col, pos, scl, rot, mat)
	var m := _cyl_mesh(snappedf(rt / r, 0.01), snappedf(rb / r, 0.01), 1.0, seg)
	return _mi(p, m, col, pos, scl * Vector3(r, h, r), rot, mat)

## Torus from a unit-outer-radius mesh keyed by the radius ratio (1% steps), scaled uniformly by `ro`.
static func _torus_mi(p: Node3D, ri: float, ro: float, col: Color, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO, mat: Material = null) -> MeshInstance3D:
	return _mi(p, _torus_mesh(snappedf(ri / ro, 0.01), 1.0), col, pos, scl * ro, rot, mat)

## Rounded box: one unit mesh per roundness, sized by the instance scale. A superellipsoid scales linearly and its
## analytic normals transform with the inverse scale (what the renderer does for non-uniform scale), so this is
## identical to rbox_mesh(size, e) — without caching a new ArrayMesh for every random prop size on the endless road.
static func _rb(p: Node3D, size: Vector3, col: Color, pos: Vector3, rot := Vector3.ZERO, e := 0.3) -> MeshInstance3D:
	return _mi(p, rbox_mesh(Vector3.ONE, e), col, pos, size, rot)

static func _root(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = rng.randf() * TAU
	n.scale = Vector3.ONE * s
	parent.add_child(n)
	return n

static func _vary(c: Color, rng: RandomNumberGenerator, amt := 0.08) -> Color:
	return Color(c.r + rng.randf_range(-amt, amt), c.g + rng.randf_range(-amt, amt), c.b + rng.randf_range(-amt, amt) * 0.6)

# ================================================================ MEADOW
const LEAF := Color("3f9e4a")
const LEAF_LIGHT := Color("6cc24a")
const BARK := Color("8a5a34")
const SUN_YELLOW := Color("f6c021")
const LILY := Color("f2862a")
const CAP_RED := Color("e2412c")
const CREAM := Color("f6ecd8")

## Lumpy tiered pine (ref: chunky LOD pines). Drooping lobes around each tier.
## snow: white caps on every tier (frost theme).
static func pine(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0, leaf := LEAF, snow := false) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.07, 0.1, 0.5, BARK, Vector3(0, 0.25, 0))
	var g := _vary(leaf.lerp(LEAF_LIGHT, rng.randf() * 0.5) if leaf == LEAF else leaf, rng, 0.04)
	for t in 4:
		var r := 0.56 - t * 0.12
		var y := 0.42 + t * 0.3
		var col := g.lightened(t * 0.04)
		_cyl(n, r * 0.25, r, 0.42, col, Vector3(0, y + 0.1, 0))
		if snow:
			_cyl(n, r * 0.22, r * 0.62, 0.16, Color("f4f9ff"), Vector3(0, y + 0.26, 0))
		var lobes := 7 - t
		for i in lobes:
			var a := TAU * (i + t * 0.5) / lobes
			_sph(n, r * 0.34, col, Vector3(cos(a) * r * 0.82, y - 0.06, sin(a) * r * 0.82), Vector3(1, 0.8, 1))
			if snow and i % 2 == 0:
				_sph(n, r * 0.24, Color("f4f9ff"), Vector3(cos(a) * r * 0.8, y + 0.02, sin(a) * r * 0.8), Vector3(1, 0.5, 1))
	_sph(n, 0.11, Color("f4f9ff") if snow else g.lightened(0.15), Vector3(0, 1.62, 0), Vector3(1, 1.6, 1))

## Merged-sphere bush (yellow or green blob).
static func blob_bush(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0, yellow := true) -> void:
	var n := _root(parent, pos, rng, s)
	var c := _vary(SUN_YELLOW if yellow else Color("74c443"), rng, 0.04)
	_sph(n, 0.42, c, Vector3(0, 0.36, 0), Vector3(1, 0.88, 1))
	_sph(n, 0.32, c.lightened(0.06), Vector3(0.32, 0.3, 0.08))
	_sph(n, 0.28, c.darkened(0.04), Vector3(-0.26, 0.26, 0.16))
	_sph(n, 0.22, c.lightened(0.1), Vector3(0.05, 0.62, -0.12))

## Orange lily with spread petals.
static func lily(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.015, 0.02, 0.18, Color("4f9a3a"), Vector3(0, 0.09, 0))
	for i in 2:
		_sph(n, 0.1, Color("5aa83e"), Vector3((i * 2 - 1) * 0.1, 0.05, 0.02), Vector3(1.4, 0.35, 0.6))
	var c := _vary(LILY, rng, 0.04)
	for i in 6:
		var pv := Node3D.new()
		pv.position = Vector3(0, 0.18, 0)
		pv.rotation = Vector3(0, TAU * i / 6.0, 0)
		n.add_child(pv)
		_mi(pv, _sphere_mesh(1.0), c if i % 2 == 0 else c.lightened(0.08), Vector3(0, 0.06, -0.11), Vector3(0.055, 0.03, 0.15), Vector3(0.75, 0, 0))
	_sph(n, 0.04, Color("ffd36a"), Vector3(0, 0.22, 0))

## Red mushroom cluster with white spots.
static func mushrooms(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var cnt := rng.randi_range(2, 3)
	for i in cnt:
		var k := 1.0 - i * 0.28
		var p := Vector3(i * 0.17 - 0.1, 0, (i % 2) * 0.12)
		_cyl(n, 0.045 * k, 0.06 * k, 0.16 * k, CREAM, p + Vector3(0, 0.08 * k, 0))
		_sph(n, 0.17 * k, CAP_RED.lightened(i * 0.05), p + Vector3(0, 0.18 * k, 0), Vector3(1, 0.62, 1))
		for d in 3:
			var a := TAU * d / 3.0 + i
			_sph(n, 0.03 * k, CREAM, p + Vector3(cos(a) * 0.09 * k, 0.25 * k, sin(a) * 0.09 * k))

static func stump(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.19, 0.24, 0.24, Color("b0703f"), Vector3(0, 0.12, 0))
	_cyl(n, 0.18, 0.18, 0.02, Color("f0c89a"), Vector3(0, 0.245, 0))
	_cyl(n, 0.1, 0.1, 0.022, Color("d9a46e"), Vector3(0, 0.25, 0))

## Rounded-cube canopy tree (yellow-green, toy block style).
static func cube_tree(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.08, 0.12, 0.6, Color("c4692f"), Vector3(0, 0.3, 0))
	var c := _vary(Color("c3d23a"), rng, 0.05)
	_rb(n, Vector3(0.95, 0.85, 0.95), c, Vector3(0, 0.98, 0))
	if rng.randf() < 0.5:
		_rb(n, Vector3(0.5, 0.45, 0.5), c.lightened(0.08), Vector3(0.28, 1.45, -0.1), Vector3(0, 0.4, 0))

## Tall teal egg trees (1–3).
static func egg_trees(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var cnt := rng.randi_range(1, 3)
	for i in cnt:
		var k := 1.0 - i * 0.25
		var p := Vector3((i - 1) * 0.45, 0, (i % 2) * 0.35)
		_cyl(n, 0.05 * k, 0.07 * k, 0.4 * k, Color("b8763f"), p + Vector3(0, 0.2 * k, 0))
		_sph(n, 0.38 * k, _vary(Color("4f8f8f"), rng, 0.03), p + Vector3(0, 0.95 * k, 0), Vector3(1, 1.65, 1))

## Fluffy round tree with leafy bumps.
static func puff_tree(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.08, 0.12, 0.6, Color("c4692f"), Vector3(0, 0.3, 0))
	var c := _vary(Color("72c043"), rng, 0.04)
	_sph(n, 0.55, c, Vector3(0, 1.0, 0), Vector3(1, 1.1, 1))
	for i in 9:
		var a := TAU * i / 9.0
		var y := 0.8 + (i % 3) * 0.25
		_sph(n, 0.2, c.lightened(0.07), Vector3(cos(a) * 0.48, y, sin(a) * 0.48), Vector3(1, 0.7, 1))

## Grass tuft with daisies.
static func daisies(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	for i in 5:
		var a := TAU * i / 5.0
		_cyl(n, 0.0, 0.035, 0.2, Color("4ea83a"), Vector3(cos(a) * 0.06, 0.1, sin(a) * 0.06), Vector3(cos(a) * 0.3, 0, sin(a) * 0.3), 6)
	for f in 2:
		var p := Vector3(f * 0.14 - 0.07, 0.17 + f * 0.04, 0.03)
		for i in 5:
			var a := TAU * i / 5.0
			_sph(n, 0.04, Color.WHITE, p + Vector3(cos(a) * 0.045, 0, sin(a) * 0.045), Vector3(1, 0.4, 1))
		_sph(n, 0.028, Color("ffcc33"), p + Vector3(0, 0.012, 0))

static func rock(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0, col := Color("a7a3b5")) -> void:
	var n := _root(parent, pos, rng, s)
	var c := _vary(col, rng, 0.03)
	_rb(n, Vector3(0.62, 0.36, 0.5), c, Vector3(0, 0.14, 0), Vector3(0, 0, 0.08), 0.45)
	if rng.randf() < 0.6:
		_rb(n, Vector3(0.32, 0.22, 0.28), c.lightened(0.06), Vector3(0.36, 0.08, 0.12), Vector3(0, 0.6, 0), 0.45)

## Big rounded grass terrace slab over a dirt block (frames the far field).
static func terrace(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, 1.0)
	n.rotation.y = rng.randf_range(-0.3, 0.3)
	var w := rng.randf_range(1.6, 2.8) * s
	var d := rng.randf_range(1.4, 2.4) * s
	var h := rng.randf_range(0.4, 0.9)
	_rb(n, Vector3(w, h, d), Color("c7834c"), Vector3(0, h * 0.5 - 0.1, 0), Vector3.ZERO, 0.22)
	_rb(n, Vector3(w + 0.16, 0.24, d + 0.16), _vary(Color("9ad050"), rng, 0.03), Vector3(0, h - 0.04, 0), Vector3.ZERO, 0.3)
	if rng.randf() < 0.7:
		blob_bush(n, Vector3(rng.randf_range(-w, w) * 0.3, h + 0.05, rng.randf_range(-d, d) * 0.3), rng, 0.6, rng.randf() < 0.5)

## Pond with white foam rim and lily pads.
static func pond(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var r := rng.randf_range(0.8, 1.3)
	_cyl_mi(n, r, r, 0.04, 28, Color.WHITE, Vector3(0, 0.0, 0), Vector3(1, 1, 0.75), Vector3.ZERO, water_mat())
	_torus_mi(n, r - 0.04, r + 0.06, Color.WHITE, Vector3(0, 0.02, 0), Vector3(1, 0.4, 0.75), Vector3.ZERO, glow_mat(Color("eafcff"), 1.05))
	for i in rng.randi_range(1, 3):
		var a := rng.randf() * TAU
		_cyl(n, 0.13, 0.13, 0.02, Color("5fae46"), Vector3(cos(a) * r * 0.5, 0.035, sin(a) * r * 0.35), Vector3.ZERO, 12)

# ================================================================ MINE (twilight)
const WOOD := Color("7b5640")
const WOOD_DARK := Color("5d3f33")
const STONE := Color("5f577e")
const STONE_LIGHT := Color("7d74a0")
const MOSS := Color("4b8a72")
const PINK_CAP := Color("c8336a")
const LANTERN := Color("ff8a3a")

## Wooden mining scaffold tower with a little roof and a ladder.
static func scaffold(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var H := rng.randf_range(2.0, 3.4)
	var w := 0.5
	for x in [-w, w]:
		for z in [-w, w]:
			_box(n, Vector3(0.13, H, 0.13), WOOD, Vector3(x, H * 0.5, z))
	for y in [H * 0.45, H]:
		for side in [-w, w]:
			_box(n, Vector3(w * 2 + 0.16, 0.1, 0.1), WOOD_DARK, Vector3(0, y, side))
			_box(n, Vector3(0.1, 0.1, w * 2 + 0.16), WOOD_DARK, Vector3(side, y, 0))
	# cross braces on two faces
	var diag := sqrt(pow(w * 2, 2) + pow(H * 0.45, 2))
	var ang := atan2(H * 0.45, w * 2)
	_box(n, Vector3(diag, 0.07, 0.07), WOOD, Vector3(0, H * 0.225, w), Vector3(0, 0, ang))
	_box(n, Vector3(0.07, 0.07, diag), WOOD, Vector3(-w, H * 0.225, 0), Vector3(ang, 0, 0))
	_box(n, Vector3(w * 2 + 0.3, 0.08, w * 2 + 0.3), WOOD_DARK.lightened(0.1), Vector3(0, H + 0.08, 0))
	_rb(n, Vector3(w * 2 + 0.5, 0.42, w * 2 + 0.5), Color("8a4f62"), Vector3(0, H + 0.62, 0), Vector3.ZERO, 0.35)
	_box(n, Vector3(0.16, 0.5, 0.16), WOOD_DARK, Vector3(0.18, H + 0.35, 0.18))
	# ladder
	for x in [-0.14, 0.14]:
		_box(n, Vector3(0.05, H, 0.05), WOOD.lightened(0.1), Vector3(x, H * 0.5, w + 0.12))
	var y2 := 0.25
	while y2 < H:
		_box(n, Vector3(0.3, 0.04, 0.04), WOOD.lightened(0.1), Vector3(0, y2, w + 0.12))
		y2 += 0.28

## Pulley wheel frame (mine head-frame silhouette).
static func pulley(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	for x in [-0.45, 0.45]:
		_box(n, Vector3(0.12, 1.5, 0.12), WOOD, Vector3(x, 0.75, 0))
	_box(n, Vector3(1.05, 0.1, 0.1), WOOD_DARK, Vector3(0, 1.38, 0))
	var wheel := Node3D.new()
	wheel.position = Vector3(0, 1.0, 0.1)
	wheel.rotation = Vector3(PI * 0.5, 0, 0)
	n.add_child(wheel)
	_mi(wheel, _torus_mesh(0.36, 0.45), Color("6a4a3e"), Vector3.ZERO)
	for i in 6:
		_box(wheel, Vector3(0.7, 0.05, 0.05), WOOD_DARK, Vector3.ZERO, Vector3(0, TAU * i / 12.0, 0))
	_cyl(wheel, 0.08, 0.08, 0.14, Color("8a86a0"), Vector3.ZERO)
	_box(n, Vector3(1.8, 0.1, 0.12), WOOD, Vector3(0.6, 0.5, -0.1), Vector3(0, 0, 0.5))

## Mine cart heaped with ore, a glowing crystal and a few leaves.
static func cart(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_rb(n, Vector3(0.86, 0.46, 0.58), Color("6b4636"), Vector3(0, 0.38, 0), Vector3.ZERO, 0.22)
	for x in [-0.3, 0.3]:
		_box(n, Vector3(0.06, 0.48, 0.62), Color("54506a"), Vector3(x, 0.39, 0))
	for x in [-0.28, 0.28]:
		for z in [-0.31, 0.31]:
			_cyl(n, 0.12, 0.12, 0.07, Color("3a3448"), Vector3(x, 0.12, z), Vector3(PI * 0.5, 0, 0))
	for i in 5:
		_sph(n, rng.randf_range(0.1, 0.15), Color("3b3352").lightened(rng.randf() * 0.1), Vector3(rng.randf_range(-0.28, 0.28), 0.62, rng.randf_range(-0.16, 0.16)))
	_mi(n, _cyl_mesh(0.0, 0.07, 0.3, 6), Color.WHITE, Vector3(0.1, 0.75, 0.0), Vector3.ONE, Vector3(0, 0, 0.3), glow_mat(Color("7fe8ff"), 1.5))
	for i in 3:
		_sph(n, 0.08, Color("4f9a5a"), Vector3(-0.2 + i * 0.12, 0.7, 0.1), Vector3(1.3, 0.5, 0.8))

## Stone lantern post with a warm glow (optionally a real light).
static func lantern(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0, light := true) -> void:
	var n := _root(parent, pos, rng, s)
	_rb(n, Vector3(0.34, 0.3, 0.34), STONE_LIGHT, Vector3(0, 0.15, 0), Vector3.ZERO, 0.35)
	_cyl(n, 0.07, 0.09, 0.5, STONE, Vector3(0, 0.5, 0))
	_box(n, Vector3(0.26, 0.05, 0.26), Color("3a3048"), Vector3(0, 0.76, 0))
	_mi(n, _box_mesh(Vector3(0.18, 0.24, 0.18)), Color.WHITE, Vector3(0, 0.9, 0), Vector3.ONE, Vector3.ZERO, glow_mat(LANTERN, 2.2))
	for x in [-0.1, 0.1]:
		for z in [-0.1, 0.1]:
			_box(n, Vector3(0.035, 0.26, 0.035), Color("3a3048"), Vector3(x, 0.9, z))
	_cyl(n, 0.0, 0.2, 0.18, Color("3a3048"), Vector3(0, 1.1, 0), Vector3.ZERO, 4)
	if light:
		var l := OmniLight3D.new()
		l.light_color = Color("ffa45a")
		l.light_energy = 2.2
		l.omni_range = 3.2
		l.omni_attenuation = 1.2
		l.position = Vector3(0, 0.95, 0)
		n.add_child(l)

## Giant layered pink mushroom (ref: mushroom-house caves) with glowing spores.
static func big_mushroom(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var H := rng.randf_range(1.0, 1.8)
	_cyl(n, 0.13, 0.2, H, Color("f0b4c8"), Vector3(0, H * 0.5, 0))
	var c := _vary(PINK_CAP, rng, 0.04)
	_cyl(n, 0.62, 0.68, 0.06, Color("f07aa4"), Vector3(0, H - 0.02, 0))
	_cyl(n, 0.42, 0.7, 0.22, c, Vector3(0, H + 0.12, 0), Vector3.ZERO, 18)
	_cyl(n, 0.2, 0.46, 0.2, c.lightened(0.06), Vector3(0, H + 0.32, 0), Vector3.ZERO, 18)
	if rng.randf() < 0.6:
		var y := H * 0.5
		_cyl(n, 0.22, 0.36, 0.14, c.darkened(0.05), Vector3(0.24, y, 0), Vector3(0, 0, -0.25), 14)
	for i in 4:
		var a := rng.randf() * TAU
		_mi(n, _sphere_mesh(0.035), Color.WHITE, Vector3(cos(a) * 0.4, H + 0.27, sin(a) * 0.4), Vector3.ONE, Vector3.ZERO, glow_mat(Color("ffb0e0"), 1.8))

## Small glowing mushrooms (pink or cyan).
static func glow_shrooms(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var col := Color("ff6ec8") if rng.randf() < 0.6 else Color("6ff0ff")
	for i in rng.randi_range(2, 4):
		var p := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var k := rng.randf_range(0.6, 1.0)
		_cyl(n, 0.02 * k, 0.03 * k, 0.16 * k, Color("e8d8f0"), p + Vector3(0, 0.08 * k, 0))
		_mi(n, _sphere_mesh(1.0), Color.WHITE, p + Vector3(0, 0.17 * k, 0), Vector3(1, 0.55, 1) * (0.07 * k), Vector3.ZERO, glow_mat(col, 1.5))

## Crystal cluster: tilted glowing hex prisms.
static func crystals(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0, tint := Color(0, 0, 0, 0), base := STONE) -> void:
	var n := _root(parent, pos, rng, s)
	var col := Color("7fe8ff") if rng.randf() < 0.55 else Color("c08aff")
	if tint.a > 0.0:
		col = tint
	_rb(n, Vector3(0.4, 0.14, 0.34), base, Vector3(0, 0.04, 0), Vector3.ZERO, 0.4)
	for i in rng.randi_range(3, 5):
		var h := rng.randf_range(0.3, 0.75)
		var a := rng.randf() * TAU
		_cyl_mi(n, 0.015, 0.075, h, 6, Color.WHITE, Vector3(cos(a) * 0.1, h * 0.45, sin(a) * 0.1), Vector3.ONE,
			Vector3(sin(a) * 0.4, 0, cos(a) * 0.4), glow_mat(col if i % 2 == 0 else col.lightened(0.25), 1.3))

## Stacked stone pillar with moss.
static func pillar(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0, stone := STONE, cap := MOSS) -> void:
	var n := _root(parent, pos, rng, s)
	var y := 0.0
	var w := rng.randf_range(0.55, 0.8)
	for i in rng.randi_range(2, 4):
		var h := rng.randf_range(0.45, 0.8)
		_rb(n, Vector3(w, h, w * 0.9), _vary(stone, rng, 0.03), Vector3(rng.randf_range(-0.05, 0.05), y + h * 0.5, 0), Vector3(0, rng.randf_range(-0.3, 0.3), 0), 0.3)
		y += h - 0.04
		w *= 0.84
	_rb(n, Vector3(w + 0.1, 0.14, w), cap, Vector3(0, y + 0.04, 0), Vector3.ZERO, 0.4)

static func cave_rock(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	rock(parent, pos, rng, s, Color("4f4874"))
	if rng.randf() < 0.5:
		glow_shrooms(parent, pos + Vector3(0.3 * s, 0, 0.2 * s), rng, 0.7 * s)

## Mossy stone ledge (mine-theme counterpart of the grass terrace).
static func ledge(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0, body := Color("4a4268"), top := Color("4f7f72"), tint := Color(0, 0, 0, 0)) -> void:
	var n := _root(parent, pos, rng, 1.0)
	n.rotation.y = rng.randf_range(-0.3, 0.3)
	var w := rng.randf_range(1.6, 2.8) * s
	var d := rng.randf_range(1.4, 2.4) * s
	var h := rng.randf_range(0.5, 1.2)
	_rb(n, Vector3(w, h, d), body, Vector3(0, h * 0.5 - 0.1, 0), Vector3.ZERO, 0.22)
	_rb(n, Vector3(w + 0.12, 0.2, d + 0.12), _vary(top, rng, 0.03), Vector3(0, h - 0.02, 0), Vector3.ZERO, 0.3)
	if rng.randf() < 0.6:
		crystals(n, Vector3(rng.randf_range(-w, w) * 0.3, h + 0.05, 0), rng, 0.9, tint, body)

# ================================================================ enemy camp
## Campfire at the centre of a waiting enemy group: stone ring, crossed logs, flickering flame + warm light.
static func campfire(parent: Node3D, pos: Vector3, stone: Color) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	for i in 8:
		var a := TAU * i / 8.0
		_rb(n, Vector3(0.2, 0.13, 0.16), stone.lightened((i % 2) * 0.08), Vector3(cos(a) * 0.36, 0.04, sin(a) * 0.36), Vector3(0, -a, 0), 0.4)
	for i in 3:
		var a := TAU * i / 3.0
		_cyl(n, 0.05, 0.06, 0.55, Color("7a4a2e"), Vector3(cos(a) * 0.08, 0.1, sin(a) * 0.08), Vector3(0.9, a, 0), 8)
	var flame := Node3D.new()
	flame.position = Vector3(0, 0.12, 0)
	n.add_child(flame)
	_mi(flame, _cyl_mesh(0.0, 0.17, 0.42, 7), Color.WHITE, Vector3(0, 0.2, 0), Vector3.ONE, Vector3.ZERO, glow_mat(Color("ff7a2a"), 2.0))
	_mi(flame, _cyl_mesh(0.0, 0.1, 0.3, 7), Color.WHITE, Vector3(0.03, 0.17, 0.02), Vector3.ONE, Vector3.ZERO, glow_mat(Color("ffd24a"), 2.4))
	var l := OmniLight3D.new()
	l.light_color = Color("ff9a4a")
	l.light_energy = 2.0
	l.omni_range = 3.4
	l.omni_attenuation = 1.1
	l.position = Vector3(0, 0.6, 0)
	n.add_child(l)
	var tw := flame.create_tween().set_loops()
	tw.tween_property(flame, "scale", Vector3(1.12, 0.82, 1.12), 0.12)
	tw.tween_property(flame, "scale", Vector3(0.9, 1.18, 0.9), 0.15)
	tw.tween_property(flame, "scale", Vector3(1.04, 0.95, 1.04), 0.1)
	var lt := l.create_tween().set_loops()
	lt.tween_property(l, "light_energy", 2.5, 0.13)
	lt.tween_property(l, "light_energy", 1.7, 0.17)
	return n

# ================================================================ FOREST (deep woods)
## Fern tuft: drooping leaf blades around a centre.
static func ferns(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var c := _vary(Color("3f9a44"), rng, 0.04)
	for i in 7:
		var a := TAU * i / 7.0
		_mi(n, _sphere_mesh(1.0), c.lightened((i % 2) * 0.08), Vector3(cos(a) * 0.15, 0.12, sin(a) * 0.15), Vector3(0.06, 0.03, 0.2), Vector3(0.5, -a + PI * 0.5, 0))

## Mossy boulder.
static func moss_rock(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var c := _vary(Color("8a9488"), rng, 0.03)
	_rb(n, Vector3(0.6, 0.38, 0.5), c, Vector3(0, 0.15, 0), Vector3(0, 0, 0.06), 0.45)
	_rb(n, Vector3(0.5, 0.12, 0.42), Color("5aa548"), Vector3(0.02, 0.33, 0), Vector3(0, 0, 0.06), 0.5)

## Fallen log with cut rings.
static func log_prop(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.16, 0.17, 1.1, Color("8a5a34"), Vector3(0, 0.16, 0), Vector3(0, 0, PI * 0.5))
	for x in [-0.55, 0.55]:
		_cyl(n, 0.15, 0.15, 0.02, Color("e8c08a"), Vector3(x, 0.16, 0), Vector3(0, 0, PI * 0.5))
	_sph(n, 0.12, Color("5aa548"), Vector3(0.1, 0.3, 0.02), Vector3(1.6, 0.4, 1))

## Little glowing forest spirit wisp on a mushroom (blue).
static func spirit(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.03, 0.04, 0.18, CREAM, Vector3(0, 0.09, 0))
	_mi(n, _sphere_mesh(0.12), Color.WHITE, Vector3(0, 0.2, 0), Vector3(1, 0.5, 1), Vector3.ZERO, glow_mat(Color("5fd8ff"), 1.4))
	_mi(n, _sphere_mesh(0.05), Color.WHITE, Vector3(0.18, 0.45 + rng.randf() * 0.2, 0.05), Vector3.ONE, Vector3.ZERO, glow_mat(Color("a8f0ff"), 2.0))

## Ancient giant tree: wide trunk with roots, layered round canopy and a glowing blue heart (ref: world map tree).
static func giant_tree(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.32, 0.5, 1.7, Color("7a4e30"), Vector3(0, 0.85, 0), Vector3.ZERO, 12)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		_cyl(n, 0.07, 0.16, 0.8, Color("6e4529"), Vector3(cos(a) * 0.45, 0.16, sin(a) * 0.45), Vector3(sin(a) * 1.1, 0, -cos(a) * 1.1), 8)
	_mi(n, _sphere_mesh(0.2), Color.WHITE, Vector3(0, 0.7, 0.36), Vector3(0.8, 1.2, 0.5), Vector3.ZERO, glow_mat(Color("5fd8ff"), 1.8))
	var c := _vary(Color("3f9a4a"), rng, 0.03)
	_sph(n, 1.05, c, Vector3(0, 2.15, 0), Vector3(1.15, 0.72, 1.15))
	for i in 7:
		var a := TAU * i / 7.0
		_sph(n, 0.48, c.lightened(0.05 + (i % 2) * 0.05), Vector3(cos(a) * 1.0, 1.95 + (i % 3) * 0.12, sin(a) * 1.0), Vector3(1, 0.75, 1))
	_sph(n, 0.62, c.lightened(0.1), Vector3(0.1, 2.75, -0.05), Vector3(1, 0.7, 1))

# ================================================================ DESERT (golden sands)
const SAND := Color("e9c47c")
const SANDSTONE := Color("d9944f")
const CACTUS := Color("4fae5a")

static func cactus(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0, small := false) -> void:
	var n := _root(parent, pos, rng, s)
	var c := _vary(CACTUS, rng, 0.04)
	if small:
		_rb(n, Vector3(0.22, 0.3, 0.22), c, Vector3(0, 0.14, 0), Vector3.ZERO, 0.7)
		_sph(n, 0.05, Color("ff7aa8"), Vector3(0, 0.31, 0))
		return
	var h := rng.randf_range(0.8, 1.2)
	_rb(n, Vector3(0.3, h, 0.3), c, Vector3(0, h * 0.5, 0), Vector3.ZERO, 0.7)
	for side in [-1.0, 1.0]:
		if rng.randf() < 0.8:
			var y := h * rng.randf_range(0.35, 0.6)
			_rb(n, Vector3(0.24, 0.16, 0.18), c.darkened(0.04), Vector3(side * 0.2, y, 0), Vector3.ZERO, 0.7)
			_rb(n, Vector3(0.18, 0.38, 0.18), c.lightened(0.04), Vector3(side * 0.3, y + 0.18, 0), Vector3.ZERO, 0.7)
	_sph(n, 0.06, Color("ffd23f"), Vector3(0, h + 0.02, 0))

static func sand_rock(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	rock(parent, pos, rng, s, Color("d7a466"))

static func dry_bush(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var c := _vary(Color("b7a24a"), rng, 0.04)
	_sph(n, 0.24, c, Vector3(0, 0.16, 0), Vector3(1, 0.7, 1))
	_sph(n, 0.17, c.lightened(0.08), Vector3(0.18, 0.13, 0.06))
	_sph(n, 0.15, c.darkened(0.06), Vector3(-0.16, 0.11, 0.08))

static func bones(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_sph(n, 0.13, Color("f6ecd8"), Vector3(0, 0.1, 0), Vector3(1, 0.85, 1.15))
	for i in 3:
		_cyl(n, 0.025, 0.025, 0.36, Color("eee2c8"), Vector3(0.18 + i * 0.08, 0.03, 0.05 * i), Vector3(PI * 0.5, 0.4 + i * 0.3, 0), 6)

## Palm tree: curved segmented trunk, drooping fronds, coconuts.
static func palm(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var lean := rng.randf_range(0.08, 0.2)
	var top := Vector3.ZERO
	for i in 6:
		var y := 0.12 + i * 0.27
		var p := Vector3(lean * y * y * 0.6, y, 0)
		_cyl(n, 0.075 - i * 0.004, 0.09 - i * 0.004, 0.28, Color("b0773f").lightened((i % 2) * 0.08), p, Vector3(0, 0, -lean * y * 0.7))
		top = p
	top.y += 0.16
	var c := _vary(Color("4fb04a"), rng, 0.04)
	for i in 7:
		var a := TAU * i / 7.0
		var pv := Node3D.new()
		pv.position = top
		pv.rotation = Vector3(0, a, 0)
		n.add_child(pv)
		_mi(pv, _sphere_mesh(1.0), c.lightened((i % 2) * 0.07), Vector3(0, -0.06, -0.36), Vector3(0.12, 0.035, 0.42), Vector3(-0.45, 0, 0))
	for i in 3:
		_sph(n, 0.06, Color("7a4a2a"), top + Vector3(cos(i * 2.1) * 0.08, -0.08, sin(i * 2.1) * 0.08))

## Layered sandstone mesa (far frame of the desert).
static func mesa(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, 1.0)
	var w := rng.randf_range(1.4, 2.4) * s
	var d := rng.randf_range(1.2, 2.0) * s
	var y := -0.1
	for i in rng.randi_range(2, 3):
		var h := rng.randf_range(0.35, 0.6)
		var col := SANDSTONE.lerp(Color("eab275"), (i % 2) * 0.6)
		_rb(n, Vector3(w, h, d), _vary(col, rng, 0.02), Vector3(0, y + h * 0.5, 0), Vector3(0, rng.randf_range(-0.15, 0.15), 0), 0.25)
		y += h - 0.03
		w *= 0.78
		d *= 0.8
	if rng.randf() < 0.5:
		cactus(n, Vector3(0, y, 0), rng, 0.55)

static func dune(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_sph(n, 1.0, _vary(SAND.lightened(0.04), rng, 0.02), Vector3(0, -0.15, 0), Vector3(1.8, 0.5, 1.1))
	_sph(n, 0.7, _vary(SAND, rng, 0.02), Vector3(0.9, -0.12, 0.3), Vector3(1.4, 0.45, 1))

# ================================================================ VOLCANO (lava fields)
const BASALT := Color("3d3238")
const LAVA := Color("ff6a1a")

static func obsidian(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	for i in rng.randi_range(2, 3):
		var h := rng.randf_range(0.25, 0.55)
		_cyl_mi(n, 0.03, 0.16, h, 5, _vary(Color("2c2232"), rng, 0.03), Vector3(i * 0.16 - 0.15, h * 0.45, (i % 2) * 0.12), Vector3.ONE, Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)))

## Glowing ember cracks / shards on the ground.
static func embers(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_rb(n, Vector3(0.42, 0.1, 0.34), BASALT, Vector3(0, 0.03, 0), Vector3.ZERO, 0.4)
	for i in 3:
		_mi(n, _box_mesh(Vector3(0.26, 0.02, 0.035)), Color.WHITE, Vector3(rng.randf_range(-0.1, 0.1), 0.085, rng.randf_range(-0.1, 0.1)), Vector3.ONE, Vector3(0, rng.randf() * PI, 0), glow_mat(LAVA, 1.8))

## Steaming vent: rock ring with a lava glow and a slow smoke puff.
static func vent(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_cyl(n, 0.16, 0.3, 0.22, BASALT.lightened(0.05), Vector3(0, 0.11, 0), Vector3.ZERO, 9)
	_mi(n, _cyl_mesh(0.13, 0.13, 0.02, 12), Color.WHITE, Vector3(0, 0.22, 0), Vector3.ONE, Vector3.ZERO, glow_mat(Color("ffa030"), 2.2))
	var puff := _mi(n, _sphere_mesh(0.16), Color.WHITE, Vector3(0, 0.45, 0), Vector3.ONE, Vector3.ZERO, Mats.puff(Color(0.55, 0.5, 0.55, 0.55)))
	var tw := puff.create_tween().set_loops()
	tw.tween_property(puff, "position:y", 0.95, 2.2).from(0.35)
	tw.parallel().tween_property(puff, "scale", Vector3.ONE * 1.8, 2.2).from(Vector3.ONE * 0.6)

static func dead_tree(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var c := Color("3a2a26")
	_cyl(n, 0.05, 0.1, 0.9, c, Vector3(0, 0.45, 0), Vector3.ZERO, 7)
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf()
		_cyl(n, 0.015, 0.04, 0.45, c.lightened(0.05), Vector3(cos(a) * 0.12, 0.65 + i * 0.1, sin(a) * 0.12), Vector3(sin(a) * 0.9, 0, -cos(a) * 0.9), 6)
	_mi(n, _sphere_mesh(0.035), Color.WHITE, Vector3(0.03, 0.3, 0.09), Vector3.ONE, Vector3.ZERO, glow_mat(LAVA, 1.6))

## Bubbling lava pool with a dark crust rim.
static func lava_pool(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var r := rng.randf_range(0.5, 0.9)
	_torus_mi(n, r - 0.06, r + 0.12, BASALT, Vector3(0, 0.02, 0), Vector3(1, 0.6, 0.8))
	_cyl_mi(n, r, r, 0.04, 22, Color.WHITE, Vector3(0, 0.01, 0), Vector3(1, 1, 0.8), Vector3.ZERO, glow_mat(LAVA, 1.25))
	_cyl_mi(n, r * 0.5, r * 0.5, 0.045, 16, Color.WHITE, Vector3(r * 0.15, 0.015, 0), Vector3(1, 1, 0.8), Vector3.ZERO, glow_mat(Color("ffb040"), 1.3))
	for i in 2:
		var b := _mi(n, _sphere_mesh(0.07), Color.WHITE, Vector3(rng.randf_range(-0.3, 0.3) * r, 0.03, rng.randf_range(-0.2, 0.2) * r), Vector3.ONE, Vector3.ZERO, glow_mat(Color("ffb040"), 2.0))
		var tw := b.create_tween().set_loops()
		tw.tween_interval(rng.randf_range(0.2, 1.4))
		tw.tween_property(b, "scale", Vector3.ONE * 1.6, 0.4).from(Vector3.ONE * 0.2)
		tw.tween_property(b, "scale", Vector3.ONE * 0.01, 0.12)

static func basalt(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	for i in rng.randi_range(3, 5):
		var h := rng.randf_range(0.5, 1.4)
		var a := TAU * i / 5.0
		_cyl(n, 0.17, 0.19, h, _vary(BASALT, rng, 0.03), Vector3(cos(a) * 0.24, h * 0.5, sin(a) * 0.24), Vector3.ZERO, 6)
		_cyl(n, 0.14, 0.17, 0.04, Color("5a4a50"), Vector3(cos(a) * 0.24, h, sin(a) * 0.24), Vector3.ZERO, 6)

## Small volcano cone with a glowing crater and a lava stream (far frame).
static func cone(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var h := rng.randf_range(1.2, 1.9)
	_cyl(n, 0.32, 1.25, h, _vary(Color("4a3a40"), rng, 0.02), Vector3(0, h * 0.5 - 0.1, 0), Vector3.ZERO, 12)
	_cyl(n, 0.26, 0.4, 0.2, Color("2e2428"), Vector3(0, h - 0.06, 0), Vector3.ZERO, 12)
	_mi(n, _cyl_mesh(0.24, 0.24, 0.03, 12), Color.WHITE, Vector3(0, h + 0.03, 0), Vector3.ONE, Vector3.ZERO, glow_mat(LAVA, 2.2))
	_mi(n, _box_mesh(Vector3(0.12, 0.02, 1.0)), Color.WHITE, Vector3(0, h * 0.5, 0.62), Vector3.ONE, Vector3(-atan(h / 1.1), 0, 0), glow_mat(LAVA, 1.6))

# ================================================================ FROST (snow peaks)
const SNOW := Color("f4f9ff")
const ICE := Color("9fdcff")

static func snow_rock(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var c := _vary(Color("8f9fb8"), rng, 0.03)
	_rb(n, Vector3(0.6, 0.36, 0.5), c, Vector3(0, 0.14, 0), Vector3(0, 0, 0.08), 0.45)
	_rb(n, Vector3(0.5, 0.14, 0.42), SNOW, Vector3(0.0, 0.3, 0), Vector3(0, 0, 0.08), 0.6)

static func snow_mound(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_sph(n, 0.32, SNOW, Vector3(0, 0.06, 0), Vector3(1.4, 0.55, 1))
	_sph(n, 0.2, Color("e6f0fb"), Vector3(0.3, 0.04, 0.1), Vector3(1.2, 0.5, 1))

## Glowing ice shards.
static func ice_bits(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	crystals(parent, pos, rng, s * 0.8, ICE, Color("c8d6e8"))

static func ice_spike(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	for i in rng.randi_range(2, 3):
		var h := rng.randf_range(0.6, 1.2) * (1.0 - i * 0.25)
		var m := _cyl_mi(n, 0.0, 0.18, h, 6, Color("bfe8ff"), Vector3(i * 0.2 - 0.15, h * 0.48, (i % 2) * 0.14), Vector3.ONE, Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.2, 0.2)))
		m.material_override = Mats.prop(_q(Color("bfe8ff")), 0.2)

static func snowman(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	_sph(n, 0.22, SNOW, Vector3(0, 0.2, 0))
	_sph(n, 0.16, SNOW, Vector3(0, 0.5, 0))
	_mi(n, _cyl_mesh(0.0, 0.035, 0.14, 6), Color("ff8a2a"), Vector3(0, 0.52, 0.17), Vector3.ONE, Vector3(PI * 0.5, 0, 0))
	for x in [-0.06, 0.06]:
		_sph(n, 0.022, Color("2a2440"), Vector3(x, 0.57, 0.14))
	_cyl(n, 0.13, 0.13, 0.04, Color("e2412c"), Vector3(0, 0.39, 0))

## Snow-capped mountain peak (far frame).
static func peak(parent: Node3D, pos: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	var n := _root(parent, pos, rng, s)
	var h := rng.randf_range(1.6, 2.4)
	_cyl(n, 0.0, 1.2, h, _vary(Color("8a9ab4"), rng, 0.02), Vector3(0, h * 0.5 - 0.1, 0), Vector3.ZERO, 7)
	_cyl(n, 0.0, 0.62, h * 0.48, SNOW, Vector3(0, h * 0.76 - 0.08, 0), Vector3.ZERO, 7)

# ================================================================ WANDERING MERCHANT
## Roadside stall of the wandering merchant: a wheeled wooden cart under a striped awning, heaped with
## potions, a chest and sacks, and the merchant himself (round robed body, big floppy hat, huge backpack)
## standing beside it. Front faces +z (toward the camera). Returns {"root", "figure"} — figure bobs / waves.
static func merchant(parent: Node3D, pos: Vector3, side := 1.0) -> Dictionary:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = -0.35 * side   # angled a little toward the road
	parent.add_child(n)
	# cart
	var cart := Node3D.new()
	cart.position = Vector3(0.28 * side, 0, -0.1)
	n.add_child(cart)
	_rb(cart, Vector3(1.08, 0.3, 0.6), WOOD, Vector3(0, 0.42, 0), Vector3.ZERO, 0.25)
	_box(cart, Vector3(1.12, 0.05, 0.64), WOOD_DARK, Vector3(0, 0.29, 0))
	for x in [-0.36, 0.36]:
		var w := _cyl(cart, 0.22, 0.22, 0.08, WOOD_DARK, Vector3(x, 0.22, 0.33), Vector3(PI * 0.5, 0, 0), 12)
		_cyl(cart, 0.07, 0.07, 0.1, Color("e0b85a"), Vector3(x, 0.22, 0.36), Vector3(PI * 0.5, 0, 0), 8)
		w.name = "wheel"
	_box(cart, Vector3(0.05, 0.05, 0.7), WOOD_DARK, Vector3(-0.62 * side, 0.36, 0.15), Vector3(0, 0, 0.0))
	# awning: four posts and a red / cream striped roof sloping toward the front
	for x in [-0.48, 0.48]:
		for z in [-0.24, 0.24]:
			_cyl(cart, 0.025, 0.025, 0.95 if z < 0.0 else 0.8, WOOD_DARK, Vector3(x, 0.55 + (0.475 if z < 0.0 else 0.4), z))
	for i in 6:
		var col := Color("e2412c") if i % 2 == 0 else Color("fff4e0")
		_rb(cart, Vector3(0.19, 0.06, 0.74), col, Vector3(-0.475 + i * 0.19, 1.38, 0.02), Vector3(-0.22, 0, 0), 0.5)
	for i in 6:
		_sph(cart, 0.07, Color("e2412c") if i % 2 == 0 else Color("fff4e0"), Vector3(-0.475 + i * 0.19, 1.27, 0.4), Vector3(1.2, 0.8, 0.6))
	# goods
	_rb(cart, Vector3(0.36, 0.24, 0.26), Color("a8642e"), Vector3(-0.22, 0.69, -0.06), Vector3(0, 0.2, 0), 0.3)
	_box(cart, Vector3(0.38, 0.04, 0.28), Color("f2c14a"), Vector3(-0.22, 0.79, -0.06), Vector3(0, 0.2, 0))
	var potion := [Color("ff5f7e"), Color("5fb4ff"), Color("8fe36a")]
	for i in 3:
		var p := Vector3(0.12 + i * 0.13, 0.66, 0.14 - (i % 2) * 0.12)
		_mi(cart, _sphere_mesh(0.075), Color.WHITE, p, Vector3.ONE, Vector3.ZERO, glow_mat(potion[i], 1.1))
		_cyl(cart, 0.025, 0.03, 0.08, Color("fff4e0"), p + Vector3(0, 0.09, 0))
	_rb(cart, Vector3(0.26, 0.3, 0.22), Color("d8b37a"), Vector3(0.36, 0.72, -0.12), Vector3.ZERO, 0.7)
	# hanging lantern on the front post
	_mi(cart, _box_mesh(Vector3(0.1, 0.13, 0.1)), Color.WHITE, Vector3(0.48 * side, 1.08, 0.3), Vector3.ONE, Vector3.ZERO, glow_mat(LANTERN, 2.2))
	# the merchant
	var fig := Node3D.new()
	fig.position = Vector3(-0.5 * side, 0, 0.3)
	n.add_child(fig)
	var body := Node3D.new()
	fig.add_child(body)
	_rb(body, Vector3(0.62, 0.36, 0.52), Color("4fa36a"), Vector3(0, 0.2, 0), Vector3.ZERO, 0.6)   # robe hem
	_rb(body, Vector3(0.48, 0.42, 0.42), Color("5cbf7a"), Vector3(0, 0.46, 0), Vector3.ZERO, 0.6)
	_box(body, Vector3(0.5, 0.06, 0.44), Color("8a5a34"), Vector3(0, 0.42, 0))                       # belt
	_sph(body, 0.05, Color("f2c14a"), Vector3(0, 0.42, 0.22))
	_rb(body, Vector3(0.5, 0.6, 0.34), Color("a8642e"), Vector3(0, 0.62, -0.3), Vector3(0.1, 0, 0), 0.35)   # backpack
	_rb(body, Vector3(0.54, 0.12, 0.38), Color("6b4636"), Vector3(0, 0.95, -0.3), Vector3(0.1, 0, 0), 0.5)
	_cyl(body, 0.09, 0.09, 0.56, Color("d8b37a"), Vector3(0, 1.0, -0.32), Vector3(0, 0, PI * 0.5), 10)       # bedroll
	_sph(body, 0.27, Color("ffd9b8"), Vector3(0, 0.86, 0.02))                                                # head
	for x in [-0.09, 0.09]:
		_sph(body, 0.035, Color("2a2238"), Vector3(x, 0.88, 0.25))
	_sph(body, 0.05, Color("ff9a8a"), Vector3(0, 0.82, 0.28))                                                # nose
	_rb(body, Vector3(0.36, 0.1, 0.12), Color("f4f1ea"), Vector3(0, 0.74, 0.22), Vector3(0.2, 0, 0), 0.6)  # beard
	_cyl(body, 0.46, 0.48, 0.05, Color("7a4ad8"), Vector3(0, 1.06, 0.02))                                    # hat brim
	_cyl(body, 0.0, 0.24, 0.42, Color("8a5ae0"), Vector3(0.04, 1.28, 0.0), Vector3(0, 0, -0.25))           # floppy cone
	_box(body, Vector3(0.5, 0.06, 0.06), Color("f2c14a"), Vector3(0, 1.1, 0.02))
	var arm := Node3D.new()
	arm.name = "arm"
	arm.position = Vector3(0.26 * side, 0.55, 0.05)
	body.add_child(arm)
	_rb(arm, Vector3(0.12, 0.3, 0.12), Color("5cbf7a"), Vector3(0, 0.15, 0), Vector3.ZERO, 0.6)
	_sph(arm, 0.07, Color("ffd9b8"), Vector3(0, 0.32, 0))
	var bt := body.create_tween().set_loops()
	bt.tween_property(body, "scale", Vector3(1.04, 0.95, 1.04), 0.45).set_trans(Tween.TRANS_SINE)
	bt.tween_property(body, "scale", Vector3(0.97, 1.04, 0.97), 0.45).set_trans(Tween.TRANS_SINE)
	var at := arm.create_tween().set_loops()
	at.tween_property(arm, "rotation:z", -0.5 * side, 0.22).set_trans(Tween.TRANS_SINE)
	at.tween_property(arm, "rotation:z", -1.9 * side, 0.22).set_trans(Tween.TRANS_SINE)
	at.tween_property(arm, "rotation:z", -0.6 * side, 0.22).set_trans(Tween.TRANS_SINE)
	at.tween_property(arm, "rotation:z", -1.9 * side, 0.22).set_trans(Tween.TRANS_SINE)
	at.tween_interval(1.4)
	var l := OmniLight3D.new()
	l.light_color = Color("ffb46a")
	l.light_energy = 1.4
	l.omni_range = 2.4
	l.omni_attenuation = 1.1
	l.position = Vector3(0.48 * side, 1.0, 0.5)
	cart.add_child(l)
	return {"root": n, "figure": fig}
