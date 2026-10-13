class_name RelicScreen
extends GearScreen
## Lobby [유물] screen: the permanent relic collection (Meta.relic_bag / Meta.relic_slots).
##   - Defs.RELIC_SLOTS worn slots: the relics worn here apply to the whole party in every run (the run no longer
##     carries relics in its bag). Tap a worn relic to take it off.
##   - collection grid: tap a relic to see it, then [장착] (the slot with the same relic, else the first empty one)
##     or [판매]. [모두 합성] merges every three of the same relic at the same ★ into the next ★ (MergeFx plays it).
## Shares GearScreen's open / close / style helpers; only the layout differs.

const SLOT_COL := Color("ffb43c")

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var title := _label("유물", 60, UiTheme.TXT_YELLOW if UiTheme.tt() else Color("ffd23f"), 14)
	title.position = Vector2(0, 22)
	title.size = Vector2(W, 80)
	_body.add_child(title)
	var x := _button("X", Color("8a8aa0"), Rect2(W - 92, 28, 70, 66), 34)
	x.pressed.connect(close)
	_body.add_child(x)
	_pill(Rect2(40, 112, 300, 60), Hud.CoinIcon.new(), str(Meta.gold), Defs.COL_GOLD)
	var own := _label("보유 %d · 장착 %d/%d" % [Meta.relic_bag.size() + Meta.worn_relics().size(), Meta.worn_relics().size(), Defs.RELIC_SLOTS], 26, Color("cfe8ff"), 8)
	own.position = Vector2(370, 112)
	own.size = Vector2(320, 60)
	_body.add_child(own)
	var sub := _label("장착한 유물은 모든 판에서 파티 전체에 적용돼요", 22, Color("a9a4cb"), 6)
	sub.position = Vector2(0, 182)
	sub.size = Vector2(W, 34)
	_body.add_child(sub)
	for i in Defs.RELIC_SLOTS:
		_relic_slot(i, Rect2(28 + i * 226, 222, 212, 300))
	var total := _label(_total_text(), 20, Color("fff2b0"), 6)
	total.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	total.position = Vector2(20, 528)
	total.size = Vector2(W - 40, 64)
	_body.add_child(total)
	_collection(Rect2(28, 600, W - 56, 500))
	_relic_detail(Rect2(28, 1112, W - 56, 150))
	_toast_l = _label("", 26, Color("fff2b0"), 8)
	_toast_l.position = Vector2(0, 1060)
	_toast_l.size = Vector2(W, 40)
	_body.add_child(_toast_l)

## "합계: 공격 속도 +10% · ..." for the worn relics.
func _total_text() -> String:
	var worn := Meta.worn_relics()
	if worn.is_empty():
		return "아래 보관함에서 유물을 골라 장착해 보세요"
	var parts := []
	for e in worn:
		parts.append(Defs.relic_desc(e["key"], int(e.get("star", 1))))
	return "적용 중: " + " · ".join(parts)

func _stars(e: Dictionary, r: Rect2, fsize: int) -> Label:
	var l := _label("★".repeat(int(e.get("star", 1))), fsize, Color("ffd23f"), 6)
	l.position = r.position
	l.size = r.size
	return l

func _relic_slot(i: int, r: Rect2) -> void:
	var e = Meta.relic_slots[i]
	var card := Panel.new()
	card.position = r.position
	card.size = r.size
	card.add_theme_stylebox_override("panel", UiTheme.night_card(22) if UiTheme.tt() else _box(Color("4c467b"), 22, 5))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(card)
	var sl := _label("%d번 칸" % (i + 1), 24, Color.WHITE, 8)
	sl.position = Vector2(0, 8)
	sl.size = Vector2(r.size.x, 34)
	card.add_child(sl)
	var ib := Panel.new()
	ib.position = Vector2(r.size.x * 0.5 - 60, 46)
	ib.size = Vector2(120, 120)
	ib.add_theme_stylebox_override("panel", _rarity_box(Inventory.rarity_of(e)) if e else UiTheme.empty_slot(16))
	ib.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_child(ib)
	if e:
		var ic := ItemIcon.new(e)
		ic.position = Vector2(10, 6)
		ic.size = Vector2(100, 92)
		ib.add_child(ic)
		ib.add_child(_stars(e, Rect2(0, 92, 120, 28), 22))
		ib.gui_input.connect(func(ev: InputEvent):   # tap the worn relic: take it off (back to the collection)
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				Meta.take_off_relic(i)
				Sfx.play("pop", -6.0, 0.9)
				_rebuild())
	else:
		var plus := _label("+", 64, Color("a9a4cb"), 0)
		plus.size = ib.size
		ib.add_child(plus)
	var nm := _label(Inventory.name_of(e) if e else "비어 있음", 21, Color.WHITE if e else Color("a9a4cb"), 7 if e else 0)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(6, 170)
	nm.size = Vector2(r.size.x - 12, 50)
	card.add_child(nm)
	if e:
		var d := _label(Defs.relic_desc(e["key"], int(e.get("star", 1))), 17, Color("cfe8ff"), 5)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		d.position = Vector2(8, 222)
		d.size = Vector2(r.size.x - 16, 72)
		card.add_child(d)

func _sorted_bag() -> Array:
	var list: Array = Meta.relic_bag.duplicate()
	list.sort_custom(func(a, b):
		var ra: int = 0 if Defs.RELICS[a["key"]]["rarity"] == "legendary" else 1
		var rb: int = 0 if Defs.RELICS[b["key"]]["rarity"] == "legendary" else 1
		if ra != rb:
			return ra < rb
		if a["key"] != b["key"]:
			return a["key"] < b["key"]
		return int(a.get("star", 1)) > int(b.get("star", 1)))
	return list

func _collection(r: Rect2) -> void:
	var box := Panel.new()
	box.position = r.position
	box.size = r.size
	box.add_theme_stylebox_override("panel", UiTheme.deck_panel(22, 64.0) if UiTheme.tt() else _box(Color("3a3560"), 22, 5))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(box)
	var t := _label("보관함 %d" % Meta.relic_bag.size(), 30, Color.WHITE, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.position = Vector2(22, 8)
	t.size = Vector2(300, 50)
	box.add_child(t)
	var ready := Meta.relic_merge_ready()
	var mb := _button("모두 합성 (%d)" % ready if ready > 0 else "합성할 것 없음", Color("ff9f1c") if ready > 0 else Color("6e6a8c"), Rect2(r.size.x - 290, 6, 274, 54), 26)
	mb.pressed.connect(func():
		var steps := Meta.merge_all_relics()
		if steps.is_empty():
			Sfx.play("click", -6.0, 0.7)
			_say("같은 유물 3개(같은 ★)가 모이면 합성할 수 있어요")
			return
		picked = steps[-1]["out"]
		_play_merge(steps))
	box.add_child(mb)
	var sc := ScrollContainer.new()
	sc.position = Vector2(14, 72)
	sc.size = Vector2(r.size.x - 28, r.size.y - 84)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	var list := _sorted_bag()
	if list.is_empty():
		var em := _label("비어 있어요 — 원정 15무리부터 유물이 떨어집니다", 20, Color("a9a4cb"), 0)
		em.position = Vector2(0, 180)
		em.size = Vector2(r.size.x, 40)
		box.add_child(em)
	# how many of each (key, ★) the collection holds: a "n/3" tag shows how close a merge is
	var counts := {}
	for e in list:
		var k := "%s#%d" % [e["key"], int(e.get("star", 1))]
		counts[k] = counts.get(k, 0) + 1
	for e in list:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(98, 108)
		var st := _rarity_box(Inventory.rarity_of(e))
		if e == picked:
			st.border_color = Color("fff27a")
			st.set_border_width_all(6)
		cell.add_theme_stylebox_override("panel", st)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var ic := ItemIcon.new(e)
		ic.position = Vector2(9, 4)
		ic.size = Vector2(80, 76)
		cell.add_child(ic)
		cell.add_child(_stars(e, Rect2(0, 78, 98, 26), 18))
		var n: int = counts["%s#%d" % [e["key"], int(e.get("star", 1))]]
		if int(e.get("star", 1)) < Defs.RELIC_MAX_STAR:
			var tag := _label("%d/3" % mini(n, 3) if n < 3 else "합성!", 15, Color.WHITE if n < 3 else Color("fff27a"), 5)
			tag.position = Vector2(46, 0)
			tag.size = Vector2(50, 22)
			cell.add_child(tag)
		var ee: Dictionary = e
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				picked = ee
				Sfx.play("click", -8.0, 1.3)
				_rebuild())
		grid.add_child(cell)

func _relic_detail(r: Rect2) -> void:
	var box := Panel.new()
	box.position = r.position
	box.size = r.size
	box.add_theme_stylebox_override("panel", UiTheme.cream_card(22) if UiTheme.tt() else _box(Color("fff4e0"), 22, 5))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(box)
	if picked.is_empty() or not Meta.relic_bag.has(picked):
		picked = {}
		var h := _label("보관함의 유물을 눌러 보세요 · 장착한 유물을 누르면 해제", 21, Color("6a5a48"), 0)
		h.size = r.size
		box.add_child(h)
		return
	var e := picked
	var ib := Panel.new()
	ib.position = Vector2(14, 14)
	ib.size = Vector2(122, 122)
	ib.add_theme_stylebox_override("panel", _rarity_box(Inventory.rarity_of(e)))
	box.add_child(ib)
	var ic := ItemIcon.new(e)
	ic.position = Vector2(10, 6)
	ic.size = Vector2(102, 92)
	ib.add_child(ic)
	ib.add_child(_stars(e, Rect2(0, 94, 122, 26), 20))
	var star := int(e.get("star", 1))
	var nm := _label("%s  ★%d" % [Inventory.name_of(e), star], 26, Defs.RARITY_COL[Inventory.rarity_of(e)].darkened(0.35), 0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(150, 8)
	nm.size = Vector2(320, 40)
	box.add_child(nm)
	var txt := Defs.relic_desc(e["key"], star)
	if star < Defs.RELIC_MAX_STAR:
		txt += "\n다음 ★: " + Defs.relic_desc(e["key"], star + 1)
	var sl := _label(txt, 17, Color("4a3a30"), 0)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.position = Vector2(150, 50)
	sl.size = Vector2(320, 90)
	box.add_child(sl)
	var eb := _button("장착", Color("27c6b0"), Rect2(r.size.x - 200, 14, 186, 60), 28)
	eb.pressed.connect(func():
		var i := Meta.wear_relic(e)
		if i < 0:
			Sfx.play("click", -6.0, 0.7)
			_say("칸이 가득 찼어요 — 위의 장착한 유물을 눌러 해제하세요")
			return
		picked = {}
		Sfx.play("chime", -6.0, 1.4)
		_rebuild()
		_say("%s → %d번 칸" % [Inventory.name_of(e), i + 1]))
	box.add_child(eb)
	var more := HudPanels.relic_detail(e["key"], star)
	more.append("장착하면 모든 판에서 파티 전체에 적용 · 같은 ★ 3개 → 다음 ★ 합성")
	_grow_detail(box, r, more)
	var price := Meta.relic_sell_price(e)
	var sb := _button("판매 %dG" % price, Color("ff7a5a"), Rect2(r.size.x - 200, 80, 186, 56), 24)
	sb.pressed.connect(func():
		var g := Meta.sell_relic(e)
		picked = {}
		Sfx.play("tick", -4.0, 1.4)
		_rebuild()
		_say("+%dG" % g))
	box.add_child(sb)
