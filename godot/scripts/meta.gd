class_name Meta
extends RefCounted
## Permanent progression: time crystals, talent tree levels, the relic collection (lobby [유물]: worn relics apply
## to every run, three of the same relic at the same ★ merge into the next ★),
## and the Habby-style gear meta: banked gold and 강화석, permanent gear (storage + each hero's loadout),
## slot levels, and the expedition chapters cleared. Saved to user://trio_save.json on every change.
##
## Gear is permanent: whatever is worn or carried in the bag during a run is written back here as it
## changes (sync_run), so quitting mid-run never loses a piece; end_run banks the run's gold and 강화석.

static var path := "user://trio_save.json"

static var crystals := 0
static var talents := {}          # id -> level
static var relic_bag: Array = []  # relics owned but not worn: {id, kind "relic", key, star}
static var relic_slots: Array = []  # Defs.RELIC_SLOTS worn relics (entry or null): active in every run
static var tutorial_done := false
static var best := {}             # mode -> best wave / group reached
static var gold := 0              # banked gold (lobby: slot upgrades)
static var stones := 0            # banked 강화석
static var storage: Array = []    # permanent gear not worn: runtime entries (Inventory.from_save)
static var loadout := {}          # cls -> {slot -> entry | null}: what each hero starts a run wearing
static var slot_lv := {}          # cls -> {slot -> level}
static var run_gear: Array = []   # gear in the live run's bag (moved to storage when the run ends / on load)
static var kept_rest := {}       # cleared chapter's bag waiting on [다음 챕터]/[로비로]: {"books": [grades], "chests": [tiers], "k"}
                                 # (saved: if the game quits there, the next load banks it like the lobby would)
static var carry := {}
static var _settled := false           # bag handed from a cleared chapter to the next one: {inventory, chests, inv_cap} (memory only)
static var cleared := 0           # expedition chapters cleared (chapter c is open when c <= cleared)
static var chapter := 0           # chapter picked in the lobby
static var expedition := true    # lobby choice for the March scene: chapter expedition (true) or endless march
static var _loaded := false
static var _fx_cache := {}       # cls -> fx(cls) result; cleared whenever the talents change

const SLOTS := ["weapon", "armor", "accessory"]
## A fresh save starts each hero with a plain 일반 weapon.
const STARTER := {"warrior": "sword1", "ranger": "bow1", "mage": "staff1"}
const TMP_SUFFIX := ".tmp"

static func load_save() -> void:
	if _loaded:
		return
	_loaded = true
	_defaults()
	var d := _read_save(path)
	if d.is_empty():
		d = _read_save(path + TMP_SUFFIX)   # a save interrupted between writing the temp file and the swap
	if d.is_empty():
		return
	crystals = maxi(0, _int(d.get("crystals", 0)))
	var t = d.get("talents", {})
	if typeof(t) == TYPE_DICTIONARY:
		for id in t:
			var def := Defs.talent(str(id))
			if not def.is_empty():
				talents[str(id)] = clampi(_int(t[id]), 0, def["max"])
	var rs = d.get("relic_slots", null)
	for i in mini(_arr(rs).size(), Defs.RELIC_SLOTS):
		if _valid_relic(rs[i]):
			relic_slots[i] = _relic_from(rs[i])
	for x in _arr(d.get("relic_bag", [])):
		if _valid_relic(x):
			relic_bag.append(_relic_from(x))
	if typeof(rs) != TYPE_ARRAY:   # older save: the legendary relics that rode along in every run's bag are now worn
		for k in _arr(d.get("relics", [])):
			if Defs.RELICS.has(str(k)):
				var e := add_relic(str(k), 1, false)
				wear_relic(e, -1, false)
	tutorial_done = typeof(d.get("tutorial_done")) == TYPE_BOOL and d["tutorial_done"]
	gold = maxi(0, _int(d.get("gold", 0)))
	stones = maxi(0, _int(d.get("stones", 0)))
	cleared = maxi(0, _int(d.get("cleared", 0)))
	chapter = clampi(_int(d.get("chapter", 0)), 0, cleared)
	storage = []
	for x in _arr(d.get("storage", [])) + _arr(d.get("run_gear", [])):   # run_gear: a run that never ended (quit / crash) keeps its bag gear
		if _valid_gear(x):
			storage.append(Inventory.from_save(x))
	run_gear = []
	_settled = false
	_settle_kept_rest(_dict(d.get("kept_rest", {})))
	var lo = d.get("loadout", null)
	var sl = d.get("slot_lv", {})
	for cls in Defs.HERO_ORDER:
		var lo_c := _dict(_dict(lo).get(cls, {}))
		var sl_c := _dict(_dict(sl).get(cls, {}))
		for slot in SLOTS:
			var x = lo_c.get(slot, null)
			loadout[cls][slot] = Inventory.from_save(x) if _valid_gear(x) else null
			slot_lv[cls][slot] = maxi(0, _int(sl_c.get(slot, 0)))
	if typeof(lo) != TYPE_DICTIONARY:
		_starter_kit()
	var b = d.get("best", {})
	if typeof(b) == TYPE_DICTIONARY:
		for m in b:
			best[str(m)] = _int(b[m])
	if _settled:
		_settled = false
		save()

## The parsed save at `p`, or {} when it is missing / unreadable / not a JSON object.
static func _read_save(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if typeof(d) == TYPE_DICTIONARY else {}

# Save-file field coercion: a hand-edited / older / corrupt save never crashes the load.
static func _int(v) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_BOOL, TYPE_STRING] else 0

static func _arr(v) -> Array:
	return v if typeof(v) == TYPE_ARRAY else []

static func _dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

static func _valid_gear(x) -> bool:
	return typeof(x) == TYPE_DICTIONARY and not Defs.item(str(x.get("key", ""))).is_empty()

static func _valid_relic(x) -> bool:
	return typeof(x) == TYPE_DICTIONARY and Defs.RELICS.has(str(x.get("key", "")))

static func _relic_from(x: Dictionary) -> Dictionary:
	return Inventory.make_relic(str(x["key"]), clampi(_int(x.get("star", 1)), 1, Defs.RELIC_MAX_STAR))

static func _relic_save(e) -> Variant:
	return {"key": e["key"], "star": int(e.get("star", 1))} if e else null

static func _defaults() -> void:
	crystals = 0
	talents = {}
	relic_bag = []
	relic_slots = []
	relic_slots.resize(Defs.RELIC_SLOTS)
	tutorial_done = false
	best = {}
	gold = 0
	stones = 0
	storage = []
	run_gear = []
	cleared = 0
	chapter = 0
	loadout = {}
	slot_lv = {}
	_fx_cache.clear()
	for cls in Defs.HERO_ORDER:
		loadout[cls] = {}
		slot_lv[cls] = {}
		for slot in SLOTS:
			loadout[cls][slot] = null
			slot_lv[cls][slot] = 0
	_starter_kit()

static func _starter_kit() -> void:
	for cls in STARTER:
		if loadout.has(cls) and loadout[cls].get("weapon") == null:
			loadout[cls]["weapon"] = Inventory.make("equip", STARTER[cls])

## Written to a temp file first and swapped in, so a crash / power loss mid-write never leaves a truncated save.
static func save() -> void:
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	var lo := {}
	for cls in loadout:
		lo[cls] = {}
		for slot in loadout[cls]:
			var e = loadout[cls][slot]
			lo[cls][slot] = Inventory.to_save(e) if e else null
	f.store_string(JSON.stringify({"crystals": crystals, "talents": talents, "relic_slots": relic_slots.map(_relic_save), "relic_bag": relic_bag.map(_relic_save), "tutorial_done": tutorial_done,
		"best": best, "gold": gold, "stones": stones, "cleared": cleared, "chapter": chapter, "slot_lv": slot_lv, "loadout": lo,
		"storage": storage.map(Inventory.to_save), "run_gear": run_gear.map(Inventory.to_save), "kept_rest": kept_rest}))
	var ok := f.get_error() == OK
	f.close()
	if ok:
		DirAccess.rename_absolute(tmp, path)

static func record_best(mode: String, value: int) -> void:
	if value > int(best.get(mode, 0)):
		best[mode] = value
		save()

static func level(id: String) -> int:
	return int(talents.get(id, 0))

static func has_flag(id: String) -> bool:
	return level(id) > 0

static func add_crystals(n: int) -> void:
	crystals += n
	save()

## "" if buyable, otherwise a reason string.
static func can_buy(id: String) -> String:
	var def := Defs.talent(id)
	var lv := level(id)
	if lv >= def["max"]:
		return "max"
	for r in def["req"]:
		if level(r) < Defs.talent(r)["max"]:
			return "locked"
	var cost: int = def["costs"][lv]
	if crystals < cost:
		return "crystal"
	return ""

static func buy(id: String) -> bool:
	if can_buy(id) != "":
		return false
	var def := Defs.talent(id)
	crystals -= int(def["costs"][level(id)])
	talents[id] = level(id) + 1
	_fx_cache.clear()
	save()
	return true

## Sum of talent effects. cls == "" -> nodes without a class; otherwise only that class's nodes.
## Cached (Stats asks for it several times per unit per frame) and read-only: callers copy before changing it.
static func fx(cls: String) -> Dictionary:
	if _fx_cache.has(cls):
		return _fx_cache[cls]
	var out := {}
	for t in Defs.TALENTS:
		if not t.has("fx"):
			continue
		if t.get("cls", "") != cls:
			continue
		var lv := level(t["id"])
		if lv <= 0:
			continue
		for k in t["fx"]:
			out[k] = out.get(k, 0.0) + t["fx"][k] * lv
	out.make_read_only()
	_fx_cache[cls] = out
	return out

# ---------------------------------------------------------------- permanent gear
static func storage_entries() -> Array:
	return storage

static func slot_level(cls: String, slot: String) -> int:
	return int(slot_lv.get(cls, {}).get(slot, 0))

static func worn(cls: String, slot: String):
	return loadout.get(cls, {}).get(slot, null)

## Lobby: put a storage piece on a hero (the piece it replaces goes back to storage).
static func wear(cls: String, e: Dictionary) -> void:
	var slot: String = Defs.item(e["key"]).get("slot", "")
	if slot == "" or not storage.has(e):
		return
	storage.erase(e)
	var old = loadout[cls][slot]
	if old:
		storage.append(old)
	loadout[cls][slot] = e
	save()

static func take_off(cls: String, slot: String) -> void:
	var e = loadout[cls][slot]
	if e == null:
		return
	loadout[cls][slot] = null
	storage.append(e)
	save()

## "" when slot (cls, slot) can be raised one level now, otherwise the reason.
static func can_upgrade(cls: String, slot: String) -> String:
	var lv := slot_level(cls, slot)
	var e = worn(cls, slot)
	if e == null:
		return "empty"
	if lv >= Gear.slot_cap(e):
		return "cap"
	var c := Gear.upgrade_cost(lv)
	if gold < int(c["gold"]):
		return "gold"
	if stones < int(c["stones"]):
		return "stones"
	return ""

static func upgrade(cls: String, slot: String) -> bool:
	if can_upgrade(cls, slot) != "":
		return false
	var c := Gear.upgrade_cost(slot_level(cls, slot))
	gold -= int(c["gold"])
	stones -= int(c["stones"])
	slot_lv[cls][slot] = slot_level(cls, slot) + 1
	save()
	return true

## Merge every group of 3 in the storage (same rules as the old bag merge: family gear by slot + grade climbs
## one grade, the family taken from one of the three materials; uniques need 3 of the exact item). Worn
## gear is never material. Returns the merge steps in order: {"in": [3 materials], "out": result} (MergeFx plays them).
static func merge_all() -> Array:
	var made := []
	var k := _find_merge()
	while k != "":
		made.append(_merge_once(k))
		k = _find_merge()
	if not made.is_empty():
		save()
	return made

## Groups in storage that already hold 3 or more (what [합성] would do right now).
static func merge_ready() -> int:
	var counts := {}
	for e in storage:
		var mk := Inventory.merge_key(e)
		if mk != "" and Inventory.merge_result(mk) != "":
			counts[mk] = counts.get(mk, 0) + 1
	var n := 0
	for mk in counts:
		n += int(counts[mk] / 3)
	return n

static func _find_merge() -> String:
	var counts := {}
	for e in storage:
		var mk := Inventory.merge_key(e)
		if mk != "":
			counts[mk] = counts.get(mk, 0) + 1
	# lowest grade first so a chain (3 일반 -> 고급 that completes 3 고급) resolves in one press
	var pick := ""
	var pick_g := 999
	for mk in counts:
		if counts[mk] >= 3 and Inventory.merge_result(mk) != "":
			var g := Gear.group_grade(mk) if Gear.is_group(mk) else 50
			if g < pick_g:
				pick_g = g
				pick = mk
	return pick

static func _merge_once(mk: String) -> Dictionary:
	var used := []
	for e in storage:
		if Inventory.merge_key(e) == mk and used.size() < 3:
			used.append(e)
	var pw := 1.0
	for e in used:
		storage.erase(e)
		pw = maxf(pw, float(e.get("pw", 1.0)))
	var result := Inventory.merge_result(mk)
	if Gear.is_group(mk):
		var mat: Dictionary = used[randi() % used.size()]
		result = Gear.key(Gear.family_of(mat["key"]), Gear.group_grade(mk) + 1)
	var ne := Inventory.make("equip", result)
	if pw > 1.0:
		ne["pw"] = pw
	storage.append(ne)
	return {"in": used, "out": ne}

## Sell a storage piece for banked gold.
static func sell(e: Dictionary) -> int:
	if not storage.has(e):
		return 0
	var price := int(Inventory.sell_price(null, e))
	storage.erase(e)
	gold += price
	save()
	return price

# ---------------------------------------------------------------- relics
## A relic found in a run (or anywhere) goes straight into the collection. Returns the new entry.
static func add_relic(key: String, star := 1, do_save := true) -> Dictionary:
	var e := Inventory.make_relic(key, star)
	relic_bag.append(e)
	if do_save:
		save()
	return e

## Worn relics (the run applies these).
static func worn_relics() -> Array:
	return relic_slots.filter(func(e): return e != null)

## Wear a collection relic in slot i (-1: the slot already holding the same relic, else the first empty one).
## The relic it replaces goes back to the collection. Returns the slot used, or -1 when every slot is taken.
static func wear_relic(e: Dictionary, i := -1, do_save := true) -> int:
	if not relic_bag.has(e):
		return -1
	if i < 0:
		for j in relic_slots.size():   # the same relic is never worn twice: a stronger copy swaps in
			if relic_slots[j] and relic_slots[j]["key"] == e["key"]:
				i = j
				break
	if i < 0:
		i = relic_slots.find(null)
	if i < 0:
		return -1
	for j in relic_slots.size():
		if j != i and relic_slots[j] and relic_slots[j]["key"] == e["key"]:
			return -1
	relic_bag.erase(e)
	if relic_slots[i]:
		relic_bag.append(relic_slots[i])
	relic_slots[i] = e
	if do_save:
		save()
	return i

static func take_off_relic(i: int) -> void:
	if i < 0 or i >= relic_slots.size() or relic_slots[i] == null:
		return
	relic_bag.append(relic_slots[i])
	relic_slots[i] = null
	save()

static func _relic_mk(e: Dictionary) -> String:
	var st := int(e.get("star", 1))
	return "%s#%d" % [e["key"], st] if st < Defs.RELIC_MAX_STAR else ""

## Groups of 3 (same relic, same ★) in the collection right now. Worn relics are never material.
static func relic_merge_ready() -> int:
	var counts := {}
	for e in relic_bag:
		var mk := _relic_mk(e)
		if mk != "":
			counts[mk] = counts.get(mk, 0) + 1
	var n := 0
	for mk in counts:
		n += int(counts[mk] / 3)
	return n

## Merge every group of 3 in the collection (lowest ★ first, so chains resolve in one press).
## Returns the merge steps in order: {"in": [3 materials], "out": result}.
static func merge_all_relics() -> Array:
	var made := []
	while true:
		var counts := {}
		for e in relic_bag:
			var mk := _relic_mk(e)
			if mk != "":
				counts[mk] = counts.get(mk, 0) + 1
		var pick := ""
		var pick_s := 999
		for mk in counts:
			var st := int(mk.get_slice("#", 1))
			if counts[mk] >= 3 and st < pick_s:
				pick_s = st
				pick = mk
		if pick == "":
			break
		var used := []
		for e in relic_bag:
			if _relic_mk(e) == pick and used.size() < 3:
				used.append(e)
		for e in used:
			relic_bag.erase(e)
		var ne := Inventory.make_relic(pick.get_slice("#", 0), pick_s + 1)
		relic_bag.append(ne)
		made.append({"in": used, "out": ne})
	if not made.is_empty():
		save()
	return made

static func relic_sell_price(e: Dictionary) -> int:
	return int(Defs.RELICS[e["key"]]["price"] * 0.25 * Defs.relic_mult(int(e.get("star", 1))))

static func sell_relic(e: Dictionary) -> int:
	if not relic_bag.has(e):
		return 0
	var price := relic_sell_price(e)
	relic_bag.erase(e)
	gold += price
	save()
	return price

# ---------------------------------------------------------------- runs
## Write the live run's permanent gear: each hero's worn pieces become the loadout, bag gear is run_gear.
static func sync_run(game: Node) -> void:
	for h in game.heroes:
		if not loadout.has(h.cls):
			continue
		for slot in SLOTS:
			loadout[h.cls][slot] = h.equipment.get(slot, null)
	run_gear = game.inventory.filter(func(e): return e.get("kind", "") == "equip")
	save()

## The run is over: its bag gear joins the storage, its gold and 강화석 are banked.
## keep_bag (chapter cleared, next chapter may follow): the bag gear stays run_gear — still saved, so quitting
## here sends it to the storage on the next load — and moves to the storage only on the way back to the lobby.
static func end_run(game: Node, run_gold: int, run_stones: int, keep_bag := false) -> void:
	sync_run(game)
	if not keep_bag:
		storage.append_array(run_gear)
		run_gear = []
	gold += maxi(0, run_gold)
	stones += maxi(0, run_stones)
	save()

## Leftover-book 강화석 by book grade (run end / lobby tidy-up).
const BOOK_STONES := {1: 1, 2: 3, 3: 6, 4: 12}

## The game quit on a cleared chapter's settlement screen before [다음 챕터] / [로비로]: bank the kept bag's
## skill books and unopened chests now, as the lobby would have (its gear already came back through run_gear).
static func _settle_kept_rest(r: Dictionary) -> void:
	kept_rest = {}
	if r.is_empty():
		return
	for g in _arr(r.get("books", [])):
		stones += int(BOOK_STONES.get(_int(g), 1))
	for t in _arr(r.get("chests", [])):
		var c := ChestLoot.roll(null, maxi(1, _int(r.get("k", 1))), clampi(_int(t), 0, ChestLoot.ITEMS.size() - 1))
		gold += int(c["gold"])
		for e in c["items"]:
			match e["kind"]:
				"equip": storage.append(e)
				"stone": stones += int(e["n"])
				"skillbook": stones += int(BOOK_STONES.get(Inventory.book_grade(e), 1))
	print("[Meta] settled a kept bag left on quit: books=", _arr(r.get("books", [])).size(), " chests=", _arr(r.get("chests", [])).size())
	_settled = true   # load_save saves once every other field is loaded

# ---------------------------------------------------------------- expedition chapters
## Chapter c (0-based) = march groups c*10+1 .. c*10+10 (Regions.PER_REGION), the region (c % 6) on lap c / 6.
static func chapter_first_group(c: int) -> int:
	return c * Regions.PER_REGION + 1

static func chapter_name(c: int) -> String:
	var r: Dictionary = Regions.info(c)
	var lap := Regions.lap(c)
	return "%d. %s%s" % [c + 1, r["name"], "" if lap == 0 else " (%d회차)" % (lap + 1)]

static func on_chapter_cleared(c: int) -> bool:
	var first := c >= cleared
	if first:
		cleared = c + 1
	chapter = mini(c + 1, cleared)
	save()
	return first
