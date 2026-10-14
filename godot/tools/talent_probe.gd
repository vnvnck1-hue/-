extends SceneTree
## Headless check of the lobby gold talents on a throwaway save:
##   Godot --headless --path . -s res://tools/talent_probe.gd

func _init() -> void:
	Meta.path = "user://trio_save_talent_probe.json"
	for p in [Meta.path, Meta.path + Meta.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Meta.load_save()
	var ok := true
	ok = _check("fresh save: no levels, cost 100", Meta.gold_talent_total() == 0 and Meta.gold_talent_cost() == 100) and ok
	ok = _check("no gold: cannot buy", Meta.can_gold_talent() == "gold" and Meta.buy_gold_talent() == "") and ok
	Meta.gold = 100
	var id := Meta.buy_gold_talent()
	ok = _check("first press pays 100 and raises one", id != "" and Meta.gold == 0 and Meta.gold_talent_level(id) == 1) and ok
	ok = _check("second cost 140", Meta.gold_talent_cost() == 140) and ok
	var camp0: float = Meta.camp_rate()["gold"]
	Meta.gold = 100000000
	var spent := 0
	var cap := 0
	for t in Meta.GOLD_TALENTS:
		cap += t["max"]
	while Meta.can_gold_talent() == "":
		var c := Meta.gold_talent_cost()
		if Meta.gold_talent_total() == 100:
			print("[Talent] cost at level 100: ", c, "  spent so far: ", spent)
		spent += c
		Meta.buy_gold_talent()
	print("[Talent] total gold to max every talent: ", spent + 100)
	ok = _check("every talent maxed (%d levels)" % cap, Meta.gold_talent_total() == cap and Meta.can_gold_talent() == "max") and ok
	var fx := Meta.fx("")
	ok = _check("fx: atk +50%, hp +75%, camp +60%", is_equal_approx(fx.get("atkMult", 0.0), 0.5) and is_equal_approx(fx.get("hpMult", 0.0), 0.75) and is_equal_approx(fx.get("campMult", 0.0), 0.6)) and ok
	ok = _check("camp rate grows with 야영 숙련", is_equal_approx(Meta.camp_rate()["gold"], camp0 / (1.0 + (0.03 if id == "gCamp" else 0.0)) * 1.6)) and ok
	ok = _check("class fx untouched", not Meta.fx("warrior").has("atkMult")) and ok
	ok = _check("effect text", Meta.gold_talent_text("gAtk", 5) == "공격력 +5%" and Meta.gold_talent_text("gDef", 3) == "받는 피해 -1.2%") and ok
	Meta._loaded = false
	Meta.load_save()
	ok = _check("save round trip", Meta.gold_talent_total() == cap and Meta.gold_talent_level("gCamp") == 20) and ok
	print("[Talent] ", "ALL OK" if ok else "FAILED")
	quit(0 if ok else 1)

func _check(what: String, cond: bool) -> bool:
	print("[Talent] ", "ok   " if cond else "FAIL ", what)
	return cond
