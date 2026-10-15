class_name MissionScreen
extends GearScreen
## Lobby [미션] screen: daily and weekly missions (Meta.DAILY / Meta.WEEKLY / Meta.DAILY_BOXES).
##   - tabs: 일일 (resets at midnight) / 주간 (resets on Monday), each badged with what can be collected.
##   - daily: the activity track (points 0..100) with five boxes at 20 / 40 / 60 / 80 / 100 — tap a lit box to open
##     it — then one row per mission: progress bar, count and [받기] (+20 activity) / 완료.
##   - weekly: one row per mission with its reward; [받기] pays it directly.
## Shares GearScreen's open / close / style helpers; only the layout differs.

const ROW_H := 92.0
const TRACK := Rect2(140, 282, 500, 22)

var weekly := false
var _boxes: Array = []

func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	_boxes.clear()
	var tt := UiTheme.tt()
	var title := _label("미션", 60, UiTheme.TXT_YELLOW if tt else Color("ffd23f"), 14)
	title.position = Vector2(0, 22)
	title.size = Vector2(W, 80)
	_body.add_child(title)
	var x := _button("X", Color("8a8aa0"), Rect2(W - 92, 28, 70, 66), 34)
	x.pressed.connect(close)
	_body.add_child(x)
	for i in 2:
		var wk := i == 1
		var on := wk == weekly
		var b := _button("주간" if wk else "일일", UiTheme.ORANGE if on else Color("5a5478"), Rect2(W * 0.5 - 210 + i * 220, 108, 200, 66), 32)
		b.pressed.connect(func():
			if weekly != wk:
				weekly = wk
				Sfx.play("click", -6.0)
				_rebuild())
		_body.add_child(b)
		var n := _ready_count(wk)
		if n > 0:
			var badge := Panel.new()
			badge.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.RED, 15, 3, INK))
			badge.position = Vector2(166, -10)
			badge.size = Vector2(30, 30)
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(badge)
			var bl := _label(str(n), 18, Color.WHITE, 4)
			bl.size = badge.size
			badge.add_child(bl)
	var reset := _label("매주 월요일 초기화 · %s" % _week_left() if weekly else "매일 자정 초기화", 20, Color("a9a4cb"), 5)
	reset.position = Vector2(0, 178)
	reset.size = Vector2(W, 30)
	_body.add_child(reset)
	var y := 214.0
	if not weekly:
		_activity()
		y = 352.0
	var list: Array = Meta.WEEKLY if weekly else Meta.DAILY
	for m in list:
		_row(m, Rect2(28, y, W - 56, ROW_H))
		y += ROW_H + 10.0
	_toast_l = _label("", 26, Color("fff2b0"), 8)
	_toast_l.position = Vector2(0, y + 6)
	_toast_l.size = Vector2(W, 70)
	_toast_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(_toast_l)

func _ready_count(wk: bool) -> int:
	var n := 0
	for m in (Meta.WEEKLY if wk else Meta.DAILY):
		if Meta.mission_state(m["id"], wk) == "claim":
			n += 1
	if not wk:
		for i in Meta.DAILY_BOXES.size():
			if Meta.box_state(i) == "claim":
				n += 1
	return n

static func _week_left() -> String:
	var wd := int(Time.get_date_dict_from_system()["weekday"])   # 0 = Sunday
	var left := (8 - wd) % 7
	return "%d일 남음" % (7 if left == 0 else left)

# ---------------------------------------------------------------- daily activity track
func _activity() -> void:
	var cap: float = Meta.DAILY_BOXES[-1]["at"]
	var pl := _label("활동 점수", 22, Color("cfe8ff"), 6)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	pl.position = Vector2(28, TRACK.position.y - 30)
	pl.size = Vector2(110, 30)
	_body.add_child(pl)
	var v := _label(str(Meta.mis_points), 30, Color("ffd23f"), 8)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.position = Vector2(40, TRACK.position.y - 4)
	v.size = Vector2(90, 36)
	_body.add_child(v)
	var bg := Panel.new()
	bg.position = TRACK.position
	bg.size = TRACK.size
	bg.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BAR_TRACK, 11, 3, INK))
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(bg)
	var k := clampf(Meta.mis_points / cap, 0.0, 1.0)
	if k > 0.0:
		var fill := Panel.new()
		fill.position = TRACK.position
		fill.size = Vector2(maxf(TRACK.size.y, TRACK.size.x * k), TRACK.size.y)
		fill.add_theme_stylebox_override("panel", UiTheme.flat(Color("ffb43c"), 11, 3, INK))
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(fill)
	for i in Meta.DAILY_BOXES.size():
		var at: float = Meta.DAILY_BOXES[i]["at"]
		var cx := TRACK.position.x + TRACK.size.x * at / cap
		var st := Meta.box_state(i)
		var box := BoxIcon.new()
		box.state = st
		box.big = i == Meta.DAILY_BOXES.size() - 1
		box.size = Vector2(56, 52)
		box.position = Vector2(cx - 28, TRACK.position.y - 56)
		box.pivot_offset = box.size * 0.5
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		box.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_open_box(idx))
		_body.add_child(box)
		_boxes.append(box)
		if st == "claim":
			var tw := box.create_tween().set_loops()
			tw.tween_property(box, "scale", Vector2(1.12, 1.12), 0.4).set_trans(Tween.TRANS_SINE)
			tw.tween_property(box, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)
		var al := _label(str(int(at)), 18, Color.WHITE, 5)
		al.position = Vector2(cx - 30, TRACK.position.y + TRACK.size.y + 2)
		al.size = Vector2(60, 26)
		_body.add_child(al)

func _open_box(i: int) -> void:
	var r := Meta.open_box(i)
	if r.is_empty():
		if Meta.box_state(i) == "open":
			_say("활동 점수 %d이 필요해요" % int(Meta.DAILY_BOXES[i]["at"]))
		return
	Sfx.play("chime", -4.0, 1.2)
	var at: Vector2 = _boxes[i].position + _boxes[i].size * 0.5
	_rebuild()
	var burst := Hud.RayBurst.new()
	burst.size = Vector2(200, 200)
	burst.position = at - burst.size * 0.5
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(burst)
	var bt := burst.create_tween()
	bt.tween_property(burst, "modulate:a", 0.0, 0.8)
	bt.tween_callback(burst.queue_free)
	_say("상자 열기! " + reward_text(r))

# ---------------------------------------------------------------- mission rows
func _row(m: Dictionary, r: Rect2) -> void:
	var st := Meta.mission_state(m["id"], weekly)
	var prog := Meta.mission_progress(m["id"], weekly)
	var goal := int(m["goal"])
	var row := Panel.new()
	row.position = r.position
	row.size = r.size
	var col := Color("4c467b") if st != "done" else Color("3a3660")
	row.add_theme_stylebox_override("panel", UiTheme.night_card(20) if UiTheme.tt() and st != "done" else _box(col, 20, 4))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(row)
	var t := _label(m["text"], 24, Color.WHITE if st != "done" else Color("a9a4cb"), 7)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.position = Vector2(20, 8)
	t.size = Vector2(r.size.x - 200, 34)
	row.add_child(t)
	var sub := ("보상: " + reward_text(m["reward"])) if weekly else "활동 +%d" % Meta.ACTIVITY
	var sl := _label(sub, 18, Color("fff2b0") if st != "done" else Color("8a86a8"), 5)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sl.position = Vector2(20, 60)
	sl.size = Vector2(r.size.x - 200, 26)
	row.add_child(sl)
	var bar := Panel.new()
	bar.position = Vector2(20, 44)
	bar.size = Vector2(r.size.x - 290, 14)
	bar.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BAR_TRACK, 7, 2, INK))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	var k := clampf(float(prog) / goal, 0.0, 1.0)
	if k > 0.0:
		var f := Panel.new()
		f.position = bar.position
		f.size = Vector2(maxf(14.0, bar.size.x * k), 14)
		f.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.GREEN if k >= 1.0 else Color("4aa8ff"), 7, 2, INK))
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(f)
	var cnt := _label("%d/%d" % [prog, goal], 20, Color.WHITE, 5)
	cnt.position = Vector2(r.size.x - 266, 36)
	cnt.size = Vector2(80, 30)
	row.add_child(cnt)
	var bw := Rect2(r.size.x - 172, 16, 156, 60)
	match st:
		"claim":
			var b := _button("받기", UiTheme.YELLOW, bw, 28)
			var id: String = m["id"]
			b.pressed.connect(func(): _claim(id))
			row.add_child(b)
			b.pivot_offset = b.size * 0.5
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "scale", Vector2(1.06, 1.06), 0.45).set_trans(Tween.TRANS_SINE)
			tw.tween_property(b, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
		"done":
			var d := _label("✓ 완료", 26, Color("7cff6a"), 7)
			d.position = bw.position
			d.size = bw.size
			row.add_child(d)
		_:
			var o := _label("진행 중", 22, Color("a9a4cb"), 5)
			o.position = bw.position
			o.size = bw.size
			row.add_child(o)

func _claim(id: String) -> void:
	var r := Meta.claim_mission(id, weekly)
	if r.is_empty():
		return
	Sfx.play("chime", -6.0, 1.3)
	_rebuild()
	_say("활동 점수 +%d!" % int(r["points"]) if not weekly else "주간 보상! " + reward_text(r))

static func reward_text(r: Dictionary) -> String:
	var t := CampScreen._reward_text(r)
	var g := int(r.get("gear", 0))
	if g > 0:
		t += (" · " if t != "" else "") + "장비 %d" % g
	return t

## Treasure box on the activity track: grey (locked), gold and glowing (ready), open with a tick (taken).
class BoxIcon extends Control:
	var state := "open"
	var big := false
	func _draw() -> void:
		var ink := UiTheme.ink()
		var w := size.x * (0.86 if big else 0.74)
		var h := size.y * 0.62
		var body := Rect2(Vector2((size.x - w) * 0.5, size.y - h - 2), Vector2(w, h))
		var col := Color("8a86a8")
		if state == "claim":
			col = Color("ffb43c") if not big else Color("ff7ad0")
			draw_circle(body.get_center(), w * 0.62, Color(1.0, 0.85, 0.3, 0.35))
		elif state == "done":
			col = Color("6a6488")
		draw_rect(body.grow(3), ink)
		draw_rect(body, col)
		var lid_y := body.position.y - (h * 0.45 if state == "done" else 0.0)
		var lid := Rect2(Vector2(body.position.x - 3, lid_y - h * 0.32), Vector2(w + 6, h * 0.36))
		draw_rect(lid.grow(3), ink)
		draw_rect(lid, col.lightened(0.15))
		draw_rect(Rect2(body.get_center() - Vector2(5, h * 0.2), Vector2(10, 12)), ink)   # latch
		if state == "done":
			var c := body.get_center()
			draw_polyline(PackedVector2Array([c + Vector2(-10, 0), c + Vector2(-2, 8), c + Vector2(12, -8)]), Color("7cff6a"), 5.0)
