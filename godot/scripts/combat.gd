class_name Combat
extends RefCounted
## Attack delivery and damage resolution (spec §3.5, §3.9).
## Fixes original bug #4: splash / pierce / lightning respect illusion immunity.

const SPLASH_R := 1.2
const PIERCE_R := 0.6
## Each of the mage's two homing bolts lands this share of a full hit (two full hits made the mage 3.3x the
## warrior's DPS; now ~2x, in line with damage dealer vs tank).
const BOLT_MULT := 0.6

static func is_immune(game: Node, e: Actor) -> bool:
	return e.is_illusion and game.illusionist_alive()

static func _in_battle(game: Node) -> bool:
	return is_instance_valid(game) and game.in_battle()

## Unit not freed and still standing. These are static coroutines / timer lambdas: they resume even when the
## units they captured were freed meanwhile (wave cleared, scene left), so every resume checks this first.
static func _live(a: Actor) -> bool:
	return is_instance_valid(a) and a.alive

## Waits t seconds of (pausable) game time on the attacker's tree.
static func _wait(a: Actor, t: float) -> Signal:
	return a.get_tree().create_timer(t, false).timeout

# ---------------------------------------------------------------- delivery
## Plays the attack and resolves hits. Awaitable; returns when the swing is done.
static func hero_attack(game: Node, h: Actor, t: Actor) -> void:
	var style: String = h.def["attack"]
	match style:
		"melee":
			var impact := h.model.play_attack("melee")
			Sfx.play("whoosh", -14.0, 1.3)
			await _wait(h, impact)
			if not _live(h) or not _in_battle(game) or not _live(t):
				return
			Vfx.hit_spark(h.global_position.lerp(t.global_position, 0.6) + Vector3(0, 0.4, 0), Color("ffe08a"), true)
			Sfx.play("thud", -6.0, 1.0)
			hero_hit(game, h, t)
		"arrow":
			var impact := h.model.play_attack("arrow")
			Sfx.play("whoosh", -16.0, 1.4)
			await _wait(h, impact * 0.7)
			if not _live(h) or not _in_battle(game) or not _live(t):
				return
			var from := h.global_position + Vector3(0, 0.45, 0) + h.fwd() * 0.25
			var on_arrow := func(_p: Vector3) -> void:
				if _live(t) and _live(h):
					Vfx.hit_spark(t.global_position + Vector3(0, 0.4, 0), Color("ffe08a"))
					Sfx.play("thud", -11.0, 1.4)
					hero_hit(game, h, t)
			Vfx.projectile("arrow", from, t, on_arrow, 12.0)
		"bolt":
			# two homing bolts; each is a full hit (original behaviour)
			var impact := h.model.play_attack("fireball")
			Sfx.play("whoosh", -12.0, 0.8)
			await _wait(h, impact)
			if not _live(h) or not h.is_inside_tree():
				return
			_fire_bolt(game, h, t, maxf(0.46 - impact, 0.16))
			await _wait(h, 0.3)
			if _live(h) and _in_battle(game):
				h.model.punch_scale(0.9, 1.15, 0.3)
				_fire_bolt(game, h, t, 0.3)

static func _fire_bolt(game: Node, h: Actor, t: Actor, dur: float) -> void:
	if not _live(h) or not _in_battle(game):
		return
	if not _live(t):
		t = game.nearest_enemy(h.global_position)
		if t == null:
			return
	var from := h.global_position + Vector3(0, 0.6, 0) + h.fwd() * 0.3
	Sfx.play("whoosh", -12.0, 1.6)
	var on_bolt := func(_p: Vector3) -> void:
		if not _live(h) or not is_instance_valid(game):
			return
		var tt := t
		if not _live(tt):
			tt = game.nearest_enemy(h.global_position)
		if tt == null:
			return
		Vfx.bolt_hit(tt.global_position + Vector3(0, 0.4, 0))
		Sfx.play("pop", -8.0, 0.7)
		hero_hit(game, h, tt, {"mult": BOLT_MULT})
	Vfx.projectile("bolt", from, t, on_bolt, 0.0, dur)

## Ranged enemy styles: projectile kind (Vfx.projectile), throw animation, flight speed, hit spark colour.
const ENEMY_SHOTS := {
	"rock": {"anim": "fireball", "speed": 8.5, "col": Color("d8c8a8")},
	"quarrel": {"anim": "arrow", "speed": 15.0, "col": Color("ffd0a0")},
	"hex": {"anim": "fireball", "speed": 7.0, "col": Color("c27aff")},
}

static func enemy_attack(game: Node, e: Actor, t: Actor) -> void:
	if Defs.is_ranged(e.kind):
		await _enemy_shot(game, e, t)
		return
	var impact := e.model.play_attack("melee")
	Sfx.play("whoosh", -18.0, 1.1)
	await _wait(e, impact)
	if not _live(e) or not _in_battle(game) or not _live(t):
		return
	if game.now < e.stun_until:
		return
	var big: bool = e.body_r > Actor.RADIUS or Defs.role(e.kind) == "boss"
	Vfx.hit_spark(e.global_position.lerp(t.global_position, 0.6) + Vector3(0, 0.4, 0), Color("ff8a8a"), big)
	Sfx.play("thud", -5.0 if big else -8.0, 0.75 if big else 1.0)
	if big:
		Vfx._shake(0.15)
	enemy_hit(game, e, t)

## Ranged enemy: wind up, then a projectile that homes onto the hero. A shot already in the air still lands
## when its shooter falls; the fire shaman's hex bursts and singes other heroes nearby (50%).
static func _enemy_shot(game: Node, e: Actor, t: Actor) -> void:
	var style: String = e.def["attack"]
	var shot: Dictionary = ENEMY_SHOTS[style]
	var impact := e.model.play_attack(shot["anim"])
	Sfx.play("whoosh", -15.0, 1.5 if style == "quarrel" else 1.0)
	await _wait(e, impact)
	if not _live(e) or not _in_battle(game) or not _live(t):
		return
	if game.now < e.stun_until:
		return
	var from := e.global_position + Vector3(0, 0.5, 0) + e.fwd() * 0.25
	var splash: float = e.def.get("splash", 0.0)
	var on_hit := func(p: Vector3) -> void:
		if not is_instance_valid(e) or not _in_battle(game):
			return
		if splash > 0.0:
			Vfx.explosion(Actor._flat(p), shot["col"], 0.55)
			Sfx.play("boom", -12.0, 1.5)
			for h in game.alive_heroes():
				if h != t and Actor._flat(h.global_position - p).length() <= splash:
					enemy_hit(game, e, h, {"mult": 0.5, "ranged": true})
		if _live(t):
			Vfx.hit_spark(t.global_position + Vector3(0, 0.4, 0), shot["col"])
			Sfx.play("thud", -10.0, 1.3)
			enemy_hit(game, e, t, {"ranged": true})
	Vfx.projectile(style, from, t, on_hit, shot["speed"])

# ---------------------------------------------------------------- resolution
## Hero hits enemy. opts: bonus (echo extra hit), counter, mult (damage share of a full hit, e.g. mage bolts).
static func hero_hit(game: Node, h: Actor, t: Actor, opts := {}) -> void:
	if not is_instance_valid(t) or not t.alive or not h.alive:
		return
	var pf := Stats.perk_fx(game)
	var dmg := floorf((h.atk + Stats.g(Stats.item_fx(h), "atk")) * Stats.atk_mult(game, h))
	var crit := randf() < Stats.crit_chance(game, h)
	if crit:
		dmg *= 2.0
	var db := Stats.dmg_bonus(h)
	if db > 0.0:
		dmg = floorf(dmg * (1.0 + db))
	dmg = maxf(1.0, floorf(dmg * float(opts.get("mult", 1.0)) * Stats.boss_dmg_mult(h, t)))
	# sustain & resources
	var ls := Stats.life_steal(game)
	if ls > 0.0:
		h.heal(floorf(dmg * ls))
	var gain := floorf(h.def["mana_per_attack"] * (1.0 + Stats.mana_gain_mult(game, h)))
	h.add_mana(gain)
	h.attack_count += 1
	for o in game.alive_heroes():
		if o != h and Stats.has_effect(o, "sharedMana"):
			o.add_mana(floorf(gain * 0.5))
	if Stats.has_relic(game, "crescendoGear"):
		game.relic_tempo = mini(15, game.relic_tempo + 1)
	var killed: Array = []
	var sk := Stats.skill_fx(h)
	if is_immune(game, t):
		game.hud.float_text(t.global_position + Vector3(0, 1.1, 0), "IMMUNE", Color("c9b8ff"))
	else:
		if randf() < Stats.freeze_chance(h):
			t.slow_until = game.now + 2.0
			Vfx.frost_hit(t.global_position)
		if Stats.has_effect(h, "knockback") and not Stats.has_effect(h, "swap"):
			t.knock_back(h.global_position, 7.0)
		if t.apply_damage(dmg, h, crit):
			killed.append(t)
	# splash
	if randf() < Stats.explosion_chance(game, h):
		Vfx.explosion(Actor._flat(t.global_position), Color("ff8a2a"), 0.6)
		Sfx.play("boom", -9.0, 1.4)
		for e in game.alive_enemies():
			if e != t and not is_immune(game, e) and Actor._flat(e.global_position - t.global_position).length() <= SPLASH_R + e.body_r - Actor.RADIUS:
				if e.apply_damage(floorf(dmg * 0.5), h):
					killed.append(e)
	# pierce
	if randf() < Stats.g(sk, "pierceChance"):
		var dir := Actor._flat(t.global_position - h.global_position).normalized()
		var spot := t.global_position + dir
		var best: Actor = null
		var bd := PIERCE_R
		for e in game.alive_enemies():
			if e == t:
				continue
			var d: float = Actor._flat(e.global_position - spot).length() - (e.body_r - Actor.RADIUS)
			if d < bd:
				bd = d
				best = e
		if best and not is_immune(game, best):
			Vfx.hit_spark(best.global_position + Vector3(0, 0.4, 0), Color("bfffb0"))
			if best.apply_damage(floorf(dmg * 0.7), h):
				killed.append(best)
	# swap places
	if Stats.has_effect(h, "swap") and t.alive:
		var hp0 := h.position
		Vfx.dust_ring(h.global_position, 0.6)
		Vfx.dust_ring(t.global_position, 0.6)
		h.position = t.position
		t.position = hp0
	# lightning every 3rd attack
	if Stats.has_effect(h, "lightning") and h.attack_count % 3 == 0:
		var others: Array = game.alive_enemies().filter(func(e): return e != t)
		if not others.is_empty():
			var z: Actor = others[randi() % others.size()]
			var ld := floorf(dmg * 0.8)
			Vfx.lightning(t.global_position + Vector3(0, 0.5, 0), z.global_position + Vector3(0, 0.5, 0))
			game.after(0.15, func():
				if _live(z) and _live(h) and is_instance_valid(game) and not is_immune(game, z):
					if z.apply_damage(ld, h):
						game.on_enemy_killed(z, h))
	for k in killed:
		game.on_enemy_killed(k, h)
	# echo crystal: extra attack
	if not opts.get("bonus", false) and not opts.get("counter", false):
		var dbl := Stats.g(pf, "doubleAttackChance")
		if dbl > 0.0 and randf() < dbl:
			game.after(0.21, func():
				if not _live(h) or not _in_battle(game):
					return
				var tt := t
				if h.cls == "mage" and not _live(tt):
					tt = game.nearest_enemy(h.global_position)
				if _live(tt):
					game.hud.callout(h.global_position + Vector3(0, 1.3, 0), "추가 공격!", Color("9fe8ff"))
					hero_hit(game, h, tt, {"bonus": true, "mult": opts.get("mult", 1.0)}))

## Enemy hits hero. opts: mult (damage scale, e.g. splash), ranged (no counter-attack from afar).
static func enemy_hit(game: Node, e: Actor, h: Actor, opts := {}) -> void:
	if not h.alive:
		return
	var dodge := minf(Stats.g(Stats.skill_fx(h), "dodgeChance"), Stats.CAP_DODGE)
	if dodge > 0.0 and randf() < dodge:
		game.hud.float_text(h.global_position + Vector3(0, 1.1, 0), "회피!", Color("c9f0ff"))
		return
	var reduce := Stats.damage_reduce(game, h)
	var final := maxf(1.0, floorf(e.atk * opts.get("mult", 1.0) * (1.0 - reduce)))
	var cc := 0.0 if opts.get("ranged", false) else Stats.counter_chance(h)
	if cc > 0.0 and randf() < cc:
		game.after(0.1, func():
			if _live(h) and _live(e) and _in_battle(game):
				h.model.play_attack("melee")
				game.hud.callout(h.global_position + Vector3(0, 1.3, 0), "반격!", Color("ffd27a"))
				hero_hit(game, h, e, {"counter": true}))
	if h.apply_damage(final, e):
		game.on_hero_down(h)

## Flat skill / ultimate damage (no crit, no dmgBonus). Returns true if it killed.
static func skill_damage(game: Node, h: Actor, e: Actor, amount: float) -> bool:
	if not is_instance_valid(e) or not e.alive:
		return false
	if is_immune(game, e):
		game.hud.float_text(e.global_position + Vector3(0, 1.1, 0), "IMMUNE", Color("c9b8ff"))
		return false
	if e.apply_damage(floorf(amount * Stats.boss_dmg_mult(h, e)), h, false, true, 0.6):
		game.on_enemy_killed(e, h)
		return true
	return false
