extends Node3D
## Lobby: a slowly turning toy diorama (the trio + a teaser of both March themes)
## and the Endless March card (the classic 6x8 board mode was retired from the lobby).
## Dev: --mode=march jumps straight in; --autoplay / --test=... default to march.

var INK: Color = UiTheme.ink()
const SCENES := {"march": "res://scenes/March.tscn"}

var font: Font
var root: Control
var stage: Node3D
var cam3d: Camera3D
var _trio: Array = []
var _t := 0.0
var _leaving := false
var _settings: Control      # 설정 창(열려 있을 때만)
var _preview_ms := 0        # 효과음 미리듣기 간격 제한

func _ready() -> void:
	var mode := ""
	var dev := false
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
		elif a == "--autoplay" or a.begins_with("--test="):
			dev = true
		elif a.begins_with("--shots="):
			shots = a.substr(8)
	if dev or shots != "" or mode != "":
		Meta.path = "user://trio_save_test.json"
	Meta.load_save()
	if mode == "" and dev:
		mode = "march"
	if SCENES.has(mode):
		get_tree().change_scene_to_file.call_deferred(SCENES[mode])
		return
	Music.play("lobby")
	add_child(Sfx.new())
	_build_stage()
	_build_ui()
	var ch := Chatter.new()   # the trio chats on the diorama too
	ch.cam = cam3d
	ch.font = font
	ch.provider = func() -> Array:
		return _trio.map(func(m: UnitModel) -> Dictionary:
			return {"n": m, "key": m.kind, "ctx": "lobby", "h": 1.05 * m.scale.y / Actor.MODEL_SCALE + 0.15})
	root.add_child(ch)
	root.move_child(ch, 0)
	if shots != "":
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots + "/lobby.png")

func _process(delta: float) -> void:
	_t += delta
	if stage:
		stage.rotation.y = sin(_t * 0.25) * 0.5

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		if _settings:
			_close_settings()
		else:
			Music.quit()
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_F2:
		_toggle_preset()

func _go(mode: String) -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("chime", -6.0, 1.2)
	var fade := ColorRect.new()
	fade.color = Color(0.08, 0.05, 0.2, 0.0)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	var tw := fade.create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.3)
	tw.tween_callback(func(): get_tree().change_scene_to_file(SCENES[mode]))

# ---------------------------------------------------------------- 3D diorama
func _build_stage() -> void:
	var w := World.new()
	add_child(w)
	w._env()
	w.env.background_color = Color("8fd0f0")
	var cam := Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 44.0
	add_child(cam)
	cam.position = Vector3(0, 4.6, 8.6)
	cam.look_at(Vector3(0, -1.9, 0), Vector3.UP)
	cam.current = true
	cam3d = cam
	stage = Node3D.new()
	add_child(stage)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# meadow half (left) and twilight mine half (right) on one toy island
	MarchProps._cyl(stage, 2.9, 2.6, 0.7, Color("c7834c"), Vector3(0, -0.36, 0), Vector3.ZERO, 40)
	MarchProps._cyl(stage, 3.0, 3.0, 0.18, Color("9ad050"), Vector3(0, -0.02, 0), Vector3.ZERO, 40)
	var mine := Node3D.new()
	stage.add_child(mine)
	MarchProps._rb(mine, Vector3(2.4, 0.3, 2.6), Color("4f4874"), Vector3(1.75, 0.0, -0.9), Vector3(0, 0.3, 0), 0.25)
	MarchProps._rb(mine, Vector3(2.5, 0.12, 2.7), Color("4f7f72"), Vector3(1.75, 0.15, -0.9), Vector3(0, 0.3, 0), 0.3)
	MarchProps.pine(stage, Vector3(-2.1, 0.06, -1.2), rng, 1.25)
	MarchProps.blob_bush(stage, Vector3(-2.4, 0.06, 0.4), rng, 0.8, true)
	MarchProps.cube_tree(stage, Vector3(-1.2, 0.06, -2.0), rng, 0.9)
	MarchProps.lily(stage, Vector3(-1.6, 0.06, 1.3), rng, 1.3)
	MarchProps.mushrooms(stage, Vector3(-2.3, 0.06, 1.2), rng, 1.0)
	MarchProps.daisies(stage, Vector3(-0.6, 0.06, 1.9), rng, 1.0)
	MarchProps.big_mushroom(stage, Vector3(2.1, 0.2, -1.5), rng, 1.0)
	MarchProps.lantern(stage, Vector3(1.4, 0.2, 0.1), rng, 1.0, true)
	MarchProps.crystals(stage, Vector3(2.5, 0.2, -0.2), rng, 1.1)
	MarchProps.cart(stage, Vector3(1.0, 0.2, -1.9), rng, 0.9)
	MarchProps.glow_shrooms(stage, Vector3(2.0, 0.2, 0.6), rng, 1.2)
	var xs := {"warrior": Vector3(-0.85, 0.07, 0.75), "ranger": Vector3(0.0, 0.07, 1.15), "mage": Vector3(0.85, 0.07, 0.75)}
	for cls in Defs.HERO_ORDER:
		var m := UnitModel.new().build(cls, Defs.TEAM_HERO)
		stage.add_child(m)
		m.position = xs[cls]
		m.rotation.y = PI
		m.scale = Vector3.ONE * Defs.HEROES[cls]["scale"] * Actor.MODEL_SCALE
		_trio.append(m)

# ---------------------------------------------------------------- UI
func _build_ui() -> void:
	var latin := SystemFont.new()
	latin.font_names = PackedStringArray(["Lilita One", "Arial Rounded MT Bold", "Segoe UI Black", "Arial Black"])
	latin.font_weight = 900
	var ko := SystemFont.new()
	ko.font_names = PackedStringArray(["Jua", "BM JUA_TTF", "Malgun Gothic", "맑은 고딕", "Noto Sans KR", "Apple SD Gothic Neo"])
	ko.font_weight = 800
	# Web builds can't see system fonts — fall back to the bundled Noto Sans KR.
	var ko_web := FontVariation.new()
	ko_web.base_font = load("res://fonts/NotoSansKR-VF.ttf")
	ko_web.variation_opentype = {"wght": 800}
	ko.fallbacks = [ko_web]
	latin.fallbacks = [ko]
	font = latin
	var layer := CanvasLayer.new()
	add_child(layer)
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var title := _label("TRIO CHESS", 104, Color("ffd23f"), 20)
	root.add_child(_place(title, Vector2(0.5, 0), Vector2(-360, 70), Vector2(720, 120)))
	var sub := _label("트리오 체스", 40, Color.WHITE, 12)
	root.add_child(_place(sub, Vector2(0.5, 0), Vector2(-360, 180), Vector2(720, 56)))
	_pop(title, 0.0)
	_pop(sub, 0.1)

	var pill := _panel(Color(0.1, 0.08, 0.2, 0.5), Vector2(200, 54), 27, 0)
	if UiTheme.tt():
		pill.add_theme_stylebox_override("panel", UiTheme.capsule(27))
	root.add_child(_place(pill, Vector2(1, 0), Vector2(-216, 16), Vector2(200, 54)))
	var gem := _label("◆ %d" % Meta.crystals, 32, Defs.COL_CRYSTAL, 8)
	gem.size = Vector2(200, 54)
	pill.add_child(gem)

	_mode_card("march", "끝없는 행군", "구불구불한 길을 따라 끝없이 전진!\n10무리마다 중간 보스가 기다립니다", Color("4cb860"), -330, false)
	var hint := _label("Esc: 종료", 22, Color(1, 1, 1, 0.8), 6)
	root.add_child(_place(hint, Vector2(0.5, 1), Vector2(-200, -70), Vector2(400, 40)))
	_preset_button()
	_settings_button()

## UI 프리셋 전환(뚜까펫 ⇄ 클래식). 누르면 저장하고 로비를 다시 지어 바로 비교할 수 있다.
## 게임 화면(HUD·팝업)은 다음에 모드에 들어갈 때 이 프리셋으로 만들어진다. 단축키 F2.
func _preset_button() -> void:
	var tt := UiTheme.tt()
	var sz := Vector2(290, 58)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = "UI: %s ⇄ (F2)" % UiTheme.PRESET_NAME[UiTheme.preset]
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 26)
	for st in ["normal", "hover", "pressed"]:
		if tt:
			b.add_theme_stylebox_override(st, UiTheme.button_box(UiTheme.NAVY.lightened(0.08 if st == "hover" else 0.0), 18, st == "pressed"))
		else:
			b.add_theme_stylebox_override(st, _box(Color("6f6cf0").lightened(0.1 if st == "hover" else 0.0), 22, 5))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, Color.WHITE)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 8)
	root.add_child(_place(b, Vector2(0, 0), Vector2(16, 16), sz))
	b.pressed.connect(_toggle_preset)

## 설정(톱니) 버튼: 크리스탈 알약 왼쪽. 누르면 음량 설정 창.
func _settings_button() -> void:
	var tt := UiTheme.tt()
	var sz := Vector2(64, 58)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = "설정"
	for st in ["normal", "hover", "pressed"]:
		if tt:
			b.add_theme_stylebox_override(st, UiTheme.button_box(UiTheme.NAVY.lightened(0.08 if st == "hover" else 0.0), 18, st == "pressed"))
		else:
			b.add_theme_stylebox_override(st, _box(Color("6f6cf0").lightened(0.1 if st == "hover" else 0.0), 22, 5))
	root.add_child(_place(b, Vector2(1, 0), Vector2(-216 - 12 - sz.x, 16), sz))
	var g := GearIcon.new()
	g.ink = INK
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.position = Vector2(sz.x * 0.5, sz.y * 0.5 - (4.0 if tt else 0.0))   # 뚜까펫 버튼은 아래 턱만큼 위로
	b.add_child(g)
	b.button_down.connect(func(): g.create_tween().tween_property(g, "rotation", g.rotation + PI / 4.0, 0.25).set_trans(Tween.TRANS_BACK))
	b.pressed.connect(_open_settings)

func _open_settings() -> void:
	if _leaving or _settings:
		return
	Sfx.play("click", -6.0)
	var tt := UiTheme.tt()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.12, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # 뒤의 모드 카드 클릭을 막는다
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_settings())
	var layer := CanvasLayer.new()   # 말풍선(z_index 1)보다 위에 그리도록 별도 층
	layer.layer = 5
	add_child(layer)
	layer.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.6, 0.2)
	_settings = dim

	var sz := Vector2(600, 600)
	var card := Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", UiTheme.night_card() if tt else _box(Color("5a57c8"), 30, 6))
	dim.add_child(_place(card, Vector2(0.5, 0.5), -sz * 0.5, sz))
	var title := _label("설정", 56, UiTheme.TXT_YELLOW if tt else Color("ffd23f"), 12)
	title.position = Vector2(0, 30)
	title.size = Vector2(sz.x, 70)
	card.add_child(title)

	var cols := {"master": UiTheme.YELLOW, "music": UiTheme.GREEN, "sfx": UiTheme.ORANGE}
	var y := 120.0
	for ch in Music.CHANNELS:
		var nm := _label(Music.CHANNEL_NAME[ch], 32, Color.WHITE, 8)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.position = Vector2(56, y)
		nm.size = Vector2(300, 48)
		card.add_child(nm)
		var pct := _label("", 30, UiTheme.TXT_VALUE if tt else Color("fff2b0"), 8)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pct.position = Vector2(sz.x - 56 - 160, y)
		pct.size = Vector2(160, 48)
		card.add_child(pct)
		var s := _slider(cols[ch])
		s.position = Vector2(56, y + 54)
		s.size = Vector2(sz.x - 112, 48)
		card.add_child(s)
		s.value = Music.get_volume(ch)
		pct.text = _pct(s.value)
		s.value_changed.connect(func(v: float):
			Music.set_volume(ch, v)
			pct.text = _pct(v)
			if ch != "music" and Time.get_ticks_msec() - _preview_ms > 110:   # 배경음악은 지금 들리니 미리듣기 불필요
				_preview_ms = Time.get_ticks_msec()
				Sfx.play("pop", -8.0))
		s.drag_ended.connect(func(_changed: bool): Music.save_volumes())
		y += 130.0

	var close := Button.new()
	close.focus_mode = Control.FOCUS_NONE
	close.text = "닫기"
	close.add_theme_font_override("font", font)
	close.add_theme_font_size_override("font_size", 32)
	var txt := Color("3a2400") if tt else Color.WHITE
	for st in ["normal", "hover", "pressed"]:
		if tt:
			close.add_theme_stylebox_override(st, UiTheme.button_box(UiTheme.YELLOW.lightened(0.08 if st == "hover" else 0.0), 20, st == "pressed"))
		else:
			close.add_theme_stylebox_override(st, _box(Color("ff9f1c").lightened(0.1 if st == "hover" else 0.0), 24, 5))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		close.add_theme_color_override(k, txt)
	if not tt:
		close.add_theme_color_override("font_outline_color", INK)
		close.add_theme_constant_override("outline_size", 8)
	close.position = Vector2(sz.x * 0.5 - 120, sz.y - 112)
	close.size = Vector2(240, 76)
	card.add_child(close)
	close.pressed.connect(_close_settings)
	_pop(card, 0.0)

func _close_settings() -> void:
	if _settings == null:
		return
	Music.save_volumes()
	Sfx.play("click", -6.0)
	var dim := _settings
	_settings = null
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := dim.create_tween()
	tw.tween_property(dim, "modulate:a", 0.0, 0.15)
	tw.tween_callback(dim.get_parent().queue_free)

func _pct(v: float) -> String:
	return "끔" if v <= 0.001 else "%d%%" % roundi(v * 100.0)

## 음량 슬라이더: 어두운 홈 + 채널 색으로 차오르는 막대 + 흰 동그라미 손잡이.
func _slider(col: Color) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.focus_mode = Control.FOCUS_NONE
	var track := UiTheme.flat(UiTheme.BAR_TRACK, 12, 3, INK)
	var fill := UiTheme.flat(col, 12, 3, INK)
	for sb in [track, fill]:
		sb.content_margin_top = 9
		sb.content_margin_bottom = 9
	s.add_theme_stylebox_override("slider", track)
	s.add_theme_stylebox_override("grabber_area", fill)
	s.add_theme_stylebox_override("grabber_area_highlight", fill)
	var knob := _knob_tex(Color.WHITE)
	for k in ["grabber", "grabber_highlight", "grabber_disabled"]:
		s.add_theme_icon_override(k, knob)
	return s

func _knob_tex(c: Color) -> ImageTexture:
	var d := 44
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	var ctr := Vector2(d, d) * 0.5
	for yy in d:
		for xx in d:
			var r := Vector2(xx + 0.5, yy + 0.5).distance_to(ctr)
			var outer := clampf(d * 0.5 - r, 0.0, 1.0)          # 외곽선 원
			var inner := clampf(d * 0.5 - 5.0 - r, 0.0, 1.0)    # 안쪽 흰 원
			var px := INK.lerp(c, inner)
			px.a = outer
			img.set_pixel(xx, yy, px)
	return ImageTexture.create_from_image(img)

## 톱니바퀴 아이콘(글꼴에 ⚙가 없는 웹 빌드도 있어 직접 그린다). (0,0)이 중심.
class GearIcon extends Control:
	var ink := Color.BLACK
	func _draw() -> void:
		draw_colored_polygon(_gear(19.0, 14.5), ink)
		draw_colored_polygon(_gear(16.0, 11.5), Color.WHITE)
		draw_circle(Vector2.ZERO, 7.5, ink)
	func _gear(r_out: float, r_in: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for j in 64:   # 톱니 8개: 8칸 주기 중 앞 4칸이 이빨
			var r := r_out if j % 8 < 4 else r_in
			pts.append(Vector2.from_angle(TAU * (j + 0.5) / 64.0) * r)
		return pts

func _toggle_preset() -> void:
	if _leaving:
		return
	_leaving = true
	Sfx.play("click", -6.0)
	UiTheme.set_preset(UiTheme.next_preset())
	get_tree().reload_current_scene.call_deferred()

func _mode_card(mode: String, title: String, desc: String, col: Color, y: float, is_new: bool) -> void:
	var sz := Vector2(640, 206)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var tt := UiTheme.tt()
	for st in ["normal", "hover", "pressed"]:
		var c := col if st == "normal" else (col.lightened(0.1) if st == "hover" else col.darkened(0.1))
		b.add_theme_stylebox_override(st, _ttukka_card(c) if tt else _box(c, 30, 6))
	root.add_child(_place(b, Vector2(0.5, 1), Vector2(-sz.x * 0.5, y), sz))
	var t := _label(title, 52, Color.WHITE, 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.position = Vector2(36, 18)
	t.size = Vector2(560, 70)
	b.add_child(t)
	var d := _label(desc, 25, UiTheme.TXT_DIM if tt else Color("fff8e8"), 0 if tt else 8)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	d.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	d.position = Vector2(38, 92)
	d.size = Vector2(440, 80)
	if tt:
		d.size = Vector2(410, 80)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_child(d)
	var best := int(Meta.best.get(mode, 0))
	var unit := "무리"
	var r := _label("최고 기록\n%s" % ("%s %d" % [unit, best] if best > 0 else "-"), 24, UiTheme.TXT_VALUE if tt else Color("fff2b0"), 8)
	r.position = Vector2(470, 100)
	r.size = Vector2(150, 80)
	b.add_child(r)
	if tt:   # 뚜까펫: 오른쪽 위 노란 "시작" 알약
		var go := Panel.new()
		go.mouse_filter = Control.MOUSE_FILTER_IGNORE
		go.add_theme_stylebox_override("panel", UiTheme.button_box(UiTheme.YELLOW, 18))
		go.position = Vector2(462, 26)
		go.size = Vector2(150, 64)
		b.add_child(go)
		var gl := _label("시작 ▶", 28, Color("3a2400"), 0)
		gl.size = Vector2(150, 56)
		go.add_child(gl)
	else:
		var arrow := _label("▶", 46, Color.WHITE, 10)
		arrow.position = Vector2(560, 18)
		arrow.size = Vector2(60, 70)
		b.add_child(arrow)
	if is_new:
		var badge := _panel(UiTheme.RED if tt else Color("ff5f6a"), Vector2(96, 42), 21, 4)
		badge.position = Vector2(sz.x - 120, -18)
		badge.rotation = 0.12
		b.add_child(badge)
		var nl := _label("NEW", 26, Color.WHITE, 8)
		nl.size = Vector2(96, 42)
		badge.add_child(nl)
	b.button_down.connect(func():
		b.create_tween().tween_property(b, "scale", Vector2(0.94, 0.94), 0.06)
		Sfx.play("click", -6.0))
	b.button_up.connect(func():
		b.create_tween().tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	b.pressed.connect(func(): _go(mode))
	_pop(b, 0.2)

## 뚜까펫 스테이지 카드: 검정 턱 → 모드 색 테두리 → 청록 선 → 남보라 본문.
func _ttukka_card(c: Color) -> StyleBox:
	var lb := UiTheme.Layered.new()
	lb.add(UiTheme.flat(UiTheme.INK, 32, 0), Vector4(3, 3, 3, 10))
	lb.add(UiTheme.flat(c, 30, 5), Vector4.ZERO)
	var hl := UiTheme.flat(Color(0, 0, 0, 0), 26, 0)
	hl.border_width_top = 4
	hl.border_color = c.lightened(0.35)
	lb.add(hl, Vector4(-5, -5, -5, -5))
	lb.add(UiTheme.flat(UiTheme.FRAME_LINE, 22, 3), Vector4(-11, -11, -11, -11))
	lb.add(UiTheme.flat(UiTheme.BODY, 18, 0), Vector4(-16, -16, -16, -16))
	return lb

# ---------------------------------------------------------------- style helpers (Hud look)
func _label(text: String, size: int, color := Color.WHITE, outline := 10) -> Label:
	var l := Label.new()
	l.text = text
	var s := LabelSettings.new()
	s.font = font
	s.font_size = size
	s.font_color = color
	s.outline_size = outline
	s.outline_color = INK
	l.label_settings = s
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _box(color: Color, radius := 12, border := 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(border)
	sb.border_color = INK
	sb.shadow_color = Color(0.1, 0.05, 0.2, 0.35)
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 8)
	sb.anti_aliasing = true
	return sb

func _panel(color: Color, sz: Vector2, radius := 12, border := 4) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", _box(color, radius, border))
	p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _place(c: Control, anchor: Vector2, pos: Vector2, sz: Vector2) -> Control:
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

func _pop(c: Control, delay: float) -> void:
	c.scale = Vector2.ZERO
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
