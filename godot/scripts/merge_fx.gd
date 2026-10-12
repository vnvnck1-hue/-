class_name MergeFx
extends Control
## Merge cutscene for the lobby [장비] / [유물] screens. Presentation only: the merge itself already happened
## (Meta.merge_all / Meta.merge_all_relics) and this just plays the steps it returned, {"in": [3], "out": e}.
##
## One step:  pop-in  -> the three materials appear in a triangle (rising pops)
##            charge  -> they orbit the centre faster and tighter, the light rays and the shake build up,
##                       sparks trail behind them (rise sfx)
##            impact  -> a short hit-stop, then a white flash, a shockwave ring, a particle burst and a hard shake
##            reveal  -> the result slams in with an overshoot, rays in its grade colour, the grade line
##                       ("희귀 → 영웅" / "★2 → ★3"), relic stars stamped one by one, fanfare; big results add confetti
## Tap: during the charge jumps straight to the impact, during the reveal finishes it, then goes to the next step.
## Several steps: a [모두 건너뛰기] button, and a results summary at the end. Emits `finished` when closed.

signal finished

var font: Font
var steps: Array = []
var INK: Color = UiTheme.ink()

var _i := -1
var _phase := ""            # "intro" | "charge" | "reveal" | "wait" | "summary"
var _stage: Control         # everything that shakes
var _rays: Rays
var _burst: Burst
var _flash: ColorRect
var _cards: Array = []
var _result: Control
var _texts: Array = []
var _tw: Tween
var _shake := 0.0
var _charge := 0.0          # 0..1 while charging (drives orbit, rays, shake, trail)
var _orbit_base := 0.0
var _trail_t := 0.0
var _hint: Label
var _skip_b: Button

const CARD := 150.0
const ORBIT_R := 230.0
const RESULT := 220.0
## Playback speed of the whole cutscene (every tween runs at this rate; the flow and beats stay the same).
const SPEED := 1.9
const BIG := ["legendary", "mythic", "ancient", "primal", "transcendent"]

## Plays `p_steps` over `parent` (a full-rect overlay). Returns the node; it frees itself when done.
static func play(parent: Node, p_font: Font, p_steps: Array) -> MergeFx:
	var fx := MergeFx.new()
	fx.font = p_font
	fx.steps = p_steps
	parent.add_child(fx)
	return fx

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.08, 0.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fast(bg.create_tween()).tween_property(bg, "color:a", 0.94, 0.22)
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rays = Rays.new()
	_stage.add_child(_rays)
	_burst = Burst.new()
	_burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_burst)
	_burst.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint = _label("", 26, Color(1, 1, 1, 0.85), 8)
	add_child(_hint)
	if steps.size() > 1:
		_skip_b = Button.new()
		_skip_b.focus_mode = Control.FOCUS_NONE
		_skip_b.text = "모두 건너뛰기 ▶▶"
		_skip_b.add_theme_font_override("font", font)
		_skip_b.add_theme_font_size_override("font_size", 24)
		for st in ["normal", "hover", "pressed"]:
			_skip_b.add_theme_stylebox_override(st, UiTheme.flat(Color(0.2, 0.18, 0.32, 0.85), 18, 3, INK))
		_skip_b.add_theme_color_override("font_outline_color", INK)
		_skip_b.add_theme_constant_override("outline_size", 6)
		add_child(_skip_b)
		_skip_b.pressed.connect(_summary)
	_next.call_deferred()

func _fast(t: Tween) -> Tween:
	return t.set_speed_scale(SPEED)

func _center() -> Vector2:
	return size * 0.5 + Vector2(0, -40)

func _process(delta: float) -> void:
	var c := _center()
	if _hint:
		_hint.position = Vector2(0, size.y - 150)
		_hint.size = Vector2(size.x, 40)
		if _phase == "wait" or _phase == "summary":
			_hint.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.006)
	if _skip_b:
		_skip_b.position = Vector2(size.x - 260, 24)
		_skip_b.size = Vector2(236, 60)
	_rays.position = c
	_rays.rotation += delta * (0.35 + _charge * 4.0)
	# charge: the three cards orbit inward, spinning up
	if _phase == "charge":
		var t := _charge
		var ang := _orbit_base + t * t * TAU * 2.6
		var r := ORBIT_R * (1.0 - 0.82 * t * t)
		for k in _cards.size():
			var card: Control = _cards[k]
			var a := ang + k * TAU / 3.0
			var p := c + Vector2(cos(a), sin(a)) * r
			card.position = p - card.size * 0.5
			card.rotation = sin(Time.get_ticks_msec() * 0.04 + k) * 0.25 * t
			card.scale = Vector2.ONE * (1.0 - 0.35 * t)
		_trail_t += delta
		if _trail_t > 0.02:
			_trail_t = 0.0
			for card in _cards:
				_burst.spark((card as Control).position + (card as Control).size * 0.5, _col_of(steps[_i]["in"][0]).lightened(0.3), 1, 60.0, 0.35, 5.0)
		_shake = maxf(_shake, t * 9.0)
	# shake
	if _shake > 0.05:
		_stage.position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		if _phase != "charge":
			_shake = lerpf(_shake, 0.0, minf(1.0, delta * 9.0 * SPEED))
	else:
		_stage.position = Vector2.ZERO
		_shake = 0.0

func _gui_input(ev: InputEvent) -> void:
	if not (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT):
		return
	accept_event()
	_tap()

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and (ev.keycode == KEY_ESCAPE or ev.keycode == KEY_SPACE or ev.keycode == KEY_ENTER):
		get_viewport().set_input_as_handled()
		if ev.keycode == KEY_ESCAPE and steps.size() > 1 and _phase != "summary":
			_summary()
		else:
			_tap()

func _tap() -> void:
	match _phase:
		"intro", "charge":
			_impact()
		"reveal":
			if _tw and _tw.is_valid():
				_tw.custom_step(5.0)   # finish the reveal at once
			_phase = "wait"
			_hint.text = "탭하여 계속"
		"wait":
			_next()
		"summary":
			_close()

# ---------------------------------------------------------------- one step
func _clear_step() -> void:
	for n in _cards + _texts:
		if is_instance_valid(n):
			n.queue_free()
	_cards.clear()
	_texts.clear()
	if _result and is_instance_valid(_result):
		_result.queue_free()
	_result = null
	_charge = 0.0
	if _tw:
		_tw.kill()

func _next() -> void:
	_i += 1
	if _i >= steps.size():
		if steps.size() > 1:
			_summary()
		else:
			_close()
		return
	_clear_step()
	var st: Dictionary = steps[_i]
	var c := _center()
	_hint.text = ""
	_hint.modulate.a = 1.0
	_rays.set_color(_col_of(st["in"][0]), 0.0)
	if steps.size() > 1:
		var cnt := _label("합성 %d / %d" % [_i + 1, steps.size()], 30, Color("ffe9a8"), 8)
		cnt.position = Vector2(0, 110)
		cnt.size = Vector2(size.x, 44)
		_stage.add_child(cnt)
		_texts.append(cnt)
	_orbit_base = -PI * 0.5
	_phase = "intro"
	_tw = _fast(create_tween())
	for k in 3:
		var e: Dictionary = st["in"][mini(k, st["in"].size() - 1)]
		var card := _card(e, CARD)
		var a := _orbit_base + k * TAU / 3.0
		card.position = c + Vector2(cos(a), sin(a)) * ORBIT_R - card.size * 0.5
		card.scale = Vector2.ZERO
		_stage.add_child(card)
		_cards.append(card)
		var kk := k
		_tw.tween_callback(func():
			Sfx.play("pop", -4.0, 1.0 + 0.18 * kk)
			_burst.spark(card.position + card.size * 0.5, _col_of(e), 10, 260.0, 0.45, 7.0))
		_tw.tween_property(card, "scale", Vector2.ONE, 0.17).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tw.tween_interval(0.04)
	_tw.tween_interval(0.12)
	_tw.tween_callback(func():
		_phase = "charge"
		Sfx.play("rise", -3.0, 0.9)
		Sfx.play("whoosh", -6.0, 0.7))
	var rays_col := _col_of(st["in"][0])
	_tw.tween_method(func(t: float):
		_charge = t
		_rays.set_color(rays_col, 0.15 + 0.5 * t), 0.0, 1.0, 0.95).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tw.tween_callback(_impact)

func _impact() -> void:
	if _phase != "intro" and _phase != "charge":
		return
	if _tw:
		_tw.kill()
	_phase = "impact"
	var st: Dictionary = steps[_i]
	var c := _center()
	for card in _cards:
		var cc: Control = card
		var tw := _fast(cc.create_tween()).set_parallel(true)
		tw.tween_property(cc, "position", c - cc.size * 0.5, 0.07).set_ease(Tween.EASE_IN)
		tw.tween_property(cc, "scale", Vector2.ONE * 0.2, 0.07)
	_charge = 0.0
	_shake = 4.0
	# hit-stop: everything holds for a beat, then the flash
	_tw = _fast(create_tween())
	_tw.tween_interval(0.1)
	_tw.tween_callback(func():
		for card in _cards:
			(card as Control).visible = false
		var out_col := _col_of(st["out"])
		_flash.color = Color(1, 1, 1, 0.95)
		_fast(_flash.create_tween()).tween_property(_flash, "color:a", 0.0, 0.45).set_ease(Tween.EASE_OUT)
		_shake = 26.0
		Sfx.play("boom", -2.0, 1.15)
		Sfx.play("clash", -5.0, 1.3)
		_burst.ring(c, out_col.lightened(0.4), 520.0, 0.5, 14.0)
		_burst.ring(c, Color.WHITE, 340.0, 0.35, 8.0)
		_burst.spark(c, out_col.lightened(0.2), 46, 720.0, 0.9, 10.0)
		_burst.spark(c, Color.WHITE, 22, 520.0, 0.6, 6.0)
		_reveal())

func _reveal() -> void:
	_phase = "reveal"
	var st: Dictionary = steps[_i]
	var out: Dictionary = st["out"]
	var c := _center()
	var col := _col_of(out)
	var big := _is_big(out)
	_rays.set_color(col, 0.0)
	var rt := _fast(_rays.create_tween())
	rt.tween_method(func(a: float): _rays.set_color(col, a), 0.0, 0.95 if big else 0.7, 0.35)
	_result = _card(out, RESULT)
	_result.position = c - _result.size * 0.5
	_result.scale = Vector2.ZERO
	_stage.add_child(_result)
	var glow := Glow.new()
	glow.col = col
	glow.size = _result.size
	glow.position = Vector2.ZERO
	glow.show_behind_parent = true
	_result.add_child(glow)
	var name_l := _label(_name_of(out), 46, col.lightened(0.45), 12)
	name_l.position = Vector2(0, c.y + RESULT * 0.5 + 34)
	name_l.size = Vector2(size.x, 64)
	name_l.pivot_offset = name_l.size * 0.5
	name_l.scale = Vector2(2.2, 2.2)
	name_l.modulate.a = 0.0
	_stage.add_child(name_l)
	_texts.append(name_l)
	var grade_l := _label(_grade_line(st), 34, Color("fff2b0"), 10)
	grade_l.position = Vector2(0, c.y + RESULT * 0.5 + 104)
	grade_l.size = Vector2(size.x, 50)
	grade_l.modulate.a = 0.0
	_stage.add_child(grade_l)
	_texts.append(grade_l)
	var up := _label("등급 UP!" if out["kind"] != "relic" else "★ UP!", 64, Color("ffd23f"), 16)
	up.position = Vector2(0, c.y - RESULT * 0.5 - 130)
	up.size = Vector2(size.x, 90)
	up.pivot_offset = up.size * 0.5
	up.rotation = -0.08
	up.scale = Vector2.ZERO
	_stage.add_child(up)
	_texts.append(up)
	_tw = _fast(create_tween())
	_tw.tween_property(_result, "scale", Vector2.ONE * 1.35, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_result, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_callback(func(): Sfx.play("fanfare", -4.0, 1.1 if big else 1.25))
	_tw.parallel().tween_property(up, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tw.tween_property(name_l, "modulate:a", 1.0, 0.01)
	_tw.parallel().tween_property(name_l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tw.tween_callback(func():
		_shake = 10.0
		Sfx.play("thud", -2.0, 1.1))
	_tw.tween_property(grade_l, "modulate:a", 1.0, 0.2)
	if out["kind"] == "relic":   # stars stamped one by one
		var n := int(out.get("star", 1))
		var sw := 52.0
		for s in n:
			var sl := _label("★", 56, Color("ffd23f"), 10)
			sl.size = Vector2(sw, 60)
			sl.pivot_offset = sl.size * 0.5
			sl.position = Vector2(c.x - n * sw * 0.5 + s * sw, c.y - RESULT * 0.5 - 60)
			sl.scale = Vector2.ZERO
			_stage.add_child(sl)
			_texts.append(sl)
			var last := s == n - 1
			_tw.tween_callback(func():
				Sfx.play("tick", -2.0, 1.2 + 0.15 * s)
				_burst.spark(sl.position + sl.size * 0.5, Color("ffd23f"), 8 if not last else 18, 240.0, 0.4, 6.0)
				if last:
					_shake = 8.0)
			_tw.tween_property(sl, "scale", Vector2.ONE, 0.14).from(Vector2.ONE * 2.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		up.position.y -= 50
	if big:
		_tw.tween_callback(func():
			Sfx.play("sparkle", -3.0, 1.0)
			_burst.confetti(Vector2(c.x, -20), size.x, 70))
	_tw.tween_callback(func():
		_phase = "wait"
		_hint.text = "탭하여 계속" if steps.size() > 1 else "탭하여 닫기")

# ---------------------------------------------------------------- summary / close
func _summary() -> void:
	if _phase == "summary":
		return
	_clear_step()
	_phase = "summary"
	if _skip_b:
		_skip_b.visible = false
	_rays.set_color(Color("ffd23f"), 0.45)
	var c := _center()
	var title := _label("합성 결과  %d회" % steps.size(), 52, Color("ffd23f"), 14)
	title.position = Vector2(0, 150)
	title.size = Vector2(size.x, 80)
	_stage.add_child(title)
	_texts.append(title)
	# group identical results: name -> count
	var shown := []
	var counts := {}
	for st in steps:
		var e: Dictionary = st["out"]
		var k := "%s#%d" % [e["key"], int(e.get("star", 0))]
		if not counts.has(k):
			counts[k] = 0
			shown.append(e)
		counts[k] += 1
	var cols := mini(4, shown.size())
	var cw := 150.0
	var gap := 18.0
	var rows := int(ceil(shown.size() / float(cols)))
	var y0 := c.y - rows * (cw + 60) * 0.5
	var tw := _fast(create_tween())
	for i in shown.size():
		var e: Dictionary = shown[i]
		var row := int(i / cols)
		var in_row := mini(cols, shown.size() - row * cols)
		var x := c.x - (in_row * cw + (in_row - 1) * gap) * 0.5 + (i % cols) * (cw + gap)
		var card := _card(e, cw - 10)
		card.position = Vector2(x + 5, y0 + row * (cw + 60))
		card.scale = Vector2.ZERO
		_stage.add_child(card)
		_cards.append(card)
		var k := "%s#%d" % [e["key"], int(e.get("star", 0))]
		if counts[k] > 1:
			var xl := _label("×%d" % counts[k], 34, Color.WHITE, 10)
			xl.position = Vector2(card.size.x - 70, card.size.y - 46)
			xl.size = Vector2(80, 44)
			card.add_child(xl)
		var nl := _label(_name_of(e), 20, _col_of(e).lightened(0.4), 6)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.position = Vector2(x - 4, y0 + row * (cw + 60) + cw - 6)
		nl.size = Vector2(cw + 8, 56)
		nl.modulate.a = 0.0
		_stage.add_child(nl)
		_texts.append(nl)
		var ii := i
		tw.tween_callback(func():
			Sfx.play("pop", -5.0, 1.0 + 0.06 * ii)
			_burst.spark(card.position + card.size * 0.5, _col_of(e), 10, 260.0, 0.4, 6.0))
		tw.tween_property(card, "scale", Vector2.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(nl, "modulate:a", 1.0, 0.16)
	tw.tween_callback(func(): Sfx.play("fanfare", -5.0, 1.2))
	_hint.text = "탭하여 닫기"

func _close() -> void:
	if _phase == "closing":
		return
	_phase = "closing"
	Sfx.play("click", -6.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := _fast(create_tween())
	tw.tween_property(self, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func():
		finished.emit()
		queue_free())

# ---------------------------------------------------------------- pieces
func _col_of(e: Dictionary) -> Color:
	return Defs.RARITY_COL.get(Inventory.rarity_of(e), Color("c8ccd8"))

func _is_big(e: Dictionary) -> bool:
	if e["kind"] == "relic":
		return int(e.get("star", 1)) >= 4 or (Defs.RELICS[e["key"]]["rarity"] == "legendary" and int(e.get("star", 1)) >= 3)
	return Inventory.rarity_of(e) in BIG

func _name_of(e: Dictionary) -> String:
	if e["kind"] == "relic":
		return Inventory.name_of(e)
	return Inventory.label_of(e)

func _grade_name(e: Dictionary) -> String:
	if e["kind"] == "relic":
		return "★%d" % int(e.get("star", 1))
	if Gear.is_family(e["key"]):
		return Gear.grade_name(Gear.grade_of_key(e["key"]))
	return HudPanels.RARITY_NAME.get(Inventory.rarity_of(e), "")

func _grade_line(st: Dictionary) -> String:
	var a := _grade_name(st["in"][0])
	var b := _grade_name(st["out"])
	if a == b:
		return "초월!"
	return "%s  →  %s" % [a, b]

## A rarity-framed item card (icon + relic ★ row), pivot at its centre.
func _card(e: Dictionary, sz: float) -> Panel:
	var p := Panel.new()
	p.size = Vector2(sz, sz)
	p.pivot_offset = p.size * 0.5
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c := _col_of(e)
	p.add_theme_stylebox_override("panel", UiTheme.flat(c.darkened(0.15), int(sz * 0.14), 5, INK))
	var ic := ItemIcon.new(e)
	ic.position = Vector2(sz * 0.08, sz * 0.06)
	ic.size = Vector2(sz * 0.84, sz * 0.84)
	p.add_child(ic)
	if e["kind"] == "relic":
		var st := _label("★".repeat(int(e.get("star", 1))), int(sz * 0.16), Color("ffd23f"), 6)
		st.position = Vector2(0, sz * 0.78)
		st.size = Vector2(sz, sz * 0.22)
		p.add_child(st)
	return p

func _label(text: String, fsize: int, color := Color.WHITE, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	var s := LabelSettings.new()
	s.font = font
	s.font_size = fsize
	s.font_color = color
	s.outline_size = outline
	s.outline_color = INK
	l.label_settings = s
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------------------------------------------------------------- drawn helpers
## Rotating light wedges behind the centre.
class Rays extends Control:
	var col := Color.WHITE
	var alpha := 0.0
	const N := 14
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_color(c: Color, a: float) -> void:
		col = c
		alpha = a
		queue_redraw()
	func _draw() -> void:
		if alpha <= 0.01:
			return
		var r := 900.0
		for i in N:
			var a0 := i * TAU / N
			var a1 := a0 + TAU / N * 0.45
			var cc := col.lightened(0.25)
			cc.a = alpha * 0.55
			var cols := PackedColorArray([cc, Color(cc, 0.0), Color(cc, 0.0)])
			draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(cos(a0), sin(a0)) * r, Vector2(cos(a1), sin(a1)) * r]), cols)
		for k in 4:   # soft core
			var core := col.lightened(0.5)
			core.a = alpha * 0.16
			draw_circle(Vector2.ZERO, 70.0 + k * 34.0, core)

## Pulsing halo drawn behind the result card.
class Glow extends Control:
	var col := Color.WHITE
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(_d: float) -> void:
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
		for k in 5:
			var cc := col.lightened(0.3)
			cc.a = 0.12 * (1.0 - k / 5.0) * (0.7 + 0.3 * pulse)
			draw_circle(c, size.x * (0.62 + k * 0.1 + 0.03 * pulse), cc)

## Lightweight 2D particles: sparks (star / diamond bits with drag), shockwave rings and falling confetti.
class Burst extends Control:
	var parts: Array = []   # {p, v, life, max, col, s, rot, w, g, kind}
	var rings: Array = []   # {p, r, max_r, life, max, col, w}
	func spark(at: Vector2, col: Color, n: int, speed: float, life: float, sz: float) -> void:
		for i in n:
			var a := randf() * TAU
			var v := Vector2(cos(a), sin(a)) * speed * randf_range(0.35, 1.0)
			parts.append({"p": at, "v": v, "life": life * randf_range(0.6, 1.0), "max": life, "col": col,
				"s": sz * randf_range(0.6, 1.3), "rot": randf() * TAU, "w": randf_range(-8, 8), "g": 300.0, "kind": randi() % 2})
	func ring(at: Vector2, col: Color, max_r: float, life: float, w: float) -> void:
		rings.append({"p": at, "max_r": max_r, "life": life, "max": life, "col": col, "w": w})
	func confetti(at: Vector2, width: float, n: int) -> void:
		var pal := [Color("ffd23f"), Color("ff6fd0"), Color("5fd0ff"), Color("8cff7a"), Color("ff7a5a"), Color.WHITE]
		for i in n:
			parts.append({"p": at + Vector2(randf_range(-width * 0.5, width * 0.5), randf_range(-200, 0)),
				"v": Vector2(randf_range(-60, 60), randf_range(120, 380)), "life": 2.6, "max": 2.6, "col": pal[i % pal.size()],
				"s": randf_range(7, 12), "rot": randf() * TAU, "w": randf_range(-10, 10), "g": 60.0, "kind": 2})
	func _process(delta: float) -> void:
		if parts.is_empty() and rings.is_empty():
			return
		delta *= 1.5   # bursts settle faster to match the quicker cutscene
		for p in parts:
			p["life"] -= delta
			var v: Vector2 = p["v"] * (1.0 - minf(1.0, delta * (1.2 if p["kind"] == 2 else 3.2)))
			v.y += p["g"] * delta
			p["v"] = v
			p["p"] = p["p"] + v * delta
			p["rot"] += p["w"] * delta
		parts = parts.filter(func(p): return p["life"] > 0.0)
		for r in rings:
			r["life"] -= delta
		rings = rings.filter(func(r): return r["life"] > 0.0)
		queue_redraw()
	func _draw() -> void:
		for r in rings:
			var t: float = 1.0 - r["life"] / r["max"]
			var c: Color = r["col"]
			c.a = 1.0 - t
			draw_arc(r["p"], r["max_r"] * (1.0 - pow(1.0 - t, 3.0)), 0.0, TAU, 64, c, r["w"] * (1.0 - t * 0.7), true)
		for p in parts:
			var c: Color = p["col"]
			c.a = clampf(p["life"] / p["max"] * 1.6, 0.0, 1.0)
			var s: float = p["s"]
			var x := Transform2D(p["rot"], p["p"])
			draw_set_transform_matrix(x)
			match p["kind"]:
				0:   # 4-point star
					draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s * 0.3, -s * 0.3), Vector2(s, 0), Vector2(s * 0.3, s * 0.3),
						Vector2(0, s), Vector2(-s * 0.3, s * 0.3), Vector2(-s, 0), Vector2(-s * 0.3, -s * 0.3)]), c)
				1:   # diamond
					draw_colored_polygon(PackedVector2Array([Vector2(0, -s * 0.8), Vector2(s * 0.5, 0), Vector2(0, s * 0.8), Vector2(-s * 0.5, 0)]), c)
				_:   # confetti strip (flutters by squashing with its spin)
					var w := s * absf(cos(p["rot"] * 1.7))
					draw_rect(Rect2(-w * 0.5, -s * 0.35, w, s * 0.7), c)
		draw_set_transform_matrix(Transform2D.IDENTITY)
