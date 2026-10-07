class_name Combat
extends RefCounted
## Attack delivery and damage resolution (spec §3.5, §3.9).
## Fixes original bug #4: splash / pierce / lightning respect illusion immunity.

const SPLASH_R := 1.2
const PIERCE_R := 0.6

static func is_immune(game: Node, e: Actor) -> bool:
	return e.is_illusion and game.illusionist_alive()

static func _in_battle(game: Node) -> bool:
	return game.in_battle()

# ---------------------------------------------------------------- delivery
## Plays the attack and resolves hits. Awaitable; returns when the swing is done.
static func hero_attack(game: Node, h: Actor, t: Actor) -> void:
	var style: String = h.def["attack"]
	match style:
		"melee":
			var impact := h.model.play_attack("melee")
			Sfx.play("whoosh", -14.0, 1.3)
			await h.get_tree().create_timer(impact, false).timeout
			if not h.alive or not _in_battle(game) or not is_instance_valid(t) or not t.alive:
				return
			Vfx.hit_spark(h.global_position.lerp(t.global_position, 0.6) + Vector3(0, 0.4, 0), Color("ffe08a"), true)
			Sfx.play("thud", -6.0, 1.0)
			hero_hit(game, h, t)
		"arrow":
			var impact := h.model.play_attack("arrow")
			Sfx.play("whoosh", -16.0, 1.4)
			await h.get_tree().create_timer(impact * 0.7, false).timeout
			if not h.alive or not _in_battle(game) or not is_instance_valid(t) or not t.alive:
				return
			var from := h.global_position + Vector3(0, 0.45, 0) + h.fwd() * 0.25
			var on_arrow := func(_p: Vector3) -> void:
				if is_instance_valid(t) and t.alive and h.alive:
					Vfx.hit_spark(t.global_position + Vector3(0, 0.4, 0), Color("ffe08a"))
					Sfx.play("thud", -11.0, 1.4)
					hero_hit(game, h, t)
			Vfx.projectile("arrow", from, t, on_arrow, 12.0)
		"bolt":
			# two homing bolts; each is a full hit (original behaviour)
			var impact := h.model.play_attack("fireball")
			Sfx.play("whoosh", -12.0, 0.8)
			await h.get_tree().create_timer(impact, false).timeout
			_fire_bolt(game, h, t, maxf(0.46 - impact, 0.16))
			await h.get_tree().create_timer(0.3, false).timeout
			if h.alive and _in_battle(game):
				h.model.punch_scale(0.9, 1.15, 0.3)
				_fire_bolt(game, h, t, 0.3)

static func _fire_bolt(game: Node, h: Actor, t: Actor, dur: float) -> void:
	if not h.alive or not _in_battle(game):
		return
	if not is_instance_valid(t) or not t.alive:
		t = game.nearest_enemy(h.global_position)
		if t == null:
			return
	var from := h.global_position + Vector3(0, 0.6, 0) + h.fwd() * 0.3
	Sfx.play("whoosh", -12.0, 1.6)
	var on_bolt := func(_p: Vector3) -> void:
		if not h.alive:
			return
		var tt := t
		if not is_instance_valid(tt) or not tt.alive:
			tt = game.nearest_enemy(h.global_position)
		if tt == null:
			return
		Vfx.bolt_hit(tt.global_position + Vector3(0, 0.4, 0))
		Sfx.play("pop", -8.0, 0.7)
		hero_hit(game, h, tt)
	Vfx.projectile("bolt", from, t, on_bolt, 0.0, dur)

static func enemy_attack(game: Node, e: Actor, t: Actor) -> void:
	var impact := e.model.play_attack("melee")
	Sfx.play("whoosh", -18.0, 1.1)
	await e.get_tree().create_timer(impact, false).timeout
	if not e.alive or not _in_battle(game) or not is_instance_valid(t) or not t.alive:
		return
	if game.now < e.stun_until:
		return
	var big: bool = e.body_r > Actor.RADIUS or Defs.role(e.kind) == "boss"
	Vfx.hit_spark(e.global_position.lerp(t.global_position, 0.6) + Vector3(0, 0.4, 0), Color("ff8a8a"), big)
	Sfx.play("thud", -5.0 if big else -8.0, 0.75 if big else 1.0)
	if big:
		Vfx.cam.add_trauma(0.15)
	enemy_hit(game, e, t)

# ---------------------------------------------------------------- resolution
## Hero hits enemy. opts: bonus (echo extra hit), counter.
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
	dmg = maxf(1.0, dmg)
	# sustain & resources
	var ls := Stats.g(pf, "lifeSteal")
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
		if randf() < Stats.g(sk, "freezeChance"):
			t.slow_until = game.now + 2.0
			Vfx.frost_hit(t.global_position)
		if Stats.has_effect(h, "knockback") and not Stats.has_effect(h, "swap") and not t.knockback_immune:
			t.knock += Actor._flat(t.global_position - h.global_position).normalized() * 7.0
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
				if is_instance_valid(z) and z.alive and not is_immune(game, z) and h.alive:
					if z.apply_damage(ld, h):
						game.on_enemy_killed(z, h))
	for k in killed:
		game.on_enemy_killed(k, h)
	# echo crystal: extra attack
	if not opts.get("bonus", false) and not opts.get("counter", false):
		var dbl := Stats.g(pf, "doubleAttackChance")
		if dbl > 0.0 and randf() < dbl:
			game.after(0.21, func():
				var tt := t
				if h.cls == "mage" and (not is_instance_valid(tt) or not tt.alive):
					tt = game.nearest_enemy(h.global_position)
				if tt and is_instance_valid(tt) and tt.alive and h.alive and game.in_battle():
					game.hud.callout(h.global_position + Vector3(0, 1.3, 0), "추가 공격!", Color("9fe8ff"))
					hero_hit(game, h, tt, {"bonus": true}))

## Enemy hits hero.
static func enemy_hit(game: Node, e: Actor, h: Actor) -> void:
	if not h.alive:
		return
	var dodge := minf(Stats.g(Stats.skill_fx(h), "dodgeChance"), Stats.CAP_DODGE)
	if dodge > 0.0 and randf() < dodge:
		game.hud.float_text(h.global_position + Vector3(0, 1.1, 0), "회피!", Color("c9f0ff"))
		return
	var reduce := Stats.damage_reduce(game, h)
	var final := maxf(1.0, floorf(e.atk * (1.0 - reduce)))
	var cc := Stats.counter_chance(h)
	if cc > 0.0 and randf() < cc:
		game.after(0.1, func():
			if h.alive and is_instance_valid(e) and e.alive and game.in_battle():
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
	if e.apply_damage(amount, h, false, true, 0.6):
		game.on_enemy_killed(e, h)
		return true
	return false
