extends SceneTree
## Perf probe: runs the march (autoplay) and prints render / frame-time monitors every 2 s, to see where a frame goes.
##   Godot --path . --rendering-method gl_compatibility --resolution 540x960 -s res://tools/perf_probe.gd -- --autoplay --nowarm
##   [--probe-scene=res://scenes/Lobby.tscn]   (--test=map with the march opens the world map)

var _t := 0.0
var _next := 3.0

func _initialize() -> void:
	var scene := "res://scenes/March.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-scene="):
			scene = a.substr(14)
	change_scene_to_file.call_deferred(scene)

func _process(delta: float) -> bool:
	_t += delta
	if _t >= _next:
		_next += 2.0
		var vp := root.get_viewport()
		var info := func(t: int, k: int) -> int: return vp.get_render_info(t, k)
		print("[Perf] by pass: visible draws=%d shadow draws=%d canvas draws=%d canvas objs=%d" % [
			info.call(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(Viewport.RENDER_INFO_TYPE_SHADOW, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
			info.call(Viewport.RENDER_INFO_TYPE_CANVAS, Viewport.RENDER_INFO_OBJECTS_IN_FRAME)])
		var subs := root.find_children("*", "SubViewport", true, false)
		var sd := 0
		for sv in subs:
			sd += (sv as SubViewport).get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		print("[Perf] subviewports=%d their draws=%d" % [subs.size(), sd])
		print("[Perf] t=%4.1f fps=%3d proc=%5.2fms objs=%4d prims=%6d draws=%4d nodes=%5d" % [_t,
			Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	if _t > 8.0 and not _dumped:
		_dumped = true
		_dump()
	return _t > 24.0

var _dumped := false

func _under(n: Node, cls: String) -> bool:
	while n:
		var sc = n.get_script()
		if sc and sc.get_global_name() == cls:
			return true
		n = n.get_parent()
	return false

## Visible geometry by mesh kind: instance count, triangles, shadow casting.
func _dump() -> void:
	var by := {}
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree() and (n as MeshInstance3D).mesh:
			var m: Mesh = (n as MeshInstance3D).mesh
			var tris := 0
			for i in m.get_surface_count():
				var a := m.surface_get_arrays(i)
				var idx = a[Mesh.ARRAY_INDEX]
				tris += (idx.size() if idx != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			var mat = (n as MeshInstance3D).material_override
			var owner := "unit" if _under(n, "UnitModel") else "world"
			var k := owner + ":" + m.get_class()
			if mat is StandardMaterial3D:
				k += "[%s%s]" % ["U" if mat.shading_mode == 0 else "L", "T" if mat.transparency != 0 else ""]
			elif mat is ShaderMaterial:
				k += "[S]"
			if m is SphereMesh:
				k += "(%d,%d)" % [(m as SphereMesh).radial_segments, (m as SphereMesh).rings]
			elif m is CylinderMesh:
				k += "(%d)" % (m as CylinderMesh).radial_segments
			elif m is CapsuleMesh:
				k += "(%d,%d)" % [(m as CapsuleMesh).radial_segments, (m as CapsuleMesh).rings]
			elif m is TorusMesh:
				k += "(%d,%d)" % [(m as TorusMesh).rings, (m as TorusMesh).ring_segments]
			var e: Array = by.get(k, [0, 0, 0])
			e[0] += 1
			e[1] += tris
			e[2] += 1 if (n as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
			by[k] = e
		elif n is CPUParticles3D or n is MultiMeshInstance3D:
			var e2: Array = by.get(n.get_class(), [0, 0, 0])
			e2[0] += 1
			by[n.get_class()] = e2
	var keys := by.keys()
	keys.sort_custom(func(a, b): return by[a][1] > by[b][1])
	for k in keys.slice(0, 25):
		print("[Mesh] %-28s n=%5d tris=%8d shadow=%5d" % [k, by[k][0], by[k][1], by[k][2]])
