extends SceneTree
## Headless check of the boss raid bookkeeping (tries, tiers, records, sweep) on a throwaway save:
##   Godot --headless --path . -s res://tools/raid_probe.gd

func _init() -> void:
	Meta.path = "user://trio_save_raid_probe.json"
	for p in [Meta.path, Meta.path + Meta.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Meta.load_save()
	var ok := true
	ok = _check("six raid bosses, each with a line-up", Defs.RAID_BOSSES.size() == 6 and Defs.RAID_BOSSES.all(func(b): return not Defs.boss_lineup(b["key"]).is_empty())) and ok
	ok = _check("murlocs come as three", Defs.boss_lineup("murlocs").size() == 3) and ok
	ok = _check("every region has a boss", range(Regions.count()).all(func(r): return not Defs.raid_boss(Regions.info(r).get("boss", "")).is_empty())) and ok
	ok = _check("tier ladder", Meta.raid_tier_of(0.1) == 0 and Meta.raid_tier_of(0.25) == 1 and Meta.raid_tier_of(3.0) == 5 and Meta.raid_tier_of(1000.0) == Meta.RAID_TIER_BARS.size()) and ok
	ok = _check("no record: no sweep", Meta.raid_sweep("spider").is_empty() and Meta.raid_left() == Meta.RAID_TRIES) and ok
	ok = _check("a try is spent", Meta.use_raid_try() and Meta.raid_left() == Meta.RAID_TRIES - 1) and ok
	var g0 := Meta.gold
	var st := Meta.storage.size()
	var r := Meta.raid_finish("spider", 12345, 4.2)
	ok = _check("finish: tier 6, record, gold and a gear piece", r["tier"] == 6 and r["best"] and Meta.gold > g0 and Meta.storage.size() == st + 1) and ok
	r = Meta.raid_finish("spider", 100, 0.3)
	ok = _check("a weaker run keeps the best", not r["best"] and Meta.raid_best["spider"] == 12345 and Meta.raid_tier["spider"] == 6) and ok
	var sw := Meta.raid_sweep("spider")
	ok = _check("sweep pays the best tier for a try", sw.get("gold", 0) == Meta.raid_reward(6)["gold"] and Meta.raid_left() == Meta.RAID_TRIES - 2) and ok
	Meta.use_raid_try()
	ok = _check("tries run out", Meta.raid_left() == 0 and not Meta.use_raid_try() and Meta.raid_sweep("spider").is_empty()) and ok
	Meta.raid_day = "2000-01-01"
	ok = _check("tries refill on a new day", Meta.raid_left() == Meta.RAID_TRIES) and ok
	Meta.save()
	Meta._loaded = false
	Meta.load_save()
	ok = _check("save round trip", Meta.raid_best.get("spider", 0) == 12345 and Meta.raid_tier.get("spider", 0) == 6 and Meta.raid_day == "2000-01-01") and ok
	print("[Raid] ", "ALL OK" if ok else "FAILED")
	quit(0 if ok else 1)

func _check(what: String, cond: bool) -> bool:
	print("[Raid] ", "ok   " if cond else "FAIL ", what)
	return cond
