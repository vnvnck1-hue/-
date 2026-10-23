class_name LobbyStyle
extends RefCounted
## Toy-camp lobby look in one place: palette, bundled fonts, soft StyleBoxes (big rounds, a shallow bottom lip,
## short low-alpha shadows, no ink outlines) and the icon set. Independent of UiTheme's presets on purpose: the
## lobby keeps this look whatever 뚜까펫 / 클래식 preset the other screens use.
## Icons: a PNG in res://art/lobby/<name>.png wins; until it exists a drawn stand-in is used (same size / place).

const SKY_TOP := Color("8fddf7")
const SKY_LOW := Color("c6f0fc")
const CREAM := Color("fff8e8")
const CREAM_LIP := Color("eadcbc")
const CREAM_INSET := Color("f3e9d3")
const CAPSULE := Color("174a61")
const CAPSULE_LIP := Color("0f3445")
const TEXT := Color("173a4a")
const TEXT_SUB := Color("7d817d")
const TEAL := Color("33bebb")
const TEAL_LIP := Color("23989a")
const YELLOW_TOP := Color("ffe74e")
const YELLOW := Color("ffcf2a")
const YELLOW_LIP := Color("d98a1b")
const MINT := Color("c6e9e2")
const MINT_LIP := Color("a7d6cc")
const ALERT := Color("ff5964")
const VAL_GOLD := Color("ffd84a")
const VAL_STONE := Color("7fd3ff")
const VAL_CRYSTAL := Color("e3b8ff")
const SHADOW := Color(0.05, 0.16, 0.2, 0.18)
const DISABLED := Color("c9c2b0")

static var _fonts := {}

## Bundled Noto Sans KR at a fixed weight (same glyphs on Windows and Web).
static func ko(weight := 800) -> Font:
	var key := "ko%d" % weight
	if not _fonts.has(key):
		var f := FontVariation.new()
		f.base_font = load("res://fonts/NotoSansKR-VF.ttf")
		f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_fonts[key] = f
	return _fonts[key]

## Rounded numerals (Lilita One) for currency values; Korean falls back to Noto.
static func num() -> Font:
	if not _fonts.has("num"):
		var f := FontVariation.new()
		f.base_font = load("res://fonts/LilitaOne-Regular.ttf")
		f.fallbacks = [ko(800)]
		f.spacing_glyph = 1
		_fonts["num"] = f
	return _fonts["num"]

static func label(text: String, size: int, color := TEXT, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	var s := LabelSettings.new()
	s.font = font if font else ko(800)
	s.font_size = size
	s.font_color = color
	s.outline_size = 0
	l.label_settings = s
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------------------------------------------------------------- surfaces
static func flat(c: Color, r: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(r)
	sb.anti_aliasing = true
	sb.corner_detail = 12
	return sb

## Raised surface: a darker lip under the face, plus a short soft drop shadow. pressed = the face sinks onto the lip.
static func raised(face: Color, lip: Color, r: int, lip_h := 6, pressed := false, shadow := true) -> StyleBox:
	var lb := UiTheme.Layered.new()
	var down := lip_h - 2 if pressed else 0
	if shadow:
		var sh := flat(SHADOW, r)
		sh.shadow_color = SHADOW
		sh.shadow_size = 6
		sh.bg_color = Color(0, 0, 0, 0)
		lb.add(sh, Vector4(0, -lip_h - 2, 0, lip_h + 2))
	lb.add(flat(lip, r), Vector4(0, 0, 0, 0))
	lb.add(flat(face, r), Vector4(0, -down, 0, -lip_h + down))
	return lb

## The big yellow start button: lip, warm face, a soft lighter band on the upper half.
static func start_box(pressed := false, disabled := false) -> StyleBox:
	var lip_h := 12
	var down := 7 if pressed else 0
	var lb := UiTheme.Layered.new()
	var sh := flat(Color(0, 0, 0, 0), 46)
	sh.shadow_color = Color(0.45, 0.25, 0.0, 0.22)
	sh.shadow_size = 10
	sh.shadow_offset = Vector2(0, 4)
	lb.add(sh, Vector4(0, 0, 0, 0))
	var face := DISABLED if disabled else YELLOW
	var lip := DISABLED.darkened(0.2) if disabled else YELLOW_LIP
	lb.add(flat(lip, 46), Vector4.ZERO)
	lb.add(flat(face, 46), Vector4(0, -down, 0, -lip_h + down))
	if not disabled:
		var hi := flat(YELLOW_TOP, 40)
		lb.add(hi, Vector4(-8, -6 - down, -8, 0), 0.52)
	return lb

static func sheet() -> StyleBox:
	var sb := flat(CREAM, 0)
	sb.corner_radius_top_left = 56
	sb.corner_radius_top_right = 56
	sb.corner_radius_bottom_left = 40
	sb.corner_radius_bottom_right = 40
	sb.shadow_color = Color(0.05, 0.2, 0.15, 0.16)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, -2)
	return sb

static func nav_bar() -> StyleBox:
	var sb := flat(CREAM, 0)
	sb.corner_radius_top_left = 44
	sb.corner_radius_top_right = 44
	sb.shadow_color = Color(0.05, 0.2, 0.15, 0.14)
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, -3)
	sb.border_width_top = 2
	sb.border_color = Color(1, 1, 1, 0.9)
	return sb

static func inset(r := 44) -> StyleBox:
	var sb := flat(CREAM_INSET, r)
	sb.border_width_top = 3
	sb.border_color = Color("e7dbc0")
	return sb

static func capsule() -> StyleBox:
	var lb := UiTheme.Layered.new()
	lb.add(flat(CAPSULE_LIP, 32), Vector4(0, 0, 0, 0))
	lb.add(flat(CAPSULE, 32), Vector4(0, 0, 0, -4))
	var hi := flat(Color(1, 1, 1, 0.07), 28)
	lb.add(hi, Vector4(-4, -3, -4, 0), 0.45)
	return lb

## Empty box for buttons whose look is drawn by children (or not at all).
static func none() -> StyleBox:
	return StyleBoxEmpty.new()

static func skin(b: BaseButton, normal: StyleBox, pressed: StyleBox = null, disabled: StyleBox = null) -> void:
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", pressed if pressed else normal)
	b.add_theme_stylebox_override("hover_pressed", pressed if pressed else normal)
	b.add_theme_stylebox_override("disabled", disabled if disabled else normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

# ---------------------------------------------------------------- icons
static var _tex := {}

static func texture(name: String) -> Texture2D:
	if not _tex.has(name):
		var p := "res://art/lobby/%s.png" % name
		_tex[name] = load(p) if ResourceLoader.exists(p) else null
	return _tex[name]

## Icon control for `name`: the PNG when present, otherwise a drawn stand-in. Never takes input.
static func icon(name: String) -> Control:
	var t := texture(name)
	var c: Control
	if t:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		c = tr
	else:
		var d := DrawnIcon.new()
		d.kind = name
		c = d
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

## Stand-in icons, drawn in the soft toy palette (no ink outlines). Coordinates are in a 100x100 box scaled to size.
class DrawnIcon extends Control:
	var kind := ""
	var _t := 0.0

	func _ready() -> void:
		set_process(kind == "nav_camp")

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var k := minf(size.x, size.y) / 100.0
		draw_set_transform((size - Vector2(100, 100) * k) * 0.5, 0.0, Vector2(k, k))
		match kind:
			"coin": _coin()
			"stone": _stone()
			"crystal": _crystal(Vector2(50, 50), 1.0)
			"gear": _gear()
			"mission": _mission()
			"attend": _attend()
			"nav_gear": _nav_gear()
			"nav_relic": _nav_relic()
			"nav_camp": _nav_camp()
			"nav_raid": _nav_raid()
			"nav_growth": _nav_growth()
			"map": _map()
		draw_set_transform(Vector2.ZERO)

	func _poly(pts: Array, c: Color) -> void:
		draw_colored_polygon(PackedVector2Array(pts), c)

	func _coin() -> void:
		draw_circle(Vector2(50, 54), 40, Color("c9821a"))
		draw_circle(Vector2(50, 50), 40, Color("ffc62e"))
		draw_circle(Vector2(50, 50), 30, Color("f2a91c"))
		draw_circle(Vector2(50, 47), 28, Color("ffcf3d"))
		draw_arc(Vector2(50, 50), 35, PI * 1.08, PI * 1.55, 12, Color("fff1a6"), 4.0, true)
		draw_circle(Vector2(50, 42), 8, Color("d68a12"))
		_poly([Vector2(45, 44), Vector2(55, 44), Vector2(58, 64), Vector2(42, 64)], Color("d68a12"))

	func _stone() -> void:
		var c := Vector2(50, 52)
		var outer: Array = []
		for i in 6:
			outer.append(c + Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * 42)
		_poly(outer, Color("2f7fe0"))
		var inner: Array = []
		for i in 6:
			inner.append(c + Vector2.from_angle(TAU * i / 6.0 - PI / 2.0) * 24 + Vector2(0, -3))
		_poly([outer[5], outer[0], inner[0], inner[5]], Color("8fd8ff"))
		_poly([outer[0], outer[1], inner[1], inner[0]], Color("5cb7ff"))
		_poly([outer[1], outer[2], inner[2], inner[1]], Color("3a8ff0"))
		_poly([outer[2], outer[3], inner[3], inner[2]], Color("2266c8"))
		_poly([outer[3], outer[4], inner[4], inner[3]], Color("2a74d8"))
		_poly([outer[4], outer[5], inner[5], inner[4]], Color("6ec6ff"))
		_poly(inner, Color("6cc4ff"))
		_poly([inner[5], inner[0], c + Vector2(-2, -8)], Color("c8eeff"))

	func _crystal(c: Vector2, s: float) -> void:
		var top := c + Vector2(0, -44) * s
		var bot := c + Vector2(0, 44) * s
		var l := c + Vector2(-26, -6) * s
		var r := c + Vector2(26, -6) * s
		var m := c + Vector2(0, -4) * s
		_poly([top, l, bot, r], Color("8a4fe0"))
		_poly([top, l, m], Color("d9b2ff"))
		_poly([top, r, m], Color("b07cff"))
		_poly([l, bot, m], Color("9a5ef0"))
		_poly([r, bot, m], Color("6c34c4"))
		_poly([top + Vector2(-2, 8) * s, top + Vector2(-9, 26) * s, top + Vector2(-4, 26) * s], Color(1, 1, 1, 0.7))

	func _gear() -> void:
		var pts: Array = []
		for j in 64:
			var r := 40.0 if j % 8 < 4 else 30.0
			pts.append(Vector2(50, 50) + Vector2.from_angle(TAU * (j + 0.5) / 64.0) * r)
		_poly(pts, Color.WHITE)
		draw_circle(Vector2(50, 50), 13, CAPSULE)

	func _mission() -> void:
		draw_rect(Rect2(20, 18, 60, 74), Color("2f5f9c"))
		_round(Rect2(20, 16, 60, 74), 10, Color("3d7bc8"))
		_round(Rect2(27, 26, 46, 58), 5, Color("fffdf4"))
		_round(Rect2(36, 10, 28, 14), 5, Color("7d8796"))
		draw_polyline(PackedVector2Array([Vector2(36, 56), Vector2(46, 66), Vector2(66, 40)]), Color("35c25a"), 9.0, true)

	func _attend() -> void:
		_round(Rect2(16, 24, 68, 66), 12, Color("d9d3c6"))
		_round(Rect2(16, 20, 68, 66), 12, Color("fffdf4"))
		_round(Rect2(16, 20, 68, 24), 12, Color("ef4c4c"))
		draw_rect(Rect2(16, 32, 68, 12), Color("ef4c4c"))
		for x in [32, 68]:
			_round(Rect2(x - 4, 12, 8, 18), 4, Color("8a8f99"))
		draw_polyline(PackedVector2Array([Vector2(36, 62), Vector2(46, 72), Vector2(64, 52)]), Color("f07a2a"), 8.0, true)

	func _nav_gear() -> void:
		# sword (blade up-right), then a small round shield in front
		var k := minf(size.x, size.y) / 100.0
		var o := (size - Vector2(100, 100) * k) * 0.5
		draw_set_transform(o + Vector2(50, 50) * k, -PI / 4.0, Vector2(k, k))
		_poly([Vector2(-7, -40), Vector2(0, -50), Vector2(7, -40), Vector2(7, 14), Vector2(-7, 14)], Color("dfe7f0"))
		_poly([Vector2(0, -50), Vector2(7, -40), Vector2(7, 14), Vector2(0, 14)], Color("b4c0cf"))
		_round(Rect2(-17, 12, 34, 9), 4, Color("f2b632"))
		_round(Rect2(-5, 20, 10, 18), 4, Color("8a5a34"))
		draw_circle(Vector2(0, 41), 6, Color("f2b632"))
		draw_set_transform(o, 0.0, Vector2(k, k))
		draw_circle(Vector2(66, 68), 24, Color("9aa6b6"))
		draw_circle(Vector2(66, 66), 24, Color("c8d2de"))
		draw_circle(Vector2(66, 66), 17, Color("2f7fe0"))
		draw_circle(Vector2(63, 62), 9, Color("5aa6ff"))

	func _nav_relic() -> void:
		draw_colored_polygon(_ellipse(Vector2(50, 80), Vector2(36, 12)), Color("8d8a9c"))
		draw_rect(Rect2(14, 70, 72, 10), Color("8d8a9c"))
		draw_colored_polygon(_ellipse(Vector2(50, 70), Vector2(36, 12)), Color("b9b5c8"))
		draw_colored_polygon(_ellipse(Vector2(50, 70), Vector2(24, 7)), Color("a49fb6"))
		_crystal(Vector2(50, 38), 0.68)

	func _nav_camp() -> void:
		for i in 7:
			var a := PI * 0.1 + PI * 0.8 * i / 6.0
			var p := Vector2(50, 74) + Vector2(cos(a) * 36, sin(a) * 10)
			draw_colored_polygon(_ellipse(p, Vector2(10, 7)), Color("9a96a6") if i % 2 == 0 else Color("b3afbd"))
		for a in [-0.3, 0.3]:
			var d := Vector2.from_angle(a) * 26
			draw_line(Vector2(50, 70) - d, Vector2(50, 70) + d, Color("8a5a34"), 9.0, true)
		var f := 1.0 + 0.06 * sin(_t * 10.0)
		_poly(_flame(Vector2(50, 70), 18, 50 * f, sin(_t * 7.0) * 3), Color("ff7a2a"))
		_poly(_flame(Vector2(50, 70), 10, 32 * (2.0 - f), sin(_t * 9.0 + 1.0) * 3), Color("ffd24a"))

	func _nav_raid() -> void:
		var k := minf(size.x, size.y) / 100.0
		var o := (size - Vector2(100, 100) * k) * 0.5
		for sgn in [-1.0, 1.0]:
			draw_set_transform(o + Vector2(50, 50) * k, sgn * PI / 4.0, Vector2(k, k))
			_poly([Vector2(-6, -36), Vector2(0, -46), Vector2(6, -36), Vector2(6, 16), Vector2(-6, 16)], Color("e3e9f1"))
			_poly([Vector2(0, -46), Vector2(6, -36), Vector2(6, 16), Vector2(0, 16)], Color("b8c3d1"))
			_round(Rect2(-15, 14, 30, 8), 4, Color("8d97a6"))
			_round(Rect2(-5, 21, 10, 18), 4, Color("8a5a34"))
		draw_set_transform(o, 0.0, Vector2(k, k))

	func _nav_growth() -> void:
		_round(Rect2(44, 52, 12, 36), 5, Color("8a5a34"))
		draw_circle(Vector2(50, 40), 24, Color("3f9e4a"))
		draw_circle(Vector2(32, 48), 17, Color("4fb14f"))
		draw_circle(Vector2(68, 48), 17, Color("4fb14f"))
		draw_circle(Vector2(50, 28), 18, Color("6cc24a"))
		draw_circle(Vector2(42, 24), 7, Color(1, 1, 1, 0.35))
		draw_colored_polygon(_ellipse(Vector2(50, 90), Vector2(22, 5)), Color(0.1, 0.25, 0.1, 0.18))

	func _map() -> void:
		var w := Color.WHITE
		_poly([Vector2(14, 26), Vector2(38, 18), Vector2(38, 76), Vector2(14, 84)], w)
		_poly([Vector2(40, 18), Vector2(62, 26), Vector2(62, 84), Vector2(40, 76)], Color(1, 1, 1, 0.82))
		_poly([Vector2(64, 26), Vector2(86, 18), Vector2(86, 76), Vector2(64, 84)], w)

	func _flame(base: Vector2, r: float, h: float, sway: float) -> Array:
		var pts: Array = []
		for i in 13:
			var a := PI * i / 12.0
			pts.append(base + Vector2(cos(a) * r, sin(a) * r * 0.5 - r * 0.2))
		pts.append(base + Vector2(-r * 0.7, -h * 0.45))
		pts.append(base + Vector2(sway, -h))
		pts.append(base + Vector2(r * 0.7, -h * 0.45))
		return pts

	func _ellipse(c: Vector2, r: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 24:
			pts.append(c + Vector2(cos(TAU * i / 24.0) * r.x, sin(TAU * i / 24.0) * r.y))
		return pts

	func _round(r: Rect2, rad: float, c: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(rad))
		sb.anti_aliasing = true
		draw_style_box(sb, r)
