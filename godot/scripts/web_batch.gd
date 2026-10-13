class_name WebBatch
extends RefCounted
## Web build draw-call batching. The march road is dressed with thousands of small prop meshes (a bush is a dozen
## spheres), ~3,400 draw calls a frame plus the shadow pass: fine for a desktop GPU, frame drops in mobile Safari's
## WebGL. On the Compatibility renderer, once a road chunk is built its static, lit, opaque prop meshes are moved
## into one MultiMesh per (mesh, material look, shadow, 4 m cell) - same shapes, same colors (per-instance color), a handful
## of draw calls. Desktop (Forward+) is untouched.
## Left alone: anything under a node with meta "no_batch" (animated props), meshes with children, unshaded /
## transparent / vertex-colored materials (glow, smoke, ground) and hidden meshes.
## The batches use BATCH_SHADER, StandardMaterial3D's prop look (Burley diffuse, GGX specular, rim, emission) with the
## albedo from the instance color, plus normals put through the inverse-transpose per instance: the Compatibility
## renderer's own instancing path skips that, so a squashed instance (a flattened plate) would shade like a cushion.

const CELL := 6.0         # metres: one MultiMesh per cell, so off-screen parts of a chunk are still culled
static var _mats := {}   # look key -> shared vertex-colored StandardMaterial3D

static func batch(root: Node3D) -> void:
	if not WebLook.compat() or not WebLook.perf.get("batch", true):
		return
	var groups := {}   # key -> {mesh, mat, shadow, xforms: [], colors: []}
	_collect(root, Transform3D.IDENTITY, groups)
	for key in groups:
		var g: Dictionary = groups[key]
		if g["xforms"].size() < 2:
			continue   # nothing to gain; leave the original mesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _lod(g["mesh"])
		mm.instance_count = g["xforms"].size()
		for i in mm.instance_count:
			mm.set_instance_transform(i, g["xforms"][i])
			mm.set_instance_color(i, g["colors"][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = g["mat"]
		mmi.cast_shadow = g["shadow"]
		root.add_child(mmi)
		for mi in g["nodes"]:
			mi.queue_free()

static func _collect(n: Node, xf: Transform3D, groups: Dictionary) -> void:
	for c in n.get_children():
		if not (c is Node3D) or c.has_meta("no_batch") or not (c as Node3D).visible:
			continue
		var cxf: Transform3D = xf * (c as Node3D).transform
		if c is MeshInstance3D and c.get_child_count() == 0:
			_take(c as MeshInstance3D, cxf, groups)
		elif c.get_class() == "Node3D" or c is MeshInstance3D:
			_collect(c, cxf, groups)

static func _take(mi: MeshInstance3D, xf: Transform3D, groups: Dictionary) -> void:
	var m := mi.material_override as StandardMaterial3D
	if mi.mesh == null or m == null or m.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			or m.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or m.vertex_color_use_as_albedo \
			or m.albedo_texture != null or m.next_pass != null or mi.material_overlay != null 			or m.metallic != 0.0 or m.cull_mode != BaseMaterial3D.CULL_BACK:   # BATCH_SHADER covers the plain prop look only
		return
	var look := "%.3f|%.3f|%.3f|%.3f|%s|%s" % [m.roughness, m.metallic_specular, m.rim, m.rim_tint,
		m.emission.to_html(), m.emission_enabled]
	var cell := Vector2i(floori(xf.origin.x / CELL), floori(xf.origin.z / CELL))
	var key := "%d|%s|%d|%s" % [mi.mesh.get_instance_id(), look, mi.cast_shadow, cell]
	var g: Dictionary = groups.get(key, {})
	if g.is_empty():
		g = {"mesh": mi.mesh, "mat": _mat(look, m), "shadow": mi.cast_shadow, "xforms": [], "colors": [], "nodes": []}
		groups[key] = g
	g["xforms"].append(xf)
	g["colors"].append(m.albedo_color)
	g["nodes"].append(mi)

const BATCH_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, skip_vertex_transform;
uniform float roughness = 0.85;
uniform float specular = 0.25;
uniform float rim = 0.25;
uniform float rim_tint = 0.6;
uniform vec3 emission : source_color = vec3(0.0);
void vertex() {
	// COLOR (the instance color) already arrives linear here
	VERTEX = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = normalize(inverse(transpose(mat3(MODELVIEW_MATRIX))) * NORMAL);
}
void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	RIM = rim;
	RIM_TINT = rim_tint;
	EMISSION = emission;
}
"""
static var _shader: Shader

## Phones: the prop spheres (a bush is a dozen of them) come in at 12x6 instead of 16x8 segments - half the
## triangles for the vertex and shadow passes; at their on-screen size the silhouette barely changes.
static var _lods := {}
static func _lod(m: Mesh) -> Mesh:
	if not WebLook.perf.get("mobile", false) or not (m is SphereMesh) or (m as SphereMesh).radial_segments <= 12:
		return m
	var low: SphereMesh = _lods.get(m.get_instance_id())
	if low == null:
		low = m.duplicate() as SphereMesh
		low.radial_segments = 12
		low.rings = 6
		_lods[m.get_instance_id()] = low
	return low

## The source material's look, with its albedo moved into the per-instance color.
static func _mat(look: String, src: StandardMaterial3D) -> ShaderMaterial:
	var m: ShaderMaterial = _mats.get(look)
	if m == null:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = BATCH_SHADER
		m = ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("roughness", src.roughness)
		m.set_shader_parameter("specular", src.metallic_specular)
		m.set_shader_parameter("rim", src.rim if src.rim_enabled else 0.0)
		m.set_shader_parameter("rim_tint", src.rim_tint)
		m.set_shader_parameter("emission", src.emission * src.emission_energy_multiplier if src.emission_enabled else Color.BLACK)
		_mats[look] = m
	return m
