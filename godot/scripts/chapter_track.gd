class_name ChapterTrack
extends Control
## Chapter progress track (top of the march screen, under the chapter chip and the currencies):
## a gold start crest, one diamond per encounter group of the current region and the mid-boss skull at the end.
## Cleared groups are filled sky blue, the group being approached / fought is the big yellow diamond (it bobs,
## faster while fighting), the rest wait in dark slate. The blue rail creeps forward with the march, so the
## distance to the next camp is readable at a glance. MapHud feeds `cleared` / `fill` / `fighting` every frame.

const N := Regions.PER_REGION
const CREST_R := 19.0
const BOSS_R := 21.0
const NODE := 13.0           # diamond half size
const RAIL_H := 10.0
const BLUE := Color("2fa8ff")
const BLUE_HI := Color("9fe2ff")
const YELLOW := Color("ffd23f")
const SLATE := Color("3d3660")
const RED := Color("ff5f6a")

var hud: Hud
var cleared := 0             # groups beaten in this region (0..N)
var fill := 0.0              # rail fill in node units (0 = crest, N = boss)
var fighting := false
var _nums: Array[Label] = []
var _t := 0.0
var _pop_i := -1             # node that just turned blue (pops once)
var _pop_t := 9.0
var _shown_cleared := -1
var _sb: Array = []          # rail styleboxes (shell, groove, fill), built on first draw

func build(p_hud: Hud) -> void:
	hud = p_hud
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in range(1, N):
		var l := hud.label(str(i), 17, Color.WHITE, 5)
		l.size = Vector2(NODE * 2.0, NODE * 2.0)
		l.pivot_offset = l.size * 0.5
		add_child(l)
		_nums.append(l)

## Rail span (crest centre -> boss centre).
func _x0() -> float:
	return CREST_R + 4.0

func _x1() -> float:
	return size.x - BOSS_R - 4.0

func node_x(i: float) -> float:
	return lerpf(_x0(), _x1(), i / float(N))

func _process(delta: float) -> void:
	_t += delta
	_pop_t += delta
	if cleared != _shown_cleared:
		if _shown_cleared >= 0 and cleared > _shown_cleared:
			_pop_i = cleared
			_pop_t = 0.0
		_shown_cleared = cleared
	var cy := size.y * 0.5
	for k in _nums.size():
		var i := k + 1
		var l := _nums[k]
		var sc := _scale(i)
		l.position = Vector2(node_x(i), cy + _bob(i)) - l.size * 0.5
		l.scale = Vector2.ONE * sc
		l.label_settings.font_color = Color.WHITE if i <= cleared + 1 else Color("9a94bc")
	queue_redraw()

func _current() -> int:
	return cleared + 1

func _bob(i: int) -> float:
	if i != _current():
		return 0.0
	return -absf(sin(_t * (7.0 if fighting else 3.5))) * 3.0

func _scale(i: int) -> float:
	var s := 1.3 if i == _current() else 1.0
	if i == _pop_i and _pop_t < 0.6:
		s += 0.5 * exp(-_pop_t * 7.0) * cos(_pop_t * 22.0)
	return s

func _draw() -> void:
	var ink := UiTheme.ink()
	var cy := size.y * 0.5
	var x0 := _x0()
	var x1 := _x1()
	# rail: ink shell, dark groove, blue fill up to the march position
	if _sb.is_empty():
		_sb = [_round(ink, RAIL_H * 0.5 + 3.0), _round(Color("241d3d"), RAIL_H * 0.5), _round(BLUE, RAIL_H * 0.5)]
	draw_style_box(_sb[0], Rect2(x0, cy - RAIL_H * 0.5 - 3.0, x1 - x0, RAIL_H + 6.0))
	draw_style_box(_sb[1], Rect2(x0, cy - RAIL_H * 0.5, x1 - x0, RAIL_H))
	var fx := node_x(clampf(fill, 0.0, float(N)))
	if fx > x0 + 1.0:
		draw_style_box(_sb[2], Rect2(x0, cy - RAIL_H * 0.5, fx - x0, RAIL_H))
		draw_rect(Rect2(x0 + 4.0, cy - RAIL_H * 0.5 + 2.0, maxf(0.0, fx - x0 - 8.0), 2.5), BLUE_HI)
	# start crest
	var c0 := Vector2(x0, cy)
	draw_circle(c0, CREST_R + 3.0, ink)
	draw_circle(c0, CREST_R, YELLOW)
	draw_circle(c0, CREST_R * 0.66, Color("f5b21e"))
	_diamond(c0, CREST_R * 0.42, Color("fff2a8"), Color(0, 0, 0, 0))
	# group diamonds
	for i in range(1, N):
		var c := Vector2(node_x(i), cy + _bob(i))
		var r := NODE * _scale(i)
		var col := BLUE if i <= cleared else (YELLOW if i == _current() else SLATE)
		if i == _current():
			var glow := 0.35 + 0.25 * sin(_t * (8.0 if fighting else 4.0))
			_diamond(c, r + 8.0, Color(YELLOW, glow * 0.5), Color(0, 0, 0, 0))
		_diamond(c, r, col, ink)
		if i <= cleared or i == _current():
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(-r, 0)]), Color(1, 1, 1, 0.22))
	# mid-boss at the end of the region
	var cb := Vector2(x1, cy + _bob(N))
	var rb := BOSS_R * _scale(N)
	if N == _current():
		var g := 0.4 + 0.3 * sin(_t * (8.0 if fighting else 4.0))
		draw_circle(cb, rb + 9.0, Color(RED, g * 0.5))
	draw_circle(cb, rb + 3.0, ink)
	draw_circle(cb, rb, BLUE if cleared >= N else RED)
	_skull(cb + Vector2(0, -1), rb * 0.62, ink)

func _diamond(c: Vector2, r: float, fill_col: Color, outline: Color) -> void:
	if outline.a > 0.0:
		var o := r + 3.5
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -o), c + Vector2(o, 0), c + Vector2(0, o), c + Vector2(-o, 0)]), outline)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), fill_col)

func _skull(c: Vector2, r: float, ink: Color) -> void:
	var bone := Color("fff4e0")
	draw_circle(c, r, bone)
	draw_rect(Rect2(c.x - r * 0.55, c.y + r * 0.35, r * 1.1, r * 0.75), bone)
	draw_circle(c + Vector2(-r * 0.38, 0.0), r * 0.27, ink)
	draw_circle(c + Vector2(r * 0.38, 0.0), r * 0.27, ink)
	draw_rect(Rect2(c.x - 1.2, c.y + r * 0.62, 2.4, r * 0.48), ink)

static func _round(col: Color, r: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(r))
	return sb
