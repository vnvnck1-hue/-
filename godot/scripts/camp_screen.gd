class_name CampScreen
extends GearScreen
## Lobby [모닥불] screen: the campfire idle rewards (Meta.camp_*).
##   - the pile grows per minute while the game is away (gold / 강화석 / time crystals, rates by chapters cleared),
##     up to Meta.CAMP_MAX_MIN; the bar and amounts tick live while the screen is open.
##   - [받기] banks the pile; [빠른 정비] gives Meta.QUICK_MIN worth at once, Meta.QUICK_PER_DAY times a day.
## Shares GearScreen's open / close / style helpers; only the layout differs.

const CARD := Rect2(40, 250, 640, 780)

var _time_l: Label
var _bar: ProgressBar
var _amt := {}            # "gold" / "stones" / "crystals" -> Label (the pile)
var _claim_b: Button
var _quick_b: Button
var _tick := 0.0

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
	var title := _label("모닥불 야영지", 52, UiTheme.TXT_YELLOW if tt else Color("ffd23f"), 12)
	title.position = Vector2(0, 24)
	title.size = Vector2(w, 70)
	card.add_child(title)
	var x := _button("X", Color("8a8aa0"), Rect2(w - 86, 24, 64, 60), 30)
	x.pressed.connect(close)
	card.add_child(x)
	var fire := FireIcon.new()
	fire.position = Vector2(w * 0.5 - 70, 96)
	fire.size = Vector2(140, 140)
	card.add_child(fire)
	var sub := _label("영웅들이 쉬는 동안 보상이 쌓여요 (최대 %d시간)" % (Meta.CAMP_MAX_MIN / 60), 22, Color("cfe8ff"), 6)
	sub.position = Vector2(0, 240)
	sub.size = Vector2(w, 34)
	card.add_child(sub)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.max_value = Meta.CAMP_MAX_MIN
	_bar.position = Vector2(48, 286)
	_bar.size = Vector2(w - 96, 34)
	_bar.add_theme_stylebox_override("background", UiTheme.flat(UiTheme.BAR_TRACK, 14, 3, INK))
	_bar.add_theme_stylebox_override("fill", UiTheme.flat(UiTheme.ORANGE, 14, 3, INK))
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(_bar)
	_time_l = _label("", 22, Color.WHITE, 7)
	_time_l.position = _bar.position
	_time_l.size = _bar.size
	card.add_child(_time_l)
	# the pile: one row per currency, with the hourly rate on the right
	var rows := [["gold", Hud.CoinIcon.new(), Defs.COL_GOLD], ["stones", Hud.StoneIcon.new(), ItemIcon.STONE_COL], ["crystals", Hud.GemIcon.new(), Defs.COL_CRYSTAL]]
	var rate := Meta.camp_rate()
	for i in rows.size():
		var k: String = rows[i][0]
		var row := Panel.new()
		row.position = Vector2(48, 344 + i * 86)
		row.size = Vector2(w - 96, 74)
		row.add_theme_stylebox_override("panel", UiTheme.capsule(37))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(row)
		var ic: Control = rows[i][1]
		ic.position = Vector2(12, 10)
		ic.size = Vector2(54, 54)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)
		var a := _label("0", 36, rows[i][2], 8)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		a.position = Vector2(80, 0)
		a.size = Vector2(240, 74)
		row.add_child(a)
		_amt[k] = a
		var rl := _label("시간당 +%s" % _num(rate[k]), 22, Color("a9a4cb"), 6)
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rl.position = Vector2(row.size.x - 220, 0)
		rl.size = Vector2(200, 74)
		row.add_child(rl)
	_claim_b = _button("받기", UiTheme.YELLOW, Rect2(48, 616, w - 96, 84), 38)
	_claim_b.pressed.connect(_claim)
	card.add_child(_claim_b)
	_quick_b = _button("", UiTheme.GREEN, Rect2(48, 712, w - 96, 56), 26)
	_quick_b.pressed.connect(_quick)
	card.add_child(_quick_b)
	_toast_l = _label("", 28, Color("fff2b0"), 8)
	_toast_l.position = Vector2(0, CARD.end.y + 16)
	_toast_l.size = Vector2(W, 44)
	_body.add_child(_toast_l)
	_refresh()

## 1.5 -> "1.5", 3.0 -> "3".
func _num(v: float) -> String:
	return str(snappedf(v, 0.1)).trim_suffix(".0")

func _refresh() -> void:
	var m := Meta.camp_minutes()
	var r := Meta.camp_reward(m)
	_bar.value = m
	_time_l.text = ("가득 찼어요! " if Meta.camp_full() else "") + "%d시간 %02d분 / %d시간" % [m / 60, m % 60, Meta.CAMP_MAX_MIN / 60]
	for k in _amt:
		_amt[k].text = str(r[k])
	_claim_b.disabled = r.values().all(func(v): return v <= 0)
	_claim_b.modulate = Color(1, 1, 1, 0.55) if _claim_b.disabled else Color.WHITE
	var left := Meta.quick_left()
	_quick_b.text = "빠른 정비: %d시간치 즉시 받기 (오늘 %d/%d)" % [Meta.QUICK_MIN / 60, left, Meta.QUICK_PER_DAY]
	_quick_b.disabled = left <= 0
	_quick_b.modulate = Color(1, 1, 1, 0.55) if _quick_b.disabled else Color.WHITE

func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0 and _bar:
		_tick = 1.0
		_refresh()

func _claim() -> void:
	var r := Meta.claim_camp()
	if r.is_empty():
		return
	Sfx.play("chime", -6.0, 1.1)
	_say(_reward_text(r))
	_refresh()

func _quick() -> void:
	var r := Meta.quick_camp()
	if r.is_empty():
		return
	Sfx.play("chime", -6.0, 1.3)
	_say("빠른 정비! " + _reward_text(r))
	_refresh()

static func _reward_text(r: Dictionary) -> String:
	var parts := []
	for k in [["gold", "골드"], ["stones", "강화석"], ["crystals", "결정"]]:
		if int(r.get(k[0], 0)) > 0:
			parts.append("%s +%d" % [k[1], int(r[k[0]])])
	return " · ".join(parts)

## Crossed logs and a flickering two-tone flame (fonts on the web build have no fire emoji).
class FireIcon extends Control:
	var _t := 0.0
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.82)
		var s := minf(size.x, size.y) / 140.0
		draw_circle(c + Vector2(0, 8) * s, 52 * s, Color(1.0, 0.55, 0.15, 0.18 + 0.05 * sin(_t * 9.0)))
		for a in [-0.35, 0.35]:
			var d := Vector2.from_angle(a) * 48 * s
			draw_line(c - d, c + d, Color("3a2416"), 20 * s, true)
			draw_line(c - d, c + d, Color("8a5a34"), 14 * s, true)
		var f := 1.0 + 0.08 * sin(_t * 11.0) + 0.05 * sin(_t * 17.0)
		draw_colored_polygon(_flame(c, 34 * s, 92 * s * f, sin(_t * 7.0) * 6 * s), Color("ff7a2a"))
		draw_colored_polygon(_flame(c + Vector2(0, -2) * s, 20 * s, 58 * s * (2.0 - f), sin(_t * 9.0 + 1.0) * 5 * s), Color("ffd24a"))
	func _flame(base: Vector2, r: float, h: float, sway: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 13:   # a round bottom half-circle, then a tip that sways
			var a := PI * i / 12.0
			pts.append(base + Vector2(cos(a) * r, sin(a) * r * 0.5 - r * 0.2))
		pts.append(base + Vector2(-r * 0.7, -h * 0.45))
		pts.append(base + Vector2(sway, -h))
		pts.append(base + Vector2(r * 0.7, -h * 0.45))
		return pts
