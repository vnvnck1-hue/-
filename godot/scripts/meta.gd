class_name Meta
extends RefCounted
## Permanent progression: time crystals, talent tree levels, legendary relics kept across runs,
## and the Habby-style gear meta: banked gold and 강화석, permanent gear (storage + each hero's loadout),
## slot levels, and the expedition chapters cleared. Saved to user://trio_save.json on every change.
##
## Gear is permanent: whatever is worn or carried in the bag during a run is written back here as it
## changes (sync_run), so quitting mid-run never loses a piece; end_run banks the run's gold and 강화석.

static var path := "user://trio_save.json"

static var crystals := 0
static var talents := {}          # id -> level
static var relics: Array = []     # legendary relic keys
static var tutorial_done := false
static var best := {}             # mode -> best wave / group reached
static var gold := 0              # banked gold (lobby: slot upgrades)
static var stones := 0            # banked 강화석
static var storage: Array = []    # permanent gear not worn: runtime entries (Inventory.from_save)
static var loadout := {}          # cls -> {slot -> entry | null}: what each hero starts a run wearing
static var slot_lv := {}          # cls -> {slot -> level}
static var run_gear: Array = []   # gear in the live run's bag (moved to storage when the run ends / on load)
static var cleared := 0           # expedition chapters cleared (chapter c is open when c <= cleared)
static var chapter := 0           # chapter picked in the lobby
static var expedition := true    # lobby choice for the March scene: chapter expedition (true) or endless march
static var _loaded := false

const SLOTS := ["weapon", "armor", "accessory"]
## A fresh save starts each hero with a plain 일반 weapon.
const STARTER := {"warrior": "sword1", "ranger": "bow1", "mage": "staff1"}

static func load_save() -> void:
	if _loaded:
		return
	_loaded = true
	_defaults()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return
	crystals = maxi(0, int(d.get("crystals", 0)))
	var t: Dictionary = d.get("talents", {})
	for id in t:
		var def := Defs.talent(id)
		if not def.is_empty():
			talents[id] = clampi(int(t[id]), 0, def["max"])
	relics = []
	for k in d.get("relics", []):
		if Defs.RELICS.has(k) and Defs.RELICS[k]["rarity"] == "legendary":
			relics.append(k)
	tutorial_done = bool(d.get("tutorial_done", false))
	gold = maxi(0, int(d.get("gold", 0)))
	stones = maxi(0, int(d.get("stones", 0)))
	cleared = maxi(0, int(d.get("cleared", 0)))
	chapter = clampi(int(d.get("chapter", 0)), 0, cleared)
	storage = []
	for x in d.get("storage", []):
		if typeof(x) == TYPE_DICTIONARY and not Defs.item(str(x.get("key", ""))).is_empty():
			storage.append(Inventory.from_save(x))
	for x in d.get("run_gear", []):   # a run that never ended (quit / crash): its bag gear is kept
		if typeof(x) == TYPE_DICTIONARY and not Defs.item(str(x.get("key", ""))).is_empty():
			storage.append(Inventory.from_save(x))
	run_gear = []
	var lo = d.get("loadout", null)
	var sl = d.get("slot_lv", {})
	for cls in Defs.HERO_ORDER:
		loadout[cls] = {}
		slot_lv[cls] = {}
		for slot in SLOTS:
			var x = lo.get(cls, {}).get(slot, null) if typeof(lo) == TYPE_DICTIONARY else null
			loadout[cls][slot] = Inventory.from_save(x) if typeof(x) == TYPE_DICTIONARY and not Defs.item(str(x.get("key", ""))).is_empty() else null
			slot_lv[cls][slot] = maxi(0, int(sl.get(cls, {}).get(slot, 0))) if typeof(sl) == TYPE_DICTIONARY else 0
	if typeof(lo) != TYPE_DICTIONARY:
		_starter_kit()
	var b = d.get("best", {})
	if typeof(b) == TYPE_DICTIONARY:
		for m in b:
			best[str(m)] = int(b[m])

static func _defaults() -> void:
	gold = 0
	stones = 0
	storage = []
	run_gear = []
	cleared = 0
	chapter = 0
	loadout = {}
	slot_lv = {}
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

static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	var lo := {}
	for cls in loadout:
		lo[cls] = {}
		for slot in loadout[cls]:
			var e = loadout[cls][slot]
			lo[cls][slot] = Inventory.to_save(e) if e else null
	f.store_string(JSON.stringify({"crystals": crystals, "talents": talents, "relics": relics, "tutorial_done": tutorial_done,
		"best": best, "gold": gold, "stones": stones, "cleared": cleared, "chapter": chapter, "slot_lv": slot_lv, "loadout": lo,
		"storage": storage.map(Inventory.to_save), "run_gear": run_gear.map(Inventory.to_save)}))

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
	save()
	return true

## Sum of talent effects. cls == "" -> nodes without a class; otherwise only that class's nodes.
static func fx(cls: String) -> Dictionary:
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
## gear is never material. Returns the produced entries.
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
	var best := ""
	var best_g := 999
	for mk in counts:
		if counts[mk] >= 3 and Inventory.merge_result(mk) != "":
			var g := Gear.group_grade(mk) if Gear.is_group(mk) else 50
			if g < best_g:
				best_g = g
				best = mk
	return best

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
	return ne

## Sell a storage piece for banked gold.
static func sell(e: Dictionary) -> int:
	if not storage.has(e):
		return 0
	var price := int(Inventory.sell_price(null, e))
	storage.erase(e)
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
static func end_run(game: Node, run_gold: int, run_stones: int) -> void:
	sync_run(game)
	storage.append_array(run_gear)
	run_gear = []
	gold += maxi(0, run_gold)
	stones += maxi(0, run_stones)
	save()

# ---------------------------------------------------------------- expedition chapters
## Chapter c (0-based) = march groups c*10+1 .. c*10+10 (Regions.PER_REGION), the region (c % 6) on lap c / 6.
static func chapter_first_group(c: int) -> int:
	return c * Regions.PER_REGION + 1

static func chapter_name(c: int) -> String:
	var r: Dictionary = Regions.info(c)
	var lap := c / Regions.LIST.size()
	return "%d. %s%s" % [c + 1, r["name"], "" if lap == 0 else " (%d회차)" % (lap + 1)]

static func on_chapter_cleared(c: int) -> bool:
	var first := c >= cleared
	if first:
		cleared = c + 1
	chapter = mini(c + 1, cleared)
	save()
	return first
