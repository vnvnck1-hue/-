extends SceneTree
## Headless merge-economy simulation (no save file touched):
##   Godot --headless --path . -s res://tools/gear_sim.gd [-- --runs=200 --groups=120]
## Plays the real drop code (Inventory.random_item_key / add / try_merge, Waves.normal for kill counts)
## with a greedy auto-equip, and prints per-region merge frequency and the grade of the equipped gear.

class FakeHero:
	extends RefCounted
	var equipment := {"weapon": null, "armor": null, "accessory": null}
	var max_hp := 300.0
	var hp := 300.0

class FakeGame:
	extends Node
	var inventory: Array = []
	var inv_cap := Defs.MAX_INVENTORY
	var gold := 0
	var perks: Array = []
	var heroes: Array = []
	var wave := 1
	var merges := 0
	func on_merged(names: Array) -> void:
		merges += names.size()

func _init() -> void:
	Meta.path = "user://trio_save_sim.json"
	var runs := 200
	var groups := 120
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="):
			runs = int(a.substr(7))
		elif a.begins_with("--groups="):
			groups = int(a.substr(9))
	print_window(groups)
	var regions := int(ceil(groups / 10.0))
	var merges := []
	var drops := []
	var sold := []
	var eq_grade := []
	var top_grade := []
	var dry := []   # groups in the region that produced no merge at all
	for r in regions:
		merges.append(0.0); drops.append(0.0); sold.append(0.0); eq_grade.append(0.0); top_grade.append(0.0); dry.append(0.0)
	for run in runs:
		var g := FakeGame.new()
		for i in 3:
			g.heroes.append(FakeHero.new())
		g.inventory.append(Inventory.make("equip", "sword2"))   # march start gift
		for k in range(1, groups + 1):
			g.wave = k
			var r := (k - 1) / 10
			var before := g.merges
			var kills := _kills(k)
			for kind in kills:
				var role := Defs.role(kind)
				var jackpot := role == "boss" or role == "giant"
				var n := 2 if role == "giant" else (1 if randf() < Defs.DROP_RATES.get(role, 0.2) + Gear.drop_bonus(k) else 0)
				for i in n:
					drops[r] += 1
					var e := Inventory.make_found(Inventory.random_item_key(k, g, jackpot), k)
					if Inventory.add(g, e).begins_with("sold:"):
						sold[r] += 1
			_auto_equip(g)
			merges[r] += g.merges - before
			if g.merges == before:
				dry[r] += 1
			if k % 10 == 0:
				var sum := 0.0
				var top := 0
				for h in g.heroes:
					for s in h.equipment:
						var e = h.equipment[s]
						var t := Inventory.tier_of(e) if e else 0
						sum += t
						top = maxi(top, t)
				eq_grade[r] += sum / 9.0
				top_grade[r] += top
		if run == 0:
			print("bag@end: ", g.inventory.map(func(x): return x["key"]))
		g.free()
	print("\nregion | groups  | drops/grp | merges/grp | dry groups | sold/grp | equipped avg grade (end) | best")
	for r in regions:
		var nm: String = Regions.info(r)["name"]
		print("%2d %-8s| %3d-%3d | %5.2f | %5.2f | %4.1f/10 | %4.2f | %4.2f | %4.2f" % [r + 1, nm, r * 10 + 1, r * 10 + 10,
			drops[r] / runs / 10.0, merges[r] / runs / 10.0, dry[r] / runs, sold[r] / runs / 10.0, eq_grade[r] / runs, top_grade[r] / runs])
	quit()

func print_window(groups: int) -> void:
	print("== drop window (grade: %) at region start -> mid-boss ==")
	for r in int(ceil(groups / 10.0)):
		var a := Gear.window(r * 10 + 1)
		var b := Gear.window(r * 10 + 10)
		var boss := Gear.window(r * 10 + 10, true)
		print("R%d B=%d start %s | end %s | boss %s | featured %s" % [r + 1, Gear.base_grade(r * 10 + 1), _fmt(a), _fmt(b), _fmt(boss), Gear.featured(r * 10 + 1)])

func _fmt(w: Dictionary) -> String:
	var keys := w.keys()
	keys.sort()
	return " ".join(keys.map(func(g): return "%s:%d" % [Gear.grade_name(g), roundi(w[g] * 100)]))

## Kill list for group k (classic composition; every 10th group = mid-boss + escorts).
func _kills(k: int) -> Array:
	var out := []
	if k % 10 == 0:
		out.append("giant")
		for i in 3:
			out.append("normal")
		return out
	for s in Defs.sub_wave_count(k):
		for x in Waves.normal(k):
			out.append(x["kind"])
	return out

## Greedy: each hero takes the highest-grade bag item for each slot (bag items rotate to the heroes).
func _auto_equip(g: FakeGame) -> void:
	for h in g.heroes:
		for slot in h.equipment:
			var best = null
			for e in g.inventory:
				if e["kind"] == "equip" and Defs.item(e["key"]).get("slot", "") == slot:
					if best == null or Inventory.tier_of(e) > Inventory.tier_of(best):
						best = e
			var cur = h.equipment[slot]
			if best and (cur == null or Inventory.tier_of(best) > Inventory.tier_of(cur)):
				g.inventory.erase(best)
				h.equipment[slot] = best
				if cur:
					g.inventory.append(cur)
	Inventory.try_merge(g)
	# a player clears lone uniques out of a nearly full bag (sells them); pairs are kept for transcendence
	if g.inventory.size() >= g.inv_cap - 2:
		for e in g.inventory.duplicate():
			if e["kind"] == "equip" and not Gear.is_family(e["key"]) and Inventory._count_key(g, e["key"]) < 2:
				g.gold += Inventory.sell_price(g, e)
				g.inventory.erase(e)
