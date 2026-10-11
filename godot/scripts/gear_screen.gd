class_name GearScreen
extends Control
## Lobby [장비] screen: the permanent gear meta (Meta).
##   - hero tabs; each hero's weapon / armor / accessory slot shows what it wears and its slot level.
##     [강화] raises the slot level with banked gold + 강화석 (Gear.upgrade_cost, capped by the worn grade).
##     The level belongs to the slot: whatever is worn there in a run (even a piece picked up mid-run) gets it.
##   - storage grid: tap a piece to see it, then [장착] (onto the selected hero) or [판매].
##     [모두 합성] merges every group of three (same slot + grade -> next grade, Meta.merge_all).
## Built over the lobby on its own canvas layer; closes with X / Esc.

signal closed

var font: Font
var INK: Color = UiTheme.ink()
var cls := "warrior"
var picked := {}          # storage entry shown in the detail bar
var _body: Control
var _toast_l: Label

const CLASS_COL := {"warrior": Color("ff7a5a"), "ranger": Color("5fcf5a"), "mage": Color("a77aff")}
const SLOT_KO := {"weapon": "무기", "armor": "방어구", "accessory": "장신구"}
const W := 720.0

func open(p_font: Font) -> void:
	font = p_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.14, 0.92)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_body.anchor_left = 0.5
	_body.anchor_right = 0.5
	_body.offset_left = -W * 0.5
	_body.offset_right = W * 0.5
	_body.offset_top = 0.0
	_body.offset_bottom = 1280.0
	_rebuild()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

func close() -> void:
	Sfx.play("click", -6.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		closed.emit()
		queue_free())

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()

# ---------------------------------------------------------------- layout
func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var title := _label("장비", 60, UiTheme.TXT_YELLOW if UiTheme.tt() else Color("ffd23f"), 14)
	title.position = Vector2(0, 22)
	title.size = Vector2(W, 80)
	_body.add_child(title)
	var x := _button("X", Color("8a8aa0"), Rect2(W - 92, 28, 70, 66), 34)
	x.pressed.connect(close)
	_body.add_child(x)
	# banked currencies
	_pill(Rect2(40, 112, 300, 60), Hud.CoinIcon.new(), str(Meta.gold), Defs.COL_GOLD)
	_pill(Rect2(380, 112, 300, 60), Hud.StoneIcon.new(), str(Meta.stones), ItemIcon.STONE_COL)
	# hero tabs
	var i := 0
	for c in Defs.HERO_ORDER:
		var on: bool = c == cls
		var b := _button(Defs.HEROES[c]["name"], CLASS_COL[c] if on else Color("5a5478"), Rect2(40 + i * 220, 192, 200, 70), 30)
		var cc: String = c
		b.pressed.connect(func():
			cls = cc
			Sfx.play("click", -6.0)
			_rebuild())
		_body.add_child(b)
		i += 1
	# slots
	for si in Meta.SLOTS.size():
		_slot_card(Meta.SLOTS[si], Rect2(28 + si * 226, 282, 212, 330))
	_storage(Rect2(28, 632, W - 56, 470))
	_detail(Rect2(28, 1112, W - 56, 150))
	_toast_l = _label("", 26, Color("fff2b0"), 8)
	_toast_l.position = Vector2(0, 1060)
	_toast_l.size = Vector2(W, 40)
	_body.add_child(_toast_l)

func _slot_card(slot: String, r: Rect2) -> void:
	var e = Meta.worn(cls, slot)
	var card := Panel.new()
	card.position = r.position
	card.size = r.size
	card.add_theme_stylebox_override("panel", UiTheme.night_card(22) if UiTheme.tt() else _box(Color("4c467b"), 22, 5))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(card)
	var sl := _label(SLOT_KO[slot], 24, Color.WHITE, 8)
	sl.position = Vector2(0, 8)
	sl.size = Vector2(r.size.x, 34)
	card.add_child(sl)
	var ib := Panel.new()
	ib.position = Vector2(r.size.x * 0.5 - 56, 46)
	ib.size = Vector2(112, 104)
	ib.add_theme_stylebox_override("panel", _rarity_box(Inventory.rarity_of(e)) if e else UiTheme.empty_slot(16))
	ib.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_child(ib)
	if e:
		var ic := ItemIcon.new(e)
		ic.position = Vector2(8, 6)
		ic.size = Vector2(96, 92)
		ib.add_child(ic)
		ib.gui_input.connect(func(ev: InputEvent):   # tap the worn piece: take it off (back to storage)
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				Meta.take_off(cls, slot)
				Sfx.play("pop", -6.0, 0.9)
				_rebuild())
	var nm := _label(Inventory.name_of(e) if e else "비어 있음", 20 if e else 20, Color.WHITE if e else Color("a9a4cb"), 7 if e else 0)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(6, 152)
	nm.size = Vector2(r.size.x - 12, 50)
	card.add_child(nm)
	var lv := Meta.slot_level(cls, slot)
	var cap := Gear.slot_cap(e)
	var eff := mini(lv, cap)
	var lvl := _label("칸 Lv.%d%s" % [lv, (" / %d" % cap) if e else ""], 24, ItemIcon.STONE_COL.lightened(0.3), 8)
	lvl.position = Vector2(0, 202)
	lvl.size = Vector2(r.size.x, 32)
	card.add_child(lvl)
	var bonus := Gear.slot_bonus(slot, eff)
	var parts := []
	for k in bonus:
		parts.append("%s +%d" % ["공격력" if k == "atk" else "체력", int(bonus[k])])
	var bl := _label(" · ".join(parts) if not parts.is_empty() else "강화 보너스 없음", 18, Color("cfe8ff"), 6)
	bl.position = Vector2(0, 232)
	bl.size = Vector2(r.size.x, 26)
	card.add_child(bl)
	var why := Meta.can_upgrade(cls, slot)
	var c := Gear.upgrade_cost(lv)
	var txt := "강화"
	match why:
		"empty": txt = "장비 없음"
		"cap": txt = "등급 한계"
		_: txt = "%dG · ◆%d" % [int(c["gold"]), int(c["stones"])]
	var ub := _button(txt, Color("27c6b0") if why == "" else Color("6e6a8c"), Rect2(10, 266, r.size.x - 20, 54), 22 if txt.length() > 6 else 26)
	ub.pressed.connect(func():
		if Meta.upgrade(cls, slot):
			Sfx.play("chime", -4.0, 1.2)
			_rebuild()
			_say("%s 칸 Lv.%d!" % [SLOT_KO[slot], Meta.slot_level(cls, slot)])
		else:
			Sfx.play("click", -6.0, 0.7)
			_say({"gold": "골드가 부족해요", "stones": "강화석이 부족해요", "cap": "장비 등급을 올려야 더 강화할 수 있어요", "empty": "먼저 장비를 끼워 주세요"}.get(Meta.can_upgrade(cls, slot), "")))
	card.add_child(ub)

func _storage(r: Rect2) -> void:
	var box := Panel.new()
	box.position = r.position
	box.size = r.size
	box.add_theme_stylebox_override("panel", UiTheme.deck_panel(22, 64.0) if UiTheme.tt() else _box(Color("3a3560"), 22, 5))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(box)
	var t := _label("보관함 %d" % Meta.storage.size(), 30, Color.WHITE, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.position = Vector2(22, 8)
	t.size = Vector2(300, 50)
	box.add_child(t)
	var ready := Meta.merge_ready()
	var mb := _button("모두 합성 (%d)" % ready if ready > 0 else "합성할 것 없음", Color("ff9f1c") if ready > 0 else Color("6e6a8c"), Rect2(r.size.x - 290, 6, 274, 54), 26)
	mb.pressed.connect(func():
		var made := Meta.merge_all()
		if made.is_empty():
			_say("같은 부위·같은 등급 3개가 모이면 합성할 수 있어요")
			return
		Sfx.play("chime", -3.0, 1.3)
		picked = made[-1]
		_rebuild()
		_say("합성 %d회! %s" % [made.size(), Inventory.label_of(made[-1])]))
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
	var list: Array = Meta.storage.duplicate()
	var order := {"weapon": 0, "armor": 1, "accessory": 2}
	list.sort_custom(func(a, b):
		var sa: int = order.get(Defs.item(a["key"]).get("slot", ""), 3)
		var sb: int = order.get(Defs.item(b["key"]).get("slot", ""), 3)
		if sa != sb:
			return sa < sb
		return Inventory.tier_of(a) > Inventory.tier_of(b))
	if list.is_empty():
		var em := _label("비어 있어요 — 원정에서 얻은 장비가 여기에 모입니다", 20, Color("a9a4cb"), 0)
		em.position = Vector2(0, 160)
		em.size = Vector2(r.size.x, 40)
		box.add_child(em)
	for e in list:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(98, 92)
		var sel: bool = e == picked
		var st := _rarity_box(Inventory.rarity_of(e))
		if sel:
			st.border_color = Color("fff27a")
			st.set_border_width_all(6)
		cell.add_theme_stylebox_override("panel", st)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var ic := ItemIcon.new(e)
		ic.position = Vector2(7, 5)
		ic.size = Vector2(84, 80)
		cell.add_child(ic)
		var ee: Dictionary = e
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				picked = ee
				Sfx.play("click", -8.0, 1.3)
				_rebuild())
		grid.add_child(cell)

func _detail(r: Rect2) -> void:
	var box := Panel.new()
	box.position = r.position
	box.size = r.size
	box.add_theme_stylebox_override("panel", UiTheme.cream_card(22) if UiTheme.tt() else _box(Color("fff4e0"), 22, 5))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(box)
	if picked.is_empty() or not Meta.storage.has(picked):
		picked = {}
		var h := _label("보관함의 장비를 눌러 보세요 · 장착한 장비를 누르면 해제", 21, Color("6a5a48"), 0)
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
	ic.position = Vector2(8, 8)
	ic.size = Vector2(106, 106)
	ib.add_child(ic)
	var def := Defs.item(e["key"])
	var nm := _label(Inventory.label_of(e), 26, Defs.RARITY_COL[Inventory.rarity_of(e)].darkened(0.35), 0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(150, 8)
	nm.size = Vector2(300, 40)
	box.add_child(nm)
	var stats := []
	var es := Stats.entry_stats(e)
	for k in es:
		if HudPanels.STAT_NAME.has(k):
			var n: Array = HudPanels.STAT_NAME[k]
			stats.append("%s +%s" % [n[0], ("%d%%" % roundi(es[k] * 100.0)) if n[1] else str(int(es[k]))])
	var sl := _label("%s · %s" % [SLOT_KO.get(def.get("slot", ""), "?"), "  ".join(stats)], 18, Color("4a3a30"), 0)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.position = Vector2(150, 50)
	sl.size = Vector2(300, 90)
	box.add_child(sl)
	var eb := _button("장착", Color("27c6b0"), Rect2(r.size.x - 200, 14, 186, 60), 28)
	eb.pressed.connect(func():
		Meta.wear(cls, e)
		picked = {}
		Sfx.play("chime", -6.0, 1.4)
		_rebuild()
		_say("%s → %s" % [Inventory.name_of(e), Defs.HEROES[cls]["name"]]))
	box.add_child(eb)
	var price := Inventory.sell_price(null, e)
	var sb := _button("판매 %dG" % price, Color("ff7a5a"), Rect2(r.size.x - 200, 80, 186, 56), 24)
	sb.pressed.connect(func():
		var g := Meta.sell(e)
		picked = {}
		Sfx.play("tick", -4.0, 1.4)
		_rebuild()
		_say("+%dG" % g))
	box.add_child(sb)

func _say(t: String) -> void:
	if _toast_l == null or not is_instance_valid(_toast_l):
		return
	_toast_l.text = t
	_toast_l.modulate.a = 1.0
	var tw := _toast_l.create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast_l, "modulate:a", 0.0, 0.4)

# ---------------------------------------------------------------- style helpers
func _label(text: String, size: int, color := Color.WHITE, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	var s := LabelSettings.new()
	s.font = font
	s.font_size = size
	s.font_color = color
	s.outline_size = outline
	s.outline_color = INK
	l.label_settings = s
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _box(color: Color, radius := 12, border := 4) -> StyleBoxFlat:
	return UiTheme.flat(color, radius, border, INK)

func _rarity_box(rarity: String) -> StyleBoxFlat:
	var c: Color = Defs.RARITY_COL.get(rarity, Color("c8ccd8"))
	return UiTheme.flat(c.darkened(0.15), 16, 4, INK)

func _button(text: String, col: Color, r: Rect2, fsize := 28) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.position = r.position
	b.size = r.size
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fsize)
	var tt := UiTheme.tt()
	for st in ["normal", "hover", "pressed"]:
		if tt:
			b.add_theme_stylebox_override(st, UiTheme.button_box(col.lightened(0.08 if st == "hover" else 0.0), 18, st == "pressed"))
		else:
			b.add_theme_stylebox_override(st, _box(col.lightened(0.1 if st == "hover" else 0.0), 20, 5))
	var tc := UiTheme.text_color(col) if tt else Color.WHITE
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, tc)
	if tc == Color.WHITE:
		b.add_theme_color_override("font_outline_color", INK)
		b.add_theme_constant_override("outline_size", 8)
	return b

func _pill(r: Rect2, icon: Control, text: String, col: Color) -> void:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.add_theme_stylebox_override("panel", UiTheme.capsule(int(r.size.y * 0.5)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(p)
	icon.position = Vector2(8, (r.size.y - 46) * 0.5)
	icon.size = Vector2(46, 46)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(icon)
	var l := _label(text, 34, col, 8)
	l.position = Vector2(56, 0)
	l.size = Vector2(r.size.x - 66, r.size.y)
	p.add_child(l)
