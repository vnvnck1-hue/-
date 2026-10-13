class_name Hud
extends CanvasLayer
## 2D overlay: top info, unit bars, floating text, banners, buttons and popups.
## Style (Toy Clash): chunky rounded font, white text, thick dark outline, drop shadow; elastic motion everywhere.

signal fight_pressed
signal overlay_closed

var INK: Color = UiTheme.ink()

var game: Node
var cam: Camera3D
var font: Font
var root: Control
var bars := {}                # Actor -> Dictionary
var sub_label: Label
var gold_label: Label
var gold_pill: Control
var crystal_label: Label
var crystal_pill: Control
var stone_label: Label
var stone_pill: Control
var gimmick_title: Label
var gimmick_hint: Label
var phase_label: Label
var fight_btn: Button
var talent_btn: Button
var flash_rect: ColorRect
var overlay: Control          # current modal popup
var _toasts: Array[Label] = []
var panels: HudPanels
var perk_hud: PerkHud
var debug_hud: DebugHud

func _ready() -> void:
	layer = 5
	var latin := SystemFont.new()
	latin.font_names = PackedStringArray(["Lilita One", "Arial Rounded MT Bold", "Segoe UI Black", "Arial Black"])
	latin.font_weight = 900
	var ko := SystemFont.new()
	ko.font_names = PackedStringArray(["Jua", "BM JUA_TTF", "Malgun Gothic", "맑은 고딕", "Noto Sans KR", "Apple SD Gothic Neo"])
	ko.font_weight = 800
	# Web builds can't see system fonts — fall back to the bundled Noto Sans KR.
	var ko_web := FontVariation.new()
	ko_web.base_font = load("res://fonts/NotoSansKR-VF.ttf")
	ko_web.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	ko.fallbacks = [ko_web]
	latin.fallbacks = [ko]
	font = latin
	if OS.has_feature("web"):   # SystemFont resolves to the theme font there, so use the bundled ones directly
		var lilita := FontVariation.new()
		lilita.base_font = load("res://fonts/LilitaOne-Regular.ttf")
		lilita.fallbacks = [ko_web]
		font = lilita
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top()
	_build_bottom()
	panels = HudPanels.new()
	panels.hud = self
	panels.game = game
	add_child(panels)
	panels.build_inventory()
	perk_hud = PerkHud.new()   # run perk button (right edge; under the region chip in March mode)
	perk_hud.hud = self
	perk_hud.game = game
	add_child(perk_hud)
	perk_hud.build(TRACK_Y + TRACK_H + 36.0)   # right column, under the "보스까지" caption
	debug_hud = DebugHud.new()   # tiny "DBG" pill under the hero status column (debug quick actions)
	debug_hud.hud = self
	debug_hud.game = game
	add_child(debug_hud)
	debug_hud.build(STATUS_Y + 3 * STATUS_STEP + 8.0)
	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)

# ---------------------------------------------------------------- style helpers
## No drop shadows on UI text (outline only).
func ls(size: int, color := Color.WHITE, outline := 10) -> LabelSettings:
	var s := LabelSettings.new()
	s.font = font
	s.font_size = size
	s.font_color = UiTheme.text_color(color) if outline == 0 and UiTheme.tt() else color
	s.outline_size = outline
	s.outline_color = INK
	s.shadow_size = 0
	s.shadow_color = Color(0, 0, 0, 0)
	return s

func label(text: String, size: int, color := Color.WHITE, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = ls(size, color, outline)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func box(color: Color, radius := 12, border := 4, border_col = null) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = border_col if border_col != null else INK
	sb.shadow_color = Color(0.1, 0.05, 0.2, 0.35)
	sb.shadow_size = 0
	sb.shadow_offset = Vector2(0, 5)
	sb.anti_aliasing = true
	return sb

func panel(color: Color, rect: Rect2, radius := 12, border := 4) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(color, radius, border))
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

## 뚜까펫식 입체 버튼. 예전 색은 역할(노랑 주요 / 연두 확인 / 남색 보조 / 빨강 판매)로 바뀐다.
func juicy_button(text: String, color: Color, rect: Rect2, fsize := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.position = rect.position
	b.size = rect.size
	b.pivot_offset = rect.size * 0.5
	b.focus_mode = Control.FOCUS_NONE
	style_button(b, color, rect.size.y)
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fsize)
	b.button_down.connect(func():
		retween(b).tween_property(b, "scale", Vector2(0.92, 0.92) if UiTheme.tt() else Vector2(0.88, 0.88), 0.06)
		Sfx.play("click", -6.0))
	b.button_up.connect(func():
		retween(b).tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	return b

## 버튼 색만 다시 칠한다(상태에 따라 색이 바뀌는 버튼용).
func style_button(b: Button, color: Color, h := 60.0) -> void:
	if not UiTheme.tt():
		_style_button_classic(b, color)
		return
	var role := UiTheme.button_role(color)
	var c := UiTheme.role_color(role) if role != "" else color
	var r := int(clampf(h * 0.3, 12.0, 26.0))
	b.add_theme_stylebox_override("normal", UiTheme.button_box(c, r))
	b.add_theme_stylebox_override("hover", UiTheme.button_box(c.lightened(0.08), r))
	b.add_theme_stylebox_override("pressed", UiTheme.button_box(c.darkened(0.06), r, true))
	b.add_theme_stylebox_override("disabled", UiTheme.button_box(UiTheme.GREY, r))
	var dark := role == "yellow"
	var tc := UiTheme.button_text(role)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, tc)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 0 if dark else 10)

## 클래식(Toy Clash) 버튼: 기존 그대로.
func _style_button_classic(b: Button, color: Color) -> void:
	var n := box(color, 22, 5)
	n.shadow_size = 1
	n.shadow_offset = Vector2(0, 7)
	var h := box(color.lightened(0.12), 22, 5)
	h.shadow_size = 1
	h.shadow_offset = Vector2(0, 7)
	var pr := box(color.darkened(0.1), 22, 5)
	var d := box(Color("8a8aa0"), 22, 5)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("disabled", d)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.7))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 10)

## A fresh tween on node n that replaces the previous one started under the same key (default: the scale
## punch). Rapid repeats (gold ticking up, hover in/out, button down/up) don't stack fighting tweens.
static func retween(n: Node, key := "scale_tw") -> Tween:
	kill_tween(n, key)
	var tw := n.create_tween()
	n.set_meta(key, tw)
	return tw

## Stop the tween started on n with retween(n, key), if it is still running.
static func kill_tween(n: Node, key := "scale_tw") -> void:
	if not n.has_meta(key):
		return
	var old: Tween = n.get_meta(key)
	if old and old.is_valid():
		old.kill()

func pop_in(c: Control, from := 0.3, dur := 0.45) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * from
	retween(c).tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func bump(c: Control, amt := 1.3) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * amt
	retween(c).tween_property(c, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Anchor-aware placement: anchor (0..1) on the full screen, pos/size in pixels relative to that anchor.
func place(c: Control, anchor: Vector2, pos: Vector2, sz: Vector2) -> Control:
	c.anchor_left = anchor.x
	c.anchor_right = anchor.x
	c.anchor_top = anchor.y
	c.anchor_bottom = anchor.y
	c.offset_left = pos.x
	c.offset_top = pos.y
	c.offset_right = pos.x + sz.x
	c.offset_bottom = pos.y + sz.y
	c.pivot_offset = sz * 0.5
	return c

## Rounded dark pill with an icon on the left and a number label.
func pill(icon: Control, anchor: Vector2, pos: Vector2, sz: Vector2, fsize := 36) -> Label:
	var p := panel(Color.WHITE, Rect2(Vector2.ZERO, sz), int(sz.y * 0.5), 0)
	p.add_theme_stylebox_override("panel", UiTheme.capsule(int(sz.y * 0.5)))
	root.add_child(place(p, anchor, pos, sz))
	if icon:
		icon.position = Vector2(6, (sz.y - 44) * 0.5)
		icon.size = Vector2(44, 44)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
	var l := label("0", fsize)
	l.position = Vector2(48 if icon else 0, 0)
	l.size = Vector2(sz.x - (56 if icon else 0), sz.y)
	l.pivot_offset = l.size * 0.5
	p.add_child(l)
	return l

# ---------------------------------------------------------------- layout
## Top band, by rank: row 1 = where (chapter chip, left; added by MapHud) and wallet (currencies, right),
## row 2 = chapter progress track (MapHud), row 3 = hero status (left) / run perks (right), then the notice band.
const TOP_Y := 14.0
const CUR_SIZE := Vector2(132, 50)
const CUR_GAP := 8.0
const TRACK_Y := 74.0
const TRACK_H := 58.0

func _build_top() -> void:
	# wallet: three equal pills, premium crystals at the far right
	var x := -16.0 - CUR_SIZE.x
	crystal_label = pill(GemIcon.new(), Vector2(1, 0), Vector2(x, TOP_Y), CUR_SIZE, 30)
	crystal_pill = crystal_label.get_parent()
	x -= CUR_SIZE.x + CUR_GAP
	stone_label = pill(StoneIcon.new(), Vector2(1, 0), Vector2(x, TOP_Y), CUR_SIZE, 30)   # this run's 강화석
	stone_pill = stone_label.get_parent()
	x -= CUR_SIZE.x + CUR_GAP
	gold_label = pill(CoinIcon.new(), Vector2(1, 0), Vector2(x, TOP_Y), CUR_SIZE, 30)
	gold_pill = gold_label.get_parent()
	# "보스까지 N무리": tucked under the boss end of the progress track
	sub_label = label("", 20, Color("ffd27a"), 8)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(place(sub_label, Vector2(1, 0), Vector2(-236, TRACK_Y + TRACK_H + 2), Vector2(212, 28)))
	# centre message band: screen-centred, right below the hero status column (NOTICE_Y)
	gimmick_title = label("", 36, Color("ffd27a"), 12)
	root.add_child(place(gimmick_title, Vector2(0.5, 0), Vector2(-340, NOTICE_Y), Vector2(680, 46)))
	gimmick_hint = label("", 22, Color("fff4e0"), 8)
	gimmick_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(place(gimmick_hint, Vector2(0.5, 0), Vector2(-320, NOTICE_Y + 44), Vector2(640, 60)))
	phase_label = label("", 24, Color("fff4c0"), 9)
	phase_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(place(phase_label, Vector2(0.5, 0), Vector2(-320, NOTICE_Y), Vector2(640, 70)))
	_build_hero_status()

# ---------------------------------------------------------------- hero status (top-left)
const HERO_INITIAL := {"warrior": "워", "ranger": "레", "mage": "메"}
const HERO_COL := {"warrior": Color("ff7a5a"), "ranger": Color("5fcf5a"), "mage": Color("a77aff")}
var status_rows := {}   # cls -> {root, badge, hp, hp_lag, mana, lv, ult, hp_t, lag_v}
## Hero status column (top-left); the centre message band sits right below it (region chip: top right).
const STATUS_Y := TRACK_Y + TRACK_H + 16.0
const STATUS_STEP := 52.0
const STATUS_BAR_W := 66.0
const NOTICE_Y := STATUS_Y + 3 * STATUS_STEP + 22.0

func _build_hero_status() -> void:
	var y := STATUS_Y
	for cls in Defs.HERO_ORDER:
		var row := panel(Color.WHITE, Rect2(0, 0, 150, 40), 20, 0)
		row.add_theme_stylebox_override("panel", UiTheme.capsule(20))
		root.add_child(place(row, Vector2(0, 0), Vector2(22, y), Vector2(150, 40)))
		# tap the row (face) to open that hero's info
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_on_status_tap(cls))
		var badge := panel(HERO_COL[cls], Rect2(-8, -6, 52, 52), 26, 4)
		badge.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
		row.add_child(badge)
		var face := _portrait(cls)
		face.position = Vector2(2, 2)
		face.size = Vector2(48, 48)
		badge.add_child(face)
		var hbg := panel(INK, Rect2(48, 7, STATUS_BAR_W + 4, 14), 6, 0)
		row.add_child(hbg)
		var lag := panel(UiTheme.trail_col(), Rect2(50, 9, STATUS_BAR_W, 10), 4, 0)
		row.add_child(lag)
		var hp := panel(UiTheme.hp_col(), Rect2(50, 9, STATUS_BAR_W, 10), 4, 0)
		row.add_child(hp)
		var mbg := panel(INK, Rect2(48, 23, STATUS_BAR_W + 4, 9), 4, 0)
		row.add_child(mbg)
		var mana := panel(Defs.COL_MANA, Rect2(50, 25, 0, 5), 2, 0)
		row.add_child(mana)
		var lv := label("1", 17, Defs.COL_GOLD, 6)
		lv.position = Vector2(118, 0)
		lv.size = Vector2(30, 40)
		row.add_child(lv)
		var ult := panel(Color(0, 0, 0, 0), Rect2(-3, -3, 156, 46), 23, 0)
		ult.add_theme_stylebox_override("panel", box(Color(0, 0, 0, 0), 23, 3, Color("ffe04a")))
		ult.visible = false
		row.add_child(ult)
		var rsp := label("", 15, Color.WHITE, 5)
		rsp.position = Vector2(48, 2)
		rsp.size = Vector2(STATUS_BAR_W + 4, 24)
		rsp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rsp.visible = false
		row.add_child(rsp)
		status_rows[cls] = {"root": row, "badge": badge, "hp": hp, "lag": lag, "mana": mana, "lv": lv, "ult": ult, "rsp": rsp, "lag_v": 1.0, "shown": 1.0, "dead": false}
		y += STATUS_STEP

func _on_status_tap(cls: String) -> void:
	if game == null or has_overlay():
		return
	var h: Actor = game.hero(cls)
	if h == null:
		return
	Sfx.play("click", -6.0, 1.2)
	bump(status_rows[cls]["root"], 1.08)
	if hero_shown() == h:
		game._select(null)
	else:
		game._select(h)
		if hero_shown() != h:   # _select may refuse (tutorial); open the panel anyway
			show_hero_panel(h)

## Live 3D head shot of a hero (own little world rendered into a texture).
func _portrait(cls: String) -> TextureRect:
	var vp := SubViewport.new()
	vp.size = Vector2i(112, 112)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c8d0ff")
	e.ambient_light_energy = 0.9
	WebLook.apply(e)
	we.environment = e
	vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.3
	vp.add_child(sun)
	sun.rotation = Vector3(-0.7, 0.5, 0)
	var m := UnitModel.new().build(cls, Defs.TEAM_HERO)
	vp.add_child(m)
	m.rotation.y = PI + 0.35
	var hy := 0.66
	var c := Camera3D.new()
	c.fov = 30.0
	vp.add_child(c)
	c.position = Vector3(0.0, hy + 0.08, 1.25)
	c.look_at(Vector3(0, hy, 0), Vector3.UP)
	c.current = true
	var tr := TextureRect.new()
	tr.texture = vp.get_texture()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr

func _update_hero_status(delta: float, t: float) -> void:
	if game == null:
		return
	for cls in status_rows:
		var r: Dictionary = status_rows[cls]
		var h: Actor = game.hero(cls)
		if h == null:
			continue
		var ratio := clampf(h.hp / h.max_hp, 0.0, 1.0) if h.alive else 0.0
		r["shown"] = lerpf(r["shown"], ratio, 1.0 - exp(-delta * 20.0))
		r["lag_v"] = move_toward(r["lag_v"], ratio, delta * 0.7) if r["lag_v"] > ratio else ratio
		(r["hp"] as Panel).size.x = STATUS_BAR_W * r["shown"]
		(r["lag"] as Panel).size.x = STATUS_BAR_W * r["lag_v"]
		var hcol := UiTheme.hp_col() if ratio > 0.5 else (Color("ffc23f") if ratio > 0.25 else Color("ff5f6a"))
		if r.get("hcol", Color.BLACK) != hcol:
			r["hcol"] = hcol
			(r["hp"] as Panel).add_theme_stylebox_override("panel", box(hcol, 4, 0))
		(r["mana"] as Panel).size.x = STATUS_BAR_W * h.mana / Defs.MAX_MANA
		(r["lv"] as Label).text = str(h.level)
		var dead := not h.alive
		if dead != r["dead"]:
			r["dead"] = dead
			(r["root"] as Control).modulate = Color(0.55, 0.55, 0.6) if dead else Color.WHITE
			bump(r["root"], 1.15)
		var rsp := (r["rsp"] as Label)
		var left: float = game.respawn_in(h) if dead else 0.0
		rsp.visible = left > 0.0
		if rsp.visible:
			rsp.text = "부활 %d초" % int(ceilf(left))
		var ult := (r["ult"] as Panel)
		ult.visible = h.alive and game.in_battle() and h.ult_ready_at <= game.now
		if ult.visible:
			ult.modulate.a = 0.5 + 0.5 * sin(t * 6.0)

func _build_bottom() -> void:
	fight_btn = juicy_button("전투 시작!", Color("ff9f1c"), Rect2(0, 0, 300, 92), 40)
	fight_btn.pressed.connect(func(): fight_pressed.emit())
	root.add_child(place(fight_btn, Vector2(0.5, 1), Vector2(-120, -116), Vector2(300, 92)))
	talent_btn = juicy_button("특성", Color("6f6cf0"), Rect2(0, 0, 150, 92), 34)
	talent_btn.pressed.connect(func(): open_talents())
	root.add_child(place(talent_btn, Vector2(0.5, 1), Vector2(-300, -116), Vector2(160, 92)))

# ---------------------------------------------------------------- state setters
func set_wave(_w: int, sub: int, subs: int) -> void:
	sub_label.text = "%d차 / %d" % [sub + 1, subs] if subs > 1 else ""

func set_gold(v: int, animate := true) -> void:
	if gold_label.text != str(v):
		gold_label.text = str(v)
		if animate:
			bump(gold_label, 1.3)

func set_stones(v: int, animate := true) -> void:
	if stone_label.text != str(v):
		stone_label.text = str(v)
		if animate:
			bump(stone_label, 1.35)

func set_crystals(v: int, animate := true) -> void:
	if crystal_label.text != str(v):
		crystal_label.text = str(v)
		if animate:
			bump(crystal_label, 1.35)

func set_gimmick(title: String, hint: String) -> void:
	gimmick_title.text = title
	gimmick_hint.text = hint
	if title != "":
		bump(gimmick_title, 1.6)

func set_phase(text: String) -> void:
	phase_label.text = text
	phase_label.visible = gimmick_title.text == "" and tut_step == 0

func set_fight(on: bool) -> void:
	fight_btn.visible = on
	talent_btn.visible = on
	if on:
		pop_in(fight_btn)
		pop_in(talent_btn)

# ---------------------------------------------------------------- unit bars
func register_unit(u: Actor) -> void:
	unregister_unit(u)   # registering twice must not orphan the first bar
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var w := 64.0 if u.body_r <= Actor.RADIUS else 110.0
	c.size = Vector2(w + 20, 30)
	root.add_child(c)
	root.move_child(c, 0)
	c.set_meta("unit_bar", true)
	var bg := panel(INK, Rect2(14, 2, w + 6, 18), 8, 0)
	c.add_child(bg)
	var lag := panel(UiTheme.trail_col(), Rect2(17, 5, w, 12), 5, 0)
	c.add_child(lag)
	var fill := panel(UiTheme.unit_bar(u.is_hero()), Rect2(17, 5, w, 12), 5, 0)
	c.add_child(fill)
	var shine := panel(Color(1, 1, 1, 0.3), Rect2(20, 6, w - 6, 3), 2, 0) if UiTheme.tt() else panel(Color(1, 1, 1, 0.35), Rect2(20, 6, w - 6, 4), 2, 0)
	c.add_child(shine)
	var mana: Panel = null
	var badge_l: Label = null
	var sp: Panel = null
	var ult: Panel = null
	if u.is_hero():
		var mbg := panel(INK, Rect2(14, 18, w + 6, 10), 4, 0)
		c.add_child(mbg)
		mana = panel(Defs.COL_MANA, Rect2(17, 20, 0, 6), 3, 0)
		c.add_child(mana)
		var badge := panel(Defs.COL_GOLD, Rect2(0, 0, 28, 26), 7, 3)
		c.add_child(badge)
		badge_l = label("1", 18, Color("5a3a00"), 0)
		badge_l.position = Vector2(0, -1)
		badge_l.size = Vector2(28, 26)
		badge.add_child(badge_l)
		sp = panel(Color("ff5f7e"), Rect2(w + 14, -12, 30, 26), 13, 3)
		var spl := label("+1", 16, Color.WHITE, 4)
		spl.size = Vector2(30, 26)
		sp.add_child(spl)
		sp.visible = false
		c.add_child(sp)
		ult = panel(Color(1, 0.85, 0.25, 0.0), Rect2(10, -6, w + 14, 40), 12, 3)
		ult.add_theme_stylebox_override("panel", box(Color(0, 0, 0, 0), 12, 4, Color("ffe04a")))
		ult.visible = false
		c.add_child(ult)
	bars[u] = {"c": c, "fill": fill, "lag": lag, "mana": mana, "lv": badge_l, "sp": sp, "ult": ult, "w": w, "lag_v": 1.0, "shown": 1.0}

func unregister_unit(u: Actor) -> void:
	if bars.has(u):
		bars[u]["c"].queue_free()
		bars.erase(u)

func _process(delta: float) -> void:
	if cam == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	_tutorial_pulse(t)
	_update_hero_status(delta, t)
	_update_spot()
	_update_loot_tags()
	for key in bars.keys():
		var b: Dictionary = bars[key]
		var u: Actor = key
		var c: Control = b["c"]
		if not is_instance_valid(u):   # freed without unregister_unit: drop its bar instead of keeping it forever
			c.queue_free()
			bars.erase(key)
			continue
		if not u.visible or not u.alive or u.model.mats.is_empty() or u.model.mats[0].albedo_color.a < 0.9:
			c.visible = false
			continue
		var head := u.global_position + Vector3(0, u.def.get("bar_h", 1.05) * u.model.scale.y / Actor.MODEL_SCALE + u.model.position.y + 0.15, 0)
		if cam.is_position_behind(head):
			c.visible = false
			continue
		c.visible = true
		var w: float = b["w"]
		c.position = cam.unproject_position(head) - Vector2(w * 0.5 + 17, 14)
		var ratio := clampf(u.hp / u.max_hp, 0.0, 1.0)
		b["shown"] = lerpf(b["shown"], ratio, 1.0 - exp(-delta * 25.0))
		if b["lag_v"] > ratio:
			b["lag_v"] = move_toward(b["lag_v"], ratio, delta * 0.8)
		else:
			b["lag_v"] = ratio
		(b["fill"] as Panel).size.x = w * b["shown"]
		(b["lag"] as Panel).size.x = w * b["lag_v"]
		if b["mana"]:
			var m := (b["mana"] as Panel)
			m.size.x = w * u.mana / Defs.MAX_MANA
			m.modulate = Color(1.6, 1.6, 1.6) if u.mana >= 99.0 else Color.WHITE
			(b["lv"] as Label).text = str(u.level)
			var sp := (b["sp"] as Panel)
			var books: int = game.books_for(u.cls)   # skill books in the bag (any book teaches any hero)
			var show_sp: bool = books > 0
			if show_sp != sp.visible:
				sp.visible = show_sp
				if show_sp:
					pop_in(sp)
			if show_sp:
				(sp.get_child(0) as Label).text = "+%d" % books
			var ult := (b["ult"] as Panel)
			ult.visible = game.in_battle() and u.ult_ready_at <= game.now
			if ult.visible:
				ult.modulate.a = 0.55 + 0.45 * sin(t * 6.0)

# ---------------------------------------------------------------- spotlight dim (gear drag stage)
## Dark stage over the 3D field (under every HUD element) with soft clear holes around the living heroes,
## so — like an ultimate — the surroundings sink into the dark and the drop targets stand out.
const SPOT_SHADER := """
shader_type canvas_item;
uniform vec2 rect_size = vec2(720.0, 1280.0);
uniform vec2 pts[3];
uniform float rads[3];
uniform int n = 0;
uniform float amount = 0.0;
void fragment() {
	vec2 p = UV * rect_size;
	float m = 1.0;
	for (int i = 0; i < 3; i++) {
		if (i < n) {
			vec2 d = (p - pts[i]) / vec2(1.0, 1.35);
			m = min(m, smoothstep(rads[i] * 0.5, rads[i], length(d)));
		}
	}
	vec2 c = UV - 0.5;
	float vig = smoothstep(0.25, 0.85, length(c * vec2(1.0, 0.7)));
	COLOR = vec4(0.03, 0.02, 0.08, amount * (0.62 * m + 0.2 * vig));
}
"""
static var _spot_shader: Shader   # compiled once, shared by every drag stage
var _spot: ColorRect
var _spot_k := 0.0
var _spot_goal := 0.0

func drag_spot(on: bool) -> void:
	_spot_goal = 1.0 if on else 0.0
	if on and (_spot == null or not is_instance_valid(_spot)):
		_spot = ColorRect.new()
		_spot.set_anchors_preset(Control.PRESET_FULL_RECT)
		_spot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _spot_shader == null:
			_spot_shader = Shader.new()
			_spot_shader.code = SPOT_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = _spot_shader
		_spot.material = mat
		root.add_child(_spot)
		root.move_child(_spot, 0)   # under every HUD element: only the field darkens

func _update_spot() -> void:
	if _spot == null or not is_instance_valid(_spot):
		return
	var real := get_process_delta_time() / maxf(Engine.time_scale, 0.001)
	_spot_k = move_toward(_spot_k, _spot_goal, minf(real, 0.05) * (5.0 if _spot_goal > _spot_k else 3.5))
	if _spot_k <= 0.0 and _spot_goal <= 0.0:
		_spot.queue_free()
		_spot = null
		return
	var pts := PackedVector2Array()
	var rads := PackedFloat32Array()
	for h in game.alive_heroes():
		var c: Vector3 = h.global_position + Vector3(0, 0.55 + h.model.position.y, 0)
		if cam.is_position_behind(c):
			continue
		var sp := cam.unproject_position(c)
		pts.append(sp)
		rads.append(cam.unproject_position(c + Vector3(1.0, 0, 0)).distance_to(sp) * 1.15)
	var n := pts.size()
	while pts.size() < 3:
		pts.append(Vector2(-9999, -9999))
		rads.append(1.0)
	var mat := _spot.material as ShaderMaterial
	mat.set_shader_parameter("rect_size", root.size)
	mat.set_shader_parameter("pts", pts)
	mat.set_shader_parameter("rads", rads)
	mat.set_shader_parameter("n", n)
	mat.set_shader_parameter("amount", _spot_k)

# ---------------------------------------------------------------- floating text
func _float(world: Vector3, text: String, size: int, col: Color, rise := 60.0, life := 0.7) -> Label:
	if cam.is_position_behind(world):
		return null
	var l := label(text, size, col, 9)
	l.size = Vector2(240, 50)
	var p := cam.unproject_position(world) + Vector2(randf_range(-16, 16), 0)
	l.position = p - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	root.add_child(l)
	l.scale = Vector2(0.4, 0.4)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.2, 1.2), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - rise, life).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "scale", Vector2(0.9, 0.9), 0.3).set_delay(0.12)
	tw.tween_property(l, "modulate:a", 0.0, 0.25).set_delay(life - 0.2)
	tw.chain().tween_callback(l.queue_free)
	return l

func damage_number(world: Vector3, amount: float, team: int, crit := false) -> void:
	var txt := str(int(round(amount)))
	if team == Defs.TEAM_HERO:
		_float(world, txt, 30, Color("ff8a9a"))
	elif crit:
		var l := _float(world + Vector3(0, 0.15, 0), txt + "!", 44, Color("ffb43c"), 75.0, 0.85)
		if l:
			l.rotation = randf_range(-0.12, 0.12)
	else:
		_float(world, txt, 32 + int(minf(amount / 20.0, 8.0)), Color.WHITE)

func heal_number(world: Vector3, amount: float) -> void:
	_float(world, "+%d" % int(round(amount)), 30, Color("8fe36a"))

func float_text(world: Vector3, text: String, col: Color) -> void:
	_float(world, text, 28, col, 50.0, 0.9)

func callout(world: Vector3, text: String, color: Color) -> void:
	if cam.is_position_behind(world):
		return
	var l := label(text, 34, color, 10)
	l.size = Vector2(360, 50)
	var p := cam.unproject_position(world)
	l.position = p - l.size * 0.5
	l.pivot_offset = l.size * 0.5
	root.add_child(l)
	l.scale = Vector2(0.2, 0.2)
	l.rotation = -0.08
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 40, 0.9).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.7)
	tw.chain().tween_callback(l.queue_free)

## Big center banner: punch in, hold, puff out.
func banner(text: String, color: Color, hold := 0.8, size := 120, y := 0.0) -> void:
	var l := label(text, size, color, 22)
	l.label_settings.outline_color = Color("5a2a08") if color == Defs.COL_GOLD else INK
	root.add_child(place(l, Vector2(0.5, 0.5), Vector2(-360, -size * 0.75 + y), Vector2(720, size * 1.5)))
	l.scale = Vector2(2.6, 2.6)
	l.modulate.a = 0.0
	l.rotation = -0.06
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 1.0, 0.1)
	tw.tween_property(l, "rotation", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(hold)
	tw.chain().set_parallel(true)
	tw.tween_property(l, "scale", Vector2(1.25, 1.25), 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.chain().tween_callback(l.queue_free)

## 뚜까펫식 리본 배너(도전 완료/레벨업): 섬광 → 회전 빛줄기 → 리본이 옆으로 펼쳐지고
## 제목이 튀어 들어온 뒤 반짝이가 흩어진다. sub는 리본 위 작은 글씨.
func ribbon_banner(title: String, sub := "", col := UiTheme.ORANGE, hold := 0.9, y := -30.0) -> void:
	var W := 640.0
	var box_c := Control.new()
	box_c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(place(box_c, Vector2(0.5, 0.5), Vector2(-W * 0.5, y - 150.0), Vector2(W, 300)))
	var rays := RayBurst.new()
	rays.size = Vector2(W, 300)
	rays.pivot_offset = rays.size * 0.5
	rays.col = col.lightened(0.5)
	rays.modulate.a = 0.0
	box_c.add_child(rays)
	var rib := Ribbon.new()
	rib.col = col
	rib.position = Vector2(20, 132)
	rib.size = Vector2(W - 40, 104)
	rib.pivot_offset = rib.size * 0.5
	rib.scale = Vector2(0.05, 1.2)
	box_c.add_child(rib)
	var t := label(title, 66, Color.WHITE, 16)
	t.position = Vector2(0, 128)
	t.size = Vector2(W, 104)
	t.pivot_offset = t.size * 0.5
	t.scale = Vector2(2.2, 2.2)
	t.modulate.a = 0.0
	box_c.add_child(t)
	if sub != "":
		var s := label(sub, 30, UiTheme.TXT_YELLOW, 10)
		s.position = Vector2(0, 84)
		s.size = Vector2(W, 46)
		s.pivot_offset = s.size * 0.5
		s.scale = Vector2.ZERO
		box_c.add_child(s)
		s.create_tween().tween_property(s, "scale", Vector2.ONE, 0.35).set_delay(0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flash(0.35, 0.3)
	var tw := box_c.create_tween().set_parallel(true)
	tw.tween_property(rays, "modulate:a", 0.85, 0.15)
	tw.tween_property(rays, "rotation", 0.7, hold + 0.9)
	tw.tween_property(rib, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "scale", Vector2.ONE, 0.3).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(t, "modulate:a", 1.0, 0.1).set_delay(0.08)
	tw.chain().tween_interval(hold)
	tw.chain().set_parallel(true)
	tw.tween_property(box_c, "modulate:a", 0.0, 0.25)
	tw.tween_property(box_c, "offset_top", box_c.offset_top - 40.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(box_c, "offset_bottom", box_c.offset_bottom - 40.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(box_c.queue_free)
	_sparkles(box_c, Vector2(W * 0.5, 184), 14)

## 반짝이 별이 사방으로 튀었다가 떨어지며 사라진다(리본 배너/보상용).
func _sparkles(parent: Control, at: Vector2, n: int) -> void:
	for i in n:
		var sp := Sparkle.new()
		sp.size = Vector2(26, 26)
		sp.pivot_offset = sp.size * 0.5
		sp.position = at - sp.size * 0.5
		sp.col = [UiTheme.TXT_YELLOW, Color.WHITE, Color("ff9ad8"), Color("8ff0ff")][i % 4]
		sp.scale = Vector2.ZERO
		parent.add_child(sp)
		var a := randf() * TAU
		var d := randf_range(140.0, 320.0)
		var dest := sp.position + Vector2(cos(a) * d, sin(a) * d * 0.55 - 40.0)
		var tw := sp.create_tween().set_parallel(true)
		var delay := 0.12 + randf() * 0.15
		tw.tween_property(sp, "scale", Vector2.ONE * randf_range(0.6, 1.2), 0.2).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "position", dest, 0.75).set_delay(delay).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "rotation", randf_range(-3.0, 3.0), 0.9).set_delay(delay)
		tw.tween_property(sp, "modulate:a", 0.0, 0.3).set_delay(delay + 0.6)

## 뚜까펫 "쫌비 습격"식 경고 띠: 빨간 가로 띠가 화면을 가로질러 들어와 두 번 깜빡이고 빠진다.
func warn_band(text: String, y := -40.0) -> void:
	var vw := get_viewport().get_visible_rect().size.x
	var band := WarnBand.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.5
	band.anchor_bottom = 0.5
	band.offset_top = y - 62.0
	band.offset_bottom = y + 62.0
	band.offset_left = -vw
	band.offset_right = -vw
	root.add_child(band)
	var t := label(text, 54, Color.WHITE, 14)
	t.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band.add_child(t)
	Sfx.play("clash", -10.0, 0.7)
	var tw := band.create_tween()
	tw.set_parallel(true)
	tw.tween_property(band, "offset_left", 0.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(band, "offset_right", 0.0, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(band, "modulate", Color(1.6, 1.6, 1.6), 0.08)
	tw.chain().tween_property(band, "modulate", Color.WHITE, 0.12)
	tw.chain().tween_property(band, "modulate", Color(1.6, 1.6, 1.6), 0.08)
	tw.chain().tween_property(band, "modulate", Color.WHITE, 0.12)
	tw.chain().tween_interval(0.7)
	tw.chain().set_parallel(true)
	tw.tween_property(band, "offset_left", vw, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.tween_property(band, "offset_right", vw, 0.22).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(band.queue_free)

func flash(a := 0.7, dur := 0.25) -> void:
	flash_rect.color = Color(1, 1, 1, a)
	var tw := flash_rect.create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, dur)

## Toasts live in the centre message band under the gimmick text: at most TOAST_MAX stacked,
## newest at the bottom; a new one pushes the oldest out.
const TOAST_Y := NOTICE_Y + 110.0
const TOAST_H := 46.0
const TOAST_MAX := 2

func toast(text: String, col := Color("ff5f9e")) -> void:
	while _toasts.size() >= TOAST_MAX:
		_toast_out(_toasts.pop_front(), true)
	var l := label(text, 30, col, 10)
	root.add_child(place(l, Vector2(0.5, 0), Vector2(-350, _toast_y(_toasts.size())), Vector2(700, TOAST_H)))
	_toasts.append(l)
	_toast_relayout()
	l.scale = Vector2(0.3, 0.3)
	var tw := l.create_tween()
	tw.tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.6)
	tw.tween_callback(func():
		if _toasts.has(l):
			_toasts.erase(l)
			_toast_out(l, false)
			_toast_relayout())
	l.set_meta("life", tw)

func _toast_y(i: int) -> float:
	return TOAST_Y + i * TOAST_H

## Slide the remaining toasts into their slots.
func _toast_relayout() -> void:
	for i in _toasts.size():
		var t := _toasts[i]
		var ty := _toast_y(i)
		if absf(t.offset_top - ty) < 0.5:
			continue
		var tw := retween(t, "slide_tw").set_parallel(true)
		tw.tween_property(t, "offset_top", ty, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(t, "offset_bottom", ty + TOAST_H, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Fade a toast away; pushed = evicted by a newer one (quick, drifts up).
func _toast_out(l: Label, pushed: bool) -> void:
	if not is_instance_valid(l):
		return
	kill_tween(l, "life")
	kill_tween(l, "slide_tw")   # a pushed toast drifts up from where it is, not toward its old slot
	var dur := 0.16 if pushed else 0.3
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "modulate:a", 0.0, dur)
	if pushed:
		tw.tween_property(l, "offset_top", l.offset_top - 30.0, dur)
		tw.tween_property(l, "offset_bottom", l.offset_bottom - 30.0, dur)
		tw.tween_property(l, "scale", Vector2(0.85, 0.85), dur)
	tw.chain().tween_callback(l.queue_free)

## 2D coin flies from a screen point into the gold counter.
func fly_coin(from: Vector2, on_arrive: Callable) -> void:
	_fly_to_pill(CoinIcon.new(), gold_pill, from, on_arrive)

## A 강화석 flying from the field (or a chest card) into the top 강화석 counter, like a coin.
func fly_stone(from: Vector2, on_arrive: Callable) -> void:
	_fly_to_pill(StoneIcon.new(), stone_pill, from, on_arrive)

func _fly_to_pill(ic: Control, target: Control, from: Vector2, on_arrive: Callable) -> void:
	ic.size = Vector2(40, 40)
	ic.position = from - ic.size * 0.5
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(ic)
	var dest := target.get_global_rect().position + Vector2(8, 6)
	var mid := from.lerp(dest, 0.5) + Vector2(randf_range(-80, 80), -120)
	var step := func(k: float) -> void:
		var a := from.lerp(mid, k)
		var b := mid.lerp(dest, k)
		ic.position = a.lerp(b, k) - ic.size * 0.5 + Vector2(20, 20) * k
		ic.scale = Vector2.ONE * (1.0 + sin(k * PI) * 0.4)
	var tw := ic.create_tween()
	tw.tween_method(step, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		ic.queue_free()
		Sfx.play("tick", -8.0, 1.8)
		on_arrive.call())

# ---------------------------------------------------------------- ultimate letterbox
var _bars: Control

## Letterbox bars with a title (ultimate name + "!", or the dragged item's name with bang = false).
func cinema_bars(on: bool, ult_name: String, hero_name: String, col: Color, bang := true) -> void:
	if not on:
		if _bars and is_instance_valid(_bars):
			var b := _bars
			_bars = null
			var tw := b.create_tween().set_parallel(true).set_ignore_time_scale(true)
			tw.tween_property(b.get_child(0), "position:y", -130.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(b.get_child(1), "offset_top", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_property(b, "modulate:a", 0.0, 0.25)
			tw.chain().tween_callback(b.queue_free)
		return
	if _bars and is_instance_valid(_bars):
		_bars.queue_free()
	_bars = Control.new()
	_bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bars)
	var top := ColorRect.new()
	top.color = Color(0.03, 0.02, 0.06, 0.55)
	top.anchor_right = 1.0
	top.offset_bottom = 120
	top.position.y = -130
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.add_child(top)
	var bot := ColorRect.new()
	bot.color = Color(0.03, 0.02, 0.06, 0.55)
	bot.anchor_top = 1.0
	bot.anchor_right = 1.0
	bot.anchor_bottom = 1.0
	bot.offset_top = 0
	bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bars.add_child(bot)
	var tw2 := _bars.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw2.tween_property(top, "position:y", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw2.tween_property(bot, "offset_top", -36.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var hn := label(hero_name, 26, col.lightened(0.3), 8)
	top.add_child(hn)
	hn.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hn.offset_top = 6
	hn.offset_bottom = 40
	var nm := label(ult_name + ("!" if bang else ""), 50 if bang else 44, col, 14)
	top.add_child(nm)
	nm.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	nm.offset_top = 36
	nm.offset_bottom = 116
	nm.pivot_offset = Vector2(get_viewport().get_visible_rect().size.x * 0.5, 45)
	nm.scale = Vector2(1.5, 1.5)
	nm.modulate.a = 0.0
	var tw3 := nm.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw3.tween_property(nm, "scale", Vector2.ONE, 0.3).set_delay(0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw3.tween_property(nm, "modulate:a", 1.0, 0.12).set_delay(0.08)

# ---------------------------------------------------------------- field loot name plates
## Minimal plates: small dark pill, rarity dot + rarity-tinted name. Plates never overlap:
## each frame they are laid out bottom-up and a plate that would overlap is pushed up so its
## bottom edge sits flush on the top edge of the one below.
var loot_tags := {}   # Node3D -> Panel
## Grouped plates (강화석): one plate for every piece of the group on the field, at their centre, with the total.
## group -> {"p": Panel, "base": text, "rarity": r, "nodes": {Node3D: amount}}
var loot_groups := {}
const LOOT_TAG_H := 22.0
const LOOT_TAG_GAP := 2.0

## A field item's name plate. With `group` set, the item joins that group's single plate ("강화석 ×32")
## instead of getting its own, adding `amount` to the shown total.
func add_loot_tag(node: Node3D, text: String, rarity: String, group := "", amount := 1) -> void:
	if group != "":
		if loot_groups.has(group) and is_instance_valid(loot_groups[group]["p"]):
			var g: Dictionary = loot_groups[group]
			g["nodes"][node] = amount
			_group_text(g)
			return
		var gp := _loot_plate(text, rarity)
		loot_groups[group] = {"p": gp, "base": text, "rarity": rarity, "nodes": {node: amount}}
		_group_text(loot_groups[group])
		return
	loot_tags[node] = _loot_plate(text, rarity)

func _loot_plate(text: String, rarity: String) -> Panel:
	var col: Color = Defs.RARITY_COL.get(rarity, Color.WHITE)
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", box(Color(0.07, 0.05, 0.14, 0.9), int(LOOT_TAG_H * 0.5), 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := panel(col, Rect2(8, (LOOT_TAG_H - 7) * 0.5, 7, 7), 4, 0)
	p.add_child(dot)
	var l := label(text, 15, col.lerp(Color.WHITE, 0.45), 0)
	l.name = "Text"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = Vector2(20, 0)
	p.add_child(l)
	_plate_text(p, text)
	root.add_child(p)
	# above every unit bar (those sit at the front of root, incl. ones still fading out) but under the rest of the HUD
	var at := 0
	while at < root.get_child_count() - 1 and root.get_child(at).has_meta("unit_bar"):
		at += 1
	root.move_child(p, at)
	p.visible = false
	p.modulate.a = 0.0
	var wr: WeakRef = weakref(p)   # the plate may be collected before it appears
	get_tree().create_timer(0.75).timeout.connect(func():
		var pp: Panel = wr.get_ref()
		if pp:
			pp.visible = true
			pp.create_tween().tween_property(pp, "modulate:a", 1.0, 0.2))
	return p

func _plate_text(p: Panel, text: String) -> void:
	var l: Label = p.get_node("Text")
	l.text = text
	var tw_text := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	p.size = Vector2(ceilf(tw_text) + 30.0, LOOT_TAG_H)
	p.pivot_offset = Vector2(p.size.x * 0.5, LOOT_TAG_H)
	l.size = Vector2(p.size.x - 24, LOOT_TAG_H)

func _group_text(g: Dictionary) -> void:
	var total := 0
	for n in g["nodes"]:
		total += int(g["nodes"][n])
	_plate_text(g["p"], "%s ×%d" % [g["base"], total])

func remove_loot_tag(node: Node3D) -> void:
	if loot_tags.has(node):
		var p: Panel = loot_tags[node]
		loot_tags.erase(node)
		if is_instance_valid(p):
			p.queue_free()
		return
	for key in loot_groups.keys():
		var g: Dictionary = loot_groups[key]
		if g["nodes"].has(node):
			g["nodes"].erase(node)
			if g["nodes"].is_empty() or not is_instance_valid(g["p"]):
				if is_instance_valid(g["p"]):
					g["p"].queue_free()
				loot_groups.erase(key)
			else:
				_group_text(g)
			return

func _update_loot_tags() -> void:
	if loot_tags.is_empty() and loot_groups.is_empty():
		return
	var items: Array = []   # [{p, rect}]
	for node in loot_tags.keys():
		var p: Panel = loot_tags[node]
		if not is_instance_valid(node) or not is_instance_valid(p):
			remove_loot_tag(node)
			continue
		var at: Vector3 = node.global_position + Vector3(0, 0.5, 0)
		var sp := cam.unproject_position(at)
		items.append({"p": p, "rect": Rect2(sp.x - p.size.x * 0.5, sp.y - LOOT_TAG_H, p.size.x, LOOT_TAG_H)})
	for key in loot_groups.keys():   # a group plate sits over the centre of its pieces
		var g: Dictionary = loot_groups[key]
		for n in g["nodes"].keys():
			if not is_instance_valid(n):
				remove_loot_tag(n)
		if not loot_groups.has(key):
			continue
		var c := Vector3.ZERO
		for n in g["nodes"]:
			c += (n as Node3D).global_position
		c /= float(g["nodes"].size())
		var gp: Panel = g["p"]
		var gsp := cam.unproject_position(c + Vector3(0, 0.5, 0))
		items.append({"p": gp, "rect": Rect2(gsp.x - gp.size.x * 0.5, gsp.y - LOOT_TAG_H, gp.size.x, LOOT_TAG_H)})
	# bottom-most (nearest the camera) first; ties broken by x so the order is stable
	items.sort_custom(func(a, b):
		var ra: Rect2 = a["rect"]
		var rb: Rect2 = b["rect"]
		return ra.position.y > rb.position.y if absf(ra.position.y - rb.position.y) > 0.5 else ra.position.x < rb.position.x)
	var placed: Array[Rect2] = []
	for it in items:
		var r: Rect2 = it["rect"]
		var moved := true
		while moved:
			moved = false
			for q in placed:
				if r.grow(LOOT_TAG_GAP * 0.5 - 0.01).intersects(q.grow(LOOT_TAG_GAP * 0.5 - 0.01)):
					r.position.y = q.position.y - LOOT_TAG_H - LOOT_TAG_GAP
					moved = true
		placed.append(r)
		(it["p"] as Panel).position = r.position.round()

# flying items sit above every HUD panel (the bag lives on HudPanels, drawn after root)
var _fly_layer: CanvasLayer
static var _sil_shader: Shader
static var _sil_mats := {}   # colour html -> ShaderMaterial

func _fly_root() -> CanvasLayer:
	if _fly_layer == null or not is_instance_valid(_fly_layer):
		_fly_layer = CanvasLayer.new()
		_fly_layer.layer = layer + 2
		add_child(_fly_layer)
	return _fly_layer

## Star twinkle tween: flat on x, flat on y (back easing), elastic settle, then shrink + fade.
func _twinkle(g: Control, peak: float, delay := 0.08) -> void:
	g.modulate.a = 0.0
	g.scale = Vector2.ZERO
	var tw := g.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(g, "modulate:a", peak, 0.05)
	tw.parallel().tween_property(g, "scale", Vector2(1.7, 0.4), 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "scale", Vector2(0.4, 1.7), 0.11).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "scale", Vector2(0.95, 0.95), 0.16).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(g, "scale", Vector2(0.2, 0.2), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(g, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

static var _add_mat: CanvasItemMaterial

## Crisp casual sparkle shapes (clean edges, saturated colour, white core).
##   "disc": solid disc
##   "ring": expanding rarity ring + flying white dots, driven by t (0..1)
##   "star": 4-point star in vivid rarity colour + white inner star + white dot
class FlyBurst extends Control:
	var mode := "disc"
	var col := Color.WHITE
	var radius := 30.0
	var dots := 6
	var thick := 1.0
	var t := 0.0:
		set(v):
			t = v
			queue_redraw()

	func _star(c: Vector2, r_out: float, r_in: float, colr: Color) -> void:
		var pts := PackedVector2Array()
		for i in 8:
			var a := -PI * 0.5 + i * PI / 4.0
			pts.append(c + Vector2.from_angle(a) * (r_out if i % 2 == 0 else r_in))
		draw_colored_polygon(pts, colr)

	func _draw() -> void:
		var c := size * 0.5
		if mode == "disc":
			draw_circle(c, radius, col, true, -1.0, true)
			return
		if mode == "ring":
			# expanding rarity ring + flying sparkle dots, driven by t (0..1)
			var k := t
			var r := lerpf(radius * 0.45, radius * 1.35, k)
			var fade := 1.0 - k * k
			draw_arc(c, r, 0.0, TAU, 48, Color(col, fade), lerpf(9.0, 2.0, k) * thick, true)
			draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, fade * 0.9), lerpf(3.0, 0.6, k) * thick, true)
			for i in dots:
				var a := i * TAU / float(dots) + 0.4
				var dr := lerpf(radius * 0.55, radius * 1.75, sqrt(k))
				var dp := c + Vector2.from_angle(a) * dr
				var rr := lerpf(5.5, 1.0, k)
				draw_circle(dp, rr, Color(col, fade), true, -1.0, true)
				draw_circle(dp, rr * 0.5, Color(1, 1, 1, fade), true, -1.0, true)
			return
		if mode == "aura":
			# stepped toon glow: three flat bands, brightest in the middle
			draw_circle(c, radius, Color(col, 0.2), true, -1.0, true)
			draw_circle(c, radius * 0.8, Color(col, 0.26), true, -1.0, true)
			draw_circle(c, radius * 0.6, Color(col.lightened(0.25), 0.38), true, -1.0, true)
			return
		_star(c, radius, radius * 0.36, col)
		_star(c, radius * 0.55, radius * 0.2, Color(1, 1, 1, 1))
		draw_circle(c, radius * 0.12, Color.WHITE, true, -1.0, true)

## Burst shape centred at `at` on the 64x64 fly holder.
func _fly_burst(mode: String, col: Color, radius: float, at := Vector2(32, 32), additive := false) -> FlyBurst:
	if _add_mat == null:
		_add_mat = CanvasItemMaterial.new()
		_add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	var b := FlyBurst.new()
	b.mode = mode
	b.col = col
	b.radius = radius
	b.size = Vector2(radius, radius) * 2.0
	if mode == "ring":
		b.size = Vector2(radius, radius) * 4.0
	b.position = at - b.size * 0.5
	b.pivot_offset = b.size * 0.5
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if additive:
		b.material = _add_mat
	return b

## Rarity colour pushed to full saturation / brightness (pastels read muddy when added).
static func _vivid(c: Color) -> Color:
	if c.s < 0.15:
		return Color(0.95, 0.96, 1.0)   # common/grey: clean silver-white (not mistaken for rare blue)
	return Color.from_hsv(c.h, maxf(c.s, 0.85), 1.0)

## 8 directions at radius r (outline / shadow spread).
func _ring(r: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in 8:
		out.append(Vector2.from_angle(i * TAU / 8.0) * r)
	return out

## Copy of the icon drawn as a flat single-colour silhouette.
func _icon_silhouette(e: Dictionary, rect: Rect2, off: Vector2, col: Color) -> ItemIcon:
	if _sil_shader == null:
		_sil_shader = Shader.new()
		_sil_shader.code = "shader_type canvas_item;
uniform vec4 tint : source_color;
void fragment() {
	COLOR = vec4(tint.rgb, COLOR.a * tint.a);
}
"
	var key := col.to_html()
	if not _sil_mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _sil_shader
		m.set_shader_parameter("tint", col)
		_sil_mats[key] = m
	var c := ItemIcon.new(e)
	c.show_tier = false
	c.position = rect.position + off
	c.size = rect.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.material = _sil_mats[key]
	return c

## Size of the icon flying into the bag, relative to the base 58 px art (outline/shadow scale with it).
const FLY_ITEM_SCALE := 1.5

const RARITY_RANK := ["common", "uncommon", "rare", "epic", "legendary", "mythic", "ancient", "primal", "transcendent"]

## Casual "gem" sparkle on a flying icon, scaled by pw (0 = uncommon .. 1 = top grade), timed to the
## moment the icon is at its biggest: the icon is born as a vivid rarity silhouette and develops,
## a stepped aura blooms behind it, a rarity ring pops with sparkle dots (a second ring at high grades),
## and 1-3 corner stars twinkle (flat on x, then on y) without covering the art.
func _fly_sparkle(holder: Control, e: Dictionary, rect: Rect2, vivid: Color, pw: float) -> void:
	var aura := _fly_burst("aura", vivid, lerpf(28.0, 46.0, pw))
	holder.add_child(aura)
	holder.move_child(aura, 0)
	aura.scale = Vector2(0.8, 0.8)
	aura.modulate.a = lerpf(0.45, 1.0, pw)
	var atw := aura.create_tween()
	atw.tween_property(aura, "scale", Vector2(1.15, 1.15), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	atw.tween_property(aura, "scale", Vector2(0.9, 0.9), 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	atw.parallel().tween_property(aura, "modulate:a", lerpf(0.2, 0.7, pw), 0.3)
	var shine := _icon_silhouette(e, rect, Vector2.ZERO, vivid)
	shine.modulate.a = lerpf(0.55, 1.0, pw)
	holder.add_child(shine)
	var stw := shine.create_tween()
	stw.tween_interval(lerpf(0.08, 0.16, pw))
	stw.tween_property(shine, "modulate:a", 0.0, lerpf(0.2, 0.36, pw)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var rings := 2 if pw >= 0.55 else 1
	for i in rings:
		var ring := _fly_burst("ring", vivid, lerpf(24.0, 38.0, pw) * (1.0 + 0.35 * i))
		ring.dots = int(round(lerpf(4.0, 10.0, pw)))
		ring.thick = lerpf(0.6, 1.3, pw)
		ring.visible = false   # t = 0 would draw a full ring before the pop starts
		holder.add_child(ring)
		var rtw := ring.create_tween()
		rtw.tween_interval(0.12 + 0.08 * i)
		rtw.tween_callback(func(): ring.visible = true)
		rtw.tween_property(ring, "t", 1.0, lerpf(0.32, 0.5, pw)).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	var stars := [[Vector2(56, 8), 1.0, 0.14], [Vector2(7, 52), 0.66, 0.22], [Vector2(60, 50), 0.55, 0.3]]
	var n := 1 if pw < 0.3 else (2 if pw < 0.6 else 3)
	for i in n:
		var st := _fly_burst("star", vivid, lerpf(10.0, 18.0, pw) * float(stars[i][1]), stars[i][0])
		holder.add_child(st)
		_twinkle(st, 1.0, stars[i][2])

## Item icon flies from the field into the next free bag slot, then calls on_arrive.
func fly_item(from: Vector2, e: Dictionary, on_arrive: Callable, slot_offset := 0) -> void:
	# bare icon (no panel) on the topmost layer: rarity-coloured outline + tight dark drop shadow,
	# both following the icon's own silhouette
	var holder := Control.new()
	holder.size = Vector2(64, 64)
	holder.pivot_offset = holder.size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := Rect2(3, 3, 58, 58)
	var rc: Color = Defs.RARITY_COL[Inventory.rarity_of(e)]
	var vivid := _vivid(rc)
	# sparkle strength by rarity: common = plain flight (no sparkle), then stronger with every grade
	var rank := RARITY_RANK.find(Inventory.rarity_of(e))
	var fx := rank > 0
	var pw := clampf((rank - 1) / float(RARITY_RANK.size() - 2), 0.0, 1.0)
	if fx:
		# the moment the field drop turns into an icon: a thick vivid rarity outline pops out and settles
		var pop_ol := Control.new()
		pop_ol.size = holder.size
		pop_ol.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for d in _ring(lerpf(4.0, 8.0, pw)):
			pop_ol.add_child(_icon_silhouette(e, rect, d, vivid))
		pop_ol.modulate.a = lerpf(0.65, 1.0, pw)
		holder.add_child(pop_ol)
		var otw := pop_ol.create_tween()
		otw.tween_interval(lerpf(0.1, 0.2, pw))
		otw.tween_property(pop_ol, "modulate:a", 0.0, lerpf(0.2, 0.4, pw)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	for d in _ring(3.0):   # shadow = outlined silhouette nudged down-right
		holder.add_child(_icon_silhouette(e, rect, d + Vector2(2, 4), Color(0.05, 0.03, 0.1, 1.0)))
	for d in _ring(3.0):
		holder.add_child(_icon_silhouette(e, rect, d, vivid if fx else rc))
	var ic := ItemIcon.new(e)
	ic.position = rect.position
	ic.size = rect.size
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(ic)
	if fx:
		_fly_sparkle(holder, e, rect, vivid, pw)
	_fly_root().add_child(holder)
	var dest := panels.next_slot_center(slot_offset)
	var mid := from.lerp(dest, 0.4) + Vector2(randf_range(-90, 90), -180)
	holder.position = from - holder.size * 0.5
	holder.scale = Vector2.ONE * 0.3 * FLY_ITEM_SCALE
	var step := func(k: float) -> void:
		var a := from.lerp(mid, k)
		var b := mid.lerp(dest, k)
		holder.position = a.lerp(b, k) - holder.size * 0.5
		holder.rotation = sin(k * PI) * 0.5
	var tw := holder.create_tween()
	tw.tween_property(holder, "scale", Vector2.ONE * 1.25 * FLY_ITEM_SCALE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_method(step, 0.0, 1.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(holder, "scale", Vector2.ONE * FLY_ITEM_SCALE, 0.55)
	tw.tween_callback(func():
		holder.queue_free()
		Sfx.play("pop", -6.0, 1.5)
		on_arrive.call())

# ---------------------------------------------------------------- overlays (delegated to HudPanels)
func has_overlay() -> bool:
	return overlay != null and is_instance_valid(overlay)

func close_overlays() -> void:
	if panels and panels.tip and not panels.tip_pinned:
		panels._close_tip()   # e.g. the merchant's item card
	if has_overlay():
		overlay.queue_free()
		overlay = null
		overlay_closed.emit()

func show_gameover(w: int) -> void:
	panels.gameover(w)

## Run results (expedition cleared / team wiped / endless march over): what is banked, then next step.
func show_settlement(r: Dictionary) -> void:
	panels.settlement(r)

func open_perks() -> bool:
	return panels.perks()

## reuse: keep the current stock (March mode: the same roadside merchant tapped again).
func open_merchant(reuse := false) -> bool:
	return panels.merchant(reuse)

func refresh_perks(gained := false) -> void:
	if perk_hud:
		perk_hud.refresh(gained)

func open_talents() -> void:
	panels.talents()

func show_hero_panel(h: Actor) -> void:
	panels.hero_panel(h)

func refresh_inventory(highlight_id := -1) -> void:
	panels.refresh_inventory(highlight_id)

func show_tip(e: Dictionary) -> void:
	panels._show_tip(e, true)

func close_tip() -> void:
	panels._close_tip()


func merchant_stock() -> Array:
	return panels.merchant_stock

func hero_shown() -> Actor:
	return panels.hero_shown

func on_hero_moved(h: Actor) -> void:
	game.tutorial_event("moved", h)

# ---------------------------------------------------------------- tutorial box
var _tut_box: Control
var tut_step := 0

func set_tutorial(step: int, title: String, text: String) -> void:
	var was := tut_step
	tut_step = step
	if _tut_box and is_instance_valid(_tut_box):
		_tut_box.queue_free()
	_tut_box = null
	phase_label.visible = step == 0 and gimmick_title.text == ""
	if step == 0:
		fight_btn.scale = Vector2.ONE
		if game:
			for h in game.heroes:
				h.set_selected(h == game.selected)
		return
	var W := 488.0
	_tut_box = panel(Color("fff4e0"), Rect2(0, 0, W, 162), 22, 5)
	root.add_child(place(_tut_box, Vector2(1, 0), Vector2(-W - 14, 140), Vector2(W, 162)))
	var head := panel(Color("27c6b0"), Rect2(0, 0, W, 48), 22, 5)
	_tut_box.add_child(head)
	var t := label("튜토리얼 %d/5 · %s" % [step, title], 24, Color.WHITE, 8)
	t.size = Vector2(W, 48)
	_tut_box.add_child(t)
	var d := label(text, 22, Color("4a3a30"), 0)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.position = Vector2(16, 52)
	d.size = Vector2(W - 32, 106)
	_tut_box.add_child(d)
	if step != was:
		pop_in(_tut_box, 0.5, 0.35)
		Sfx.play("chime", -10.0, 1.6)

func nudge_tutorial() -> void:
	if _tut_box and is_instance_valid(_tut_box):
		var tw := _tut_box.create_tween()
		for i in 4:
			tw.tween_property(_tut_box, "rotation", 0.03 * (1 if i % 2 == 0 else -1), 0.04)
		tw.tween_property(_tut_box, "rotation", 0.0, 0.04)
		Sfx.play("thud", -8.0, 0.8)

func _tutorial_pulse(t: float) -> void:
	if tut_step == 0:
		return
	var k := 1.0 + 0.07 * (0.5 + 0.5 * sin(t * 7.0))
	if (tut_step == 2 or tut_step == 4) and fight_btn.visible:
		fight_btn.scale = Vector2(k, k)
	if tut_step == 5:
		panels.pulse_first_item(k)
	if game == null:
		return
	for h in game.alive_heroes():
		var glow := false
		match tut_step:
			1: glow = not game.tut_moved.has(h.cls)
			3: glow = game.books_for(h.cls) > 0
			4: glow = h.cls == "mage" and game.in_battle()
		h.ring_mat.albedo_color = (Defs.COL_GOLD * (1.0 + 0.6 * sin(t * 7.0))) if glow else (Defs.COL_GOLD * 1.15 if h == game.selected else h.color() * 1.15)

# ---------------------------------------------------------------- ultimate aim banner
var _aim_box: Control
var _aim_count: Label

func show_aim(ult_name: String) -> void:
	hide_aim()
	_aim_box = panel(Color(0.1, 0.08, 0.2, 0.7), Rect2(0, 0, 560, 110), 24, 0)
	_aim_box.add_theme_stylebox_override("panel", UiTheme.capsule(24, 0.92, 0.7))
	root.add_child(place(_aim_box, Vector2(0.5, 1), Vector2(-280, -250), Vector2(560, 110)))
	var t := label(ult_name + " 조준 중", 40, Color("ffe04a"), 12)
	t.size = Vector2(560, 56)
	_aim_box.add_child(t)
	_aim_count = label("", 26, Color.WHITE, 8)
	_aim_count.position = Vector2(0, 56)
	_aim_count.size = Vector2(560, 44)
	_aim_box.add_child(_aim_count)
	pop_in(_aim_box, 0.6, 0.25)

func set_aim_count(n: int) -> void:
	if _aim_count:
		_aim_count.text = "대상 %d명 · 손을 떼면 발동!" % n

func hide_aim() -> void:
	if _aim_box and is_instance_valid(_aim_box):
		_aim_box.queue_free()
	_aim_box = null
	_aim_count = null

# ---------------------------------------------------------------- custom drawn icons
## 강화석 counter icon (same gem the item icon draws).
class StoneIcon extends Control:
	func _draw() -> void:
		ItemIcon.draw_stone(self, size * 0.5, minf(size.x, size.y) * 0.4)

class CoinIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.42
		draw_circle(c + Vector2(0, 3), r + 3.0, UiTheme.ink())
		draw_circle(c, r + 3.0, UiTheme.ink())
		draw_circle(c, r, Color("ffd23f"))
		draw_circle(c, r * 0.68, Color("f5b21e"))
		draw_arc(c, r * 0.68, PI * 1.1, PI * 1.6, 10, Color("fff2a8"), 3.0)
		draw_rect(Rect2(c.x - 2.5, c.y - r * 0.4, 5, r * 0.8), Color("fff2a8"))

class GemIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.44
		var outer := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.85, -r * 0.2), c + Vector2(0, r), c + Vector2(-r * 0.85, -r * 0.2)])
		var big := PackedVector2Array()
		for p in outer:
			big.append(c + (p - c) * 1.22)
		draw_colored_polygon(big, UiTheme.ink())
		draw_colored_polygon(outer, Defs.COL_CRYSTAL)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.85, -r * 0.2), c + Vector2(0, -r * 0.05)]), Color("b8d4ff"))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(-r * 0.85, -r * 0.2), c + Vector2(0, -r * 0.05)]), Color("dce9ff"))

# ---------------------------------------------------------------- 뚜까펫식 연출 도형
## 리본 띠: 양 끝이 접혀 뒤로 넘어간 꼬리 + 아래쪽 진한 그림자 + 두꺼운 검정 외곽선.
class Ribbon extends Control:
	var col := UiTheme.ORANGE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var tail := h * 0.42
		var drop := h * 0.22
		var dark := col.darkened(0.45)
		# 꼬리(뒤로 접힌 끝): 본체보다 조금 아래, 제비꼬리 홈
		for sx: float in [-1.0, 1.0]:
			var x0: float = 0.0 if sx < 0.0 else w
			var inner: float = x0 - sx * tail * 0.2
			var outer: float = x0 + sx * tail
			var poly := PackedVector2Array([Vector2(inner, drop), Vector2(outer, drop), Vector2(outer - sx * tail * 0.45, drop + h * 0.5), Vector2(outer, h + drop), Vector2(inner, h + drop)])
			_outlined(poly, dark, 5.0)
			# 접힌 그늘 삼각형
			draw_colored_polygon(PackedVector2Array([Vector2(x0 + sx * 2.0, h), Vector2(inner, h + drop - 3.0), Vector2(x0 + sx * 2.0, h + drop - 3.0)]), dark.darkened(0.4))
		# 본체
		var body := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
		_outlined(body, col, 6.0)
		# 아래쪽 진한 면 + 위쪽 밝은 줄
		draw_rect(Rect2(3, h * 0.62, w - 6, h * 0.38 - 3), col.darkened(0.12))
		draw_rect(Rect2(3, 3, w - 6, h * 0.16), col.lightened(0.28))
		draw_line(Vector2(3, h * 0.62), Vector2(w - 3, h * 0.62), col.darkened(0.25), 2.0)

	func _outlined(poly: PackedVector2Array, fill: Color, ow: float) -> void:
		var closed := poly.duplicate()
		closed.append(poly[0])
		draw_colored_polygon(poly, fill)
		draw_polyline(closed, UiTheme.ink(), ow, true)

## 회전하는 빛줄기(보상/클리어 뒤 배경).
class RayBurst extends Control:
	var col := Color("fff2a8")

	func _draw() -> void:
		var c := size * 0.5
		var r := size.y * 0.95
		var inner := Color(col, 0.55)
		var outer := Color(col, 0.0)
		for i in 12:
			var a := TAU * i / 12.0
			var a2 := a + TAU / 12.0 * 0.42
			draw_polygon(PackedVector2Array([c, c + Vector2(cos(a), sin(a)) * r, c + Vector2(cos(a2), sin(a2)) * r]), PackedColorArray([inner, outer, outer]))
		for k in 4:
			draw_circle(c, 70.0 - k * 16.0, Color(Color.WHITE, 0.08 + k * 0.06))

## 네 갈래 반짝이 별.
class Sparkle extends Control:
	var col := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.5
		var pts := PackedVector2Array()
		for i in 8:
			var a := TAU * i / 8.0 - PI * 0.5
			var rr := r if i % 2 == 0 else r * 0.28
			pts.append(c + Vector2(cos(a), sin(a)) * rr)
		var big := PackedVector2Array()
		for p in pts:
			big.append(c + (p - c) * 1.35)
		draw_colored_polygon(big, Color(UiTheme.ink(), 0.6))
		draw_colored_polygon(pts, col)

## 빨간 경고 띠: 위아래 검정 선, 사선 무늬, 양쪽 "!" 경고 원.
class WarnBand extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(0, 0, w, h), UiTheme.ink())
		draw_rect(Rect2(0, 6, w, h - 12), Color("d8263a"))
		var s := 34.0
		var x := -h
		while x < w + h:
			draw_colored_polygon(PackedVector2Array([Vector2(x, 6), Vector2(x + s, 6), Vector2(x + s - (h - 12), h - 6), Vector2(x - (h - 12), h - 6)]), Color("c01c30"))
			x += s * 2.0
		draw_rect(Rect2(0, 6, w, 6), Color("ff6b7a"))
		for cx in [70.0, w - 70.0]:
			var c: Vector2 = Vector2(cx, h * 0.5)
			draw_circle(c, 31.0, UiTheme.ink())
			draw_circle(c, 26.0, Color("ffe14a"))
			draw_rect(Rect2(c.x - 4.5, c.y - 16, 9, 20), UiTheme.ink())
			draw_circle(c + Vector2(0, 12), 5.0, UiTheme.ink())
