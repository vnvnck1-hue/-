class_name Specials
extends RefCounted
## Gimmick enemy behaviours (spec §4.5, §4.6), reinterpreted for free movement:
## ninja leaps next to the farthest hero, sprinter moves in 2-tile dashes, splitter splits on death.

const NINJA_JUMP_CD := 1.7
const SPRINT_CD := 0.76
const SPRINT_DIST := 2.0

## Returns true when it handled this tick's movement.
static func move(game: Node, a: Actor) -> bool:
	if a.is_hero() or a.target == null:
		return false
	var out_of_range := a.reach_to(a.target) > a.attack_range() + Actor.RANGE_PAD
	match a.kind:
		"mammoth", "abyss":
			return BossSkills.tick(game, a)
		"ninja":
			if out_of_range and game.now - a.special_t >= NINJA_JUMP_CD:
				a.special_t = game.now
				_ninja_leap(game, a)
				return true
		"sprinter":
			if out_of_range:
				if game.now - a.special_t >= SPRINT_CD * (2.0 if game.now < a.slow_until else 1.0):
					a.special_t = game.now
					_dash(game, a)
				else:
					a.model.walk = lerpf(a.model.walk, 0.0, 0.2)
				return true
	return false

static func _ninja_leap(game: Node, a: Actor) -> void:
	var t := a.target
	var away := Actor._flat(a.global_position - t.global_position)
	if away.length() < 0.01:
		away = Vector3(0, 0, -1)
	var spot := t.global_position + away.normalized() * (t.body_r + a.body_r + 0.1)
	spot.x = clampf(spot.x, -Actor.BOARD_X, Actor.BOARD_X)
	spot.z = clampf(spot.z, -Actor.BOARD_Z, Actor.BOARD_Z)
	a.busy = true
	Vfx.speed_puffs(a.global_position, Color("c8c0e0"))
	Vfx.dust_ring(a.global_position, 0.5)
	Sfx.play("whoosh", -6.0, 1.8)
	game.hud.callout(a.global_position + Vector3(0, 1.2, 0), "슉!", Color("c9b8ff"))
	var tw := a.hop_to(spot, 0.32, 1.6)
	await tw.finished
	if not is_instance_valid(a):
		return
	a.busy = false
	if a.alive:
		Vfx.dust_ring(a.global_position, 0.6)
		a.last_attack = minf(a.last_attack, game.now - a.attack_interval() + 0.15)

static func _dash(game: Node, a: Actor) -> void:
	var to := Actor._flat(a.target.global_position - a.global_position)
	var dist := minf(SPRINT_DIST, maxf(0.0, a.reach_to(a.target) - a.attack_range()))
	if dist < 0.05:
		return
	var spot := a.global_position + to.normalized() * dist
	a.busy = true
	for i in 3:
		Vfx.speed_puffs(a.global_position.lerp(spot, i / 3.0), Color("ffd29a"))
	Sfx.play("whoosh", -12.0, 2.0)
	var tw := a.hop_to(spot, 0.18, 0.25)
	await tw.finished
	if not is_instance_valid(a):
		return
	a.busy = false

## Splitter death: up to two small splitlings around the corpse (current wave scaling).
static func split(game: Node, e: Actor) -> void:
	var offs := [Vector3(0.5, 0, 0), Vector3(-0.5, 0, 0), Vector3(0, 0, 0.5), Vector3(0, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5)]
	var made := 0
	var mult := Defs.scaling(game.wave)
	for o in offs:
		if made >= 2:
			break
		var p: Vector3 = e.global_position + o
		if absf(p.x) > Actor.BOARD_X or absf(p.z) > Actor.BOARD_Z:
			continue
		var s: Actor = game.spawn_enemy_at("splitling", p, mult)
		s.drop_in(0.6, 0.05 * made)
		made += 1
	Vfx.explosion(Actor._flat(e.global_position), Color("8fe36a"), 0.5)
	Sfx.play("pop", -4.0, 0.6)
