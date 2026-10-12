class_name HudMobile
extends Node
## Mobile-game style chrome for March mode:
##   - bottom navigation bar with 5 main buttons (상점 / 영웅 / 전투 / 특성 / 도감). Only 특성 works
##     (opens the talent tree); the others are placeholders that look real but don't react.
##   - a row of small round skill indicators right above the bag: each hero's mana skill and ultimate,
##     showing charge / cooldown and flashing when the skill is cast, in real time.

var INK: Color = UiTheme.ink()
const NAV_H := 118.0
const NAV := [
	{"id": "shop", "text": "상점", "live": false, "badge": true},
	{"id": "hero", "text": "영웅", "live": false, "badge": false},
	{"id": "battle", "text": "전투", "live": false, "badge": false, "current": true},
	{"id": "talent", "text": "특성", "live": true, "badge": false},
	{"id": "codex", "text": "도감", "live": false, "badge": false},
]
const SHORT_ACTIVE := {"warrior": "강습", "ranger": "사격", "mage": "영도"}
const SHORT_ULT := {"warrior": "충격", "ranger": "포화", "mage": "번개"}

var hud: Hud
var game: Node
var dials: Array = []

func build() -> void:
	_build_nav()
	_build_dials()

# ---------------------------------------------------------------- bottom navigation
func _build_nav() -> void:
	var bar := hud.panel(Color(0.09, 0.07, 0.18, 0.9), Rect2(0, 0, 720, NAV_H), 0, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 0
	bar.offset_right = 0
	bar.offset_top = -NAV_H
	bar.offset_bottom = 0
	var sb := hud.box(Color(UiTheme.NIGHT_DEEP, 0.97), 0, 0)
	sb.border_width_top = 5
	sb.border_color = UiTheme.ink()
	if not UiTheme.tt():
		sb = hud.box(Color(0.09, 0.07, 0.18, 0.92), 0, 0)
		sb.border_width_top = 4
		sb.border_color = Color("3a2f66")
	bar.add_theme_stylebox_override("panel", sb)
	hud.root.add_child(bar)
	var cells := HBoxContainer.new()
	cells.set_anchors_preset(Control.PRESET_FULL_RECT)
	cells.add_theme_constant_override("separation", 0)
	cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(cells)
	for n in NAV:
		cells.add_child(_nav_button(n))

func _nav_button(n: Dictionary) -> Control:
	var cell := Control.new()
	cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cell.custom_minimum_size = Vector2(100, NAV_H)
	cell.mouse_filter = Control.MOUSE_FILTER_STOP if n["live"] else Control.MOUSE_FILTER_IGNORE
	var current: bool = n.get("current", false)
	if current:
		var bg := hud.panel(Color("ff9f1c"), Rect2(0, 0, 112, 112), 30, 5)
		if UiTheme.tt():
			bg.add_theme_stylebox_override("panel", UiTheme.button_box(UiTheme.YELLOW, 28))
		bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
		bg.offset_left = -56
		bg.offset_right = 56
		bg.offset_top = -26
		bg.offset_bottom = 86
		cell.add_child(bg)
	var icon := NavIcon.new()
	icon.kind = n["id"]
	icon.big = current
	var isz := 64.0 if current else 50.0
	icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
	icon.offset_left = -isz * 0.5
	icon.offset_right = isz * 0.5
	icon.offset_top = -12.0 if current else 12.0
	icon.offset_bottom = icon.offset_top + isz
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	var l := hud.label(n["text"], 24 if current else 22, Color.WHITE if current or n["live"] else (UiTheme.TXT_DIM if UiTheme.tt() else Color("d8d2f0")), 8)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.offset_left = -60
	l.offset_right = 60
	l.offset_top = 64 if current else 66
	l.offset_bottom = l.offset_top + 34
	cell.add_child(l)
	if n["badge"]:
		var b := hud.panel(UiTheme.RED if UiTheme.tt() else Color("ff4f5e"), Rect2(0, 0, 24, 24), 12, 3)
		b.set_anchors_preset(Control.PRESET_CENTER_TOP)
		b.offset_left = 14
		b.offset_right = 38
		b.offset_top = 8
		b.offset_bottom = 32
		cell.add_child(b)
		var bl := hud.label("!", 16, Color.WHITE, 4)
		bl.size = Vector2(24, 24)
		b.add_child(bl)
	if n["live"]:
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
				if ev.pressed:
					icon.pivot_offset = icon.size * 0.5
					icon.scale = Vector2(0.85, 0.85)
					Sfx.play("click", -6.0)
				else:
					var tw := icon.create_tween()
					tw.tween_property(icon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
					if n["id"] == "talent" and not hud.has_overlay():
						hud.open_talents())
	return cell

# ---------------------------------------------------------------- skill indicators
func _build_dials() -> void:
	var row := Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := 3 * (58 * 2 + 6) + 2 * 30.0
	hud.root.add_child(hud.place(row, Vector2(0.5, 1), Vector2(-w * 0.5, -412), Vector2(w, 64)))
	var x := 0.0
	for cls in Defs.HERO_ORDER:
		for kind in ["active", "ult"]:
			var d := SkillDial.new()
			d.game = game
			d.cls = cls
			d.kind = kind
			d.font = hud.font
			d.text = SHORT_ACTIVE[cls] if kind == "active" else SHORT_ULT[cls]
			d.col = Hud.HERO_COL[cls]
			d.position = Vector2(x, 3)
			d.size = Vector2(58, 58)
			d.pivot_offset = d.size * 0.5
			d.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(d)
			dials.append(d)
			x += 64.0
		x += 30.0 - 6.0

## One round skill indicator: charge / cooldown sweep, ready glow, flash on cast.
class SkillDial extends Control:
	var INK: Color = UiTheme.ink()
	var game: Node
	var cls := ""
	var kind := "active"
	var text := ""
	var col := Color.WHITE
	var font: Font
	var _flash := 0.0
	var _last := -1.0
	var _t := 0.0
	var _cd := 0.0

	func _process(delta: float) -> void:
		var real := delta / maxf(Engine.time_scale, 0.001)
		_t += real
		_flash = maxf(0.0, _flash - real * 2.5)
		var h: Actor = game.hero(cls) if game else null
		if h:
			# cast detection: mana dropped (skill) / cooldown restarted (ultimate)
			var v: float = h.mana if kind == "active" else h.ult_ready_at
			if _last >= 0.0 and ((kind == "active" and v < _last - 40.0) or (kind == "ult" and v > _last + 0.5)):
				_flash = 1.0
				if kind == "ult":
					_cd = maxf(0.1, h.ult_ready_at - game.now)
				scale = Vector2(1.3, 1.3)
				Hud.retween(self).set_ignore_time_scale(true).tween_property(self, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
			_last = v
		queue_redraw()

	func _ratio(h: Actor) -> float:
		if kind == "active":
			return clampf(h.mana / Defs.MAX_MANA, 0.0, 1.0)
		var cd: float = _cd if _cd > 0.0 else Defs.ULTIMATES[cls]["cooldown"] / 1000.0
		return clampf(1.0 - (h.ult_ready_at - game.now) / cd, 0.0, 1.0)

	func _draw() -> void:
		var h: Actor = game.hero(cls) if game else null
		if h == null:
			return
		var c := size * 0.5
		var r := size.x * 0.5 - 3.0
		var alive: bool = h.alive
		var ratio := _ratio(h) if alive else 0.0
		var ready := ratio >= 0.999 and alive
		var base := col if kind == "active" else col.lerp(Color("ffd23f"), 0.35)
		draw_circle(c, r + 3.0, INK)
		draw_circle(c, r, Color(0.16, 0.13, 0.28))
		# sweep (clockwise from 12 o'clock)
		if ratio > 0.001:
			var pts := PackedVector2Array([c])
			var steps := 32
			for i in steps + 1:
				var a := -PI * 0.5 + TAU * ratio * i / steps
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, base.darkened(0.25) if not ready else base)
		if ready:
			var pulse := 0.5 + 0.5 * sin(_t * 7.0)
			draw_arc(c, r + 1.0, 0.0, TAU, 40, Color(1, 0.95, 0.5, 0.6 + 0.4 * pulse), 4.0, true)
		if kind == "ult":
			draw_arc(c, r - 3.0, 0.0, TAU, 40, Color("ffd23f", 0.8), 2.0, true)
		if _flash > 0.0:
			draw_circle(c, r, Color(1, 1, 1, _flash * 0.8))
		if not alive:
			draw_circle(c, r, Color(0.1, 0.1, 0.12, 0.6))
		# label: skill short name, or remaining seconds on a cooling ultimate
		var t := text
		var fs := 17
		if kind == "ult" and alive and not ready and game.in_battle():
			t = "%.0f" % ceilf(h.ult_ready_at - game.now)
			fs = 22
		elif not alive and game.respawn_in(h) > 0.0:
			t = "%.0f" % ceilf(game.respawn_in(h))   # seconds until the fallen hero gets back up
			fs = 22
		var tsz := font.get_string_size(t, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var p := Vector2(c.x - tsz.x * 0.5, c.y + fs * 0.36)
		draw_string_outline(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, INK)
		draw_string(font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if alive else Color(0.7, 0.7, 0.75))
		# tiny "궁" tag for ultimates
		if kind == "ult":
			var tp := c + Vector2(r * 0.55, -r * 0.62)
			draw_circle(tp, 10.0, INK)
			draw_circle(tp, 8.0, Color("ffd23f"))
			var gs := font.get_string_size("궁", HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			draw_string(font, tp + Vector2(-gs.x * 0.5, 4.5), "궁", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)

## Simple drawn nav icons (toy style: white fill, thick ink outline).
class NavIcon extends Control:
	var INK: Color = UiTheme.ink()
	var kind := ""
	var big := false

	func _draw() -> void:
		var s := size.x
		var c := size * 0.5
		var fill := Color.WHITE
		match kind:
			"shop":
				var body := Rect2(s * 0.16, s * 0.34, s * 0.68, s * 0.52)
				draw_arc(Vector2(c.x, s * 0.36), s * 0.2, PI, TAU, 16, INK, s * 0.14)
				draw_arc(Vector2(c.x, s * 0.36), s * 0.2, PI, TAU, 16, Color("ffd23f"), s * 0.07)
				_rrect(body.grow(s * 0.05), INK)
				_rrect(body, Color("ffd23f"))
				draw_circle(Vector2(c.x, s * 0.58), s * 0.07, INK)
			"hero":
				for sx in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([c + Vector2(sx * s * 0.2, -s * 0.05), c + Vector2(sx * s * 0.44, -s * 0.36), c + Vector2(sx * s * 0.3, s * 0.04)]), INK)
					draw_colored_polygon(PackedVector2Array([c + Vector2(sx * s * 0.22, -s * 0.04), c + Vector2(sx * s * 0.39, -s * 0.29), c + Vector2(sx * s * 0.28, s * 0.02)]), Color("fff4e0"))
				draw_circle(c + Vector2(0, s * 0.06), s * 0.32, INK)
				draw_circle(c + Vector2(0, s * 0.06), s * 0.25, Color("8ab4ff"))
				draw_rect(Rect2(c.x - s * 0.18, c.y + s * 0.02, s * 0.36, s * 0.07), INK)
			"battle":
				for sx in [-1.0, 1.0]:
					var a := c + Vector2(-sx * s * 0.32, -s * 0.32)
					var b := c + Vector2(sx * s * 0.3, s * 0.3)
					draw_line(a, b, INK, s * 0.17)
					draw_line(a, b, fill, s * 0.08)
					var g := c + Vector2(sx * s * 0.17, s * 0.17)
					var perp := Vector2(sx, -1.0).normalized().orthogonal() * s * 0.13
					draw_line(g - perp, g + perp, INK, s * 0.12)
					draw_line(g - perp, g + perp, Color("ffd23f"), s * 0.05)
			"talent":
				var pts := PackedVector2Array()
				var pts2 := PackedVector2Array()
				for i in 10:
					var a := -PI * 0.5 + TAU * i / 10.0
					var rr := s * (0.46 if i % 2 == 0 else 0.2)
					pts.append(c + Vector2(cos(a), sin(a)) * (rr + s * 0.05))
					pts2.append(c + Vector2(cos(a), sin(a)) * rr)
				draw_colored_polygon(pts, INK)
				draw_colored_polygon(pts2, Color("a98cff"))
			"codex":
				var l := Rect2(s * 0.12, s * 0.2, s * 0.38, s * 0.62)
				var r := Rect2(s * 0.5, s * 0.2, s * 0.38, s * 0.62)
				_rrect(l.grow(s * 0.05), INK)
				_rrect(r.grow(s * 0.05), INK)
				_rrect(l, Color("7fd88a"))
				_rrect(r, Color("9ae6a2"))
				for i in 3:
					var y := s * (0.36 + i * 0.13)
					draw_line(Vector2(s * 0.2, y), Vector2(s * 0.42, y), INK, 2.0)
					draw_line(Vector2(s * 0.58, y), Vector2(s * 0.8, y), INK, 2.0)

	func _rrect(r: Rect2, col: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(r.size.x * 0.2))
		sb.anti_aliasing = true
		draw_style_box(sb, r)
