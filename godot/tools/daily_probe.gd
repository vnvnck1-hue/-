extends SceneTree
## Headless check of the lobby daily pair (campfire idle rewards, 7-day attendance) on a throwaway save:
##   Godot --headless --path . -s res://tools/daily_probe.gd

func _init() -> void:
	Meta.path = "user://trio_save_daily_probe.json"
	for p in [Meta.path, Meta.path + Meta.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Meta.load_save()
	var ok := true
	# campfire
	ok = _check("fresh fire is empty", Meta.camp_minutes() == 0 and Meta.claim_camp().is_empty()) and ok
	Meta.camp_since -= 90 * 60 + 30
	var g0 := Meta.gold
	var r := Meta.claim_camp()
	ok = _check("90 min pays 1.5 h of gold", r.get("gold", 0) == 150 and Meta.gold == g0 + 150) and ok
	ok = _check("the started minute keeps counting", Meta._now() - Meta.camp_since == 30) and ok
	Meta.camp_since -= 30 * 3600
	ok = _check("pile caps at 12 h", Meta.camp_minutes() == Meta.CAMP_MAX_MIN and Meta.camp_full()) and ok
	Meta.claim_camp()
	ok = _check("full pile restarts from now", Meta.camp_minutes() == 0) and ok
	Meta.camp_since = Meta._now() + 3600
	ok = _check("clock set back counts as none", Meta.camp_minutes() == 0) and ok
	for i in Meta.QUICK_PER_DAY:
		ok = _check("quick patrol %d" % (i + 1), Meta.quick_camp().get("gold", 0) == 200) and ok
	ok = _check("quick patrol used up", Meta.quick_left() == 0 and Meta.quick_camp().is_empty()) and ok
	Meta.quick_day = "2000-01-01"
	ok = _check("quick patrol refills on a new day", Meta.quick_left() == Meta.QUICK_PER_DAY) and ok
	# attendance
	ok = _check("first visit can claim", Meta.can_attend()) and ok
	var st := Meta.storage.size()
	for d in 7:
		var a := Meta.attend()
		ok = _check("day %d claimed" % (d + 1), a.get("day", 0) == d + 1) and ok
		ok = _check("one claim a day", not Meta.can_attend() and Meta.attend().is_empty()) and ok
		Meta.att_date = "2000-01-01"   # next day
	ok = _check("day 7 adds a gear piece", Meta.storage.size() == st + 1) and ok
	ok = _check("cycle wraps to day 1", Meta.att_day == 0 and Meta.attend().get("day", 0) == 1) and ok
	Meta.att_date = "2999-01-01"
	ok = _check("a clock set back never reopens a day", not Meta.can_attend()) and ok
	# save round trip
	Meta.att_date = "2000-01-02"
	Meta.camp_since = Meta._now() + 3600   # a fire lit "in the future" (clock set back) is relit on load
	Meta.save()
	Meta._loaded = false
	Meta.load_save()
	ok = _check("future fire relit on load", Meta.camp_since <= Meta._now()) and ok
	Meta.camp_since = Meta._now() - 600
	Meta.save()
	var since := Meta.camp_since
	Meta._loaded = false
	Meta.load_save()
	ok = _check("save round trip", Meta.att_day == 1 and Meta.att_date == "2000-01-02" and Meta.camp_since == since and Meta.quick_day == "2000-01-01") and ok
	print("[Daily] ", "ALL OK" if ok else "FAILED")
	quit(0 if ok else 1)

func _check(what: String, cond: bool) -> bool:
	print("[Daily] ", "ok   " if cond else "FAIL ", what)
	return cond
