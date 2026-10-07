class_name Meta
extends RefCounted
## Permanent progression: time crystals, talent tree levels, legendary relics kept across runs.
## Saved to user://trio_save.json on every change.

static var path := "user://trio_save.json"

static var crystals := 0
static var talents := {}          # id -> level
static var relics: Array = []     # legendary relic keys
static var tutorial_done := false
static var best := {}             # mode -> best wave / group reached
static var _loaded := false

static func load_save() -> void:
	if _loaded:
		return
	_loaded = true
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
	var b = d.get("best", {})
	if typeof(b) == TYPE_DICTIONARY:
		for m in b:
			best[str(m)] = int(b[m])

static func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"crystals": crystals, "talents": talents, "relics": relics, "tutorial_done": tutorial_done, "best": best}))

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
