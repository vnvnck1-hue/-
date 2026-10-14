class_name AttendScreen
extends GearScreen
## Lobby [출석] screen: the repeating 7-day attendance (Meta.ATTEND / Meta.attend).
##   - seven day cards (days 1-4 on top, 5-7 below, day 7 wide): claimed days carry a tick, today's card glows.
##   - [받기] claims today; after day 7 the table starts over at day 1. A missed day never resets the cycle.
## Shares GearScreen's open / close / style helpers; only the layout differs.

const CARD := Rect2(30, 230, 660, 800)

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	var tt := UiTheme.tt()
	var card := Panel.new()
	card.position = CARD.position
	card.size = CARD.size
	card.add_theme_stylebox_override("panel", UiTheme.night_card() if tt else _box(Color("5a57c8"), 30, 6))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_body.add_child(card)
	var w := CARD.size.x
	var title := _label("7일 출석", 52, UiTheme.TXT_YELLOW if tt else Color("ffd23f"), 12)
	title.position = Vector2(0, 24)
	title.size = Vector2(w, 70)
	card.add_child(title)
	var x := _button("X", Color("8a8aa0"), Rect2(w - 86, 24, 64, 60), 30)
	x.pressed.connect(close)
	card.add_child(x)
	var sub := _label("하루 한 번! 7일차를 받으면 1일차부터 다시 시작해요", 22, Color("cfe8ff"), 6)
	sub.position = Vector2(0, 96)
	sub.size = Vector2(w, 34)
	card.add_child(sub)
	var can := Meta.can_attend()
	# claimed in this cycle: days before att_day; right after day 7 (att_day wrapped to 0, claimed today) all seven
	var done := 7 if (not can and Meta.att_day == 0 and Meta.att_date != "") else Meta.att_day
	var cw := (w - 48 - 3 * 12) / 4.0
	for i in Meta.ATTEND.size():
		var r: Rect2
		if i < 4:
			r = Rect2(24 + i * (cw + 12), 146, cw, 230)
		elif i < 6:
			r = Rect2(24 + (i - 4) * (cw + 12), 390, cw, 230)
		else:
			r = Rect2(24 + 2 * (cw + 12), 390, cw * 2 + 12, 230)
		_day_card(card, i, r, i < done, can and i == Meta.att_day)
	var b := _button("받기" if can else "내일 또 만나요", UiTheme.YELLOW if can else Color("5a5478"), Rect2(48, 650, w - 96, 90), 38)
	b.disabled = not can
	b.pressed.connect(_claim)
	card.add_child(b)
	_toast_l = _label("", 28, Color("fff2b0"), 8)
	_toast_l.position = Vector2(0, CARD.end.y + 16)
	_toast_l.size = Vector2(W, 44)
	_body.add_child(_toast_l)

func _day_card(parent: Control, i: int, r: Rect2, claimed: bool, today: bool) -> void:
	var row: Dictionary = Meta.ATTEND[i]
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.pivot_offset = r.size * 0.5
	var col := Color("ffb43c") if today else (Color("3c3866") if claimed else Color("4c467b"))
	p.add_theme_stylebox_override("panel", UiTheme.flat(col, 20, 4, INK))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var dl := _label("%d일차" % (i + 1), 26, Color.WHITE, 8)
	dl.position = Vector2(0, 8)
	dl.size = Vector2(r.size.x, 36)
	p.add_child(dl)
	# reward icons side by side (day 7 has several), each with its amount under it
	var keys := []
	for k in ["gold", "stones", "crystals", "gear"]:
		if row.has(k):
			keys.append(k)
	var iw := minf(110.0, (r.size.x - 16) / keys.size())
	var x0 := (r.size.x - iw * keys.size()) * 0.5
	for j in keys.size():
		var k: String = keys[j]
		var ic: Control
		var amount := str(row[k])
		var tc := Color.WHITE
		match k:
			"gold":
				ic = Hud.CoinIcon.new()
				tc = Defs.COL_GOLD
			"stones":
				ic = Hud.StoneIcon.new()
				tc = ItemIcon.STONE_COL
			"crystals":
				ic = Hud.GemIcon.new()
				tc = Defs.COL_CRYSTAL
			"gear":
				ic = _gear_icon()
				amount = "장비"
		ic.position = Vector2(x0 + j * iw + (iw - 70) * 0.5, 56)
		ic.size = Vector2(70, 70)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(ic)
		var al := _label(amount, 24, tc, 7)
		al.position = Vector2(x0 + j * iw, 132)
		al.size = Vector2(iw, 36)
		p.add_child(al)
	if claimed:
		var dim := ColorRect.new()
		dim.color = Color(0.05, 0.03, 0.12, 0.45)
		dim.position = Vector2(4, 4)
		dim.size = r.size - Vector2(8, 8)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(dim)
		var ck := _label("✓", 72, Color("7cff6a"), 10)
		ck.size = r.size
		p.add_child(ck)
	elif today:
		var tl := _label("오늘", 24, Color("3a2400"), 0)
		tl.position = Vector2(0, r.size.y - 50)
		tl.size = Vector2(r.size.x, 40)
		p.add_child(tl)
		var tw := p.create_tween().set_loops()
		tw.tween_property(p, "scale", Vector2(1.05, 1.05), 0.5).set_trans(Tween.TRANS_SINE)
		tw.tween_property(p, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_SINE)

## Day 7's gear piece: a sample gear icon (sword of the usual grade).
func _gear_icon() -> Control:
	return ItemIcon.new(Inventory.make("equip", "sword3"))

func _claim() -> void:
	var r := Meta.attend()
	if r.is_empty():
		return
	Sfx.play("chime", -6.0, 1.2)
	var row: Dictionary = r["reward"]
	var t := "%d일차 보상! " % int(r["day"]) + CampScreen._reward_text(row)
	if r["gear"]:
		t += " · %s" % Inventory.name_of(r["gear"])
	_rebuild()
	_say(t)
