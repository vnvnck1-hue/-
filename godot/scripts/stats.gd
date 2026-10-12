class_name Stats
extends RefCounted
## Effect aggregation (skills, skill books, equipment, run perks, relics, talent tree) and derived combat stats.
## Fixes original bug #1: the common talent atkMult is counted once (in talent_fx), not also in perk_fx.

const CAP_ATK_SPEED := 0.7
const CAP_MOVE_SPEED := 0.75
const CAP_REDUCE := 0.75     # was 0.9 (late gear alone reached it: 1/10 damage taken)
const CAP_LIFESTEAL := 0.35
const CAP_DODGE := 0.75
const CAP_ULT_CD := 0.85

static func g(d: Dictionary, k: String) -> float:
	return float(d.get(k, 0.0))

static func _add(out: Dictionary, fx: Dictionary, mul := 1.0) -> void:
	for k in fx:
		out[k] = out.get(k, 0.0) + float(fx[k]) * mul

## Skills learned from skill books this run (fx per level x level).
static func skill_fx(h: Actor) -> Dictionary:
	var out := {}
	for s in h.learned:
		var bd := Defs.book(s["id"])
		if not bd.is_empty():
			_add(out, bd["fx"], s["level"])
	return out

static func entry_stats(e: Dictionary) -> Dictionary:
	var out := {}
	var def := Defs.item(e.get("key", ""))
	if def.has("stats"):
		_add(out, def["stats"])
	if e.has("pw"):   # era power of a unique found later in the march: flat stats only
		for k in ["atk", "hp"]:
			if out.has(k):
				out[k] = floorf(out[k] * float(e["pw"]))
	if e.has("bonus"):
		_add(out, e["bonus"])
	return out

## What a worn item gives in a hero's slot: its own stats + the permanent slot level bonus (Gear.slot_bonus;
## the level that counts is capped by the item's grade).
static func equip_stats(h: Actor, slot: String, e) -> Dictionary:
	if e == null:
		return {}
	var out := entry_stats(e)
	if h.is_hero():
		_add(out, Gear.slot_bonus(slot, slot_level(h, slot, e)))
	return out

static func slot_level(h: Actor, slot: String, e) -> int:
	return mini(Meta.slot_level(h.cls, slot), Gear.slot_cap(e))

static func item_fx(h: Actor) -> Dictionary:
	var out := {}
	for slot in h.equipment:
		var e = h.equipment[slot]
		if e:
			_add(out, equip_stats(h, slot, e))
	return out

static func has_effect(h: Actor, eff: String) -> bool:
	for slot in h.equipment:
		var e = h.equipment[slot]
		if e and eff in Defs.item(e["key"]).get("effects", []):
			return true
	return false

## Team-wide: run perks + the relics worn in the lobby (game.relics, ★-scaled) + class-less talents (except atk/hp multipliers).
static func perk_fx(game: Node) -> Dictionary:
	var out := {}
	for p in game.perks:
		_add(out, Defs.PERKS[p]["fx"])
	for e in game.relics:
		_add(out, Defs.relic_fx(e["key"], int(e.get("star", 1))))
	var common := Meta.fx("")
	for k in common:
		if k != "atkMult" and k != "hpMult":
			out[k] = out.get(k, 0.0) + common[k]
	return out

static func has_relic(game: Node, key: String) -> bool:
	return relic_star(game, key) > 0

## ★ of the worn relic `key` this run (0 = not worn).
static func relic_star(game: Node, key: String) -> int:
	for e in game.relics:
		if e["key"] == key:
			return int(e.get("star", 1))
	return 0

## Per-class: common atk/hp multipliers + that class's talent nodes.
static func talent_fx(h: Actor) -> Dictionary:
	var out := {}
	var common := Meta.fx("")
	out["atkMult"] = g(common, "atkMult")
	out["hpMult"] = g(common, "hpMult")
	if h.cls != "":
		_add(out, Meta.fx(h.cls))
	return out

# ---------------------------------------------------------------- derived (heroes)
static func atk_mult(game: Node, h: Actor) -> float:
	return 1.0 + g(perk_fx(game), "atkMult") + g(talent_fx(h), "atkMult")

static func attack_power(game: Node, h: Actor) -> int:
	return maxi(1, int(floorf((h.atk + g(item_fx(h), "atk")) * atk_mult(game, h))))

static func atk_speed_bonus(game: Node, h: Actor) -> float:
	var s := g(skill_fx(h), "atkSpeedBonus") + g(item_fx(h), "atkSpeedBonus") + g(perk_fx(game), "atkSpeedBonus") + g(talent_fx(h), "atkSpeedBonus")
	var tempo_star := relic_star(game, "crescendoGear")
	if tempo_star > 0:
		s += minf(Defs.relic_tempo_cap(tempo_star), game.relic_tempo * 0.02 * Defs.relic_mult(tempo_star))
	return s

## seconds
static func attack_interval(game: Node, h: Actor) -> float:
	return h.def["speed"] / 1000.0 * (1.0 - minf(atk_speed_bonus(game, h), CAP_ATK_SPEED))

## tiles per second
static func move_speed(game: Node, h: Actor) -> float:
	var bonus := g(item_fx(h), "moveSpeedBonus") + g(perk_fx(game), "moveSpeedBonus")
	return 1000.0 / (h.def["move"] * (1.0 - minf(bonus, CAP_MOVE_SPEED)))

static func attack_range(game: Node, h: Actor) -> float:
	return h.def["range"] + g(item_fx(h), "range") + g(perk_fx(game), "range") + g(talent_fx(h), "range")

static func crit_chance(game: Node, h: Actor) -> float:
	return g(skill_fx(h), "critChance") + g(item_fx(h), "critChance") + g(perk_fx(game), "critChance") + g(talent_fx(h), "critChance")

static func dmg_bonus(h: Actor) -> float:
	return g(skill_fx(h), "dmgBonus") + g(item_fx(h), "dmgBonus")

static func explosion_chance(game: Node, h: Actor) -> float:
	return g(skill_fx(h), "explosionChance") + g(item_fx(h), "explosionChance") + g(perk_fx(game), "splashChance")

static func counter_chance(h: Actor) -> float:
	return g(skill_fx(h), "counterChance") + g(item_fx(h), "counterChance") + g(talent_fx(h), "counterChance")

static func mana_gain_mult(game: Node, h: Actor) -> float:
	return g(perk_fx(game), "manaGainMult") + g(talent_fx(h), "manaGainMult") + g(skill_fx(h), "manaGainMult")

static func ult_cooldown(game: Node, h: Actor) -> float:
	var red := minf(CAP_ULT_CD, g(perk_fx(game), "ultCooldownReduce") + g(talent_fx(h), "ultCooldownReduce") + g(skill_fx(h), "ultCooldownReduce"))
	return floorf(Defs.ULTIMATES[h.cls]["cooldown"] * (1.0 - red)) / 1000.0

static func damage_reduce(game: Node, h: Actor) -> float:
	var r := g(skill_fx(h), "dmgReduce") + g(item_fx(h), "dmgReduce") + g(perk_fx(game), "dmgReduce") + g(talent_fx(h), "dmgReduce")
	if game.now < h.guard_until:
		r += 0.5
	if Meta.has_flag("warTaunt") and game.hero_alive("warrior"):
		r += 0.03
	if h.cls == "warrior" and Meta.has_flag("warLastStand") and h.hp / h.max_hp <= 0.3:
		r += 0.15
	return minf(CAP_REDUCE, r)

static func life_steal(game: Node) -> float:
	return minf(CAP_LIFESTEAL, g(perk_fx(game), "lifeSteal"))

## Freeze-on-hit chance: skill books + talents (냉기 숙련).
static func freeze_chance(h: Actor) -> float:
	return g(skill_fx(h), "freezeChance") + g(talent_fx(h), "freezeChance")

## Extra damage against bosses and mid-bosses (talent 약점 추적).
static func boss_dmg_mult(h: Actor, t: Actor) -> float:
	var r := Defs.role(t.kind)
	if h.is_hero() and (r == "boss" or r == "giant" or r == "illusionist"):
		return 1.0 + g(talent_fx(h), "bossDmgBonus")
	return 1.0

## Ultimate damage bonus from talents + 전설 skill books.
static func ult_damage_bonus(h: Actor) -> float:
	return g(talent_fx(h), "ultDamageBonus") + g(skill_fx(h), "ultDamageBonus")
