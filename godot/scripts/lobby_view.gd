class_name LobbyView
extends Control
## Toy-camp lobby 2D layer: currency HUD + settings, the mission / attendance buttons, the reward pill over the
## campfire chest, the expedition sheet (tab, chapter row, objective, start, endless link) and the 5-tab bottom
## navigation. Presentation and input only: it shows a snapshot handed in by Lobby (refresh) and emits signals;
## rewards, saving and scene changes stay in Lobby / Meta / the existing screens.
## Layout is authored on the 720 x 1280 logical canvas: the top group sticks to the safe area's top, the bottom
## group (sheet + navigation) to its bottom, and a taller screen's spare height goes to the 3D camp between them.

signal equipment_requested
signal relics_requested
signal camp_requested          # the 캠프 tab (home): nothing to open
signal reward_requested        # chest / 보상 받기 -> CampScreen
signal challenge_requested
signal growth_requested
signal mission_requested
signal attendance_requested
signal settings_requested
signal chapter_step_requested(step: int)
signal expedition_requested
signal endless_requested

const W := 720.0
const BOTTOM_H := 476.0        # tab top (y=804) .. screen bottom (1280)
const NAV_H := 120.0

var blocked := false           # a screen is open on top: every button is inert
var reward_pos := Vector2(-999, -999)   # chest anchor projected to this control's space (Lobby updates it)

var _top: Control
var _bottom: Control
var _nav_bg: Panel
var _nav: Control
var _vals := {}                # currency key -> Label
var _chapter: Label
var _objective: Label
var _prev: Button
var _next: Button
var _start: Button
var _reward: Button
var _reward_label: Label
var _reward_dot: Control
var _reward_pill: Panel
var _gear_dot: Control
var _safe_top := 0.0
var _safe_bottom := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_reward()
	_build_top()
	_build_bottom()
	get_viewport().size_changed.connect(_layout)
	_layout()

## entrance: a short fade and a small rise (skipped on the quiet reload after a screen closes).
func enter(quiet: bool) -> void:
	if quiet:
		return
	for g in [_top, _bottom, _nav, _reward]:
		var c := g as Control
		var y := c.position.y
		c.modulate.a = 0.0
		c.position.y = y + (12.0 if g != _top else -12.0)
		var tw := c.create_tween().set_parallel()
		tw.tween_property(c, "modulate:a", 1.0, 0.28).set_delay(0.05)
		tw.tween_property(c, "position:y", y, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(0.05)

func _layout() -> void:
	var vs := get_viewport_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var scr := Vector2(DisplayServer.window_get_size())
	_safe_top = 0.0
	_safe_bottom = 0.0
	if scr.y > 0 and safe.size.y > 0 and safe.size.y < scr.y:   # notch / home indicator (mobile)
		_safe_top = safe.position.y * vs.y / scr.y
		_safe_bottom = (scr.y - safe.end.y) * vs.y / scr.y
	_top.position = Vector2((vs.x - W) * 0.5, _safe_top)
	_bottom.position = Vector2((vs.x - W) * 0.5, vs.y - _safe_bottom - BOTTOM_H)
	_nav_bg.position = Vector2(0, vs.y - _safe_bottom - NAV_H)
	_nav_bg.size = Vector2(vs.x, NAV_H + _safe_bottom)
	_nav.position = Vector2((vs.x - W) * 0.5, vs.y - _safe_bottom - NAV_H)

func _process(_delta: float) -> void:
	_place_reward()

# ---------------------------------------------------------------- data in
## s: gold, stones, crystals, chapter (name), first, last (arrow ends), objective, gear_alert, camp ("" | ready | full), camp_alert
func refresh(s: Dictionary) -> void:
	_set_value("gold", int(s["gold"]))
	_set_value("stones", int(s["stones"]))
	_set_value("crystals", int(s["crystals"]))
	_chapter.text = s["chapter"]
	var fs := 38
	_chapter.label_settings.font_size = fs
	while fs > 26 and _chapter.label_settings.font.get_string_size(_chapter.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > _chapter.size.x - 8:
		fs -= 2
		_chapter.label_settings.font_size = fs
	_chapter.autowrap_mode = TextServer.AUTOWRAP_WORD if fs <= 26 else TextServer.AUTOWRAP_OFF
	_objective.text = s["objective"]
	_set_arrow(_prev, not s["first"])
	_set_arrow(_next, not s["last"])
	_gear_dot.visible = s["gear_alert"]
	var camp: String = s["camp"]
	_reward_label.text = "보상 쌓는 중" if camp == "" else "보상 받기"
	_reward_label.label_settings.font_color = LobbyStyle.TEXT_SUB if camp == "" else LobbyStyle.TEXT
	_reward_pill.modulate.a = 0.82 if camp == "" else 1.0
	_reward_dot.visible = s["camp_alert"]
	var w := 164.0 if camp == "" else 140.0
	_reward_pill.size.x = w
	_reward_pill.position.x = (_reward.size.x - w) * 0.5
	_reward_label.size.x = w
	_reward_dot.position = Vector2(_reward_pill.position.x + w - 16, _reward_pill.position.y - 6)

static func fmt(v: int) -> String:
	if v >= 1_000_000_000:
		return "%.1fB" % (v / 1_000_000_000.0)
	if v >= 1_000_000:
		return ("%.2fM" if v < 10_000_000 else "%.1fM") % (v / 1_000_000.0)
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out

func _set_value(key: String, v: int) -> void:
	var l: Label = _vals[key]
	l.text = fmt(v)
	var fs := 30
	while fs > 22 and l.label_settings.font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > l.size.x:
		fs -= 1
	l.label_settings.font_size = fs

func _set_arrow(b: Button, on: bool) -> void:
	b.disabled = not on
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW
	(b.get_child(0) as Control).modulate = Color(1, 1, 1, 1) if on else Color(1, 1, 1, 0.35)

# ---------------------------------------------------------------- top
func _build_top() -> void:
	_top = Control.new()
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.size = Vector2(W, 360)
	add_child(_top)
	var cur := [["gold", "coin", 24.0, 188.0, LobbyStyle.VAL_GOLD], ["stones", "stone", 224.0, 160.0, LobbyStyle.VAL_STONE],
		["crystals", "crystal", 396.0, 188.0, LobbyStyle.VAL_CRYSTAL]]
	for c in cur:
		var pill := Panel.new()
		pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_theme_stylebox_override("panel", LobbyStyle.capsule())
		pill.position = Vector2(c[2], 32)
		pill.size = Vector2(c[3], 64)
		_top.add_child(pill)
		var ic := LobbyStyle.icon(c[1])
		ic.position = Vector2(6, 8)
		ic.size = Vector2(46, 46)
		pill.add_child(ic)
		var v := LobbyStyle.label("0", 30, c[4], LobbyStyle.num())
		v.position = Vector2(54, 0)
		v.size = Vector2(c[3] - 54 - 14, 60)
		pill.add_child(v)
		_vals[c[0]] = v
	# settings: 72 round button inside an 88 touch box
	var set_b := _plain_button(Rect2(608, 24, 88, 88))
	_top.add_child(set_b)
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_theme_stylebox_override("panel", LobbyStyle.capsule())
	disc.position = Vector2(8, 8)
	disc.size = Vector2(72, 72)
	set_b.add_child(disc)
	var g := LobbyStyle.icon("gear")
	g.position = Vector2(14, 12)
	g.size = Vector2(44, 44)
	g.pivot_offset = Vector2(22, 22)
	disc.add_child(g)
	set_b.button_down.connect(func(): _press_tween(g).tween_property(g, "rotation", g.rotation + PI / 4.0, 0.22).set_trans(Tween.TRANS_BACK))
	_wire(set_b, disc, settings_requested)
	# mission / attendance: cream buttons on the right edge
	_side_button(Rect2(608, 144, 88, 96), "mission", "미션", mission_requested)
	_side_button(Rect2(608, 256, 88, 96), "attend", "출석", attendance_requested)

func _side_button(r: Rect2, icon: String, text: String, sig: Signal) -> void:
	var b := _plain_button(r)
	_top.add_child(b)
	var face := Panel.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", LobbyStyle.raised(LobbyStyle.CREAM, LobbyStyle.CREAM_LIP, 22, 6))
	face.size = r.size
	b.add_child(face)
	var ic := LobbyStyle.icon(icon)
	ic.position = Vector2((r.size.x - 54) * 0.5, 6)
	ic.size = Vector2(54, 54)
	face.add_child(ic)
	var l := LobbyStyle.label(text, 22, LobbyStyle.TEXT)
	l.position = Vector2(0, 58)
	l.size = Vector2(r.size.x, 28)
	face.add_child(l)
	_wire(b, face, sig)

# ---------------------------------------------------------------- reward pill over the chest
func _build_reward() -> void:
	_reward = _plain_button(Rect2(0, 0, 176, 168))
	_reward.tooltip_text = ""
	add_child(_reward)
	_reward_pill = Panel.new()
	_reward_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reward_pill.add_theme_stylebox_override("panel", LobbyStyle.raised(LobbyStyle.CREAM, LobbyStyle.CREAM_LIP, 22, 4))
	_reward_pill.position = Vector2(18, 8)
	_reward_pill.size = Vector2(140, 46)
	_reward.add_child(_reward_pill)
	_reward_label = LobbyStyle.label("보상 받기", 22, LobbyStyle.TEXT)
	_reward_label.size = Vector2(140, 42)
	_reward_pill.add_child(_reward_label)
	_reward_dot = _dot(16)
	_reward.add_child(_reward_dot)
	_wire(_reward, _reward_pill, reward_requested)

## Pill bottom sits on the chest anchor; the touch box covers the pill and the chest under it.
func _place_reward() -> void:
	var p := reward_pos - Vector2(_reward.size.x * 0.5, 56)
	var vs := get_viewport_rect().size
	p.x = clampf(p.x, 8.0, vs.x - _reward.size.x - 8.0)
	_reward.position = p

# ---------------------------------------------------------------- bottom: sheet + navigation
func _build_bottom() -> void:
	_bottom = Control.new()
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.size = Vector2(W, BOTTOM_H)
	add_child(_bottom)

	var sheet := Panel.new()
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.add_theme_stylebox_override("panel", LobbyStyle.sheet())
	sheet.position = Vector2(16, 28)
	sheet.size = Vector2(688, 352)
	_bottom.add_child(sheet)

	# 원정 tab, overlapping the sheet's top edge
	var tab := Panel.new()
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_theme_stylebox_override("panel", LobbyStyle.raised(LobbyStyle.TEAL, LobbyStyle.TEAL_LIP, 28, 6))
	tab.position = Vector2(248, 0)
	tab.size = Vector2(224, 64)
	_bottom.add_child(tab)
	var map := LobbyStyle.icon("map")
	map.position = Vector2(46, 11)
	map.size = Vector2(40, 40)
	tab.add_child(map)
	var tl := LobbyStyle.label("원정", 32, Color.WHITE, LobbyStyle.ko(900))
	tl.position = Vector2(92, 0)
	tl.size = Vector2(90, 58)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tab.add_child(tl)

	# chapter row: ‹ name ›
	var row := Panel.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_stylebox_override("panel", LobbyStyle.inset(40))
	row.position = Vector2(92, 72)
	row.size = Vector2(536, 76)
	_bottom.add_child(row)
	_prev = _arrow_button(Rect2(84, 64, 104, 92), -1)
	_next = _arrow_button(Rect2(532, 64, 104, 92), 1)
	_chapter = LobbyStyle.label("", 38, LobbyStyle.TEXT, LobbyStyle.ko(900))
	_chapter.position = Vector2(196, 72)
	_chapter.size = Vector2(328, 76)
	_chapter.clip_text = false
	_bottom.add_child(_chapter)
	_objective = LobbyStyle.label("", 24, LobbyStyle.TEXT_SUB, LobbyStyle.ko(700))
	_objective.position = Vector2(160, 148)
	_objective.size = Vector2(400, 30)
	_bottom.add_child(_objective)

	# 출발
	_start = _plain_button(Rect2(72, 182, 576, 108))
	LobbyStyle.skin(_start, LobbyStyle.start_box(), LobbyStyle.start_box(true), LobbyStyle.start_box(false, true))
	_bottom.add_child(_start)
	var face := Control.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.size = Vector2(576, 96)
	_start.add_child(face)
	var go := LobbyStyle.label("출발", 56, LobbyStyle.TEXT, LobbyStyle.ko(900))
	var gw := go.label_settings.font.get_string_size("출발", HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x
	var tri := Triangle.new()
	var total := gw + 22.0 + 34.0
	go.position = Vector2((576 - total) * 0.5, 0)
	go.size = Vector2(gw, 92)
	face.add_child(go)
	tri.position = Vector2(go.position.x + gw + 22.0, 30)
	tri.size = Vector2(34, 36)
	face.add_child(tri)
	_wire(_start, face, expedition_requested, 7.0)

	# 끝없는 행군: thin mint pill, generous touch height
	var end_b := _plain_button(Rect2(168, 294, 384, 66))
	_bottom.add_child(end_b)
	var pill := Panel.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", LobbyStyle.raised(LobbyStyle.MINT, LobbyStyle.MINT_LIP, 24, 3, false, false))
	pill.position = Vector2(0, 10)
	pill.size = Vector2(384, 46)
	end_b.add_child(pill)
	var el := LobbyStyle.label("끝없는 행군", 24, LobbyStyle.TEXT, LobbyStyle.ko(800))
	var ew := el.label_settings.font.get_string_size("끝없는 행군", HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	el.position = Vector2((384 - ew - 22) * 0.5, 0)
	el.size = Vector2(ew, 42)
	pill.add_child(el)
	var chev := Chevron.new()
	chev.dir = 1
	chev.col = LobbyStyle.TEXT
	chev.width = 3.5
	chev.position = Vector2(el.position.x + ew + 10, 13)
	chev.size = Vector2(12, 18)
	pill.add_child(chev)
	_wire(end_b, pill, endless_requested, 2.0)

	# navigation: 장비 / 유물 / 캠프 / 도전 / 성장 (its bar covers the sheet's lower edge)
	_nav_bg = Panel.new()
	_nav_bg.mouse_filter = Control.MOUSE_FILTER_STOP   # taps between the tabs stop here, not in the camp
	_nav_bg.add_theme_stylebox_override("panel", LobbyStyle.nav_bar())
	add_child(_nav_bg)
	_nav = Control.new()
	_nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_nav.size = Vector2(W, NAV_H)
	add_child(_nav)
	var nav := _nav
	var items := [["nav_gear", "장비", equipment_requested], ["nav_relic", "유물", relics_requested], ["nav_camp", "캠프", camp_requested],
		["nav_raid", "도전", challenge_requested], ["nav_growth", "성장", growth_requested]]
	var cw := W / items.size()
	for x in [cw, cw * 4.0]:
		var sep := ColorRect.new()
		sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sep.color = Color(0.09, 0.23, 0.29, 0.08)
		sep.position = Vector2(x - 1, 30)
		sep.size = Vector2(2, 56)
		nav.add_child(sep)
	for i in items.size():
		var home: bool = i == 2
		var b := _plain_button(Rect2(i * cw, 0, cw, NAV_H))
		nav.add_child(b)
		var face2 := Control.new()
		face2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face2.size = Vector2(cw, NAV_H)
		b.add_child(face2)
		if home:
			var sel := Panel.new()
			sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			sel.add_theme_stylebox_override("panel", LobbyStyle.raised(LobbyStyle.TEAL, LobbyStyle.TEAL_LIP, 30, 5, false, false))
			sel.position = Vector2(8, -6)
			sel.size = Vector2(cw - 16, 118)
			face2.add_child(sel)
		var isz := 78.0 if home else 66.0
		var ic := LobbyStyle.icon(items[i][0])
		ic.position = Vector2((cw - isz) * 0.5, (4.0 if home else 10.0) - (6.0 if home else 0.0))
		ic.size = Vector2(isz, isz)
		face2.add_child(ic)
		var l := LobbyStyle.label(items[i][1], 24, Color.WHITE if home else LobbyStyle.TEXT, LobbyStyle.ko(800))
		l.position = Vector2(0, 76)
		l.size = Vector2(cw, 34)
		face2.add_child(l)
		if i == 0:
			_gear_dot = _dot(16)
			_gear_dot.position = Vector2(cw * 0.5 + 24, 8)
			face2.add_child(_gear_dot)
		_wire(b, face2, items[i][2], 3.0)

func _arrow_button(r: Rect2, step: int) -> Button:
	var b := _plain_button(r)
	_bottom.add_child(b)
	var face := Panel.new()
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_theme_stylebox_override("panel", LobbyStyle.raised(Color("fffdf6"), LobbyStyle.CREAM_LIP, 22, 4, false, false))
	face.position = Vector2(16, 16)
	face.size = Vector2(72, 58)
	b.add_child(face)
	var chev := Chevron.new()
	chev.dir = step
	chev.col = LobbyStyle.TEXT
	chev.width = 5.0
	chev.position = Vector2(27, 17)
	chev.size = Vector2(16, 22)
	face.add_child(chev)
	b.button_down.connect(func():
		if b.disabled:
			return
		_press_tween(face).tween_property(face, "position:y", 19.0, 0.06))
	b.button_up.connect(func(): _press_tween(face).tween_property(face, "position:y", 16.0, 0.14))
	b.pressed.connect(func():
		if not blocked and not b.disabled:
			chapter_step_requested.emit(step))
	return b

# ---------------------------------------------------------------- button plumbing
func _plain_button(r: Rect2) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.flat = false
	LobbyStyle.skin(b, LobbyStyle.none())
	b.position = r.position
	b.size = r.size
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b

## Press feel shared by every button: the face sinks `sink` px (onto its lip) and scales down a hair; release
## springs back. One press tween per face (rapid taps replace it instead of stacking).
func _wire(b: Button, face: Control, sig: Signal, sink := 4.0) -> void:
	var base_y := face.position.y
	face.pivot_offset = face.size * 0.5
	b.button_down.connect(func():
		if blocked:
			return
		var tw := _press_tween(face).set_parallel()
		tw.tween_property(face, "position:y", base_y + sink, 0.08)
		tw.tween_property(face, "scale", Vector2(0.97, 0.97), 0.08))
	b.button_up.connect(func():
		var tw := _press_tween(face).set_parallel()
		tw.tween_property(face, "position:y", base_y, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(face, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	b.pressed.connect(func():
		if not blocked:
			sig.emit())

func _press_tween(c: Control) -> Tween:
	var old: Tween = c.get_meta("press_tw") if c.has_meta("press_tw") else null
	if old and old.is_valid():
		old.kill()
	var tw := c.create_tween()
	c.set_meta("press_tw", tw)
	return tw

func _dot(d: float) -> Control:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := LobbyStyle.flat(LobbyStyle.ALERT, int(d * 0.5))
	sb.border_width_left = 2
	sb.border_width_right = 2
	sb.border_width_top = 2
	sb.border_width_bottom = 2
	sb.border_color = Color.WHITE
	p.add_theme_stylebox_override("panel", sb)
	p.size = Vector2(d, d)
	return p

## Chevron ‹ › (dir -1 / 1), round caps.
class Chevron extends Control:
	var dir := 1
	var col := Color.BLACK
	var width := 4.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var a := Vector2(0.0 if dir > 0 else size.x, 0)
		var m := Vector2(size.x if dir > 0 else 0.0, size.y * 0.5)
		var c := Vector2(a.x, size.y)
		draw_polyline(PackedVector2Array([a, m, c]), col, width, true)
		for p in [a, m, c]:
			draw_circle(p, width * 0.5, col)

## The ▶ on 출발: a soft-cornered triangle.
class Triangle extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var pts := PackedVector2Array([Vector2(3, 2), Vector2(size.x - 2, size.y * 0.5), Vector2(3, size.y - 2)])
		draw_colored_polygon(pts, LobbyStyle.TEXT)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), LobbyStyle.TEXT, 5.0, true)
