extends SceneTree
## Dev: every equipment / special / relic key -> are all its stats, effects and relic fx described on the item card?

func _init() -> void:
	var missing := []
	var keys: Array = Defs.ITEMS.keys() + Defs.LEGENDARY.keys() + Defs.TRANSCENDENT.keys() + ["crown"]
	for f in Defs.FAMILIES:
		for g in range(5, 12):
			keys.append(Gear.key(f, g))
	for k in keys:
		var d := Defs.item(k)
		for s in d.get("stats", {}):
			if not HudPanels.STAT_NAME.has(s):
				missing.append("%s stat %s" % [k, s])
		for x in d.get("effects", []):
			if not HudPanels.EFFECT_NAME.has(x) or HudPanels.EFFECT_BODY.get(x, "") == "":
				missing.append("%s effect %s" % [k, x])
	for k in Defs.RELICS:
		for s in Defs.RELICS[k]["fx"]:
			if not Defs.RELIC_FX_NAME.has(s) or HudPanels.stat_note(s, 0.1) == "":
				missing.append("relic %s fx %s" % [k, s])
		print("[Audit] relic ", k, ": ", " / ".join(HudPanels.relic_detail(k, 1)).replace("\n", " "))
	for b in Defs.ITEMS.values() + Defs.LEGENDARY.values():
		for s in b.get("stats", {}):
			if s in HudPanels.EQUIP_NOTE_KEYS and HudPanels.stat_note(s, 0.1) == "":
				missing.append("note " + s)
	print("[Audit] checked ", keys.size(), " gear keys, ", Defs.RELICS.size(), " relics; missing=", missing)
	quit()
