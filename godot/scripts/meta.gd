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
static var camp_since := 0       # unix seconds the campfire started piling up rewards (lobby [모닥불])
static var quick_day := ""       # local date ("YYYY-MM-DD") of the [빠른 정비] uses counted in quick_used
static var quick_used := 0
static var att_day := 0          # 7-day attendance: index (0..6) of the next day to claim; wraps back to 0 after day 7
static var att_date := ""        # local date of the last claim ("" = never)
static var gold_talents := {}    # GOLD_TALENTS id -> level (lobby [탤런트]: gold sink, random stat +1 per press)
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
	camp_since = _int(d.get("camp_since", 0))
	if camp_since <= 0 or camp_since > _now():   # older save (the fire is lit now) / a clock set back
		camp_since = _now()
	quick_day = str(d.get("quick_day", ""))
	quick_used = maxi(0, _int(d.get("quick_used", 0)))
	att_day = clampi(_int(d.get("att_day", 0)), 0, ATTEND.size() - 1)
	att_date = str(d.get("att_date", ""))
	raid_day = str(d.get("raid_day", ""))
	raid_used = maxi(0, _int(d.get("raid_used", 0)))
	raid_best = {}
	raid_tier = {}
	for k in _dict(d.get("raid_best", {})):
		raid_best[str(k)] = maxi(0, _int(d["raid_best"][k]))
	for k in _dict(d.get("raid_tier", {})):
		raid_tier[str(k)] = clampi(_int(d["raid_tier"][k]), 0, RAID_TIER_BARS.size())
	mis_day = str(d.get("mis_day", ""))
	mis_counts = _dict(d.get("mis_counts", {})).duplicate()
	mis_claimed = _arr(d.get("mis_claimed", [])).duplicate()
	mis_points = maxi(0, _int(d.get("mis_points", 0)))
	mis_boxes = _arr(d.get("mis_boxes", [])).map(func(v): return _int(v))
	mis_week = str(d.get("mis_week", ""))
	wk_counts = _dict(d.get("wk_counts", {})).duplicate()
	wk_claimed = _arr(d.get("wk_claimed", [])).duplicate()
	for dct in [mis_counts, wk_counts]:
		for k in dct.keys():
			dct[k] = _int(dct[k])
	var gt = d.get("gold_talents", {})
	for g in GOLD_TALENTS:
		gold_talents[g["id"]] = clampi(_int(_dict(gt).get(g["id"], 0)), 0, g["max"])
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
	camp_since = _now()
	quick_day = ""
	quick_used = 0
	att_day = 0
	att_date = ""
	mis_day = ""
	mis_counts = {}
	mis_claimed = []
	mis_points = 0
	mis_boxes = []
	mis_week = ""
	wk_counts = {}
	wk_claimed = []
	raid_day = ""
	raid_used = 0
	raid_best = {}
	raid_tier = {}
	gold_talents = {}
	for t in GOLD_TALENTS:
		gold_talents[t["id"]] = 0
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
		"storage": storage.map(Inventory.to_save), "run_gear": run_gear.map(Inventory.to_save), "kept_rest": kept_rest,
		"camp_since": camp_since, "quick_day": quick_day, "quick_used": quick_used, "att_day": att_day, "att_date": att_date,
		"gold_talents": gold_talents, "raid_day": raid_day, "raid_used": raid_used, "raid_best": raid_best, "raid_tier": raid_tier,
		"mis_day": mis_day, "mis_counts": mis_counts, "mis_claimed": mis_claimed, "mis_points": mis_points, "mis_boxes": mis_boxes,
		"mis_week": mis_week, "wk_counts": wk_counts, "wk_claimed": wk_claimed}))
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
	if cls == "":   # gold talents are party-wide (atk / hp multipliers reach each hero through Stats.talent_fx)
		for t in GOLD_TALENTS:
			var lv := gold_talent_level(t["id"])
			if lv > 0:
				out[t["stat"]] = out.get(t["stat"], 0.0) + t["per"] * lv
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
	track("gear_up")
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
		track("gear_up")
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
	track("chapter_clear")
	return first

# ---------------------------------------------------------------- campfire (idle rewards)
## The trio rests at the lobby campfire while the game is away: gold / 강화석 / time crystals pile up per minute
## (rates grow with the chapters cleared) for up to CAMP_MAX_MIN. [받기] banks the pile; [빠른 정비] hands over
## QUICK_MIN worth at once, QUICK_PER_DAY times a day (free for now: the ad / energy hook comes with the BM layer).
const CAMP_MAX_MIN := 720
const QUICK_MIN := 120
const QUICK_PER_DAY := 3

static func _now() -> int:
	return int(Time.get_unix_time_from_system())

static func _today() -> String:
	return Time.get_date_string_from_system()

## Per hour at the current progress: {"gold", "stones", "crystals"} (floats).
static func camp_rate() -> Dictionary:
	var m := 1.0 + float(fx("").get("campMult", 0.0))   # gold talent 야영 숙련
	return {"gold": (100.0 + 40.0 * cleared) * m, "stones": (3.0 + cleared) * m, "crystals": (1.0 + 0.5 * cleared) * m}

## Whole minutes piled up (a clock set back counts as none).
static func camp_minutes() -> int:
	return clampi((_now() - camp_since) / 60, 0, CAMP_MAX_MIN)

static func camp_full() -> bool:
	return camp_minutes() >= CAMP_MAX_MIN

## What `minutes` of rest is worth: {"gold", "stones", "crystals"} (ints).
static func camp_reward(minutes: int) -> Dictionary:
	var r := camp_rate()
	var out := {}
	for k in r:
		out[k] = int(floor(r[k] * minutes / 60.0))
	return out

static func _bank(r: Dictionary) -> void:
	gold += int(r.get("gold", 0))
	stones += int(r.get("stones", 0))
	crystals += int(r.get("crystals", 0))

## Bank the pile. The unpaid part of a started minute keeps counting; a full pile restarts from now.
## Returns what was given ({} when nothing had piled up yet).
static func claim_camp() -> Dictionary:
	var m := camp_minutes()
	var r := camp_reward(m)
	if r.values().all(func(v): return v <= 0):
		return {}
	_bank(r)
	camp_since = _now() if m >= CAMP_MAX_MIN or camp_since > _now() else camp_since + m * 60
	save()
	track("camp")
	return r

static func quick_left() -> int:
	return QUICK_PER_DAY - (quick_used if quick_day == _today() else 0)

## [빠른 정비]: QUICK_MIN of rest right now (the pile at the fire is untouched). {} when today's uses are gone.
static func quick_camp() -> Dictionary:
	if quick_left() <= 0:
		return {}
	if quick_day != _today():
		quick_day = _today()
		quick_used = 0
	quick_used += 1
	var r := camp_reward(QUICK_MIN)
	_bank(r)
	save()
	track("camp")
	return r

# ---------------------------------------------------------------- 7-day attendance
## One claim per local day, days 1..7 in order, then the table starts over at day 1. A missed day does not
## reset the cycle: the next visit simply claims the next day. Day 7 adds a gear piece (one grade above the
## chapter's usual roll) to the storage.
const ATTEND := [
	{"gold": 500},
	{"stones": 15},
	{"crystals": 20},
	{"gold": 1000},
	{"stones": 30},
	{"crystals": 40},
	{"gold": 1500, "stones": 30, "gear": 1},
]

static func can_attend() -> bool:
	return att_date == "" or _today() > att_date   # ISO dates compare as strings; a clock set back never re-opens a day

## Claim today's day. Returns {"day": 1..7, "reward": the ATTEND row, "gear": entry or null}, or {} if already claimed.
static func attend() -> Dictionary:
	if not can_attend():
		return {}
	var day := att_day
	var row: Dictionary = ATTEND[day]
	_bank(row)
	var gear = null
	if int(row.get("gear", 0)) > 0:
		var k := chapter_first_group(cleared)
		gear = Inventory.make_found(Gear.key(Gear.roll_family(k), Gear.roll_grade(k) + 1), k)
		storage.append(gear)
	att_day = (day + 1) % ATTEND.size()
	att_date = _today()
	save()
	return {"day": day + 1, "reward": row, "gear": gear}

# ---------------------------------------------------------------- gold talents
## Archero-style gold sink: [강화] pays gold_talent_cost() and raises one random (not maxed) talent by 1.
## The cost grows with the total level bought, so banked gold always has somewhere to go.
## stat: the Meta.fx("") key it adds to (campMult only feeds camp_rate); per: added per level.
const GOLD_TALENTS := [
	{"id": "gAtk", "name": "공격 훈련", "short": "공", "stat": "atkMult", "per": 0.01, "max": 50, "fmt": "공격력 +%s%%", "col": Color("ff7a5a")},
	{"id": "gHp", "name": "체력 단련", "short": "체", "stat": "hpMult", "per": 0.015, "max": 50, "fmt": "최대 체력 +%s%%", "col": Color("5fcf5a")},
	{"id": "gDef", "name": "철갑", "short": "방", "stat": "dmgReduce", "per": 0.004, "max": 30, "fmt": "받는 피해 -%s%%", "col": Color("6fa8ff")},
	{"id": "gCrit", "name": "날카로운 눈", "short": "치", "stat": "critChance", "per": 0.004, "max": 25, "fmt": "치명타 확률 +%s%%", "col": Color("ff5f9a")},
	{"id": "gGold", "name": "황금 손", "short": "금", "stat": "goldMult", "per": 0.02, "max": 25, "fmt": "적 처치 골드 +%s%%", "col": Color("ffd23f")},
	{"id": "gCamp", "name": "야영 숙련", "short": "불", "stat": "campMult", "per": 0.03, "max": 20, "fmt": "모닥불 보상 +%s%%", "col": Color("ff9f1c")},
]

static func gold_talent_level(id: String) -> int:
	return int(gold_talents.get(id, 0))

static func gold_talent_total() -> int:
	var n := 0
	for id in gold_talents:
		n += int(gold_talents[id])
	return n

static func gold_talent_def(id: String) -> Dictionary:
	for t in GOLD_TALENTS:
		if t["id"] == id:
			return t
	return {}

## "공격력 +5%" at level lv.
static func gold_talent_text(id: String, lv: int) -> String:
	var t := gold_talent_def(id)
	return t["fmt"] % str(snappedf(t["per"] * lv * 100.0, 0.1)).trim_suffix(".0")

## Gold for the next press (by the total level bought so far): 100, 140, 190, ... ~24k at level 100.
static func gold_talent_cost() -> int:
	var n := gold_talent_total()
	return int(roundf((100.0 + 40.0 * n + 2.0 * n * n) / 10.0) * 10.0)

## "" when [강화] can be pressed now, otherwise the reason ("max" / "gold").
static func can_gold_talent() -> String:
	if GOLD_TALENTS.all(func(t): return gold_talent_level(t["id"]) >= t["max"]):
		return "max"
	if gold < gold_talent_cost():
		return "gold"
	return ""

## Pay and raise one random unmaxed talent. Returns its id ("" when it could not be bought).
static func buy_gold_talent() -> String:
	if can_gold_talent() != "":
		return ""
	var open := GOLD_TALENTS.filter(func(t): return gold_talent_level(t["id"]) < t["max"])
	var t: Dictionary = open[randi() % open.size()]
	gold -= gold_talent_cost()
	gold_talents[t["id"]] = gold_talent_level(t["id"]) + 1
	_fx_cache.clear()
	save()
	track("talent")
	return t["id"]

# ---------------------------------------------------------------- boss raid (보스 토벌)
## RAID_TRIES a day (shared by every boss). A raid is RAID_TIME seconds against an endless boss line-up
## (Defs.RAID_BOSSES): each time the boss's bar empties it fills again, and the damage dealt sets the tier
## (RAID_TIER_BARS, in boss bars). Tier rewards bank at once; [소탕] replays a boss's best tier without fighting.
## The fight is tuned to the hardest chapter cleared (raid_chapter): hero start level / head start and boss numbers.
const RAID_TRIES := 3
const RAID_TIME := 90.0
const RAID_TIER_BARS := [0.25, 0.5, 1.0, 1.5, 2.5, 4.0, 6.0, 9.0, 13.0, 18.0, 25.0, 35.0, 50.0, 70.0, 100.0]
const RAID_HP := 4.0               # the raid line-up's bar is this many times the mid-boss's hp
static var raid := ""              # boss key picked in the lobby for the next March scene ("" = no raid)
static var raid_day := ""
static var raid_used := 0
static var raid_best := {}         # boss key -> best damage
static var raid_tier := {}         # boss key -> best tier (0 = never fought)

static func raid_chapter() -> int:
	return maxi(0, cleared - 1)

static func raid_left() -> int:
	return RAID_TRIES - (raid_used if raid_day == _today() else 0)

static func use_raid_try() -> bool:
	if raid_left() <= 0:
		return false
	if raid_day != _today():
		raid_day = _today()
		raid_used = 0
	raid_used += 1
	save()
	track("raid")
	return true

## Tier reached with `bars` boss bars of damage (0 = below the first tier).
static func raid_tier_of(bars: float) -> int:
	var t := 0
	for i in RAID_TIER_BARS.size():
		if bars >= RAID_TIER_BARS[i]:
			t = i + 1
	return t

## Rewards of tier t at the current raid chapter: {"gold", "stones", "crystals", "gear": count}.
static func raid_reward(t: int) -> Dictionary:
	if t <= 0:
		return {}
	var c := raid_chapter()
	return {"gold": (200 + 60 * c) * t, "stones": (4 + c) * t, "crystals": 3 * t, "gear": (1 if t >= 5 else 0) + (1 if t >= 8 else 0) + (1 if t >= 12 else 0)}

## Bank a tier's rewards (gear pieces go to the storage). Returns the reward with "items": [gear entries].
static func _grant_raid(t: int) -> Dictionary:
	var r := raid_reward(t)
	if r.is_empty():
		return {}
	_bank(r)
	var k := chapter_first_group(raid_chapter()) + Regions.PER_REGION - 1
	var items := []
	for i in int(r["gear"]):
		var e := Inventory.make_found(Gear.key(Gear.roll_family(k), Gear.roll_grade(k, true)), k)
		storage.append(e)
		items.append(e)
	r["items"] = items
	return r

## A raid ended with `dmg` damage worth `bars` bars. Returns {"tier", "best" (new record), "reward"}.
static func raid_finish(key: String, dmg: int, bars: float) -> Dictionary:
	var t := raid_tier_of(bars)
	var best := dmg > int(raid_best.get(key, 0))
	if best:
		raid_best[key] = dmg
	raid_tier[key] = maxi(int(raid_tier.get(key, 0)), t)
	var r := _grant_raid(t)
	save()
	return {"tier": t, "best": best, "reward": r}

## [소탕]: the boss's best tier again, for one of today's tries. {} when it can't.
static func raid_sweep(key: String) -> Dictionary:
	var t := int(raid_tier.get(key, 0))
	if t <= 0 or not use_raid_try():
		return {}
	var r := _grant_raid(t)
	save()
	return r

# ---------------------------------------------------------------- missions (일일 · 주간)
## Daily missions reset at local midnight, weekly ones on Monday. track(event) counts progress from wherever
## the thing happens (lobby, runs, raid). A finished daily mission is claimed for ACTIVITY points; the activity
## track opens DAILY_BOXES at 20 / 40 / 60 / 80 / 100. A finished weekly mission pays its reward directly.
## Events: run_start, raid, camp, talent, gear_up, group_clear, chapter_clear, daily_full.
const DAILY := [
	{"id": "run", "text": "원정 또는 행군 출발", "event": "run_start", "goal": 1},
	{"id": "raid", "text": "보스 토벌 도전 (소탕 포함)", "event": "raid", "goal": 1},
	{"id": "camp", "text": "모닥불 보상 받기", "event": "camp", "goal": 1},
	{"id": "talent", "text": "골드 탤런트 강화", "event": "talent", "goal": 1},
	{"id": "gear", "text": "장비 강화 또는 합성", "event": "gear_up", "goal": 1},
	{"id": "groups", "text": "적 무리 처치", "event": "group_clear", "goal": 15},
]
const ACTIVITY := 20           # points per claimed daily mission
const DAILY_BOXES := [
	{"at": 20, "reward": {"gold": 300}},
	{"at": 40, "reward": {"stones": 12}},
	{"at": 60, "reward": {"crystals": 15}},
	{"at": 80, "reward": {"gold": 800, "stones": 15}},
	{"at": 100, "reward": {"crystals": 30, "gear": 1}},
]
const WEEKLY := [
	{"id": "w_daily", "text": "활동 점수 100 달성 (일)", "event": "daily_full", "goal": 5, "reward": {"crystals": 100, "gear": 2}},
	{"id": "w_raid", "text": "보스 토벌 도전", "event": "raid", "goal": 10, "reward": {"crystals": 60, "gear": 1}},
	{"id": "w_clear", "text": "원정 챕터 클리어", "event": "chapter_clear", "goal": 5, "reward": {"gold": 3000, "stones": 60}},
	{"id": "w_groups", "text": "적 무리 처치", "event": "group_clear", "goal": 100, "reward": {"gold": 2000, "stones": 30}},
	{"id": "w_talent", "text": "골드 탤런트 강화", "event": "talent", "goal": 10, "reward": {"stones": 40, "crystals": 30}},
]
static var mis_day := ""          # local date the daily state belongs to
static var mis_counts := {}       # daily mission id -> progress
static var mis_claimed: Array = []   # daily mission ids claimed today
static var mis_points := 0        # today's activity points
static var mis_boxes: Array = []  # DAILY_BOXES indices opened today
static var mis_week := ""         # Monday (local date) the weekly state belongs to
static var wk_counts := {}
static var wk_claimed: Array = []

## Local date of this week's Monday ("YYYY-MM-DD").
static func _week_key() -> String:
	var d := Time.get_date_dict_from_system()
	var u := Time.get_unix_time_from_datetime_dict(d)   # the local date read as UTC midnight: fine for day steps
	return Time.get_date_string_from_unix_time(u - ((int(d["weekday"]) + 6) % 7) * 86400)

## Start a new day / week when the clock has moved on (called before every read or write).
static func _mis_roll() -> void:
	if mis_day != _today():
		mis_day = _today()
		mis_counts = {}
		mis_claimed = []
		mis_points = 0
		mis_boxes = []
	if mis_week != _week_key():
		mis_week = _week_key()
		wk_counts = {}
		wk_claimed = []

## Count `n` of `event` toward every daily and weekly mission that listens to it.
static func track(event: String, n := 1) -> void:
	_mis_roll()
	for m in DAILY:
		if m["event"] == event:
			mis_counts[m["id"]] = mini(int(m["goal"]), int(mis_counts.get(m["id"], 0)) + n)
	for m in WEEKLY:
		if m["event"] == event:
			wk_counts[m["id"]] = mini(int(m["goal"]), int(wk_counts.get(m["id"], 0)) + n)
	save()

static func mission_progress(id: String, weekly := false) -> int:
	_mis_roll()
	return int((wk_counts if weekly else mis_counts).get(id, 0))

static func _mission_def(id: String, weekly: bool) -> Dictionary:
	for m in (WEEKLY if weekly else DAILY):
		if m["id"] == id:
			return m
	return {}

## "claim" (done, not claimed), "done" (claimed) or "open".
static func mission_state(id: String, weekly := false) -> String:
	_mis_roll()
	var m := _mission_def(id, weekly)
	if (wk_claimed if weekly else mis_claimed).has(id):
		return "done"
	return "claim" if mission_progress(id, weekly) >= int(m.get("goal", 1)) else "open"

## Claim a finished mission: daily -> ACTIVITY points, weekly -> its reward. Returns the reward ({} if nothing).
static func claim_mission(id: String, weekly := false) -> Dictionary:
	if mission_state(id, weekly) != "claim":
		return {}
	if weekly:
		wk_claimed.append(id)
		var r := _grant(_mission_def(id, true)["reward"])
		save()
		return r
	mis_claimed.append(id)
	var before := mis_points
	mis_points = mini(DAILY_BOXES[-1]["at"], mis_points + ACTIVITY)
	if before < DAILY_BOXES[-1]["at"] and mis_points >= DAILY_BOXES[-1]["at"]:
		track("daily_full")   # saves
	else:
		save()
	return {"points": ACTIVITY}

## "claim" / "done" / "open" for activity box i.
static func box_state(i: int) -> String:
	_mis_roll()
	if mis_boxes.has(i):
		return "done"
	return "claim" if mis_points >= int(DAILY_BOXES[i]["at"]) else "open"

static func open_box(i: int) -> Dictionary:
	if box_state(i) != "claim":
		return {}
	mis_boxes.append(i)
	var r := _grant(DAILY_BOXES[i]["reward"])
	save()
	return r

## Anything to collect on the [미션] screen (lobby badge).
static func missions_ready() -> int:
	var n := 0
	for m in DAILY:
		if mission_state(m["id"]) == "claim":
			n += 1
	for m in WEEKLY:
		if mission_state(m["id"], true) == "claim":
			n += 1
	for i in DAILY_BOXES.size():
		if box_state(i) == "claim":
			n += 1
	return n

## Bank a reward dictionary (gold / stones / crystals, "gear": pieces of the current chapter's grade +1 into the
## storage). Returns it with "items": [gear entries].
static func _grant(reward: Dictionary) -> Dictionary:
	var r := reward.duplicate()
	_bank(r)
	var k := chapter_first_group(maxi(0, cleared - 1)) + Regions.PER_REGION - 1
	var items := []
	for i in int(r.get("gear", 0)):
		var e := Inventory.make_found(Gear.key(Gear.roll_family(k), Gear.roll_grade(k, true)), k)
		storage.append(e)
		items.append(e)
	r["items"] = items
	return r
