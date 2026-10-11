class_name Inventory
extends RefCounted
## Inventory data ops: entries, random rolls, merge rules, equip, sell (spec §5, §6).
## Entry kinds: "equip" {key, bonus?, pw?}, "special" {key}, "relic" {key}, "skillbook" {skill},
## "stone" {n} (강화석: never stays in the bag — it is counted into game.stones the moment it lands).
## Gear is permanent (Meta storage / loadout) and never merges during a run: merging happens in the lobby
## storage (Meta.merge_all), using the same merge rules defined here.

static var _id := 0

static func make(kind: String, key: String) -> Dictionary:
	_id += 1
	var e := {"id": _id, "kind": kind, "key": key}
	if kind == "equip":
		var def := Defs.item(key)
		if not Gear.is_family(key) and int(def.get("tier", 1)) >= 5 and randf() < 0.35:
			e["bonus"] = {"moveSpeedBonus": round((0.05 + randf() * 0.35) * 100.0) / 100.0}
	return e

## A skill book of the given grade (1 일반 ~ 4 전설) for a random hero (or `cls`).
static func make_skillbook(grade := 1, cls := "") -> Dictionary:
	_id += 1
	var c: String = cls if cls != "" else Defs.HERO_ORDER[randi() % 3]
	var list := Defs.books_of(c, clampi(grade, 1, 4))
	return {"id": _id, "kind": "skillbook", "skill": list[randi() % list.size()]}

## A pile of n 강화석 (shown as one loot / card, counted on landing).
static func make_stone(n: int) -> Dictionary:
	_id += 1
	return {"id": _id, "kind": "stone", "n": maxi(1, n)}

## Rebuild a saved gear entry ({key, pw?, bonus?}) with a fresh id.
static func from_save(d: Dictionary) -> Dictionary:
	_id += 1
	var e := {"id": _id, "kind": "equip", "key": str(d.get("key", ""))}
	if d.has("pw"):
		e["pw"] = float(d["pw"])
	if d.has("bonus") and typeof(d["bonus"]) == TYPE_DICTIONARY:
		e["bonus"] = d["bonus"]
	return e

static func to_save(e: Dictionary) -> Dictionary:
	var d := {"key": e["key"]}
	if e.has("pw"):
		d["pw"] = e["pw"]
	if e.has("bonus"):
		d["bonus"] = e["bonus"]
	return d

static func _keys_where(dict: Dictionary, pred: Callable) -> Array:
	var out := []
	for k in dict:
		if pred.call(dict[k]):
			out.append(k)
	return out

static func random_legendary(ultra: bool) -> String:
	var keys := _keys_where(Defs.LEGENDARY, func(d): return d.get("ultra", false) == ultra)
	return keys[randi() % keys.size()]

static func random_relic(rarity: String) -> String:
	var keys := _keys_where(Defs.RELICS, func(d): return d["rarity"] == rarity)
	return keys[randi() % keys.size()]

## getRandomItem(wave): rare uniques as before, otherwise family gear from the stage drop window
## (Gear: region base grade, featured families, merge assist when `game` is given).
static func random_item_key(wave: int, game: Node = null, boss := false, assist := Gear.ASSIST) -> String:
	if wave >= 25 and randf() < 0.006:
		return random_legendary(true)
	if wave >= 15 and randf() < 0.03:
		return random_legendary(false)
	return Gear.roll_key(game, wave, boss, assist)

## A found / bought equipment entry for group k: uniques carry the era power of where they were found.
static func make_found(key: String, k: int) -> Dictionary:
	var e := make("equip", key)
	era_scale(e, k)
	return e

static func era_scale(e: Dictionary, k: int) -> void:
	if Gear.is_family(e["key"]):
		return
	var pw := Gear.era_power(int(Defs.item(e["key"]).get("tier", 5)), k)
	if pw > 1.0:
		e["pw"] = pw

static func tier_of(e: Dictionary) -> int:
	match e["kind"]:
		"equip":
			return int(Defs.item(e["key"]).get("tier", 1))
		"skillbook":
			return int(Defs.book(e["skill"]).get("grade", 1)) + 1
		"stone":
			return 2
		"relic":
			return 6 if Defs.RELICS[e["key"]]["rarity"] == "legendary" else 4
	return 3

static func rarity_of(e: Dictionary) -> String:
	if e["kind"] == "relic":
		return Defs.RELICS[e["key"]]["rarity"]
	if e["kind"] == "skillbook":
		return Defs.book_rarity(int(Defs.book(e["skill"]).get("grade", 1)))
	if e["kind"] == "stone":
		return "rare"
	if e["kind"] == "special":
		return "legendary" if e["key"] == "crown" else "rare"
	if Gear.is_family(e["key"]):
		return Gear.rarity(tier_of(e))
	return Defs.RARITY.get(tier_of(e), "common")

static func name_of(e: Dictionary) -> String:
	match e["kind"]:
		"equip":
			return Defs.item(e["key"]).get("name", e["key"])
		"special":
			return Defs.SPECIAL[e["key"]]["name"]
		"relic":
			return Defs.RELICS[e["key"]]["name"]
		"skillbook":
			return skillbook_def(e).get("name", "스킬북")
		"stone":
			return "강화석 ×%d" % int(e["n"])
	return "?"

static func skillbook_def(e: Dictionary) -> Dictionary:
	return Defs.book(e.get("skill", ""))

const BOOK_SELL := {1: 40, 2: 120, 3: 350, 4: 900}

static func sell_price(game: Node, e: Dictionary) -> int:
	var gm := Stats.g(Stats.perk_fx(game), "goldMult") if game else 0.0
	match e["kind"]:
		"skillbook":
			return BOOK_SELL.get(int(skillbook_def(e).get("grade", 1)), 40)
		"stone":
			return 0
		"relic":
			return int(floorf(Defs.RELICS[e["key"]]["price"] * 0.5 * (1.0 + gm)))
		"special":
			return int(floorf(Defs.SPECIAL[e["key"]]["price"] * 0.5))
	if Gear.is_family(e["key"]):
		return int(floorf(Gear.sell_price(tier_of(e)) * (1.0 + gm)))
	return int(floorf(Defs.ITEM_SELL.get(tier_of(e), 10) * float(e.get("pw", 1.0)) * (1.0 + gm)))

## Adds to inventory. 강화석 go straight to the run's stone count. When the bag is full, gear goes to the
## permanent storage instead (it is never lost) and anything else is sold. Returns "added" | "stone" |
## "stored" | "sold:<gold>".
static func add(game: Node, e: Dictionary) -> String:
	if e["kind"] == "stone":
		game.add_stones(int(e["n"]))
		return "stone"
	if game.inventory.size() >= game.inv_cap:
		if e["kind"] == "equip" and game.has_method("stash_gear"):
			game.stash_gear(e)
			return "stored"
		var g := sell_price(game, e)
		game.gold += g
		return "sold:%d" % g
	game.inventory.append(e)
	if e["kind"] == "relic":
		save_relics(game)
	settle(game)
	return "added"

static func save_relics(game: Node) -> void:
	var keys := []
	for e in game.inventory:
		if e["kind"] == "relic" and Defs.RELICS[e["key"]]["rarity"] == "legendary":
			keys.append(e["key"])
	Meta.relics = keys
	Meta.save()

## What three of merge key `k` become ("" = no merge): a family group climbs one grade forever
## (the group of the next grade; the family is picked from the materials in Meta.merge_all), uniques / the crown become
## their transcendent form.
static func merge_result(k: String) -> String:
	if Gear.is_group(k):
		return Gear.group(Gear.group_slot(k), Gear.group_grade(k) + 1)
	var asc := Defs.transcendent_of(k)
	if asc != "" and int(Defs.item(k).get("tier", 1)) >= 5:
		return asc
	return ""

## What an entry merges with: family gear by slot + grade (Gear.group_of), uniques / the crown by exact key.
static func merge_key(e: Dictionary) -> String:
	if e["kind"] == "equip" and Gear.is_family(e["key"]):
		return Gear.group_of(e["key"])
	if e["kind"] == "equip" or (e["kind"] == "special" and e["key"] == "crown"):
		return e["key"]
	return ""

## After the bag or the heroes' gear changed: no merging during a run any more — the game just writes the
## permanent gear it holds right now to the save (so quitting mid-run never loses a piece).
static func settle(game: Node) -> void:
	if game.has_method("sync_gear"):
		game.sync_gear()

static func label_of(e: Dictionary) -> String:
	var label: String = Defs.item(e["key"])["name"]
	if Gear.is_family(e["key"]) and Gear.grade_of_key(e["key"]) <= Gear.STAR_FROM:
		label += " [%s]" % Gear.grade_name(Gear.grade_of_key(e["key"]))
	return label

## Equip from inventory onto hero. Previous item returns to inventory.
static func equip(game: Node, h: Actor, e: Dictionary) -> void:
	var def := Defs.item(e["key"])
	var slot: String = def["slot"]
	var old = h.equipment[slot]
	var old_hp := Stats.g(Stats.equip_stats(h, slot, old), "hp") if old else 0.0
	var new_hp := Stats.g(Stats.equip_stats(h, slot, e), "hp")
	game.inventory.erase(e)
	h.equipment[slot] = e
	if old:
		game.inventory.append(old)
	var diff := new_hp - old_hp
	h.max_hp = maxf(1.0, h.max_hp + diff)
	h.hp = minf(h.hp + maxf(0.0, diff), h.max_hp)
	settle(game)
