class_name RaidScreen
extends GearScreen
## Lobby [토벌] screen: the boss raid (Meta.raid_* / Defs.RAID_BOSSES).
##   - six boss cards (the region bosses): best tier and best damage per boss; tap one to pick it.
##   - the picked boss's skill hint and what its best tier pays.
##   - [도전 ▶] spends one of today's tries and starts the raid (start_raid); [소탕] replays the best tier's
##     rewards for a try without fighting.
## Shares GearScreen's open / close / style helpers; only the layout differs.

signal start_raid(key: String)

const CARD_SZ := Vector2(322, 150)
const GRID_Y := 226.0

var pick := ""

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	if pick == "":
		pick = Defs.RAID_BOSSES[0]["key"]
	var tt := UiTheme.tt()
	var title := _label("보스 토벌", 60, UiTheme.TXT_YELLOW if tt else Color("ffd23f"), 14)
	title.position = Vector2(0, 22)
	title.size = Vector2(W, 80)
	_body.add_child(title)
	var x := _button("X", Color("8a8aa0"), Rect2(W - 92, 28, 70, 66), 34)
	x.pressed.connect(close)
	_body.add_child(x)
	var left := _label("오늘 남은 도전 %d / %d" % [Meta.raid_left(), Meta.RAID_TRIES], 28, Color("cfe8ff"), 8)
	left.position = Vector2(0, 108)
	left.size = Vector2(W, 44)
	_body.add_child(left)
	var sub := _label("%d초 동안 쓰러지지 않는 보스에게 최대한 큰 피해를!" % int(Meta.RAID_TIME), 22, Color("a9a4cb"), 6)
	sub.position = Vector2(0, 156)
	sub.size = Vector2(W, 34)
	_body.add_child(sub)
	for i in Defs.RAID_BOSSES.size():
		_card(Defs.RAID_BOSSES[i], Vector2(W * 0.5 - CARD_SZ.x - 8 + (i % 2) * (CARD_SZ.x + 16), GRID_Y + int(i / 2) * (CARD_SZ.y + 14)))
	_detail(Rect2(28, 732, W - 56, 220))
	var can := Meta.raid_left() > 0
	var go := _button("도전 ▶", UiTheme.YELLOW if can else Color("5a5478"), Rect2(40, 972, 400, 100), 42)
	go.modulate = Color.WHITE if can else Color(1, 1, 1, 0.55)
	go.pressed.connect(func():
		if Meta.raid_left() > 0:
			start_raid.emit(pick))
	_body.add_child(go)
	var tier := int(Meta.raid_tier.get(pick, 0))
	var sw := _button("소탕", UiTheme.GREEN if can and tier > 0 else Color("5a5478"), Rect2(460, 972, 220, 100), 38)
	sw.modulate = Color.WHITE if can and tier > 0 else Color(1, 1, 1, 0.55)
	sw.pressed.connect(_sweep)
	_body.add_child(sw)
	_toast_l = _label("", 26, Color("fff2b0"), 8)
	_toast_l.position = Vector2(0, 1086)
	_toast_l.size = Vector2(W, 80)
	_toast_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_toast_l)

func _card(b: Dictionary, pos: Vector2) -> void:
	var on: bool = b["key"] == pick
	var card := Button.new()
	card.focus_mode = Control.FOCUS_NONE
	card.position = pos
	card.size = CARD_SZ
	var col: Color = b["col"]
	for st in ["normal", "hover", "pressed"]:
		card.add_theme_stylebox_override(st, UiTheme.flat(col.darkened(0.35) if on else Color("3c3866"), 20, 6 if on else 4, Color("fff26a") if on else INK))
	card.pressed.connect(func():
		pick = b["key"]
		Sfx.play("click", -6.0)
		_rebuild())
	_body.add_child(card)
	var ic := Panel.new()   # colour badge with the boss's initial
	ic.position = Vector2(14, 16)
	ic.size = Vector2(64, 64)
	ic.add_theme_stylebox_override("panel", UiTheme.flat(col, 32, 4, INK))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ic)
	var il := _label(str(b["name"]).substr(0, 1), 34, Color.WHITE, 8)
	il.size = ic.size
	ic.add_child(il)
	var nm := _label(b["name"], 24, Color.WHITE, 8)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(88, 12)
	nm.size = Vector2(CARD_SZ.x - 96, 36)
	card.add_child(nm)
	var rg := _label(Regions.info(int(b["region"]))["name"], 19, Color("a9a4cb"), 5)
	rg.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rg.position = Vector2(88, 48)
	rg.size = Vector2(CARD_SZ.x - 96, 28)
	card.add_child(rg)
	var tier := int(Meta.raid_tier.get(b["key"], 0))
	var best := int(Meta.raid_best.get(b["key"], 0))
	var rec := _label("최고 %d단계 · %s" % [tier, _num(best)] if tier > 0 or best > 0 else "기록 없음", 21, Color("fff2b0") if tier > 0 else Color("a9a4cb"), 6)
	rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rec.position = Vector2(16, 98)
	rec.size = Vector2(CARD_SZ.x - 32, 36)
	card.add_child(rec)

func _detail(r: Rect2) -> void:
	var box := Panel.new()
	box.position = r.position
	box.size = r.size
	box.add_theme_stylebox_override("panel", UiTheme.night_card(22) if UiTheme.tt() else _box(Color("4c467b"), 22, 5))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(box)
	var b := Defs.raid_boss(pick)
	var info: Dictionary = Defs.BOSS_INFO.get(pick, {})
	var nm := _label(b["name"], 30, Color("ffd23f"), 8)
	nm.position = Vector2(0, 12)
	nm.size = Vector2(r.size.x, 40)
	box.add_child(nm)
	var h := _label(info.get("hint", ""), 21, Color("cfe8ff"), 5)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.position = Vector2(20, 56)
	h.size = Vector2(r.size.x - 40, 60)
	box.add_child(h)
	var tier := int(Meta.raid_tier.get(pick, 0))
	var t := maxi(tier, 1)
	var rw := Meta.raid_reward(t)
	var line := "%s단계 보상: 골드 %d · 강화석 %d · 결정 %d%s" % ["최고 %d" % tier if tier > 0 else "1", rw["gold"], rw["stones"], rw["crystals"],
		" · 장비 %d" % rw["gear"] if rw["gear"] > 0 else ""]
	var rl := _label(line, 21, Color("fff2b0"), 5)
	rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rl.position = Vector2(20, 124)
	rl.size = Vector2(r.size.x - 40, 60)
	box.add_child(rl)
	var hint2 := _label("원정 %d챕터 기준 난이도 · 단계가 높을수록 보상이 커져요" % (Meta.raid_chapter() + 1), 18, Color("a9a4cb"), 4)
	hint2.position = Vector2(0, r.size.y - 36)
	hint2.size = Vector2(r.size.x, 28)
	box.add_child(hint2)

func _sweep() -> void:
	var r := Meta.raid_sweep(pick)
	if r.is_empty():
		return
	Sfx.play("chime", -6.0, 1.2)
	var t := "소탕 완료! " + CampScreen._reward_text(r)
	if not r.get("items", []).is_empty():
		t += " · " + ", ".join(r["items"].map(func(e): return Inventory.name_of(e)))
	_rebuild()
	_say(t)

static func _num(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
