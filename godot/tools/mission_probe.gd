extends SceneTree
## Headless check of the daily / weekly missions and the activity boxes on a throwaway save:
##   Godot --headless --path . -s res://tools/mission_probe.gd

func _init() -> void:
	Meta.path = "user://trio_save_mission_probe.json"
	for p in [Meta.path, Meta.path + Meta.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Meta.load_save()
	var ok := true
	ok = _check("fresh: nothing to collect", Meta.missions_ready() == 0 and Meta.mission_state("run") == "open") and ok
	Meta.track("run_start")
	ok = _check("run start finishes the daily mission", Meta.mission_state("run") == "claim" and Meta.missions_ready() == 1) and ok
	ok = _check("claim gives activity", Meta.claim_mission("run").get("points", 0) == Meta.ACTIVITY and Meta.mis_points == 20) and ok
	ok = _check("claimed once only", Meta.mission_state("run") == "done" and Meta.claim_mission("run").is_empty()) and ok
	var g0 := Meta.gold
	ok = _check("box 1 opens at 20", Meta.box_state(0) == "claim" and Meta.open_box(0).get("gold", 0) == 300 and Meta.gold == g0 + 300) and ok
	ok = _check("box 2 locked", Meta.box_state(1) == "open" and Meta.open_box(1).is_empty()) and ok
	Meta.track("group_clear", 7)
	ok = _check("partial progress", Meta.mission_progress("groups") == 7 and Meta.mission_state("groups") == "open") and ok
	Meta.track("group_clear", 50)
	ok = _check("progress caps at the goal", Meta.mission_progress("groups") == 15 and Meta.mission_progress("w_groups", true) == 57) and ok
	# real hooks
	Meta.camp_since -= 3600
	Meta.claim_camp()
	Meta.gold += 100000
	Meta.buy_gold_talent()
	Meta.use_raid_try()
	ok = _check("camp / talent / raid hooks", Meta.mission_state("camp") == "claim" and Meta.mission_state("talent") == "claim" and Meta.mission_state("raid") == "claim") and ok
	for id in ["groups", "camp", "talent", "raid"]:
		Meta.claim_mission(id)
	ok = _check("100 points counts one weekly day", Meta.mis_points == 100 and Meta.mission_progress("w_daily", true) == 1) and ok
	var st := Meta.storage.size()
	Meta.open_box(4)
	ok = _check("box 5 adds a gear piece", Meta.storage.size() == st + 1) and ok
	Meta.wk_counts["w_raid"] = 10
	var c0 := Meta.crystals
	var r := Meta.claim_mission("w_raid", true)
	ok = _check("weekly pays its reward", r.get("crystals", 0) == 60 and Meta.crystals == c0 + 60 and Meta.mission_state("w_raid", true) == "done") and ok
	Meta.save()
	Meta._loaded = false
	Meta.load_save()
	ok = _check("save round trip", Meta.mis_points == 100 and Meta.mission_state("run") == "done" and Meta.mission_state("w_raid", true) == "done" and Meta.mission_progress("w_groups", true) == 57) and ok
	Meta.mis_day = "2000-01-01"
	ok = _check("new day resets dailies", Meta.mission_state("run") == "open" and Meta.mis_points == 0 and Meta.box_state(0) == "open") and ok
	ok = _check("weekly survives the day", Meta.mission_state("w_raid", true) == "done") and ok
	Meta.mis_week = "2000-01-03"
	ok = _check("new week resets weeklies", Meta.mission_state("w_raid", true) == "open" and Meta.mission_progress("w_groups", true) == 0) and ok
	ok = _check("week key is a Monday", Time.get_datetime_dict_from_unix_time(Time.get_unix_time_from_datetime_string(Meta._week_key()))["weekday"] == 1) and ok
	print("[Mission] ", "ALL OK" if ok else "FAILED")
	quit(0 if ok else 1)

func _check(what: String, cond: bool) -> bool:
	print("[Mission] ", "ok   " if cond else "FAIL ", what)
	return cond
