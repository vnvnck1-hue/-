class_name RaidHud
extends Control
## Boss raid HUD, centred at the top of the screen (boss HP bar spec, adapted to the endless raid line-up):
##   name  — the boss's name in gold, the bars broken so far (×N) at the bar's right end
##   track — the boss's HP: a big layered bar. The raid boss never falls, so every emptied bar is one "layer";
##           layers cycle purple → green → blue → pink → red, the track behind shows the next layer's colour
##           (35% darker). A yellow delay chip trails the fill (held 0.25 s after a hit, then ~1 s to catch up).
##   timer — the raid's time left: blue > 25%, orange 10-25%, red flashing ≤ 10%; m:ss on the right
##   info  — total damage and the tier reached (secondary, small)
## Juice: intro (bar 1.22 → 0.94 → 1.04 → 1, name 2.9 → 1 glowing, fill wipes 0 → 100%, timer fills),
## hit flash + punch (crits / big hits shake the bar), layer break (flash 2.4x, squash, shake, glass shards),
## countdown ticks, and an exit sequence (flash, chip drains, the track splits from the middle, name floats away).
## Everything here is display only: MarchMain feeds set_state / set_hp / hit and calls intro / outro.

signal outro_done

const W := 640.0
const H := 128.0
const TRACK := Rect2(20, 34, 600, 38)
const PAD := 4.0
const FILL_W := 592.0                # TRACK width minus padding
const TIMER := Rect2(64, 82, 470, 12)
const LAYER_COLS := [Color("aa66ee"), Color("44dd99"), Color("55aadd"), Color("ee3399"), Color("ee5555")]
const CHIP_COL := Color("ffe082")
const CHIP_K := 0.035                 # per 60 fps frame
const CHIP_HOLD := 0.25
const SHAKE_T := 0.32

var hud: Hud
var _name: Label
var _plate: Panel
var _count: Label
var _track: Panel
var _track_sb: StyleBoxFlat
var _glow: Panel
var _chip: ColorRect
var _fill: ColorRect
var _timer_bg: Panel
var _timer_fill: ColorRect
var _timer_l: Label
var _info: Label
var _ratio := 1.0
var _chip_v := 1.0
var _chip_hold := 0.0
var _layer := -1
var _shake := 0.0
var _shake_amp := 0.0
var _base_x := 0.0
var _filling := false                 # intro wipe owns the fill / chip widths
var _timer_intro := false             # timer fill intro: no warning colours, label fixed
var _timer_k := 0.0
var _left := 90.0
var _total := 90.0
var _last_tick := -1
var _punch_at := -1.0
var _clock := 0.0
var _leaving := false
var _tweens := {}

func build(p_hud: Hud, boss_name: String) -> void:
	hud = p_hud
	size = Vector2(W, H)
	pivot_offset = Vector2(W * 0.5, TRACK.position.y + TRACK.size.y * 0.5)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := Panel.new()   # dark name plate: the name stays readable over banners and bright fields
	var pw := minf(W - 40.0, hud.font.get_string_size(boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 70.0)
	plate.position = Vector2((W - pw) * 0.5, 0)
	plate.size = Vector2(pw, 33)
	plate.add_theme_stylebox_override("panel", UiTheme.flat(Color(0.07, 0.05, 0.16, 0.92), 16, 3, Color(1.0, 0.82, 0.25, 0.85)))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	_plate = plate
	_name = hud.label(boss_name, 28, Color("ffd23f"), 9)
	_name.position = Vector2(0, -2)
	_name.size = Vector2(W, 36)
	_name.pivot_offset = Vector2(W * 0.5, 18)
	add_child(_name)
	_count = hud.label("", 20, Color.WHITE, 6)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.position = Vector2(TRACK.end.x - 140, 4)
	_count.size = Vector2(140, 28)
	add_child(_count)
	# gold outer glow (boss track), then the track itself
	_glow = Panel.new()
	_glow.position = TRACK.position - Vector2(5, 5)
	_glow.size = TRACK.size + Vector2(10, 10)
	_glow.add_theme_stylebox_override("panel", UiTheme.flat(Color(0, 0, 0, 0), 17, 3, Color(1.0, 0.82, 0.25, 0.85)))
	_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_glow)
	_track = Panel.new()
	_track.position = TRACK.position
	_track.size = TRACK.size
	_track.pivot_offset = TRACK.size * 0.5
	_track.clip_contents = true
	_track_sb = UiTheme.flat(UiTheme.BAR_TRACK, 12, 4, UiTheme.ink())
	_track.add_theme_stylebox_override("panel", _track_sb)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_track)
	_chip = _rect(_track, CHIP_COL, Rect2(PAD, PAD, FILL_W, TRACK.size.y - PAD * 2))
	_fill = _rect(_track, LAYER_COLS[0], Rect2(PAD, PAD, FILL_W, TRACK.size.y - PAD * 2))
	_rect(_track, Color(1, 1, 1, 0.18), Rect2(PAD, PAD, FILL_W, 8))   # gloss
	# time gauge
	var clock := ClockIcon.new()
	clock.position = Vector2(TIMER.position.x - 30, TIMER.position.y - 7)
	clock.size = Vector2(24, 24)
	add_child(clock)
	_timer_bg = Panel.new()
	_timer_bg.position = TIMER.position
	_timer_bg.size = TIMER.size
	_timer_bg.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BAR_TRACK, 6, 2, UiTheme.ink()))
	_timer_bg.clip_contents = true
	_timer_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_timer_bg)
	_timer_fill = _rect(_timer_bg, Color("4aa8ff"), Rect2(2, 2, TIMER.size.x - 4, TIMER.size.y - 4))
	_timer_l = hud.label("1:30", 22, Color.WHITE, 6)
	_timer_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_timer_l.position = Vector2(TIMER.end.x + 10, TIMER.position.y - 10)
	_timer_l.size = Vector2(70, 32)
	_timer_l.pivot_offset = Vector2(20, 16)
	add_child(_timer_l)
	_info = hud.label("", 20, Color("fff2b0"), 6)
	_info.position = Vector2(0, 100)
	_info.size = Vector2(W, 28)
	add_child(_info)
	visible = false
	_apply_layer(0)

func _rect(parent: Control, col: Color, r: Rect2) -> ColorRect:
	var c := ColorRect.new()
	c.color = col
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c

## Fresh tween under `key`, killing the previous one (no stacked scale / modulate tweens).
func _retween(node: Node, key: String) -> Tween:
	var old: Tween = _tweens.get(key)
	if old and old.is_valid():
		old.kill()
	var tw := node.create_tween()
	_tweens[key] = tw
	return tw

# ---------------------------------------------------------------- feeding
## Boss HP within the current layer (0..1) and the layers broken so far.
func set_hp(ratio: float, layers: int) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)
	if layers != _layer:
		var broke := _layer >= 0 and layers > _layer
		_apply_layer(layers)
		if broke:
			_layer_break(layers - 1)

func set_state(left: float, total: float, dmg: int, tier: int, frac: float, maxed: bool) -> void:
	_left = left
	_total = total
	_info.text = "피해 %s    ★ %d단계  %s" % [_num(dmg), tier, "최고 단계!" if maxed else "다음 %d%%" % int(clampf(frac, 0.0, 1.0) * 100.0)]
	if not _timer_intro:
		_timer_l.text = "%d:%02d" % [int(ceilf(left)) / 60, int(ceilf(left)) % 60]
		var s := int(ceilf(left))
		if s != _last_tick and left > 0.0:
			if s == 10 or s <= 5:   # countdown: one tick at 10 s, then every second from 5
				Sfx.play("tick", -4.0, 1.4 if s <= 5 else 1.1)
				if s <= 5:
					_timer_l.scale = Vector2(1.3, 1.3)
					_retween(_timer_l, "tl").tween_property(_timer_l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_last_tick = s

## A hit on the line-up. layer_hp: the struck boss's bar (big hits shake the bar a little).
func hit(amount: float, crit: bool, layer_hp: float) -> void:
	if not visible or _leaving:
		return
	_chip_hold = CHIP_HOLD
	_fill.modulate = Color(1.8, 1.8, 1.8)
	_retween(_fill, "flash").tween_property(_fill, "modulate", Color.WHITE, 0.08)
	if _clock - _punch_at >= 0.05:   # rapid multi-hits only refresh the flash
		_punch_at = _clock
		_track.scale = Vector2(1.0, 1.06)
		_retween(_track, "punch").tween_property(_track, "scale", Vector2.ONE, 0.08)
	if crit:
		_start_shake(4.0)
	elif amount >= layer_hp * 0.15:
		_start_shake(2.0)

func _start_shake(amp: float) -> void:
	if amp >= _shake_amp * (_shake / SHAKE_T):
		_shake = SHAKE_T
		_shake_amp = amp

# ---------------------------------------------------------------- layers
func _apply_layer(n: int) -> void:
	_layer = n
	_fill.color = LAYER_COLS[n % LAYER_COLS.size()]
	_track_sb.bg_color = (LAYER_COLS[(n + 1) % LAYER_COLS.size()] as Color).darkened(0.35)   # next layer preview
	_count.text = "×%d 파괴" % n if n > 0 else ""

func _layer_break(broken: int) -> void:
	_chip_v = 1.0
	_chip_hold = 0.0
	_track.modulate = Color(2.4, 2.4, 2.4)
	var tw := _retween(_track, "punch")
	tw.tween_property(_track, "scale", Vector2(1.04, 1.15), 0.06)
	tw.tween_property(_track, "scale", Vector2.ONE, 0.2)
	_retween(_track, "bright").tween_property(_track, "modulate", Color.WHITE, 0.32)
	_start_shake(4.0)
	_count.scale = Vector2(1.5, 1.5)
	_count.pivot_offset = Vector2(110, 14)
	_retween(_count, "count").tween_property(_count, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Sfx.play("clash", -6.0, 1.6)
	_shards(LAYER_COLS[broken % LAYER_COLS.size()], 6 + mini(broken, 4) / 2 * 2)

## Glass shards of the broken layer's colour, flung from the bar's right end.
func _shards(col: Color, n: int) -> void:
	var from := TRACK.position + Vector2(PAD + FILL_W * clampf(_ratio, 0.15, 1.0), TRACK.size.y * 0.5)
	for i in n:
		var s := ColorRect.new()
		s.color = col.lightened(randf() * 0.3)
		s.size = Vector2(randf_range(6, 12), randf_range(4, 9))
		s.pivot_offset = s.size * 0.5
		s.position = from - s.size * 0.5
		s.rotation = randf() * TAU
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(s)
		var to := from + Vector2(randf_range(-40, 90), randf_range(-60, 50))
		var tw := s.create_tween().set_parallel(true)
		tw.tween_property(s, "position", to - s.size * 0.5, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "rotation", s.rotation + randf_range(-6, 6), 0.5)
		tw.tween_property(s, "modulate:a", 0.0, 0.5).set_delay(0.15)
		tw.chain().tween_callback(s.queue_free)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	_clock += delta
	if not visible:
		return
	var inner := TRACK.size.y - PAD * 2
	if not _filling and not _leaving:
		_fill.size = Vector2(FILL_W * _ratio, inner)
		if _ratio > _chip_v:
			_chip_v = _ratio   # healing: the chip follows at once
		elif _chip_hold > 0.0:
			_chip_hold -= delta
		else:
			_chip_v += (_ratio - _chip_v) * CHIP_K * 60.0 * delta
			if absf(_chip_v - _ratio) < 0.002:
				_chip_v = _ratio
		_chip.size = Vector2(FILL_W * _chip_v, inner)
	# shake (whole HUD sideways, decaying)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta)
		position.x = _base_x + sin(_shake * 90.0) * _shake_amp * (_shake / SHAKE_T)
	else:
		position.x = _base_x
	# time gauge
	if not _timer_intro:
		var k := clampf(_left / maxf(_total, 0.001), 0.0, 1.0)
		_timer_k = k
		var col := Color("4aa8ff")
		if k <= 0.1:
			col = Color("ff4a4a").lerp(Color.WHITE, 0.5 + 0.5 * sin(_clock * 20.0))
		elif k <= 0.25:
			col = Color("ff9a3a")
		_timer_fill.color = col
		_timer_l.add_theme_color_override("font_color", Color("ff6a6a") if k <= 0.1 else Color.WHITE)
	_timer_fill.size.x = (TIMER.size.x - 4) * _timer_k

# ---------------------------------------------------------------- intro / outro
## The raid begins: the bar bursts in, the name lands, HP wipes in from the left, then the timer fills.
func intro() -> void:
	_base_x = position.x
	visible = true
	_filling = true
	_timer_intro = true
	_timer_k = 0.0
	_timer_l.text = "%d:%02d" % [int(_total) / 60, int(_total) % 60]
	_fill.size.x = 0.0
	_chip.size.x = 0.0
	scale = Vector2(1.22, 1.22)
	var tw := _retween(self, "intro")
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2(1.04, 1.04), 0.2)
	tw.tween_property(self, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_name.scale = Vector2(2.9, 2.9)
	_name.modulate = Color(3, 3, 3, 0)
	var nt := _retween(_name, "name").set_parallel(true)
	nt.tween_property(_name, "scale", Vector2.ONE, 0.78).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	nt.tween_property(_name, "modulate", Color.WHITE, 0.78)
	Sfx.play("clash", -4.0, 0.8)
	var wipe := _retween(_fill, "wipe")
	wipe.tween_interval(0.34)
	wipe.tween_method(func(v: float) -> void:
		var inner := TRACK.size.y - PAD * 2
		_fill.size = Vector2(FILL_W * v * _ratio, inner)
		_chip.size = Vector2(FILL_W * v * _ratio, inner), 0.0, 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	wipe.tween_callback(func():
		_filling = false
		_chip_v = _ratio
		Sfx.play("sparkle", -8.0, 1.2))
	var tt := _retween(_timer_fill, "timer")
	tt.tween_interval(0.34)
	tt.tween_property(self, "_timer_k", 1.0, 1.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tt.tween_callback(func(): _timer_intro = false)

## The raid is over: flash, the chip drains what the last stretch took, the track splits from the middle and the
## name floats away. Emits outro_done after ~0.9 s.
func outro() -> void:
	if _leaving or not visible:
		outro_done.emit.call_deferred()
		return
	_leaving = true
	_shake = 0.0
	position.x = _base_x
	_track.modulate = Color(3, 3, 3)
	_retween(_track, "bright").tween_property(_track, "modulate", Color.WHITE, 0.3)
	var inner := TRACK.size.y - PAD * 2
	_chip.size = Vector2(maxf(_chip.size.x, _fill.size.x), inner)
	var drain := _retween(_chip, "drain").set_parallel(true)
	drain.tween_property(_fill, "size:x", 0.0, 0.12)
	drain.tween_property(_chip, "size:x", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	var tw := _retween(self, "outro")
	tw.tween_interval(0.4)
	tw.tween_callback(func(): Sfx.play("clash", -6.0, 0.7))
	tw.tween_property(_track, "scale:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_glow, "scale:x", 0.0, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_name, "position:y", _name.position.y - 20.0, 0.45)
	tw.parallel().tween_property(_name, "modulate:a", 0.0, 0.45)
	tw.parallel().tween_property(_plate, "modulate:a", 0.0, 0.45)
	tw.parallel().tween_property(_count, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(_timer_bg, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(_timer_l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func():
		visible = false
		outro_done.emit())

static func _num(v: int) -> String:
	var s := str(v)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out

## Tiny stopwatch in front of the time gauge.
class ClockIcon extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5 + Vector2(0, 1)
		var r := minf(size.x, size.y) * 0.42
		draw_rect(Rect2(c + Vector2(-3, -r - 5), Vector2(6, 4)), UiTheme.ink())
		draw_circle(c, r + 2.0, UiTheme.ink())
		draw_circle(c, r, Color("dff0ff"))
		draw_line(c, c + Vector2(0, -r * 0.7), UiTheme.ink(), 2.5)
		draw_line(c, c + Vector2(r * 0.5, 0), UiTheme.ink(), 2.5)
