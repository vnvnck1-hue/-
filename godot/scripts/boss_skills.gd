class_name BossSkills
extends RefCounted
## Mid-boss signature skills, layered on the giant-golem numbers (same hp / atk / range):
##   mammoth (철갑 전쟁 맘모스) — 대지 진동: rears up while a red ring grows on the ground, then stamps down.
##            Every hero inside the ring takes a hit and is thrown back.
##   abyss (심연의 군주) — 심연 낙인: raises its claws and brands the ground under up to two heroes;
##            a beat later each brand erupts. Heroes who walk out of the circle are safe.

const STOMP_CD := 6.5
const STOMP_R := 2.3
const STOMP_WIND := 0.8
const BRAND_CD := 7.0
const BRAND_R := 1.0
const BRAND_DELAY := 1.2
const FIRST_CAST := 2.5      # seconds into the fight before the first cast

## Called every AI tick before movement. Returns true while the boss is busy with its skill.
static func tick(game: Node, a: Actor) -> bool:
	if not a.has_meta("boss_armed"):
		a.set_meta("boss_armed", true)
		a.special_t = game.now - maxf(STOMP_CD, BRAND_CD) + FIRST_CAST
	match a.kind:
		"mammoth":
			if game.now - a.special_t >= STOMP_CD and a.reach_to(a.target) < STOMP_R:
				a.special_t = game.now
				_stomp(game, a)
				return true
		"abyss":
			if game.now - a.special_t >= BRAND_CD:
				a.special_t = game.now
				_brand(game, a)
				return true
	return false

static func _stomp(game: Node, a: Actor) -> void:
	var m := a.model
	var at := Actor._flat(a.global_position)
	a.busy = true
	_warn(at, STOMP_R, Color(1.0, 0.32, 0.22), STOMP_WIND)
	game.hud.callout(a.global_position + Vector3(0, 3.4, 0), "대지 진동!", Color("ffb36b"))
	Sfx.play("whoosh", -4.0, 0.45)
	var tw := m.create_tween()
	tw.tween_property(m, "attack_lean", -0.6, STOMP_WIND * 0.85).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	m.punch_scale(0.88, 1.18, STOMP_WIND)
	game._shot_later(STOMP_WIND * 0.7, "boss_stomp_warn")
	await a.get_tree().create_timer(STOMP_WIND, false).timeout
	if not is_instance_valid(a):
		return
	var tw2 := m.create_tween()
	tw2.tween_property(m, "attack_lean", 0.4, 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw2.tween_property(m, "attack_lean", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not a.alive or not game.in_battle():
		a.busy = false
		return
	await a.get_tree().create_timer(0.07, false).timeout
	if not is_instance_valid(a):
		return
	Vfx.slam(at, STOMP_R / 1.2)
	Vfx.debris(at, 14, Color("7a5236"))
	if Vfx.cam:
		Vfx.cam.add_trauma(0.55)
	Sfx.play("boom", -2.0, 0.55)
	m.punch_scale(1.3, 0.72, 0.45)
	game._shot_later(0.06, "boss_stomp_hit")
	for h in game.alive_heroes():
		var d := Actor._flat(h.global_position - at)
		if d.length() <= STOMP_R + h.body_r:
			Combat.enemy_hit(game, a, h)
			if h.alive and d.length() > 0.01:
				h.knock += d.normalized() * 6.5
	await a.get_tree().create_timer(0.35, false).timeout
	if is_instance_valid(a):
		a.busy = false

static func _brand(game: Node, a: Actor) -> void:
	var targets: Array = game.alive_heroes()
	if targets.is_empty():
		return
	targets.shuffle()
	var m := a.model
	a.busy = true
	m._arm_busy = true
	game.hud.callout(a.global_position + Vector3(0, 3.8, 0), "심연 낙인!", Color("e08aff"))
	Sfx.play("whoosh", -6.0, 0.6)
	var up := m.create_tween().set_parallel(true)
	up.tween_property(m.arm_l, "rotation", Vector3(-2.7, 0, -0.5), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	up.tween_property(m.arm_r, "rotation", Vector3(-2.7, 0, 0.5), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	m.punch_scale(0.9, 1.15, 0.4)
	Vfx.sparks(a.global_position + Vector3(0, 2.4, 0), Color("ff4fd8"), 16, 4.0, 0.6, "star", 0.2, 2.0)
	var spots: Array = []
	for h in targets.slice(0, 2):
		var p := Actor._flat(h.global_position)
		spots.append(p)
		_warn(p, BRAND_R, Color(0.8, 0.3, 1.0), BRAND_DELAY)
	game._shot_later(0.5, "boss_brand_warn")
	await a.get_tree().create_timer(0.55, false).timeout
	if not is_instance_valid(a):
		return
	var down := m.create_tween().set_parallel(true)
	down.tween_property(m.arm_l, "rotation", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	down.tween_property(m.arm_r, "rotation", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	down.chain().tween_callback(func(): m._arm_busy = false)
	a.busy = false
	await a.get_tree().create_timer(BRAND_DELAY - 0.55, false).timeout
	if not is_instance_valid(a) or not a.alive or not game.in_battle():
		return
	Sfx.play("boom", -3.0, 0.8)
	game._shot_later(0.06, "boss_brand_hit")
	for p in spots:
		Vfx.explosion(p, Color("c86bff"), 0.85)
		Vfx.sparks(p + Vector3(0, 0.3, 0), Color("ff4fd8"), 14, 5.0, 0.6, "star", 0.18, -6.0)
		for h in game.alive_heroes():
			if Actor._flat(h.global_position - p).length() <= BRAND_R + h.body_r:
				Combat.enemy_hit(game, a, h)

## Telegraph: a pulsing outline at full size plus a fill that grows to it right as the hit lands.
static func _warn(pos: Vector3, r: float, col: Color, dur: float) -> void:
	var make := func(shape: String, c: Color, additive: bool) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var q := PlaneMesh.new()
		q.size = Vector2(1, 1)
		mi.mesh = q
		mi.material_override = Mats.ground(shape, c, additive)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		Vfx._add(mi, pos + Vector3(0, 0.035, 0))
		return mi
	var ring: MeshInstance3D = make.call("ring", Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.95), true)
	ring.scale = Vector3.ONE * r * 2.0
	var rm := ring.material_override as StandardMaterial3D
	var tw := ring.create_tween()
	tw.set_loops(int(ceilf(dur / 0.24)))
	tw.tween_property(rm, "albedo_color:a", 0.35, 0.12)
	tw.tween_property(rm, "albedo_color:a", 0.95, 0.12)
	var fill: MeshInstance3D = make.call("blob", Color(col.r, col.g, col.b, 0.42), false)
	fill.scale = Vector3.ONE * 0.1
	var tf := fill.create_tween()
	tf.tween_property(fill, "scale", Vector3.ONE * r * 2.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Vfx._free_later(ring, dur + 0.02)
	Vfx._free_later(fill, dur + 0.02)
