class_name ItemIcon
extends Control
## Item icon sized to its rect: the painted PNG from res://art/items/<id>.png when one exists
## (imported from art/catalog by tools/icon_import/import_icons.py), otherwise drawn procedurally
## (chunky dark outline + flat toy colours). Grade pips / 초월 stars are drawn on top either way.

const ICON_DIR := "res://art/items/"
static var _tex_cache := {}

var INK: Color = UiTheme.ink()
const METAL := Color("dfe6ee")
const WOOD := Color("b8733a")
const GOLD := Color("ffd23f")

var entry := {}
var show_tier := true

func _init(e: Dictionary = {}) -> void:
	entry = e
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

func set_entry(e: Dictionary) -> void:
	entry = e
	queue_redraw()

## Catalog id of the PNG for an entry ("" if it has none). 초월 grades (9+) reuse the 태초 (8) art.
static func icon_id(e: Dictionary) -> String:
	match e.get("kind", ""):
		"equip":
			var k: String = e["key"]
			var fam := Gear.family_of(k)
			if fam != "":
				return Gear.key(fam, mini(Gear.grade_of_key(k), Gear.STAR_FROM))
			return k
		"relic", "special":
			return e["key"]
		"skillbook":
			return "skillbook%d" % Inventory.book_grade(e)   # one painted cover per book grade
	return ""

static func texture_for(e: Dictionary) -> Texture2D:
	var id := icon_id(e)
	if id == "":
		return null
	if not _tex_cache.has(id):
		var path := ICON_DIR + id + ".png"
		_tex_cache[id] = load(path) if ResourceLoader.exists(path) else null
	return _tex_cache[id]

func _shape() -> String:
	match entry.get("kind", ""):
		"special":
			return entry["key"]
		"relic":
			return "relic"
		"skillbook":
			return "book"
		"stone":
			return "stone"
		"equip":
			var k: String = entry["key"]
			var fam := Gear.family_of(k)
			if fam != "":
				return fam
			var def := Defs.item(k)
			match def.get("slot", ""):
				"weapon": return "legend_weapon"
				"armor": return "shield"
			return "orb"
	return ""

func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	draw_line(a, b, INK, w + 6.0, true)
	draw_circle(a, (w + 6.0) * 0.5, INK)
	draw_circle(b, (w + 6.0) * 0.5, INK)
	draw_line(a, b, col, w, true)
	draw_circle(a, w * 0.5, col)
	draw_circle(b, w * 0.5, col)

func _circ(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r + 3.0, INK)
	draw_circle(c, r, col)

func _poly(pts: PackedVector2Array, col: Color) -> void:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	c /= pts.size()
	var big := PackedVector2Array()
	for p in pts:
		big.append(p + (p - c).normalized() * 3.5)
	draw_colored_polygon(big, INK)
	draw_colored_polygon(pts, col)

func _draw() -> void:
	if entry.is_empty():
		return
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var P := func(x: float, y: float) -> Vector2: return o + Vector2(x, y) * s
	var tint: Color = Defs.RARITY_COL[Inventory.rarity_of(entry)]
	var w := s * 0.09
	var tex := texture_for(entry)
	if tex != null:
		var pad := s * 0.06
		draw_texture_rect(tex, Rect2(o + Vector2(pad, pad * 0.4), Vector2(s - pad * 2.0, s - pad * 2.0)), false)
	match "" if tex != null else _shape():
		"sword":
			_line(P.call(0.25, 0.75), P.call(0.72, 0.28), METAL, w * 1.3)
			_line(P.call(0.2, 0.58), P.call(0.42, 0.8), GOLD, w)
			_line(P.call(0.18, 0.82), P.call(0.27, 0.73), WOOD, w)
		"axe":
			_line(P.call(0.28, 0.82), P.call(0.62, 0.22), WOOD, w)
			_poly(PackedVector2Array([P.call(0.5, 0.2), P.call(0.8, 0.22), P.call(0.82, 0.48), P.call(0.6, 0.45)]), METAL)
		"bow":
			draw_arc(P.call(0.35, 0.5), s * 0.34, -1.2, 1.2, 16, INK, w + 6.0, true)
			draw_arc(P.call(0.35, 0.5), s * 0.34, -1.2, 1.2, 16, WOOD, w, true)
			var t: Vector2 = P.call(0.35, 0.5) + Vector2(cos(-1.2), sin(-1.2)) * s * 0.34
			var b: Vector2 = P.call(0.35, 0.5) + Vector2(cos(1.2), sin(1.2)) * s * 0.34
			draw_line(t, b, Color.WHITE, 2.5, true)
		"staff":
			_line(P.call(0.35, 0.85), P.call(0.6, 0.35), WOOD, w)
			_circ(P.call(0.64, 0.28), s * 0.13, Color("b07aff"))
			draw_circle(P.call(0.6, 0.24), s * 0.04, Color(1, 1, 1, 0.8))
		"shield":
			_poly(PackedVector2Array([P.call(0.22, 0.2), P.call(0.78, 0.2), P.call(0.74, 0.58), P.call(0.5, 0.84), P.call(0.26, 0.58)]), Color("5fa8e8"))
			_line(P.call(0.5, 0.3), P.call(0.5, 0.68), METAL, w * 0.6)
			_line(P.call(0.34, 0.44), P.call(0.66, 0.44), METAL, w * 0.6)
		"helmet":
			draw_circle(P.call(0.5, 0.55), s * 0.31, INK)
			draw_circle(P.call(0.5, 0.55), s * 0.28, METAL)
			_line(P.call(0.3, 0.58), P.call(0.7, 0.58), INK, w * 0.4)
			_line(P.call(0.5, 0.3), P.call(0.5, 0.22), Color("e04a5a"), w)
		"ring":
			draw_arc(P.call(0.5, 0.58), s * 0.24, 0, TAU, 24, INK, w + 6.0, true)
			draw_arc(P.call(0.5, 0.58), s * 0.24, 0, TAU, 24, GOLD, w, true)
			_circ(P.call(0.5, 0.3), s * 0.1, Color("5fd0ff"))
		"amulet", "orb":
			draw_arc(P.call(0.5, 0.3), s * 0.24, 0.2, PI - 0.2, 16, INK, 6.0, true)
			draw_arc(P.call(0.5, 0.3), s * 0.24, 0.2, PI - 0.2, 16, GOLD, 3.0, true)
			_circ(P.call(0.5, 0.62), s * 0.17, tint if _shape() == "orb" else Color("e05a8a"))
			draw_circle(P.call(0.45, 0.57), s * 0.05, Color(1, 1, 1, 0.75))
		"legend_weapon":
			_line(P.call(0.25, 0.75), P.call(0.74, 0.26), tint.lightened(0.3), w * 1.5)
			_line(P.call(0.2, 0.56), P.call(0.44, 0.8), GOLD, w)
			draw_circle(P.call(0.74, 0.26), s * 0.06, Color.WHITE)
		"crown":
			_poly(PackedVector2Array([P.call(0.18, 0.72), P.call(0.18, 0.32), P.call(0.34, 0.5), P.call(0.5, 0.25), P.call(0.66, 0.5), P.call(0.82, 0.32), P.call(0.82, 0.72)]), GOLD)
			draw_circle(P.call(0.5, 0.58), s * 0.06, Color("e04a5a"))
		"relic":
			_poly(PackedVector2Array([P.call(0.5, 0.15), P.call(0.8, 0.42), P.call(0.5, 0.86), P.call(0.2, 0.42)]), tint)
			draw_colored_polygon(PackedVector2Array([P.call(0.5, 0.15), P.call(0.8, 0.42), P.call(0.5, 0.45)]), tint.lightened(0.4))
		"book":
			var cover := tint.darkened(0.15)
			_poly(PackedVector2Array([P.call(0.26, 0.24), P.call(0.8, 0.2), P.call(0.8, 0.84), P.call(0.26, 0.86)]), Color("f4ecd8"))   # pages
			_poly(PackedVector2Array([P.call(0.2, 0.18), P.call(0.74, 0.16), P.call(0.74, 0.8), P.call(0.2, 0.82)]), cover)
			_line(P.call(0.27, 0.18), P.call(0.27, 0.82), cover.darkened(0.35), w * 0.55)
			_circ(P.call(0.5, 0.48), s * 0.12, GOLD)
			_star(P.call(0.5, 0.48), s * 0.07)
		"revive":
			_poly(PackedVector2Array([P.call(0.3, 0.82), P.call(0.42, 0.45), P.call(0.68, 0.15), P.call(0.66, 0.42), P.call(0.45, 0.72)]), Color("fff4e0"))
			_line(P.call(0.3, 0.84), P.call(0.6, 0.3), Color("e8b860"), 3.0)
		"fullHeal":
			_circ(P.call(0.5, 0.6), s * 0.22, Color("ff6b8a"))
			_line(P.call(0.5, 0.36), P.call(0.5, 0.2), Color("cfe8ff"), w)
			_line(P.call(0.5, 0.5), P.call(0.5, 0.7), Color.WHITE, w * 0.6)
			_line(P.call(0.4, 0.6), P.call(0.6, 0.6), Color.WHITE, w * 0.6)
		"stone":
			draw_stone(self, o + Vector2(s, s) * 0.5, s * 0.36)
		"massKill":
			_poly(PackedVector2Array([P.call(0.58, 0.12), P.call(0.28, 0.55), P.call(0.48, 0.55), P.call(0.4, 0.88), P.call(0.74, 0.42), P.call(0.54, 0.42)]), GOLD)
		"inventoryExpand":
			_poly(PackedVector2Array([P.call(0.24, 0.38), P.call(0.76, 0.38), P.call(0.82, 0.84), P.call(0.18, 0.84)]), Color("c8894a"))
			draw_arc(P.call(0.5, 0.38), s * 0.14, PI, TAU, 10, INK, 6.0, true)
			_line(P.call(0.5, 0.52), P.call(0.5, 0.72), Color.WHITE, 3.5)
			_line(P.call(0.4, 0.62), P.call(0.6, 0.62), Color.WHITE, 3.5)
	if entry.get("kind", "") == "skillbook" and show_tier:
		# its grade: pips along the bottom
		var gn := Inventory.book_grade(entry)
		for i in gn:
			var gc := o + Vector2(s * 0.5 + (i - (gn - 1) * 0.5) * s * 0.13, s * 0.95)
			draw_circle(gc, s * 0.055, INK)
			draw_circle(gc, s * 0.035, tint.lightened(0.2))
	if show_tier and entry.get("kind", "") == "equip":
		var tier := Inventory.tier_of(entry)
		if Gear.is_family(entry["key"]) and tier > Gear.STAR_FROM:
			# 초월 ★n: gold stars instead of grade pips
			var stars := mini(tier - Gear.STAR_FROM, 5)
			for i in stars:
				_star(o + Vector2(s * 0.5 + (i - (stars - 1) * 0.5) * s * 0.16, s * 0.93), s * 0.085)
		else:
			var n := mini(tier, 8)
			var step := 0.13 if n <= 7 else 0.115
			for i in n:
				var c := o + Vector2(s * 0.5 + (i - (n - 1) * 0.5) * s * step, s * 0.95)
				draw_circle(c, s * 0.055, INK)
				draw_circle(c, s * 0.035, tint.lightened(0.2))

const CLASS_GEM := {"warrior": Color("ff7a5a"), "ranger": Color("5fcf5a"), "mage": Color("a77aff")}

## 강화석: a faceted blue gem (also drawn by HUD counters). (c = centre, r = radius)
static func draw_stone(ci: CanvasItem, c: Vector2, r: float) -> void:
	var ink: Color = UiTheme.ink()
	var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.86, -r * 0.35), c + Vector2(r * 0.62, r * 0.78),
		c + Vector2(-r * 0.62, r * 0.78), c + Vector2(-r * 0.86, -r * 0.35)])
	var big := PackedVector2Array()
	for p in pts:
		big.append(c + (p - c) * (1.0 + 4.0 / maxf(r, 1.0)))
	ci.draw_colored_polygon(big, ink)
	ci.draw_colored_polygon(pts, STONE_COL)
	ci.draw_colored_polygon(PackedVector2Array([pts[0], pts[1], c + Vector2(0, -r * 0.1)]), STONE_COL.lightened(0.45))
	ci.draw_colored_polygon(PackedVector2Array([pts[0], c + Vector2(0, -r * 0.1), pts[4]]), STONE_COL.lightened(0.2))
	ci.draw_colored_polygon(PackedVector2Array([pts[2], pts[3], c + Vector2(0, -r * 0.1)]), STONE_COL.darkened(0.25))
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.45), r * 0.1, Color(1, 1, 1, 0.85))

const STONE_COL := Color("4fb6ff")

func _star(c: Vector2, r: float) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + i * PI / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	_poly(pts, GOLD)
