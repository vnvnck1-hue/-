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
	if not _present(game, a):
		return
	var tw2 := m.create_tween()
	tw2.tween_property(m, "attack_lean", 0.4, 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw2.tween_property(m, "attack_lean", 0.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not a.alive or not game.in_battle():
		a.busy = false
		return
	await a.get_tree().create_timer(0.07, false).timeout
	if not _present(game, a):
		return
	Vfx.slam(at, STOMP_R / 1.2)
	Vfx.debris(at, 14, Color("7a5236"))
	Vfx._shake(0.55)
	Sfx.play("boom", -2.0, 0.55)
	m.punch_scale(1.3, 0.72, 0.45)
	game._shot_later(0.06, "boss_stomp_hit")
	for h in game.alive_heroes():
		var d := Actor._flat(h.global_position - at)
		if d.length() <= STOMP_R + h.body_r:
			Combat.enemy_hit(game, a, h)
			if h.alive and d.length() > 0.01:
				h.knock += d.normalized() * 6.5
	if not a.is_inside_tree():
		return
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
	if not _present(game, a):
		return
	var down := m.create_tween().set_parallel(true)
	down.tween_property(m.arm_l, "rotation", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	down.tween_property(m.arm_r, "rotation", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	down.chain().tween_callback(func(): m._arm_busy = false)
	a.busy = false
	await a.get_tree().create_timer(BRAND_DELAY - 0.55, false).timeout
	if not _present(game, a) or not a.alive or not game.in_battle():
		return
	Sfx.play("boom", -3.0, 0.8)
	game._shot_later(0.06, "boss_brand_hit")
	for p in spots:
		Vfx.explosion(p, Color("c86bff"), 0.85)
		Vfx.sparks(p + Vector3(0, 0.3, 0), Color("ff4fd8"), 14, 5.0, 0.6, "star", 0.18, -6.0)
		for h in game.alive_heroes():
			if Actor._flat(h.global_position - p).length() <= BRAND_R + h.body_r:
				Combat.enemy_hit(game, a, h)

## Boss and field still exist after an await (these static coroutines outlive a freed boss / left scene).
static func _present(game: Node, a: Actor) -> bool:
	return is_instance_valid(game) and is_instance_valid(a) and a.is_inside_tree()

## Telegraph: a pulsing outline at full size plus a fill that grows to it right as the hit lands.
static func _warn(pos: Vector3, r: float, col: Color, dur: float) -> void:
	var make := func(shape: String, c: Color, additive: bool) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = Vfx._unit_plane()
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

# ---------------------------------------------------------------- region bosses (boss raid line-up)
## spider (독니 거미 여왕) — 도약 습격: a green circle marks the farthest hero, the queen leaps onto it, slams and leaves
##            a web that binds whoever stands in it; 거미줄 발사: webs up to two heroes (bound for a moment).
## warden (화염 집행자) — 용암 내려찍기: raises the hammer while a lane of circles lines up toward a hero, then the lane
##            erupts from the boss outward and keeps burning for a while.
## flytrap (세머리 파리지옥) — rooted; 가시 씨앗: lobs a spiked seed at up to three heroes; each bursts into a poison cloud.
## murlocs — 대사제 해일 (a wave under every hero + heals the trio), 조련사 갈고리 (hooks the farthest hero and reels
##            them in), 작살병 돌진 (charges down a marked lane).
const LEAP_CD := 7.5
const LEAP_R := 1.3
const LEAP_WIND := 1.0
const WEB_CD := 5.5
const WEB_BIND := 1.3
const LAVA_CD := 7.0
const LAVA_N := 6
const LAVA_R := 0.75
const LAVA_WIND := 1.0
const SEED_CD := 6.5
const SEED_R := 1.0
const SEED_FLIGHT := 1.1
const TIDE_CD := 9.0
const TIDE_R := 0.95
const TIDE_DELAY := 1.3
const TIDE_HEAL := 0.06
const HOOK_CD := 6.5
const HOOK_MIN := 2.2       # only hooks a hero standing at least this far (edge to edge)
const CHARGE_CD := 7.0
const CHARGE_WIND := 0.8

static func _armed(game: Node, a: Actor, first: float) -> void:
	if not a.has_meta("boss_armed2"):
		a.set_meta("boss_armed2", true)
		a.special_t = game.now - 100.0 + first
		a.set_meta("sk2_t", game.now - 100.0 + first + 2.5)

static func _ready2(game: Node, a: Actor, cd: float) -> bool:
	return game.now - float(a.get_meta("sk2_t", -99.0)) >= cd

## Region-boss skills; returns true while busy (Specials.move calls this before the boss walks).
static func tick2(game: Node, a: Actor) -> bool:
	match a.kind:
		"spider":
			_armed(game, a, FIRST_CAST)
			if game.now - a.special_t >= LEAP_CD:
				a.special_t = game.now
				_leap(game, a)
				return true
			if _ready2(game, a, WEB_CD):
				a.set_meta("sk2_t", game.now)
				_webs(game, a)
				return true
		"warden":
			_armed(game, a, FIRST_CAST)
			if game.now - a.special_t >= LAVA_CD:
				a.special_t = game.now
				_lava(game, a)
				return true
		"flytrap":
			_armed(game, a, FIRST_CAST - 0.5)
			if game.now - a.special_t >= SEED_CD:
				a.special_t = game.now
				_seeds(game, a)
				return true
		"murPriest":
			_armed(game, a, FIRST_CAST + 1.0)
			if game.now - a.special_t >= TIDE_CD:
				a.special_t = game.now
				_tide(game, a)
				return true
		"murWhip":
			_armed(game, a, FIRST_CAST + 2.0)
			if game.now - a.special_t >= HOOK_CD:
				var far := _farthest(game, a)
				if far and a.reach_to(far) >= HOOK_MIN:
					a.special_t = game.now
					_hook(game, a, far)
					return true
		"murSpear":
			_armed(game, a, FIRST_CAST + 3.0)
			if game.now - a.special_t >= CHARGE_CD and a.target and a.target.alive:
				a.special_t = game.now
				_charge(game, a, a.target)
				return true
	return false

static func _farthest(game: Node, a: Actor) -> Actor:
	var best: Actor = null
	var bd := -1.0
	for h in game.alive_heroes():
		var d := Actor._flat(h.global_position - a.global_position).length()
		if d > bd:
			bd = d
			best = h
	return best

static func _wait(a: Node, t: float) -> Signal:
	return a.get_tree().create_timer(t, false).timeout

## Lingering ground hazard: every 0.5 s each hero inside takes `mult` of the boss's hit (bind > 0: also held
## in place that long). It outlives the boss (the zone keeps burning even if its caster falls).
static func _hazard(game: Node, a: Actor, pos: Vector3, r: float, dur: float, col: Color, mult: float, bind := 0.0) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = Vfx._unit_plane()
	mi.material_override = Mats.ground("blob", Color(col.r, col.g, col.b, 0.5), false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	Vfx._add(mi, pos + Vector3(0, 0.03, 0))
	mi.scale = Vector3.ONE * 0.1
	var tw := mi.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE * r * 2.0, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(0.0, dur - 0.5))
	tw.tween_property(mi, "scale", Vector3.ONE * 0.05, 0.3)
	Vfx._free_later(mi, dur + 0.05)
	var t := 0.0
	var hit := {}
	while t < dur:
		await game.get_tree().create_timer(0.5, false).timeout
		t += 0.5
		if not is_instance_valid(game) or not game.in_battle():
			return
		Vfx.puff(pos + Vector3(randf_range(-r, r) * 0.6, 0.15, randf_range(-r, r) * 0.6), Color(col.r, col.g, col.b, 0.8), r * 0.5, Vector3(0, 0.5, 0), 0.6)
		for h in game.alive_heroes():
			if Actor._flat(h.global_position - pos).length() <= r + h.body_r * 0.5:
				if is_instance_valid(a):
					Combat.enemy_hit(game, a, h, {"mult": mult, "ranged": true})
				if bind > 0.0 and not hit.has(h):
					hit[h] = true
					h.stun_until = maxf(h.stun_until, game.now + bind)
					game.hud.float_text(h.global_position + Vector3(0, 1.2, 0), "거미줄!", Color("e8f0ff"))

## Hits every hero within r of p (edge to edge) for mult x the boss's hit. Returns the heroes hit.
static func _blast(game: Node, a: Actor, p: Vector3, r: float, mult: float) -> Array:
	var out := []
	for h in game.alive_heroes():
		if Actor._flat(h.global_position - p).length() <= r + h.body_r:
			Combat.enemy_hit(game, a, h, {"mult": mult})
			out.append(h)
	return out

# --- spider
static func _leap(game: Node, a: Actor) -> void:
	var t := _farthest(game, a)
	if t == null:
		return
	var spot := Actor._flat(t.global_position)
	var m := a.model
	a.busy = true
	_warn(spot, LEAP_R, Color(0.6, 1.0, 0.2), LEAP_WIND)
	game.hud.callout(a.global_position + Vector3(0, 2.6, 0), "도약 습격!", Color("c8ff6a"))
	Sfx.play("whoosh", -6.0, 0.7)
	m.punch_scale(1.25, 0.72, LEAP_WIND)   # crouch, legs coiled
	game._shot_later(LEAP_WIND * 0.6, "boss_spider_leap_warn")
	await _wait(a, LEAP_WIND * 0.75)
	if not _present(game, a) or not a.alive or not game.in_battle():
		if _present(game, a):
			a.busy = false
		return
	var tw := a.hop_to(spot, 0.4, 2.2)
	await tw.finished
	if not _present(game, a):
		return
	Vfx.slam(spot, LEAP_R / 1.2)
	Vfx.debris(spot, 12, Color("6b3e26"))
	Vfx._shake(0.45)
	Sfx.play("boom", -3.0, 0.7)
	game._shot_later(0.05, "boss_spider_leap_hit")
	if a.alive and game.in_battle():
		_blast(game, a, spot, LEAP_R, 1.2)
		_hazard(game, a, spot, LEAP_R * 0.9, 3.0, Color(0.92, 0.95, 1.0), 0.0, WEB_BIND)
	await _wait(a, 0.3)
	if is_instance_valid(a):
		a.busy = false

static func _webs(game: Node, a: Actor) -> void:
	var targets: Array = game.alive_heroes()
	if targets.is_empty():
		return
	targets.shuffle()
	a.busy = true
	game.hud.callout(a.global_position + Vector3(0, 2.4, 0), "거미줄 발사!", Color("e8f0ff"))
	a.model.punch_scale(0.85, 1.2, 0.3)
	await _wait(a, 0.3)
	if not _present(game, a):
		return
	for h in targets.slice(0, 2):
		var from := a.global_position + Vector3(0, 0.9, 0) + a.fwd() * 0.6
		Vfx.projectile("web", from, h, func(_p: Vector3) -> void:
			if not is_instance_valid(game) or not game.in_battle() or not is_instance_valid(h) or not h.alive:
				return
			Vfx.pop_sprite(h.global_position + Vector3(0, 0.4, 0), "ring", Color(0.95, 0.97, 1.0), 1.1, 0.4)
			game.hud.float_text(h.global_position + Vector3(0, 1.2, 0), "거미줄!", Color("e8f0ff"))
			h.stun_until = maxf(h.stun_until, game.now + WEB_BIND)
			if is_instance_valid(a):
				Combat.enemy_hit(game, a, h, {"mult": 0.5, "ranged": true}), 8.0)
	Sfx.play("whoosh", -8.0, 1.4)
	await _wait(a, 0.25)
	if is_instance_valid(a):
		a.busy = false

# --- warden
static func _lava(game: Node, a: Actor) -> void:
	var t: Actor = a.target if a.target and a.target.alive else _farthest(game, a)
	if t == null:
		return
	var m := a.model
	var at := Actor._flat(a.global_position)
	var dir := Actor._flat(t.global_position - a.global_position)
	dir = dir.normalized() if dir.length() > 0.01 else Vector3(0, 0, 1)
	var spots: Array = []
	for i in LAVA_N:
		spots.append(Actor.field_clamp(at + dir * (a.body_r + 0.5 + i * 1.0)))
	a.busy = true
	m._arm_busy = true
	a._face(dir, 1.0, 100.0)
	game.hud.callout(a.global_position + Vector3(0, 3.6, 0), "용암 내려찍기!", Color("ffb36b"))
	Sfx.play("whoosh", -5.0, 0.5)
	m.create_tween().tween_property(m.arm_r, "rotation", Vector3(-2.9, 0, 0.2), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	m.lean_to(-0.3, LAVA_WIND * 0.8)
	for i in spots.size():
		_warn(spots[i], LAVA_R, Color(1.0, 0.45, 0.15), LAVA_WIND + i * 0.08)
	game._shot_later(LAVA_WIND * 0.6, "boss_warden_warn")
	await _wait(a, LAVA_WIND)
	if not _present(game, a):
		return
	var down := m.create_tween()
	down.tween_property(m.arm_r, "rotation", Vector3(0.9, 0, -0.2), 0.07).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	down.tween_property(m.arm_r, "rotation", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	down.tween_callback(func(): m._arm_busy = false)
	m.lean_to(0.0, 0.3)
	m.punch_scale(1.25, 0.75, 0.4)
	Vfx._shake(0.4)
	Sfx.play("boom", -3.0, 0.6)
	if not a.alive or not game.in_battle():
		a.busy = false
		return
	game._shot_later(0.25, "boss_warden_hit")
	for i in spots.size():
		var p: Vector3 = spots[i]
		game.after(i * 0.08, func():
			if not is_instance_valid(game) or not game.in_battle():
				return
			Vfx.explosion(p, Color("ff7a2a"), 0.75)
			Vfx.sparks(p + Vector3(0, 0.2, 0), Color("ffd24a"), 8, 4.0, 0.5, "star", 0.14)
			if is_instance_valid(a):
				_blast(game, a, p, LAVA_R, 1.0)
				_hazard(game, a, p, LAVA_R * 0.85, 2.5, Color(1.0, 0.4, 0.1), 0.25))
	await _wait(a, 0.35)
	if is_instance_valid(a):
		a.busy = false

# --- flytrap
static func _seeds(game: Node, a: Actor) -> void:
	var targets: Array = game.alive_heroes()
	if targets.is_empty():
		return
	targets.shuffle()
	a.busy = true
	game.hud.callout(a.global_position + Vector3(0, 3.4, 0), "가시 씨앗!", Color("c8ff6a"))
	a.model.punch_scale(0.82, 1.25, 0.5)
	Sfx.play("pop", -4.0, 0.7)
	var spots := []
	for h in targets.slice(0, 3):
		var p := Actor._flat(h.global_position)
		spots.append(p)
		_warn(p, SEED_R, Color(0.55, 1.0, 0.3), SEED_FLIGHT + 0.15)
	game._shot_later(0.7, "boss_flytrap_warn")
	await _wait(a, 0.15)
	if not _present(game, a):
		return
	for i in spots.size():
		var p: Vector3 = spots[i]
		var mark := Node3D.new()
		Vfx._add(mark, p)
		Vfx._free_later(mark, SEED_FLIGHT + 0.5)
		var from := a.global_position + Vector3((i - 1) * 0.5, 2.4, 0)
		Vfx.projectile("seed", from, mark, func(_q: Vector3) -> void:
			if not is_instance_valid(game) or not game.in_battle():
				return
			Vfx.explosion(p, Color("8fe04a"), 0.8)
			Vfx.debris(p, 6, Color("e8dcb0"))
			Sfx.play("boom", -8.0, 1.2)
			if is_instance_valid(a):
				_blast(game, a, p, SEED_R, 1.0)
				_hazard(game, a, p, SEED_R, 3.5, Color(0.55, 0.9, 0.25), 0.22), 0.0, SEED_FLIGHT)
	await _wait(a, 0.4)
	if is_instance_valid(a):
		a.busy = false

# --- murlocs
static func _tide(game: Node, a: Actor) -> void:
	var targets: Array = game.alive_heroes()
	if targets.is_empty():
		return
	a.busy = true
	game.hud.callout(a.global_position + Vector3(0, 2.2, 0), "해일 소환!", Color("8fe0ff"))
	Sfx.play("whoosh", -6.0, 0.8)
	a.model.punch_scale(0.85, 1.2, 0.4)
	Vfx.sparks(a.global_position + Vector3(0, 1.6, 0), Color("fff27a"), 14, 3.0, 0.6, "star", 0.16, 1.0)
	var spots := []
	for h in targets:
		var p := Actor._flat(h.global_position)
		spots.append(p)
		_warn(p, TIDE_R, Color(0.3, 0.7, 1.0), TIDE_DELAY)
	for e in game.alive_enemies():   # the deep's blessing mends the trio
		if e.def.get("boss_key", "") == "murlocs" and e.alive:
			e.heal(e.max_hp * TIDE_HEAL, true)
			Vfx.sparks(e.global_position + Vector3(0, 0.8, 0), Color("8fffd0"), 8, 2.0, 0.5, "star", 0.12, 2.0)
	game._shot_later(0.6, "boss_tide_warn")
	await _wait(a, 0.45)
	if is_instance_valid(a):
		a.busy = false
	await _wait(a, TIDE_DELAY - 0.45)
	if not _present(game, a) or not a.alive or not game.in_battle():
		return
	Sfx.play("boom", -6.0, 1.3)
	for p in spots:
		Vfx.explosion(p, Color("4fb8ff"), 0.8)
		Vfx.sparks(p + Vector3(0, 0.3, 0), Color("c8f0ff"), 12, 5.0, 0.6, "circle", 0.12, -8.0)
		_blast(game, a, p, TIDE_R, 1.0)

static func _hook(game: Node, a: Actor, h: Actor) -> void:
	a.busy = true
	a._face(Actor._flat(h.global_position - a.global_position), 1.0, 100.0)
	game.hud.callout(a.global_position + Vector3(0, 2.2, 0), "갈고리!", Color("ffd27a"))
	var dir := Actor._flat(h.global_position - a.global_position).normalized()
	var n := int(clampf(a.reach_to(h) / 0.9, 2.0, 7.0))
	for i in n:
		_warn(Actor._flat(a.global_position) + dir * (0.6 + i * 0.9), 0.35, Color(1.0, 0.85, 0.4), 0.55)
	a.model.play_attack("melee")
	Sfx.play("whoosh", -6.0, 1.3)
	await _wait(a, 0.55)
	if not _present(game, a) or not a.alive or not game.in_battle() or not is_instance_valid(h) or not h.alive:
		if _present(game, a):
			a.busy = false
		return
	var from := a.global_position + Vector3(0, 0.6, 0)
	Vfx.projectile("hook", from, h, func(_p: Vector3) -> void:
		if not is_instance_valid(game) or not game.in_battle() or not is_instance_valid(h) or not h.alive or not is_instance_valid(a):
			return
		game.hud.float_text(h.global_position + Vector3(0, 1.2, 0), "끌려간다!", Color("ffd27a"))
		Combat.enemy_hit(game, a, h, {"mult": 0.8, "ranged": true})
		if h.alive:
			var to := Actor._flat(a.global_position) + Actor._flat(h.global_position - a.global_position).normalized() * (a.body_r + h.body_r + 0.25)
			h.hop_to(Actor.field_clamp(to), 0.35, 0.7)
			h.stun_until = maxf(h.stun_until, game.now + 0.7)
			Sfx.play("thud", -6.0, 0.9), 14.0)
	await _wait(a, 0.5)
	if is_instance_valid(a):
		a.busy = false

static func _charge(game: Node, a: Actor, t: Actor) -> void:
	var start := Actor._flat(a.global_position)
	var dir := Actor._flat(t.global_position - a.global_position)
	if dir.length() < 0.01:
		return
	var length := clampf(dir.length() + 1.2, 2.5, 6.0)
	dir = dir.normalized()
	var end := Actor.field_clamp(start + dir * length, a.body_r - Actor.RADIUS)
	a.busy = true
	a._face(dir, 1.0, 100.0)
	game.hud.callout(a.global_position + Vector3(0, 2.0, 0), "작살 돌진!", Color("ff9a6a"))
	var n := int(ceilf(start.distance_to(end) / 0.8))
	for i in n:
		_warn(start.lerp(end, (i + 1.0) / n), 0.55, Color(1.0, 0.35, 0.3), CHARGE_WIND)
	a.model.lean_to(-0.4, CHARGE_WIND * 0.8)
	a.model.punch_scale(1.2, 0.8, CHARGE_WIND)
	await _wait(a, CHARGE_WIND)
	if not _present(game, a) or not a.alive or not game.in_battle():
		if _present(game, a):
			a.busy = false
		return
	a.model.lean_to(0.5, 0.08)
	Sfx.play("whoosh", -3.0, 0.9)
	var hit := {}
	var dur := 0.32
	var k := 0.0
	while k < 1.0:
		await a.get_tree().process_frame
		if not _present(game, a):
			return
		k = minf(1.0, k + a.get_process_delta_time() / dur)
		a.position = start.lerp(end, k)
		Vfx.puff(a.global_position + Vector3(0, 0.1, 0), Color(0.85, 0.95, 1.0), 0.25, Vector3.ZERO, 0.3)
		for h in game.alive_heroes():
			if not hit.has(h) and Actor._flat(h.global_position - a.global_position).length() <= a.body_r + h.body_r + 0.25:
				hit[h] = true
				Combat.enemy_hit(game, a, h, {"mult": 1.1})
				var side := Vector3(-dir.z, 0, dir.x)
				if side.dot(h.global_position - a.global_position) < 0.0:
					side = -side
				h.knock += side * 5.0 + dir * 2.0
				Vfx.hit_spark(h.global_position + Vector3(0, 0.4, 0), Color("ff8a8a"), true)
	a.model.lean_to(0.0, 0.3)
	game._shot_later(0.0, "boss_charge_end")
	await _wait(a, 0.3)
	if is_instance_valid(a):
		a.busy = false
