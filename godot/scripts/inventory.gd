class_name Inventory
extends RefCounted
## Inventory data ops: entries, random rolls, auto-merge, equip, sell (spec §5, §6).
## Entry kinds: "equip" {key, bonus?}, "special" {key}, "relic" {key}, "skillbook" {cls, skill, revealed}.

static var _id := 0

static func make(kind: String, key: String) -> Dictionary:
	_id += 1
	var e := {"id": _id, "kind": kind, "key": key}
	if kind == "equip":
		var def := Defs.item(key)
		if not Gear.is_family(key) and int(def.get("tier", 1)) >= 5 and randf() < 0.35:
			e["bonus"] = {"moveSpeedBonus": round((0.05 + randf() * 0.35) * 100.0) / 100.0}
	return e

static func make_skillbook() -> Dictionary:
	_id += 1
	var cls: String = Defs.HERO_ORDER[randi() % 3]
	var list: Array = Defs.SKILLBOOK_SKILLS[cls]
	return {"id": _id, "kind": "skillbook", "cls": cls, "skill": list[randi() % list.size()]["id"], "revealed": false}

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
			return 5
		"relic":
			return 6 if Defs.RELICS[e["key"]]["rarity"] == "legendary" else 4
	return 3

static func rarity_of(e: Dictionary) -> String:
	if e["kind"] == "relic":
		return Defs.RELICS[e["key"]]["rarity"]
	if e["kind"] == "skillbook":
		return "mythic"
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
			if not e["revealed"]:
				return "봉인된 스킬북"
			return skillbook_def(e)["name"]
	return "?"

static func skillbook_def(e: Dictionary) -> Dictionary:
	for s in Defs.SKILLBOOK_SKILLS[e["cls"]]:
		if s["id"] == e["skill"]:
			return s
	return {}

static func sell_price(game: Node, e: Dictionary) -> int:
	var gm := Stats.g(Stats.perk_fx(game), "goldMult")
	match e["kind"]:
		"skillbook":
			return 300
		"relic":
			return int(floorf(Defs.RELICS[e["key"]]["price"] * 0.5 * (1.0 + gm)))
		"special":
			return int(floorf(Defs.SPECIAL[e["key"]]["price"] * 0.5))
	if Gear.is_family(e["key"]):
		return int(floorf(Gear.sell_price(tier_of(e)) * (1.0 + gm)))
	return int(floorf(Defs.ITEM_SELL.get(tier_of(e), 10) * float(e.get("pw", 1.0)) * (1.0 + gm)))

## Adds to inventory. When the bag is full: an item that completes a merge still goes in (the merge frees
## room); otherwise the cheapest lone, outgrown family item in the bag is sold to make room for a better
## one, and failing that the incoming item is sold. Returns "added" | "sold:<gold>".
static func add(game: Node, e: Dictionary) -> String:
	if game.inventory.size() >= game.inv_cap and not _completes_merge(game, e):
		var junk := _outgrown(game, e)
		var victim: Dictionary = junk if not junk.is_empty() else e
		var g := sell_price(game, victim)
		game.gold += g
		if victim == e:
			return "sold:%d" % g
		game.inventory.erase(victim)
		game.inventory.append(e)
		settle(game)
		return "sold:%d" % g
	game.inventory.append(e)
	if e["kind"] == "equip" or (e["kind"] == "special" and e["key"] == "crown"):
		settle(game)
	if e["kind"] == "relic":
		save_relics(game)
	return "added"

static func save_relics(game: Node) -> void:
	var keys := []
	for e in game.inventory:
		if e["kind"] == "relic" and Defs.RELICS[e["key"]]["rarity"] == "legendary":
			keys.append(e["key"])
	Meta.relics = keys
	Meta.save()

## Merges only use what is in the bag: equipped gear is never a merge material.
static func _count_key(game: Node, k: String) -> int:
	var n := 0
	for x in game.inventory:
		if merge_key(x) == k:
			n += 1
	return n

static func _completes_merge(game: Node, e: Dictionary) -> bool:
	var k := merge_key(e)
	return k != "" and _merge_result(k) != "" and _count_key(game, k) >= 2

## Cheapest family item in the bag that has no partner and is graded below the incoming family item.
static func _outgrown(game: Node, incoming: Dictionary) -> Dictionary:
	if incoming["kind"] != "equip" or not Gear.is_family(incoming["key"]):
		return {}
	var g_in := tier_of(incoming)
	var best := {}
	for x in game.inventory:
		if x["kind"] != "equip" or not Gear.is_family(x["key"]) or tier_of(x) >= g_in:
			continue
		if _count_key(game, merge_key(x)) >= 2:
			continue
		if best.is_empty() or tier_of(x) < tier_of(best):
			best = x
	return best

## What three of merge key `k` become ("" = no merge): a family group climbs one grade forever
## (the group of the next grade; the family is picked in merge_once), uniques / the crown become
## their transcendent form.
static func _merge_result(k: String) -> String:
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

## Auto-merge: 3 of one merge key in the bag -> next grade / transcendent. Repeats until stable.
## Returns the list of produced item names. Instant (no staging) — used when the game has no merge show.
static func try_merge(game: Node) -> Array:
	var made := []
	var k := find_merge(game)
	while k != "":
		made.append(label_of(merge_once(game, k, false)))
		k = find_merge(game)
	if not made.is_empty() and game.has_method("on_merged"):
		game.on_merged(made)
	return made

## After the bag changed: hand merges to the game's sequential merge show if it has one
## (it may hold them until incoming loot has landed), otherwise merge instantly.
static func settle(game: Node) -> void:
	if game.has_method("queue_merges"):
		game.queue_merges()
	else:
		try_merge(game)

## First key that has 3 copies in the bag and a merge result ("" = nothing to merge).
static func find_merge(game: Node) -> String:
	var counts := {}
	var order := []
	for e in game.inventory:
		var k := merge_key(e)
		if k != "":
			if not counts.has(k):
				order.append(k)
			counts[k] = counts.get(k, 0) + 1
	for k in order:
		if counts[k] >= 3 and _merge_result(k) != "":
			return k
	return ""

## Bag indices a merge of `key` consumes, in _remove_n's order (from the back of the bag).
static func merge_sources(game: Node, key: String, n := 3) -> Array:
	var bag := []
	var i: int = game.inventory.size() - 1
	while i >= 0 and bag.size() < n:
		if merge_key(game.inventory[i]) == key:
			bag.append(i)
		i -= 1
	return bag

## Bag index the merge result of `key` lands on (the first of its sources).
static func merge_target(game: Node, key: String) -> int:
	var bag := merge_sources(game, key)
	if bag.is_empty():
		return game.inventory.size()
	var m: int = bag[0]
	for x in bag:
		m = mini(m, x)
	return m

## Performs one merge of `key`; the result takes the slot of its first source. Returns the new entry.
## A family group's result takes the family of one of its three materials at random.
static func merge_once(game: Node, key: String, notify := true) -> Dictionary:
	var at := merge_target(game, key)
	var result := _merge_result(key)
	var used := _remove_n(game, key, 3)
	if Gear.is_group(key):
		var mats: Array = used["keys"]
		result = Gear.key(Gear.family_of(mats[randi() % mats.size()]), Gear.group_grade(key) + 1)
	var ne := make("equip", result)
	var pw: float = used["pw"]
	if pw > 1.0:
		ne["pw"] = pw   # a unique keeps the strongest era power of its three sources
	game.inventory.insert(clampi(at, 0, game.inventory.size()), ne)
	if notify and game.has_method("on_merged"):
		game.on_merged([label_of(ne)])
	return ne

static func label_of(e: Dictionary) -> String:
	var label: String = Defs.item(e["key"])["name"]
	if Gear.is_family(e["key"]) and Gear.grade_of_key(e["key"]) <= Gear.STAR_FROM:
		label += " [%s]" % Gear.grade_name(Gear.grade_of_key(e["key"]))
	return label

## Removes n bag entries of merge key `key`. Returns {"pw": highest era power among them, "keys": their item keys}.
static func _remove_n(game: Node, key: String, n: int) -> Dictionary:
	var left := n
	var pw := 1.0
	var keys := []
	var i: int = game.inventory.size() - 1
	while i >= 0 and left > 0:
		if merge_key(game.inventory[i]) == key:
			pw = maxf(pw, float(game.inventory[i].get("pw", 1.0)))
			keys.append(game.inventory[i]["key"])
			game.inventory.remove_at(i)
			left -= 1
		i -= 1
	return {"pw": pw, "keys": keys}

## Equip from inventory onto hero. Previous item returns to inventory.
static func equip(game: Node, h: Actor, e: Dictionary) -> void:
	var def := Defs.item(e["key"])
	var slot: String = def["slot"]
	var old = h.equipment[slot]
	var old_hp := Stats.g(Stats.entry_stats(old), "hp") if old else 0.0
	var new_hp := Stats.g(Stats.entry_stats(e), "hp")
	game.inventory.erase(e)
	h.equipment[slot] = e
	if old:
		game.inventory.append(old)
	var diff := new_hp - old_hp
	h.max_hp = maxf(1.0, h.max_hp + diff)
	h.hp = minf(h.hp + maxf(0.0, diff), h.max_hp)
	settle(game)
