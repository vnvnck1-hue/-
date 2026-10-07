class_name Cinematic
extends RefCounted
## Ultimate cast presentation:
##   intro  - battle freezes, letterbox, camera dollies to the caster, stage lights dim, a spotlight
##            hits the caster who strikes a charge-up pose (only the caster + intro VFX keep moving)
##   hold   - battle resumes under the dark stage so the skill VFX and motion read clearly;
##            the spotlight follows the caster, then the daylight fades back.

const INTRO_TIME := 0.5
const STAGE_DIM := 0.38      # how dark the stage gets (was full dark)
const CAM_FOCUS := 0.3       # how far the camera dollies toward the caster (was all the way)

static var stage: Node3D          # always-processing parent for lights / intro VFX
static var _dim_users := 0
static var _dim := 0.0
static var _dim_tw: Tween
static var active := false        # intro running (blocks other ult inputs)

static func _ensure_stage(game: Node) -> void:
	if stage == null or not is_instance_valid(stage):
		stage = Node3D.new()
		stage.name = "CinematicStage"
		stage.process_mode = Node.PROCESS_MODE_ALWAYS
		game.add_child(stage)

static func _set_dim(game: Node, v: float) -> void:
	_dim = v
	game.world.set_cine_dim(v)

static func _tween_dim(game: Node, to: float, dur: float) -> void:
	if _dim_tw and _dim_tw.is_valid():
		_dim_tw.kill()
	_dim_tw = stage.create_tween()
	_dim_tw.tween_method(func(v: float): _set_dim(game, v), _dim, to, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

static func _spotlight(at: Vector3, col: Color) -> SpotLight3D:
	var sl := SpotLight3D.new()
	sl.light_color = col
	sl.light_energy = 0.0
	sl.spot_range = 12.0
	sl.spot_angle = 16.0
	sl.spot_attenuation = 0.6
	sl.shadow_enabled = true
	stage.add_child(sl)
	sl.global_position = at + Vector3(0.6, 7.5, 1.2)
	sl.look_at(at, Vector3.UP)
	return sl

## Awaitable. Returns a handle Dictionary to pass to release().
static func intro(game: Node, h: Actor, ult_name: String, col: Color) -> Dictionary:
	_ensure_stage(game)
	active = true
	_dim_users += 1
	game.cam.cancel_hitstop()
	var tree: SceneTree = game.get_tree()
	tree.paused = true
	var old_mode := h.process_mode
	h.process_mode = Node.PROCESS_MODE_ALWAYS
	var old_root := Vfx.root
	Vfx.root = stage
	old_root.visible = false   # hide frozen battle VFX so only the ultimate is in focus
	# stage: dim world, spotlight + warm rim on the caster
	_tween_dim(game, STAGE_DIM, 0.18)
	var spot := _spotlight(h.global_position, Color(1.0, 0.95, 0.85))
	var rim := OmniLight3D.new()
	rim.light_color = col.lightened(0.3)
	rim.omni_range = 2.6
	rim.light_energy = 0.0
	stage.add_child(rim)
	rim.global_position = h.global_position + Vector3(-0.6, 1.0, -0.8)
	var lt := stage.create_tween().set_parallel(true)
	lt.tween_property(spot, "light_energy", 2.6, 0.18)
	lt.tween_property(rim, "light_energy", 1.4, 0.18)
	game.cam.focus_amount = CAM_FOCUS
	game.cam.focus(h.global_position, true)
	game.cam.kick_fov(-1.2)
	game.hud.cinema_bars(true, ult_name, h.def["name"], col)
	Sfx.play("whoosh", -6.0, 0.6)
	# caster pose: crouch, leap up with a spin, charge sparks, land
	h.model.flash(col.lightened(0.4), 2.2, 0.6)
	var pose := h.create_tween()
	pose.tween_callback(func(): h.model.punch_scale(0.75, 1.3, 0.25))
	pose.tween_property(h.model, "position:y", 0.55, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pose.parallel().tween_property(h.model, "rotation:y", h.model.rotation.y + TAU, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pose.tween_callback(func():
		h.model.play_attack("fireball" if h.cls == "mage" else ("arrow" if h.cls == "ranger" else "melee"))
		Vfx.sparks(h.global_position + Vector3(0, 0.8, 0), col, 18, 3.5, 0.5, "star5", 0.16, -2.0, Vector3.UP, 180.0)
		Vfx.pop_sprite(h.global_position + Vector3(0, 0.8, 0), "star", Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, 0.8), 1.3, 0.3, 0.8)
		Sfx.play("chime", -4.0, 0.7))
	pose.tween_property(h.model, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	pose.tween_callback(func():
		h.model.punch_scale(1.45, 0.6, 0.4)
		Vfx.ground_ring(h.global_position, Color(col.r * 1.2, col.g * 1.2, col.b * 1.2, 0.8), 0.3, 2.4, 0.35))
	Vfx.ground_ring(h.global_position, Color(col.r, col.g, col.b, 0.7), 2.2, 0.4, 0.5, "ring_soft")
	await tree.create_timer(INTRO_TIME, true, false, true).timeout
	# resume the battle (stage stays dark)
	Vfx.root = old_root
	old_root.visible = true
	if is_instance_valid(h):
		h.process_mode = old_mode
	game.cam.focus(h.global_position, false)
	game.hud.cinema_bars(false, "", "", col)
	tree.paused = false
	active = false
	return {"spot": spot, "rim": rim, "hero": h}

## Keep the dark stage for `hold` seconds with the spotlight following the caster, then fade back.
static func release(game: Node, handle: Dictionary, hold: float) -> void:
	var spot: SpotLight3D = handle["spot"]
	var rim: OmniLight3D = handle["rim"]
	var h: Actor = handle["hero"]
	var t := 0.0
	var tree: SceneTree = game.get_tree()
	while t < hold:
		await tree.process_frame
		var dt := tree.root.get_process_delta_time()
		if tree.paused:
			continue
		t += dt
		if is_instance_valid(h) and is_instance_valid(spot):
			spot.global_position = spot.global_position.lerp(h.global_position + Vector3(0.6, 7.5, 1.2), 0.2)
			spot.look_at(h.global_position, Vector3.UP)
			rim.global_position = h.global_position + Vector3(-0.6, 1.0, -0.8)
	if is_instance_valid(spot):
		var ft := stage.create_tween().set_parallel(true)
		ft.tween_property(spot, "light_energy", 0.0, 0.35)
		ft.tween_property(rim, "light_energy", 0.0, 0.35)
		var ws: WeakRef = weakref(spot)
		var wrim: WeakRef = weakref(rim)
		ft.chain().tween_callback(func():
			for w in [ws, wrim]:
				var n: Node = w.get_ref()
				if n:
					n.queue_free())
	_dim_users = maxi(0, _dim_users - 1)
	if _dim_users == 0:
		_tween_dim(game, 0.0, 0.45)

## Hard reset (wave end / game over).
static func reset(game: Node) -> void:
	_dim_users = 0
	game.fx_root.visible = true
	Vfx.root = game.fx_root
	active = false
	if stage and is_instance_valid(stage):
		for c in stage.get_children():
			if c is Light3D:
				c.queue_free()
		_tween_dim(game, 0.0, 0.3)
	game.cam.focus(Vector3.ZERO, false)
	game.hud.cinema_bars(false, "", "", Color.WHITE)
