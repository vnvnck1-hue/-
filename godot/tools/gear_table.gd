extends SceneTree
## Prints the family gear stat table (grades 1-10): Godot --headless --path . -s res://tools/gear_table.gd
func _init() -> void:
	for f in Defs.FAMILIES:
		var row := []
		for g in range(1, 11):
			var d := Defs.item(Gear.key(f, g))
			var st := []
			for s in d["stats"]:
				var v: float = d["stats"][s]
				st.append(("%s %d%%" % [s, roundi(v * 100)]) if v < 1.0 and s != "range" else ("%s %d" % [s, int(v)]))
			row.append("%d %s: %s" % [g, d["name"], ", ".join(st)])
		print("## ", f, "\n", "\n".join(row))
	print("buy: ", range(1, 13).map(func(g): return Gear.buy_price(g)))
	print("sell: ", range(1, 13).map(func(g): return Gear.sell_price(g)))
	quit()
