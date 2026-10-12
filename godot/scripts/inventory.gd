class_name Inventory
extends RefCounted
## Inventory data ops: entries, random rolls, merge rules, equip, sell (spec §5, §6).
## Entry kinds: "equip" {key, bonus?, pw?}, "special" {key}, "relic" {key, star}, "skillbook" {grade},
## "stone" {n} (강화석: never stays in the bag — it is counted into game.stones the moment it lands).
## Relics never stay in the bag either: a found relic goes straight into the lobby collection (Meta.add_relic);
## the run wears the relics equipped in the lobby (game.relics).
## Gear is permanent (Meta storage / loadout) and never merges during a run: merging happens in the lobby
## storage (Meta.merge_all), using the same merge rules defined here. Skill books do merge in the bag:
## Defs.BOOK_MERGE books of one grade become one book of the next grade (Main.queue_merges, HudPanels.play_merge).

static var _id := 0

static func make(kind: String, key: String) -> Dictionary:
	_id += 1
	var e := {"id": _id, "kind": kind, "key": key}
	if kind == "equip":
		var def := Defs.item(key)
		if not Gear.is_family(key) and int(def.get("tier", 1)) >= 5 and randf() < 0.35:
			e["bonus"] = {"moveSpeedBonus": round((0.05 + randf() * 0.35) * 100.0) / 100.0}
	return e

## A relic at ★ star (1 ~ Defs.RELIC_MAX_STAR).
static func make_relic(key: String, star := 1) -> Dictionary:
	_id += 1
	return {"id": _id, "kind": "relic", "key": key, "star": clampi(star, 1, Defs.RELIC_MAX_STAR)}

## A skill book of the given grade (1 일반 ~ Defs.BOOK_TOP 전설): which skills it shows is rolled when it is read.
static func make_skillbook(grade := 1) -> Dictionary:
	_id += 1
	return {"id": _id, "kind": "skillbook", "grade": clampi(grade, 1, Defs.BOOK_TOP)}

## Grade of a skill book entry (old single-skill books carry their skill's grade).
static func book_grade(e: Dictionary) -> int:
	if e.has("grade"):
		return int(e["grade"])
	return int(Defs.book(e.get("skill", "")).get("grade", 1))

## A pile of n 강화석 (shown as one loot / card, counted on landing).
static func make_stone(n: int) -> Dictionary:
	_id += 1
	return {"id": _id, "kind": "stone", "n": maxi(1, n)}

## Rebuild a saved gear entry ({key, pw?, bonus?}) with a fresh id.
static func from_save(d: Dictionary) -> Dictionary:
	_id += 1
	var e := {"id": _id, "kind": "equip", "key": str(d.get("key", ""))}
	if typeof(d.get("pw")) in [TYPE_INT, TYPE_FLOAT]:
		e["pw"] = float(d["pw"])
	if typeof(d.get("bonus")) == TYPE_DICTIONARY:
		e["bonus"] = d["bonus"].duplicate()
	return e

static func to_save(e: Dictionary) -> Dictionary:
	var d := {"key": e["key"]}
	if e.has("pw"):
		d["pw"] = e["pw"]
	if e.has("bonus"):
		d["bonus"] = e["bonus"].duplicate()
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
			return book_grade(e) + 1
		"stone":
			return 2
		"relic":
			return 6 if Defs.RELICS[e["key"]]["rarity"] == "legendary" else 4
	return 3

static func rarity_of(e: Dictionary) -> String:
	if e["kind"] == "relic":
		return Defs.RELICS[e["key"]]["rarity"]
	if e["kind"] == "skillbook":
		return Defs.book_rarity(book_grade(e))
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
			return "%s 스킬북" % Defs.book_grade_name(book_grade(e))
		"stone":
			return "강화석 ×%d" % int(e["n"])
	return "?"

const BOOK_SELL := {1: 40, 2: 120, 3: 350, 4: 900}

static func sell_price(game: Node, e: Dictionary) -> int:
	var gm := Stats.g(Stats.perk_fx(game), "goldMult") if game else 0.0
	match e["kind"]:
		"skillbook":
			return BOOK_SELL.get(book_grade(e), 40)
		"stone":
			return 0
		"relic":
			return int(floorf(Defs.RELICS[e["key"]]["price"] * 0.5 * (1.0 + gm)))
		"special":
			return int(floorf(Defs.SPECIAL[e["key"]]["price"] * 0.5))
	if Gear.is_family(e["key"]):
		return int(floorf(Gear.sell_price(tier_of(e)) * (1.0 + gm)))
	return int(floorf(Defs.ITEM_SELL.get(tier_of(e), 10) * float(e.get("pw", 1.0)) * (1.0 + gm)))

## Adds to inventory. 강화석 go straight to the run's stone count, relics to the lobby collection. When the bag is full, gear goes to the
## permanent storage instead (it is never lost) and anything else is sold. Returns "added" | "stone" |
## "relic" | "stored" | "sold:<gold>".
static func add(game: Node, e: Dictionary) -> String:
	if e["kind"] == "stone":
		game.add_stones(int(e["n"]))
		return "stone"
	if e["kind"] == "relic":
		Meta.add_relic(e["key"], int(e.get("star", 1)))
		return "relic"
	if game.inventory.size() >= game.inv_cap and not (e["kind"] == "skillbook" and completes_book_merge(game, e)):
		if e["kind"] == "equip" and game.has_method("stash_gear"):
			game.stash_gear(e)
			return "stored"
		var g := sell_price(game, e)
		game.gold += g
		return "sold:%d" % g
	game.inventory.append(e)
	settle(game)
	return "added"

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

## After the bag or the heroes' gear changed: gear never merges during a run — the game just writes the
## permanent gear it holds right now to the save (so quitting mid-run never loses a piece) — and skill books
## of one grade merge (staged one by one in the bag by Main.queue_merges).
static func settle(game: Node) -> void:
	if game.has_method("sync_gear"):
		game.sync_gear()
	if game.has_method("queue_merges"):
		game.queue_merges()

# ---------------------------------------------------------------- skill book merge (in the bag)
## Lowest book grade with Defs.BOOK_MERGE copies in the bag that can still climb (0 = nothing to merge).
static func book_merge_grade(game: Node) -> int:
	var counts := {}
	for e in game.inventory:
		if e["kind"] == "skillbook":
			var g := book_grade(e)
			counts[g] = counts.get(g, 0) + 1
	for g in range(1, Defs.BOOK_TOP):
		if counts.get(g, 0) >= Defs.BOOK_MERGE:
			return g
	return 0

## A book that would complete a merge may still come into a full bag (the merge frees the room again).
static func completes_book_merge(game: Node, e: Dictionary) -> bool:
	var g := book_grade(e)
	if g >= Defs.BOOK_TOP:
		return false
	var n := 0
	for x in game.inventory:
		if x["kind"] == "skillbook" and book_grade(x) == g:
			n += 1
	return n + 1 >= Defs.BOOK_MERGE

## Bag indices a merge of grade-g books consumes (from the back of the bag).
static func book_sources(game: Node, g: int) -> Array:
	var out := []
	var i: int = game.inventory.size() - 1
	while i >= 0 and out.size() < Defs.BOOK_MERGE:
		var e: Dictionary = game.inventory[i]
		if e["kind"] == "skillbook" and book_grade(e) == g:
			out.append(i)
		i -= 1
	return out

## One book merge: Defs.BOOK_MERGE grade-g books leave the bag and one grade g+1 book takes the slot of the first.
static func merge_books_once(game: Node, g: int) -> Dictionary:
	var src := book_sources(game, g)
	if src.size() < Defs.BOOK_MERGE:
		return {}
	var at: int = src.min()
	for i in src:   # descending, so the earlier indices stay valid
		game.inventory.remove_at(i)
	var ne := make_skillbook(g + 1)
	game.inventory.insert(clampi(at, 0, game.inventory.size()), ne)
	return ne

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
