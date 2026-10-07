class_name Skills
extends RefCounted
## Active skills (auto-cast at full mana, spec §3.7) and ultimates (hold a hero 0.3s -> aim with the
## battle paused -> release to cast, spec §3.8). Aim previews live under a node that keeps processing.

const HOLD_TIME := 0.3
const CONE_MIN := 0.15

static var hold_hero: Actor
static var hold_start := 0.0
static var aiming := false
static var aim_point := Vector3.ZERO
static var aim_root: Node3D
static var _preview: Node3D
static var _markers: Array = []

static func base_damage(game: Node, h: Actor, mult: float) -> float:
	return maxf(1.0, floorf(Stats.attack_power(game, h) * mult))

# ================================================================ active skills
static func cast_active(game: Node, h: Actor) -> void:
	if game.alive_enemies().is_empty():
		return
	h.mana = 0.0
	var def: Dictionary = Defs.ACTIVE_SKILLS[h.cls]
	game.hud.callout(h.global_position + Vector3(0, 1.5, 0), def["name"] + "!", Color("9fe8ff"))
	h.model.flash(Color(0.6, 0.9, 1.0), 1.8, 0.35)
	# brief hit-stop + zoom kick so the skill cast reads clearly
	h.model.punch_scale(1.35, 0.7, 0.35)
	Vfx.pop_sprite(h.global_position + Vector3(0, 0.6, 0), "star", Color(1.0, 1.6, 2.0), 1.6, 0.22, 0.6)
	Vfx.ground_ring(h.global_position, Color(0.6, 1.2, 1.8, 0.9), 0.3, 2.2, 0.3)
	Vfx.cam.hitstop(0.13)
	Vfx.cam.kick_fov(-3.0)
	Vfx.cam.add_trauma(0.12)
	Sfx.play("chime", -8.0, 1.8)
	match h.cls:
		"warrior": _jump_slam(game, h, def)
		"ranger": _multi_shot(game, h, def)
		"mage": _absolute_zero(game, h, def)

## Leap to the farthest enemy, crash down: big hit on the target, splash around, stun everything hit.
static func _jump_slam(game: Node, h: Actor, def: Dictionary) -> void:
	var target: Actor = null
	var far := -1.0
	for e in game.alive_enemies():
		var d: float = Actor._flat(e.global_position - h.global_position).length()
		if d > far:
			far = d
			target = e
	if target == null:
		return
	h.busy = true
	h.guard_until = game.now + def["guard"] / 1000.0
	var dir := Actor._flat(target.global_position - h.global_position)
	var land := target.global_position - dir.normalized() * (target.body_r + 0.35)
	land.x = clampf(land.x, -Actor.BOARD_X, Actor.BOARD_X)
	land.z = clampf(land.z, -Actor.BOARD_Z, Actor.BOARD_Z)
	var target_spot := target.global_position
	h.model.punch_scale(0.75, 1.3, 0.25)
	Sfx.play("whoosh", -4.0, 0.7)
	var tw := h.hop_to(land, 0.3, 1.8, false)
	await tw.finished
	if not is_instance_valid(h):
		return
	h.position.y = 0.0
	h.busy = false
	if not h.alive or not game.in_battle():
		return
	h.model.punch_scale(1.55, 0.5, 0.6)
	Vfx.slam(h.global_position, 1.4)
	Sfx.play("boom", -2.0, 0.85)
	var ap := Stats.attack_power(game, h)
	var base := base_damage(game, h, def["mult"])
	for e in game.alive_enemies():
		var extra := 0.0
		var on_target: bool = e == target or Actor._flat(e.global_position - target_spot).length() < 0.4
		var near: bool = Actor._flat(e.global_position - h.global_position).length() <= 1.4 + e.body_r - Actor.RADIUS
		if on_target:
			extra += floorf(e.max_hp * def["impact_hp"]) + floorf(ap * def["impact_atk"])
			if not e.knockback_immune:
				e.knock += Actor._flat(e.global_position - h.global_position).normalized() * 6.0
		if near:
			extra += base
		if extra > 0.0:
			e.stun_until = maxf(e.stun_until, game.now + def["stun"] / 1000.0)
			Combat.skill_damage(game, h, e, extra)

## Hop back from danger, then fire three strong arrows at the closest enemies.
static func _multi_shot(game: Node, h: Actor, def: Dictionary) -> void:
	var origin := h.global_position
	var targets: Array = game.alive_enemies()
	targets.sort_custom(func(a, b): return a.global_position.distance_to(origin) < b.global_position.distance_to(origin))
	var spot := _retreat_spot(game, h)
	h.busy = true
	if spot.distance_to(h.position) > 0.1:
		await h.hop_to(spot, 0.22, 0.6).finished
		if not is_instance_valid(h):
			return
	h.busy = false
	var dmg := base_damage(game, h, def["mult"])
	for i in mini(int(def["count"]), targets.size()):
		var t: Actor = targets[i]
		game.after(i * 0.1, func():
			if not h.alive or not game.in_battle() or not is_instance_valid(t) or not t.alive:
				return
			h.model.play_attack("arrow")
			Sfx.play("whoosh", -8.0, 1.5)
			var on_hit := func(_p: Vector3) -> void:
				if is_instance_valid(t) and t.alive:
					Vfx.hit_spark(t.global_position + Vector3(0, 0.4, 0), Color("ff8ad8"), true)
					Combat.skill_damage(game, h, t, dmg)
			Vfx.projectile("arrow", h.global_position + Vector3(0, 0.5, 0), t, on_hit, 0.0, 0.15))

static func _retreat_spot(game: Node, h: Actor) -> Vector3:
	var p := h.position
	var cands := [p + Vector3(0, 0, 1), p + Vector3(-1, 0, 0), p + Vector3(1, 0, 0)]
	var best := p
	var best_score := -INF
	for i in cands.size():
		var c: Vector3 = cands[i]
		if absf(c.x) > Actor.BOARD_X or absf(c.z) > Actor.BOARD_Z:
			continue
		var blocked := false
		for u in game.all_alive():
			if u != h and Actor._flat(u.global_position - c).length() < 0.55:
				blocked = true
		if blocked:
			continue
		if i == 0:
			return c
		var e: Actor = game.nearest_enemy(c)
		var score: float = Actor._flat(e.global_position - c).length() if e else 0.0
		if score > best_score:
			best_score = score
			best = c
	return best

## Cold wave across the whole board: damage + freeze everything.
static func _absolute_zero(game: Node, h: Actor, def: Dictionary) -> void:
	h.model.play_attack("fireball")
	Vfx.frost_wave(Vector3(0, 0, 1.5), 4.5)
	Sfx.play("whoosh", -3.0, 0.5)
	var dmg := base_damage(game, h, def["mult"])
	game.after(0.3, func():
		if not h.alive or not game.in_battle():
			return
		Sfx.play("boom", -6.0, 1.6)
		var until: float = game.now + def["freeze"] / 1000.0
		for e in game.alive_enemies():
			Vfx.frost_hit(e.global_position)
			if not Combat.is_immune(game, e):
				e.stun_until = maxf(e.stun_until, until)
				e.slow_until = maxf(e.slow_until, until)
				e.frozen_until = maxf(e.frozen_until, until)
			Combat.skill_damage(game, h, e, dmg))

# ================================================================ ultimates: input
static func begin_hold(game: Node, h: Actor) -> void:
	if aiming or Cinematic.active or h == null or not h.alive or h.busy:
		return
	if h.ult_ready_at > game.now:
		game.hud.float_text(h.global_position + Vector3(0, 1.3, 0), "%.1f초" % (h.ult_ready_at - game.now), Color("dfe6ee"))
		return
	if not game.tutorial_allows("ult", h):
		return
	hold_hero = h
	hold_start = game._clock
	h.model.punch_scale(0.9, 1.1, 0.25)

## Called every frame during battle; enters aim mode once the hold passes HOLD_TIME.
static func update_hold(game: Node) -> void:
	if hold_hero == null or aiming:
		return
	if not is_instance_valid(hold_hero) or not hold_hero.alive or not game.in_battle():
		hold_hero = null
		return
	if game._clock - hold_start >= HOLD_TIME:
		_enter_aim(game)

static func aim_motion(game: Node, sp: Vector2) -> void:
	if not aiming:
		return
	var p: Vector3 = game._ray_plane(sp, 0.0)
	if p != Vector3.INF:
		aim_point = p
		_update_preview(game)

static func end_hold(game: Node, sp: Vector2) -> void:
	if aiming:
		aim_motion(game, sp)
		var h := hold_hero
		_exit_aim(game)
		if is_instance_valid(h) and h.alive and game.in_battle():
			cast_ultimate(game, h, aim_point)
	hold_hero = null

static func cancel(game: Node) -> void:
	if aiming:
		_exit_aim(game)
	hold_hero = null

static func _enter_aim(game: Node) -> void:
	aiming = true
	game.get_tree().paused = true
	if aim_root == null or not is_instance_valid(aim_root):
		aim_root = Node3D.new()
		aim_root.process_mode = Node.PROCESS_MODE_ALWAYS
		game.add_child(aim_root)
	_preview = Node3D.new()
	aim_root.add_child(_preview)
	var e: Actor = game.nearest_enemy(hold_hero.global_position)
	aim_point = e.global_position if e else hold_hero.global_position + Vector3(0, 0, -2)
	game.hud.show_aim(Defs.ULTIMATES[hold_hero.cls]["name"])
	Sfx.play("whoosh", -6.0, 0.6)
	_update_preview(game)

static func _exit_aim(game: Node) -> void:
	aiming = false
	game.get_tree().paused = false
	if _preview and is_instance_valid(_preview):
		_preview.queue_free()
	_preview = null
	_markers.clear()
	game.hud.hide_aim()

# ================================================================ ultimates: preview
static func _update_preview(game: Node) -> void:
	if _preview == null:
		return
	for c in _preview.get_children():
		c.queue_free()
	var h := hold_hero
	var hit: Array = []
	match h.cls:
		"warrior":
			var ring := MeshInstance3D.new()
			var q := PlaneMesh.new()
			q.size = Vector2(1, 1)
			ring.mesh = q
			ring.material_override = Mats.ground("ring", Color(1.3, 1.0, 0.45, 0.6), true)
			ring.scale = Vector3.ONE * 3.2
			_preview.add_child(ring)
			ring.global_position = h.global_position + Vector3(0, 0.05, 0)
			hit = game.alive_enemies()
		"ranger":
			var u: Dictionary = Defs.ULTIMATES["ranger"]
			var cone := Vfx.cone_mesh(u["length"], u["angle"] * 0.5, Color(1.4, 1.2, 0.4, 0.35))
			_preview.add_child(cone)
			cone.global_position = h.global_position + Vector3(0, 0.04, 0)
			cone.rotation.y = _aim_yaw(h.global_position, aim_point)
			hit = cone_targets(game, h.global_position, aim_point)
		"mage":
			var path := chain_path(game, h)
			var prev := h.global_position + Vector3(0, 0.6, 0)
			for e in path:
				var p: Vector3 = e.global_position + Vector3(0, 0.5, 0)
				_preview.add_child(_beam(prev, p))
				prev = p
			hit = path
	for e in hit:
		var m := MeshInstance3D.new()
		var tq := TorusMesh.new()
		tq.inner_radius = 0.34
		tq.outer_radius = 0.44
		m.mesh = tq
		m.material_override = Mats.glow(Color("ff4a5a"), 1.6)
		m.scale = Vector3(1, 0.3, 1) * (e.body_r / Actor.RADIUS)
		_preview.add_child(m)
		m.global_position = e.global_position + Vector3(0, 0.06, 0)
	game.hud.set_aim_count(hit.size())

static func _beam(a: Vector3, b: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bx := BoxMesh.new()
	bx.size = Vector3(0.07, 0.07, a.distance_to(b))
	mi.mesh = bx
	mi.material_override = Mats.glow(Color(0.6, 0.9, 1.6), 1.4)
	mi.position = (a + b) * 0.5
	if a.distance_to(b) > 0.01:
		mi.look_at_from_position((a + b) * 0.5, b, Vector3.UP)
	return mi

static func _aim_yaw(from: Vector3, to: Vector3) -> float:
	var d := Actor._flat(to - from)
	return atan2(-d.x, -d.z)

## Enemies inside the ranger's cone (angle measured from the hero toward the aim point).
static func cone_targets(game: Node, origin: Vector3, aim: Vector3) -> Array:
	var u: Dictionary = Defs.ULTIMATES["ranger"]
	var dir := Actor._flat(aim - origin)
	if dir.length() < 0.01:
		dir = Vector3(0, 0, -1)
	var a0 := atan2(dir.x, dir.z)
	var out := []
	for e in game.alive_enemies():
		var v := Actor._flat(e.global_position - origin)
		var d := v.length()
		if d <= CONE_MIN or d > u["length"] + e.body_r - Actor.RADIUS:
			continue
		if absf(angle_difference(a0, atan2(v.x, v.z))) <= u["angle"] * 0.5:
			out.append(e)
	return out

## Chain lightning path: from the mage to the nearest unvisited enemy, repeatedly.
static func chain_path(game: Node, h: Actor) -> Array:
	var n: int = Defs.ULTIMATES["mage"]["bounces"] + int(Stats.g(Stats.talent_fx(h), "mageUltBounces"))
	var out := []
	var from := h.global_position
	var left: Array = game.alive_enemies()
	for i in n:
		var best: Actor = null
		var bd := INF
		for e in left:
			var d: float = Actor._flat(e.global_position - from).length()
			if d < bd:
				bd = d
				best = e
		if best == null:
			break
		out.append(best)
		left.erase(best)
		from = best.global_position
	return out

# ================================================================ ultimates: cast
const ULT_COL := {"warrior": Color("ffb070"), "ranger": Color("9fe86a"), "mage": Color("8fc8ff")}

static func cast_ultimate(game: Node, h: Actor, aim: Vector3) -> void:
	if Cinematic.active:
		return
	var u: Dictionary = Defs.ULTIMATES[h.cls]
	h.ult_ready_at = game.now + Stats.ult_cooldown(game, h)
	game.on_ult_used(h)
	# cinematic intro: freeze, dim the stage, spotlight + close-up on the caster
	var handle: Dictionary = await Cinematic.intro(game, h, u["name"], ULT_COL[h.cls])
	if not is_instance_valid(h) or not h.alive or not game.in_battle():
		Cinematic.release(game, handle, 0.0)
		return
	var ap := Stats.attack_power(game, h)
	var ult_dmg := maxf(1.0, floorf(ap * u.get("mult", 1.0) * (1.0 + Stats.g(Stats.talent_fx(h), "ultDamageBonus"))))
	game.hud.flash(0.12, 0.2)
	h.model.flash(Color(1, 0.9, 0.5), 2.0, 0.4)
	var hold := 1.1
	match u["type"]:
		"chain":
			hold = 0.1 * chain_path(game, h).size() + 0.8
		"cone":
			hold = u["channel"] / 1000.0 + 0.3
	Cinematic.release(game, handle, hold)
	match u["type"]:
		"shockwave":
			h.model.punch_scale(1.5, 0.55, 0.5)
			Vfx.slam(h.global_position, 2.2)
			Vfx.ground_ring(h.global_position, Color(1.6, 1.3, 0.6, 1.0), 0.5, 12.0, 0.55)
			Sfx.play("boom", -1.0, 0.7)
			for e in game.alive_enemies():
				if not Combat.is_immune(game, e):
					e.stun_until = maxf(e.stun_until, game.now + u["stun"] / 1000.0)
					if not e.knockback_immune:
						e.knock += Actor._flat(e.global_position - h.global_position).normalized() * 6.0
				Combat.skill_damage(game, h, e, ult_dmg)
		"chain":
			var path := chain_path(game, h)
			var prev := h.global_position + Vector3(0, 0.7, 0)
			h.model.play_attack("fireball")
			for i in path.size():
				var e: Actor = path[i]
				var from := prev
				prev = e.global_position + Vector3(0, 0.5, 0)
				game.after(i * 0.1, func():
					if not is_instance_valid(e):
						return
					Vfx.lightning(from, e.global_position + Vector3(0, 0.5, 0), 0.11)
					Sfx.play("thud", -6.0, 1.8)
					Vfx.cam.add_trauma(0.12)
					game.after(0.05, func(): Combat.skill_damage(game, h, e, ult_dmg)))
			if Meta.has_flag("magFinal") and randf() < 0.1:
				Meta.add_crystals(1)
				game.hud.set_crystals(Meta.crystals)
				game.hud.float_text(h.global_position + Vector3(0, 1.4, 0), "+1 결정", Defs.COL_CRYSTAL)
		"cone":
			_cone_barrage(game, h, aim, u, maxf(1.0, floorf(ap * u["tick_mult"])))

static func _cone_barrage(game: Node, h: Actor, aim: Vector3, u: Dictionary, tick_dmg: float) -> void:
	h.busy = true
	var origin := h.global_position
	var yaw := _aim_yaw(origin, aim)
	h.model.rotation.y = yaw
	var cone := Vfx.cone_mesh(u["length"], u["angle"] * 0.5, Color(1.6, 1.2, 0.4, 0.3))
	Vfx.root.add_child(cone)
	cone.global_position = origin + Vector3(0, 0.04, 0)
	cone.rotation.y = yaw
	var ticks := int(u["channel"] / u["tick"])
	for i in ticks:
		await h.get_tree().create_timer(u["tick"] / 1000.0, false).timeout
		if not is_instance_valid(h) or not h.alive or not game.in_battle():
			break
		h.model.play_attack("arrow")
		Sfx.play("whoosh", -10.0, 1.6)
		for e in cone_targets(game, origin, aim):
			Vfx.arrow_rain(e.global_position)
			Combat.skill_damage(game, h, e, tick_dmg)
	if is_instance_valid(cone):
		var tw := cone.create_tween()
		tw.tween_property(cone.material_override, "albedo_color:a", 0.0, 0.25)
		tw.tween_callback(cone.queue_free)
	if is_instance_valid(h):
		h.busy = false
