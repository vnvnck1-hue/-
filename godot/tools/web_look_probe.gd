extends SceneTree
## Web look probe: renders a fixed battle board with glowing VFX stand-ins (daylight + dimmed stage) and saves
## PNGs, so the Forward+ desktop look and the Compatibility (web) look can be compared frame for frame.
##   Godot --path . --resolution 540x960 [--rendering-method gl_compatibility] -s res://tools/web_look_probe.gd -- --out=DIR [--map]
## See scripts/web_look.gd for the corrections this is used to tune.

var _out := "user://web_look_probe"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_build.call_deferred()

func _build() -> void:
	if root.get_node_or_null("WebLookHook") == null:
		root.add_child(WebLook.new())
	if Array(OS.get_cmdline_user_args()).has("--map"):   # the world map (own environment, sea shader, plaque lights)
		var m := WorldMap.new()
		root.add_child(m)
		m.build(0, 0.3, [], 0)
		await create_timer(3.0).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out + "/map.png")
		quit()
		return
	var w := World.new()
	root.add_child(w)
	w.build()
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	root.add_child(cam)
	cam.position = Vector3(0, 16.0, 9.4)
	cam.look_at(Vector3(0, 0, 0.55), Vector3.UP)
	cam.current = true
	# hero-ish blocks, glowing orbs (Mats.glow, energy 1..3), additive rings and an alpha slash
	var cols := [Color("ff9a3c"), Color("6fd3ff"), Color("ff5fd2"), Color("ffe36b")]
	for i in 4:
		for k in 3:
			var s := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.22
			sm.height = 0.44
			s.mesh = sm
			s.material_override = Mats.glow(cols[i], 1.0 + k)
			s.position = Vector3(-2.2 + i * 1.45, 0.5, -2.0 + k * 1.3)
			w.add_child(s)
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.35
		tm.outer_radius = 0.45
		ring.mesh = tm
		ring.material_override = Mats.fx(Color(cols[i], 0.8), true)
		ring.position = Vector3(-2.2 + i * 1.45, 0.08, 2.4)
		w.add_child(ring)
		var b := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.8, 0.5)
		b.mesh = bm
		b.material_override = Mats.toy(cols[(i + 1) % 4])
		b.position = Vector3(-2.2 + i * 1.45, 0.4, 3.4)
		w.add_child(b)
	var slash := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(4.0, 0.5)
	slash.mesh = qm
	slash.material_override = Mats.fx(Color(1.6, 1.3, 0.6, 0.7))
	slash.rotation = Vector3(-PI / 2, 0.4, 0)
	slash.position = Vector3(0, 0.9, 0.6)
	w.add_child(slash)
	_shoot(w)

func _shoot(w: World) -> void:
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out + "/day.png")
	w.set_dim(1.0)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out + "/dim.png")
	w.set_dim(0.5)
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out + "/half.png")
	quit()
