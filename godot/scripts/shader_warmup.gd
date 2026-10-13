extends Node
## Web build hitch fix. WebGL compiles a shader the first time something draws with it, and in Chrome on Windows
## (ANGLE / D3D11) a lit material costs ~1.3 s per compile (plus its instanced twin), which froze fights for seconds.
## Autoload "ShaderWarmup", Compatibility renderer only: every Environment that goes through WebLook.apply() gets an
## off-screen stage drawn with that same environment, where each material variant the game uses is drawn once
## (lit by an omni and a shadowed spot, and outside them; plain and as a particle), and a fogged twin of the first
## environment is queued too so the march's fog variants are ready before the first fight. While that runs a small
## "preparing graphics" overlay covers the screen; the browser caches the results, so later visits are quick.
## Desktop (Forward+) does nothing.
##
## The variant list (res://warmup_shaders/*.tres) is captured by playing the game with
##   Godot --path . --rendering-method gl_compatibility -- --capture-shaders [--mode=march --autoplay | --test=... ]
## Each run adds the variants it saw; clear the folder and re-capture after changing materials / VFX.

const DIR := "res://warmup_shaders"
const HOLD_FRAMES := 2         # frames each material stays on stage

var _capture := false
var _seen := {}
var _scan_t := 0.0
var _mats3d: Array[Material] = []
var _mats2d: Array[Material] = []
var _queue: Array[Environment] = []
var _done := {}
var _running := false
var _overlay: CanvasLayer
var _bar: ColorRect
var _steps := 0
var _step := 0

func _ready() -> void:
	_capture = Array(OS.get_cmdline_user_args()).has("--capture-shaders")
	if _capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		for f in DirAccess.get_files_at(DIR):
			_seen[f.get_basename()] = true
		print("[ShaderWarmup] capture on, %d known" % _seen.size())
		return
	if not WebLook.compat():
		return
	if Array(OS.get_cmdline_user_args()).has("--nowarm") or 			(OS.has_feature("web") and str(JavaScriptBridge.eval("location.search")).contains("nowarm")):
		return   # dev: measure / screenshot without the warm-up (?nowarm on the web)
	for f in ResourceLoader.list_directory(DIR):   # also sees exported (remapped) resources
		if not f.ends_with(".tres"):
			continue
		var m := load(DIR + "/" + f) as Material
		if m is CanvasItemMaterial or (m is ShaderMaterial and (m as ShaderMaterial).shader \
				and (m as ShaderMaterial).shader.get_mode() == Shader.MODE_CANVAS_ITEM):
			_mats2d.append(m)
		elif m != null:
			_mats3d.append(m)

## Queue a warm-up for an environment (WebLook.apply calls this). Environments that render alike run once.
func warm(e: Environment) -> void:
	if _capture or _mats3d.is_empty() or not e.glow_enabled:
		return   # glow-less environments are the small UI portrait / chest views: few materials, not worth a pass
	_enqueue(e)
	if _done.size() == 1 and not e.fog_enabled:   # the march fogs its world: get those variants ready too
		var f := e.duplicate() as Environment
		f.fog_enabled = true
		f.fog_mode = Environment.FOG_MODE_DEPTH
		_enqueue(f)

func _enqueue(e: Environment) -> void:
	var key := "%s%s%s%s%s" % [e.fog_enabled, e.fog_mode, e.glow_enabled, e.tonemap_mode, e.ambient_light_source]
	if _done.has(key):
		return
	_done[key] = true
	_queue.append(e)
	_steps += _mats3d.size()
	if not _running:
		_running = true   # set now: a second enqueue in the same frame must not start a second loop
		_run.call_deferred()

func _run() -> void:
	_show_overlay()
	if not _mats2d.is_empty():
		_warm2d()
	while not _queue.is_empty():
		await _warm3d(_queue.pop_front())
	_running = false
	if _overlay:
		_overlay.queue_free()
		_overlay = null
		_bar = null

func _warm2d() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	for m in _mats2d:
		var r := ColorRect.new()
		r.size = Vector2(32, 32)
		r.material = m
		vp.add_child(r)
	_free_later(vp, 4)
	_mats2d.clear()

func _warm3d(env: Environment) -> void:
	var t0 := Time.get_ticks_msec()
	var st := _stage(env)
	for m in _mats3d:
		var made: Array[Node] = []
		_put(st["root"], m, made)
		for f in HOLD_FRAMES:
			await get_tree().process_frame
		for n in made:
			n.queue_free()
		_step += 1
		if _bar:
			_bar.scale.x = float(_step) / maxf(1.0, float(_steps))
	st["vp"].queue_free()
	print("[ShaderWarmup] %d materials warmed in %d ms (fog=%s)" % [_mats3d.size(), Time.get_ticks_msec() - t0, env.fog_enabled])

func _free_later(n: Node, frames: int) -> void:
	for f in frames:
		await get_tree().process_frame
	n.queue_free()

## Off-screen stage with the scene's environment: shadowed sun + fill, an omni and a shadowed spot (ultimate
## spotlight) lighting the near spot; the far spot is outside both (objects without omni / spot variants).
func _stage(env: Environment) -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 64)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.0
	vp.add_child(cam)
	cam.position = Vector3(0, 10, 0.01)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	vp.add_child(sun)
	sun.rotation = Vector3(-1.0, 0.4, 0)
	var fill := DirectionalLight3D.new()
	vp.add_child(fill)
	fill.rotation = Vector3(-0.4, -2.0, 0)
	var omni := OmniLight3D.new()
	omni.omni_range = 2.5
	vp.add_child(omni)
	omni.position = Vector3(0, 1, -2.0)
	var spot := SpotLight3D.new()
	spot.shadow_enabled = true
	spot.spot_range = 5.0
	spot.spot_angle = 40.0
	vp.add_child(spot)
	spot.position = Vector3(0, 4, -2.0)
	spot.rotation = Vector3(-PI / 2, 0, 0)
	var root := Node3D.new()
	vp.add_child(root)
	return {"vp": vp, "root": root}

## A material on a plain mesh and on a one-particle CPUParticles3D (instanced variant), inside and outside the
## local lights.
func _put(root: Node3D, m: Material, made: Array[Node]) -> void:
	for z in [-2.0, 3.0]:
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		sm.radial_segments = 6
		sm.rings = 3
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = m
		root.add_child(mi)
		mi.position = Vector3(-0.5, 0, z)
		var p := CPUParticles3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.4, 0.4)
		qm.material = m
		p.mesh = qm
		p.amount = 1
		p.lifetime = 10.0
		p.gravity = Vector3.ZERO
		root.add_child(p)
		p.position = Vector3(0.5, 0.3, z)
		made.append(mi)
		made.append(p)

## A note and a progress strip while the first warm-up runs (input is blocked meanwhile).
func _show_overlay() -> void:
	if _overlay or _done.size() > 2:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 128
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.12, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.position = Vector2(-220, -40)
	box.size = Vector2(440, 80)
	dim.add_child(box)
	var l := Label.new()
	l.text = "그래픽 준비 중… (처음 한 번만)"
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.2))
	l.add_theme_constant_override("outline_size", 10)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	var back := ColorRect.new()
	back.color = Color(1, 1, 1, 0.25)
	back.custom_minimum_size = Vector2(440, 12)
	box.add_child(back)
	_bar = ColorRect.new()
	_bar.color = Color("ffd23f")
	_bar.size = Vector2(440, 12)
	_bar.scale.x = 0.0
	back.add_child(_bar)

# ---------------------------------------------------------------- capture (dev)
func _process(delta: float) -> void:
	if not _capture:
		return
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.1   # periodic rescan: some materials switch modes (transparency, emission) at runtime
	_scan(get_tree().root)

func _scan(n: Node) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		_take(g.material_override)
		_take(g.material_overlay)
		var mesh: Mesh = null
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mesh = mi.mesh
			if mesh:
				for i in mesh.get_surface_count():
					_take(mi.get_surface_override_material(i))
		elif n is CPUParticles3D:
			mesh = (n as CPUParticles3D).mesh
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
			mesh = (n as MultiMeshInstance3D).multimesh.mesh
		if mesh:
			for i in mesh.get_surface_count():
				_take(mesh.surface_get_material(i))
	elif n is CanvasItem:
		_take((n as CanvasItem).material)
	for c in n.get_children():
		_scan(c)

func _take(m: Material) -> void:
	while m:
		var key := _key(m)
		if key != "" and not _seen.has(key):
			_seen[key] = true
			var copy := _sanitized(m)
			var err := ResourceSaver.save(copy, "%s/%s.tres" % [DIR, key])
			print("[ShaderWarmup] + %s %s (%s)" % [key, m.get_class(), "ok" if err == OK else str(err)])
		m = m.next_pass

## Shader identity: for BaseMaterial3D the generated shader depends only on its flags / modes / features and which
## textures are set (not on colors or numbers); for ShaderMaterial on the shader code.
func _key(m: Material) -> String:
	if m is ShaderMaterial:
		var sh := (m as ShaderMaterial).shader
		return "" if sh == null else "s%08x" % (sh.code.hash() & 0xffffffff)
	var parts := [m.get_class()]
	for p in m.get_property_list():
		if not (p.usage & PROPERTY_USAGE_STORAGE) or p.name == "next_pass" or p.name == "render_priority":
			continue
		var v = m.get(p.name)
		if p.type == TYPE_BOOL or p.type == TYPE_INT:
			parts.append("%s=%s" % [p.name, v])
		elif p.type == TYPE_OBJECT and p.hint == PROPERTY_HINT_RESOURCE_TYPE:
			parts.append("%s=%s" % [p.name, v != null])
	return "m%08x" % (",".join(parts).hash() & 0xffffffff)

## A copy without the real textures (a 2x2 stand-in keeps the "has texture" variant) and without next_pass.
func _sanitized(m: Material) -> Material:
	var c := m.duplicate() as Material
	c.next_pass = null
	var tex := _stand_in()
	if c is ShaderMaterial:
		for u in (c as ShaderMaterial).shader.get_shader_uniform_list():
			if (c as ShaderMaterial).get_shader_parameter(u.name) is Texture:
				(c as ShaderMaterial).set_shader_parameter(u.name, tex)
	else:
		for p in c.get_property_list():
			if p.type == TYPE_OBJECT and c.get(p.name) is Texture2D:
				c.set(p.name, tex)
	return c

static var _tex: ImageTexture
static func _stand_in() -> ImageTexture:
	if _tex == null:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_tex = ImageTexture.create_from_image(img)
	return _tex
