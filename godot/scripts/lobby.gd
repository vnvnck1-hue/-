extends Node3D
## Lobby: a slowly turning toy diorama (the trio + a teaser of both March themes), the banked currencies,
## the expedition card (pick a chapter: one region of the march, beat its mid-boss to open the next),
## the endless march card, the [장비] screen (GearScreen: permanent gear, storage merges, slot levels) and the
## [유물] screen (RelicScreen: the relic collection, the worn relic slots, ★ merges), and the daily pair:
## [미션] (MissionScreen: daily / weekly missions and the activity boxes), [토벌] (RaidScreen: the daily boss raid against the region bosses), [탤런트] (TalentScreen: gold talents, the gold sink), [모닥불] (CampScreen: idle rewards piling up at the campfire on the diorama) and [출석] (AttendScreen: the
## repeating 7-day attendance, opened by itself on the first lobby visit of a day with an unclaimed day).
## (The classic 6x8 board mode was retired from the lobby.)
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
var _debug_dirty := false   # 디버그 버튼이 저장을 바꿨다: 설정을 닫을 때 로비를 다시 그린다
var _gear: GearScreen       # 장비 창(열려 있을 때만)
var _relic: RelicScreen     # 유물 창(열려 있을 때만)
var _daily: GearScreen      # 모닥불·출석·탤런트 창(열려 있을 때만)
static var _attend_shown := false   # 출석 창 자동 열기는 실행당 한 번(닫고 돌아올 때마다 다시 뜨지 않게)
## The lobby reloads itself after one of its own screens closes (currencies / badges / stage refresh) — that
## reload must not replay the buttons' entrance pop. Set right before such a reload, consumed by the next _ready.
static var _quiet_reload := false
var _quiet := false         # building the UI without the entrance pop (this lobby came from _quiet_reload)
var _chapter_l: Label
var _chapter_s: Label
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
	_quiet = _quiet_reload
	_quiet_reload = false
	_build_ui()
	_quiet = false
	var ch := Chatter.new()   # the trio chats on the diorama too
	ch.cam = cam3d
	ch.font = font
	ch.provider = func() -> Array:
		return _trio.map(func(m: UnitModel) -> Dictionary:
			return {"n": m, "key": m.kind, "ctx": "lobby", "h": 1.05 * m.scale.y / Actor.MODEL_SCALE + 0.15})
	root.add_child(ch)
	root.move_child(ch, 0)
	if shots == "" and not _attend_shown and Meta.can_attend():
		_attend_shown = true
		get_tree().create_timer(0.7).timeout.connect(_open_attend)
	if shots != "":
		await get_tree().create_timer(1.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shots + "/lobby.png")
		if Array(OS.get_cmdline_user_args()).has("--open=gear"):   # dev: the gear screen too
			for i in 6:
				Meta.storage.append(Inventory.make("equip", ["sword1", "axe1", "shield1", "ring1", "helmet2", "bow2"][i]))
			Meta.stones += 20
			Meta.gold += 500
			Meta.storage.append(Inventory.make("equip", "eclipseBlade"))   # effects + special stats in the detail bar
			_open_gear()
			await get_tree().create_timer(0.6).timeout
			_gear.picked = Meta.storage[-1]
			_gear._rebuild()
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots + "/gear.png")
			var ring: Dictionary = Meta.storage.filter(func(x): return x["key"] == "ring1")[0]   # worn piece -> detail bar with [해제]
			Meta.wear(_gear.cls, ring)
			_gear.picked = ring
			_gear.picked_slot = "accessory"
			_gear._rebuild()
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots + "/gear_worn.png")
			_gear._hold_start("accessory")   # held [강화]: repeats, level-up burst each time
			for k in [0.1, 0.9]:
				await get_tree().create_timer(k).timeout
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(shots + "/gear_hold_%d.png" % int(k * 10))
			print("[Gear] hold levels=", _gear._hold_n, " slot lv=", Meta.slot_level(_gear.cls, "accessory"))
			_gear._hold_stop()
			for k in ["bow1", "staff1", "sword1"]:   # completes a 일반 무기 group (and a chain) for the cutscene
				Meta.storage.append(Inventory.make("equip", k))
			await _dev_merge_shots(shots, "gear")
		if Array(OS.get_cmdline_user_args()).has("--open=relic"):   # dev: the relic screen + its merge cutscene
			if _gear:   # --open=gear ran first: drop its screen without the scene reload its close() does
				_gear.get_parent().queue_free()
				_gear = null
			for k in ["vampireChalice", "vampireChalice", "vampireChalice", "luckyCompass", "luckyCompass", "luckyCompass",
					"guardianIdol", "echoCrystal", "crescendoGear", "crescendoGear"]:
				Meta.add_relic(k, 1, false)
			Meta.add_relic("echoCrystal", 3, false)
			Meta.add_relic("echoCrystal", 3, false)
			Meta.add_relic("echoCrystal", 3, false)
			Meta.wear_relic(Meta.relic_bag[7], -1, false)
			_open_relic()
			await get_tree().create_timer(0.6).timeout
			_relic.picked = Meta.relic_bag[0]
			_relic._rebuild()
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots + "/relic.png")
			await _dev_merge_shots(shots, "relic")
		if Array(OS.get_cmdline_user_args()).has("--open=talent"):   # dev: the gold talent screen and one press
			Meta.gold += 3000
			_open_talent()
			await _dev_shot(shots, "talent")
			_daily._press()
			await get_tree().create_timer(0.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(shots + "/talent_spin.png")
			await _dev_shot(shots, "talent_land")
			_daily.get_parent().queue_free()
			_daily = null
		if Array(OS.get_cmdline_user_args()).has("--open=mission"):   # dev: the mission screen (daily, then weekly)
			for i in 3:
				Meta.track(["run_start", "camp", "talent"][i])
			Meta.track("group_clear", 8)
			Meta.claim_mission("run")
			_open_mission()
			await _dev_shot(shots, "mission_daily")
			_daily.weekly = true
			_daily._rebuild()
			await _dev_shot(shots, "mission_weekly")
			_daily.get_parent().queue_free()
			_daily = null
		if Array(OS.get_cmdline_user_args()).has("--open=settings"):   # dev: the settings panel with the debug menu
			Meta.raid_used = Meta.RAID_TRIES
			Meta.raid_day = Time.get_date_string_from_system()
			_open_settings()
			await _dev_shot(shots, "settings")
			var dbg: Button = _settings.find_children("*", "Button", true, false).filter(func(x): return x.text.begins_with("토벌"))[0]
			dbg.pressed.emit()
			print("[Debug] raid tickets after press: ", Meta.raid_left())
			await _dev_shot(shots, "settings_after")
		if Array(OS.get_cmdline_user_args()).has("--open=raid"):   # dev: the boss raid screen
			_open_raid()
			await _dev_shot(shots, "raid")
			_daily.pick = "murlocs"
			_daily._rebuild()
			await _dev_shot(shots, "raid_murlocs")
			_daily.get_parent().queue_free()
			_daily = null
		if Array(OS.get_cmdline_user_args()).has("--open=daily"):   # dev: the campfire and attendance screens
			Meta.camp_since -= 5 * 3600 + 23 * 60
			_open_camp()
			await _dev_shot(shots, "camp")
			_daily._claim()
			await _dev_shot(shots, "camp_claimed")
			_daily.get_parent().queue_free()
			_daily = null
			Meta.att_day = 6
			Meta.att_date = "2000-01-01"
			_open_attend()
			await _dev_shot(shots, "attend")
			_daily._claim()
			await _dev_shot(shots, "attend_claimed")
		Music.quit()

func _dev_shot(shots: String, tag: String) -> void:
	await get_tree().create_timer(0.7).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shots, tag])

## Dev: press the open screen's [모두 합성] and capture the cutscene at its beats.
func _dev_merge_shots(shots: String, tag: String) -> void:
	var scr: GearScreen = _gear if tag == "gear" else _relic
	var steps := Meta.merge_all() if tag == "gear" else Meta.merge_all_relics()
	if steps.is_empty():
		return
	scr._play_merge(steps)
	var beats := [0.25, 0.65, 0.9, 1.05, 1.8]
	var t := 0.0
	for i in beats.size():
		await get_tree().create_timer(beats[i] - t).timeout
		t = beats[i]
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/merge_%s_%d.png" % [shots, tag, i])
	if scr._fx:
		scr._fx._summary()
		await get_tree().create_timer(1.2).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/merge_%s_summary.png" % [shots, tag])
		scr._fx._close()
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/merge_%s_after.png" % [shots, tag])

func _process(delta: float) -> void:
	_t += delta
	if stage:
		stage.rotation.y = sin(_t * 0.25) * 0.5

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		if _gear or _relic or _daily:
			return
		if _settings:
			_close_settings()
		else:
			Music.quit()
	elif ev is InputEventKey and ev.pressed and ev.keycode == KEY_F2:
		_toggle_preset()

func _go(mode: String, expedition := false, raid := "") -> void:
	if _leaving or _gear or _relic or _daily:
		return
	Meta.expedition = expedition
	Meta.raid = raid
	if raid == "":
		Meta.track("run_start")   # daily mission: 원정 또는 행군 출발
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
	MarchProps.campfire(stage, Vector3(0, 0.07, 2.0), Color("8a8478"))   # [모닥불]: the trio rests here between runs
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
	ko_web.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 800}
	ko.fallbacks = [ko_web]
	latin.fallbacks = [ko]
	font = latin
	if OS.has_feature("web"):   # SystemFont resolves to the theme font there, so use the bundled ones directly
		var lilita := FontVariation.new()
		lilita.base_font = load("res://fonts/LilitaOne-Regular.ttf")
		lilita.fallbacks = [ko_web]
		font = lilita
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

	# banked currencies: gold, 강화석, time crystals
	var cur := [[Hud.CoinIcon.new(), Meta.gold, Defs.COL_GOLD], [Hud.StoneIcon.new(), Meta.stones, ItemIcon.STONE_COL], [Hud.GemIcon.new(), Meta.crystals, Defs.COL_CRYSTAL]]
	for i in cur.size():
		var pill := _panel(Color(0.1, 0.08, 0.2, 0.5), Vector2(206, 58), 29, 0)
		pill.add_theme_stylebox_override("panel", UiTheme.capsule(29))
		root.add_child(_place(pill, Vector2(0.5, 0), Vector2(-327 + i * 224, 246), Vector2(206, 58)))
		var ic: Control = cur[i][0]
		ic.position = Vector2(8, 6)
		ic.size = Vector2(46, 46)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pill.add_child(ic)
		var v := _label(str(cur[i][1]), 32, cur[i][2], 8)
		v.position = Vector2(56, 0)
		v.size = Vector2(142, 58)
		pill.add_child(v)

	_gear_button()
	_relic_button()
	_camp_button()
	_attend_button()
	_talent_button()
	_raid_button()
	_mission_button()
	_expedition_card()
	_mode_card("march", "끝없는 행군", "1무리부터 끝없이 전진! 최고 기록에 도전", Color("4cb860"), -246, false)
	var hint := _label("Esc: 종료", 22, Color(1, 1, 1, 0.8), 6)
	root.add_child(_place(hint, Vector2(0.5, 1), Vector2(-200, -40), Vector2(400, 36)))
	_preset_button()
	_settings_button()

## UI 프리셋 전환(뚜까펫 ⇄ 클래식). 누르면 저장하고 로비를 다시 지어 바로 비교할 수 있다.
## 게임 화면(HUD·팝업)은 다음에 모드에 들어갈 때 이 프리셋으로 만들어진다. 단축키 F2.
func _preset_button() -> void:
	var sz := Vector2(290, 58)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = "UI: %s ⇄ (F2)" % UiTheme.PRESET_NAME[UiTheme.preset]
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 26)
	_skin_button(b, UiTheme.NAVY, Color("6f6cf0"), 18, 22)
	_text_color(b, Color.WHITE)
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
	_skin_button(b, UiTheme.NAVY, Color("6f6cf0"), 18, 22)
	root.add_child(_place(b, Vector2(1, 0), Vector2(-216 - 12 - sz.x, 16), sz))
	var g := GearIcon.new()
	g.ink = INK
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.position = Vector2(sz.x * 0.5, sz.y * 0.5 - (4.0 if tt else 0.0))   # 뚜까펫 버튼은 아래 턱만큼 위로
	b.add_child(g)
	b.button_down.connect(func(): _press_tween(g).tween_property(g, "rotation", g.rotation + PI / 4.0, 0.25).set_trans(Tween.TRANS_BACK))
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

	var sz := Vector2(600, 790)   # volume sliders, then the debug section
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

	_debug_section(card, sz, y)

	var close := Button.new()
	close.focus_mode = Control.FOCUS_NONE
	close.text = "닫기"
	close.add_theme_font_override("font", font)
	close.add_theme_font_size_override("font_size", 32)
	_skin_yellow(close)
	close.position = Vector2(sz.x * 0.5 - 120, sz.y - 112)
	close.size = Vector2(240, 76)
	card.add_child(close)
	close.pressed.connect(_close_settings)
	_pop(card, 0.0)

## 디버그: test shortcuts for playtesting (they change the real save).
func _debug_section(card: Control, sz: Vector2, y: float) -> void:
	var tt := UiTheme.tt()
	var line := ColorRect.new()
	line.color = Color(1, 1, 1, 0.18)
	line.position = Vector2(40, y + 4)
	line.size = Vector2(sz.x - 80, 3)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(line)
	var t := _label("디버그", 30, UiTheme.TXT_YELLOW if tt else Color("ffd23f"), 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.position = Vector2(56, y + 16)
	t.size = Vector2(300, 44)
	card.add_child(t)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 26)
	_skin_button(b, UiTheme.RED, Color("ff5f6a"), 18, 22)
	_text_color(b, Color.WHITE)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 7)
	b.position = Vector2(56, y + 66)
	b.size = Vector2(sz.x - 112, 64)
	card.add_child(b)
	var refresh := func(): b.text = "토벌 티켓 충전  (남은 도전 %d/%d)" % [Meta.raid_left(), Meta.RAID_TRIES]
	refresh.call()
	b.pressed.connect(func():
		Meta.raid_day = Time.get_date_string_from_system()
		Meta.raid_used = 0
		Meta.save()
		_debug_dirty = true
		Sfx.play("chime", -6.0, 1.3)
		refresh.call()
		_press_tween(b).tween_property(b, "scale", Vector2(1.06, 1.06), 0.06)
		_press_tween(b).tween_property(b, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	b.pivot_offset = b.size * 0.5

func _close_settings() -> void:
	if _settings == null:
		return
	if _debug_dirty:   # badges / counts on the lobby read the save again
		_debug_dirty = false
		_leaving = true
		get_tree().reload_current_scene.call_deferred()
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

static var _knobs := {}   # "fill/ink" -> texture: the settings panel reopens without repainting pixels

func _knob_tex(c: Color) -> ImageTexture:
	var key := "%s/%s" % [c.to_html(), INK.to_html()]
	if _knobs.has(key):
		return _knobs[key]
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
	_knobs[key] = ImageTexture.create_from_image(img)
	return _knobs[key]

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
	_reload_quiet()

func _mode_card(mode: String, title: String, desc: String, col: Color, y: float, is_new: bool) -> void:
	var sz := Vector2(640, 190)
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
		_press_tween(b).tween_property(b, "scale", Vector2(0.94, 0.94), 0.06)
		Sfx.play("click", -6.0))
	b.button_up.connect(func():
		_press_tween(b).tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	b.pressed.connect(func(): _go(mode, false))
	_pop(b, 0.2)

## Expedition: one chapter per region of the march (◀ ▶ picks an opened chapter). Beat its mid-boss to open
## the next; the run then settles (gear is permanent, gold / 강화석 banked).
func _expedition_card() -> void:
	var tt := UiTheme.tt()
	var sz := Vector2(640, 250)
	var col := Color("e0843a")
	var card := Panel.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_theme_stylebox_override("panel", _ttukka_card(col) if tt else _box(col, 30, 6))
	root.add_child(_place(card, Vector2(0.5, 1), Vector2(-sz.x * 0.5, -520), sz))
	var t := _label("원정", 52, Color.WHITE, 14)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.position = Vector2(36, 16)
	t.size = Vector2(300, 64)
	card.add_child(t)
	var d := _label("중간 보스를 쓰러뜨리면 다음 챕터가 열려요", 22, UiTheme.TXT_DIM if tt else Color("fff8e8"), 0 if tt else 8)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	d.position = Vector2(38, 78)
	d.size = Vector2(560, 34)
	card.add_child(d)
	var prev := _small_button("◀", Rect2(32, 124, 74, 74))
	var next := _small_button("▶", Rect2(330, 124, 74, 74))
	card.add_child(prev)
	card.add_child(next)
	_chapter_l = _label("", 30, Color.WHITE, 10)
	_chapter_l.position = Vector2(106, 118)
	_chapter_l.size = Vector2(224, 52)
	card.add_child(_chapter_l)
	_chapter_s = _label("", 20, UiTheme.TXT_VALUE if tt else Color("fff2b0"), 7)
	_chapter_s.position = Vector2(106, 164)
	_chapter_s.size = Vector2(224, 34)
	card.add_child(_chapter_s)
	prev.pressed.connect(func(): _pick_chapter(-1))
	next.pressed.connect(func(): _pick_chapter(1))
	var go := Button.new()
	go.focus_mode = Control.FOCUS_NONE
	go.text = "출발 ▶"
	go.add_theme_font_override("font", font)
	go.add_theme_font_size_override("font_size", 36)
	_skin_yellow(go)
	go.position = Vector2(424, 118)
	go.size = Vector2(190, 86)
	card.add_child(go)
	go.pressed.connect(func():
		Sfx.play("click", -6.0)
		_go("march", true))
	_pick_chapter(0)
	_pop(card, 0.15)

func _small_button(text: String, r: Rect2) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.position = r.position
	b.size = r.size
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 30)
	_skin_button(b, UiTheme.NAVY, Color("6f6cf0"), 18, 20)
	_text_color(b, Color.WHITE)
	return b

func _pick_chapter(step: int) -> void:
	var c := clampi(Meta.chapter + step, 0, Meta.cleared)
	if step != 0 and c != Meta.chapter:
		Sfx.play("click", -6.0, 1.2)
	Meta.chapter = c
	if step != 0:
		Meta.save()
	_chapter_l.text = Meta.chapter_name(c)
	_chapter_s.text = "클리어 ✓" if c < Meta.cleared else "도전 중 · 무리 10"

## [장비]: permanent gear, storage merges and slot upgrades (GearScreen).
func _gear_button() -> void:
	var sz := Vector2(290, 86)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = "장비"
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 40)
	_skin_button(b, UiTheme.GREEN, Color("27c6b0"), 22, 26)
	_text_color(b, Color.WHITE)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 9)
	root.add_child(_place(b, Vector2(0.5, 1), Vector2(-sz.x - 10, -630), sz))
	if Meta.merge_ready() > 0:
		var badge := _panel(UiTheme.RED, Vector2(150, 40), 20, 3)
		badge.position = Vector2(sz.x - 110, -16)
		badge.rotation = 0.08
		b.add_child(badge)
		var bl := _label("합성 가능!", 22, Color.WHITE, 6)
		bl.size = Vector2(150, 40)
		badge.add_child(bl)
	b.pressed.connect(_open_gear)
	_pop(b, 0.1)

## [유물]: the relic collection, worn slots and ★ merges (RelicScreen).
func _relic_button() -> void:
	var sz := Vector2(290, 86)
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = "유물"
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", 40)
	_skin_button(b, UiTheme.ORANGE, Color("ff9f1c"), 22, 26)
	_text_color(b, Color.WHITE)
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 9)
	root.add_child(_place(b, Vector2(0.5, 1), Vector2(10, -630), sz))
	var badge_t := ""
	if Meta.relic_merge_ready() > 0:
		badge_t = "합성 가능!"
	elif Meta.worn_relics().size() < Defs.RELIC_SLOTS and not Meta.relic_bag.is_empty():
		badge_t = "장착 가능!"
	if badge_t != "":
		var badge := _panel(UiTheme.RED, Vector2(150, 40), 20, 3)
		badge.position = Vector2(sz.x - 110, -16)
		badge.rotation = 0.08
		b.add_child(badge)
		var bl := _label(badge_t, 22, Color.WHITE, 6)
		bl.size = Vector2(150, 40)
		badge.add_child(bl)
	b.pressed.connect(_open_relic)
	_pop(b, 0.14)

func _open_relic() -> void:
	if _leaving or _gear or _relic or _daily or _settings:
		return
	Sfx.play("click", -6.0)
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_relic = RelicScreen.new()
	layer.add_child(_relic)
	_relic.open(font)
	_relic.closed.connect(func():
		_relic = null
		layer.queue_free()
		_reload_quiet())

func _open_gear() -> void:
	if _leaving or _gear or _relic or _daily or _settings:
		return
	Sfx.play("click", -6.0)
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_gear = GearScreen.new()
	layer.add_child(_gear)
	_gear.open(font)
	_gear.closed.connect(func():
		_gear = null
		layer.queue_free()
		_reload_quiet())   # currencies / badges refresh

## [모닥불] / [출석]: square buttons on the left / right edge under the currency pills, each with a red badge
## when something is waiting (a pile worth an hour or more / a full fire; an unclaimed attendance day).
func _camp_button() -> void:
	var m := Meta.camp_minutes()
	_side_button("모닥불", UiTheme.ORANGE, Color("ff9f1c"), 0.0, "가득!" if Meta.camp_full() else ("받기!" if m >= 60 else ""), _open_camp, CampScreen.FireIcon.new(), SIDE_Y[0])

func _attend_button() -> void:
	var cal := CalendarIcon.new()
	cal.day = Meta.att_day + 1 if Meta.can_attend() else (Meta.att_day if Meta.att_day > 0 else 7)
	_side_button("출석", UiTheme.GREEN, Color("27c6b0"), 1.0, "받기!" if Meta.can_attend() else "", _open_attend, cal, SIDE_Y[0])

## [탤런트]: under [모닥불]; badged while the next level is affordable.
func _talent_button() -> void:
	_side_button("탤런트", UiTheme.NAVY, Color("6f6cf0"), 0.0, "강화!" if Meta.can_gold_talent() == "" else "", _open_talent, Hud.CoinIcon.new(), SIDE_Y[1])

## Side buttons: three per side between the currency pills and the 장비 / 유물 row.
const SIDE_SZ := Vector2(116, 98)
const SIDE_Y := [318.0, 424.0, 530.0]

func _side_button(text: String, tt_col: Color, classic_col: Color, side: float, badge_t: String, on_press: Callable, icon: Control, y: float) -> void:
	var sz := SIDE_SZ
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	_skin_button(b, tt_col, classic_col, 22, 26)
	var x := 16.0 if side == 0.0 else -16.0 - sz.x
	root.add_child(_place(b, Vector2(side, 0), Vector2(x, y), sz))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2((sz.x - 60) * 0.5, 3)
	icon.size = Vector2(60, 60)
	b.add_child(icon)
	var l := _label(text, 24, Color.WHITE, 7)
	l.position = Vector2(0, 62)
	l.size = Vector2(sz.x, 34)
	b.add_child(l)
	if badge_t != "":
		var badge := _panel(UiTheme.RED, Vector2(96, 38), 19, 3)
		badge.position = Vector2(sz.x - 70 if side == 0.0 else -26, -14)   # the right button's badge leans inward (screen edge)
		badge.rotation = 0.1 if side == 0.0 else -0.1
		b.add_child(badge)
		var bl := _label(badge_t, 20, Color.WHITE, 6)
		bl.size = Vector2(96, 38)
		badge.add_child(bl)
		var tw := badge.create_tween().set_loops()
		badge.pivot_offset = Vector2(48, 19)
		tw.tween_property(badge, "scale", Vector2(1.1, 1.1), 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(badge, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	b.button_down.connect(func():
		_press_tween(b).tween_property(b, "scale", Vector2(0.92, 0.92), 0.06))
	b.button_up.connect(func():
		_press_tween(b).tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	b.pressed.connect(on_press)
	_pop(b, 0.12)

## Little calendar page: red binding on top, the cycle's day number in the middle.
class CalendarIcon extends Control:
	var day := 1
	func _draw() -> void:
		var r := Rect2(size * 0.12, size * 0.76)
		draw_rect(r.grow(3), Color("2a1b3d"), true)
		draw_rect(r, Color.WHITE, true)
		draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.28)), Color("ff5f6a"), true)
		var f := ThemeDB.fallback_font
		var t := str(day)
		var fs := int(r.size.y * 0.52)
		var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(r.get_center().x - w * 0.5, r.end.y - r.size.y * 0.16), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("2a1b3d"))

func _open_camp() -> void:
	_open_daily(CampScreen.new())

## [토벌]: right side under [출석]; badged while today's tries remain.
func _raid_button() -> void:
	var ic := ItemIcon.new(Inventory.make("equip", "axe4"))
	_side_button("토벌", UiTheme.RED, Color("ff5f6a"), 1.0, "도전!" if Meta.raid_left() > 0 else "", _open_raid, ic, SIDE_Y[1])

func _open_raid() -> void:
	if _leaving or _gear or _relic or _daily or _settings:
		return
	var scr := RaidScreen.new()
	scr.start_raid.connect(func(key: String):
		if not Meta.use_raid_try():
			return
		var layer := scr.get_parent()
		_daily = null
		layer.queue_free()
		_go("march", false, key))
	_open_daily(scr)

## [미션]: right side, third row; badged while something can be collected.
func _mission_button() -> void:
	_side_button("미션", Color("4aa8ff"), Color("4aa8ff"), 1.0, "받기!" if Meta.missions_ready() > 0 else "", _open_mission, ClipboardIcon.new(), SIDE_Y[2])

func _open_mission() -> void:
	_open_daily(MissionScreen.new())

## Clipboard with ticked lines (the mission list).
class ClipboardIcon extends Control:
	func _draw() -> void:
		var ink := UiTheme.ink()
		var r := Rect2(size.x * 0.18, size.y * 0.14, size.x * 0.64, size.y * 0.8)
		draw_rect(r.grow(3), ink)
		draw_rect(r, Color("f4ead2"))
		draw_rect(Rect2(r.position.x + r.size.x * 0.28, r.position.y - 6, r.size.x * 0.44, 10), Color("8a5a34"))   # clip
		for i in 3:
			var y := r.position.y + r.size.y * (0.28 + i * 0.24)
			draw_polyline(PackedVector2Array([Vector2(r.position.x + 7, y), Vector2(r.position.x + 11, y + 4), Vector2(r.position.x + 18, y - 4)]), Color("3aa84a"), 3.0)
			draw_line(Vector2(r.position.x + 23, y), Vector2(r.end.x - 6, y), Color("8a86a8"), 3.0)

func _open_talent() -> void:
	_open_daily(TalentScreen.new())

func _open_attend() -> void:
	_open_daily(AttendScreen.new())

func _open_daily(scr: GearScreen) -> void:
	if _leaving or _gear or _relic or _daily or _settings:
		scr.free()
		return
	Sfx.play("click", -6.0)
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	_daily = scr
	layer.add_child(scr)
	scr.open(font)
	scr.closed.connect(func():
		_daily = null
		layer.queue_free()
		_reload_quiet())   # currencies / badges refresh

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
## Button look in both presets: 뚜까펫 3D button in tt_col (radius r_tt) / classic flat box in classic_col.
func _skin_button(b: Button, tt_col: Color, classic_col: Color, r_tt: int, r_classic: int) -> void:
	var tt := UiTheme.tt()
	for st in ["normal", "hover", "pressed"]:
		if tt:
			b.add_theme_stylebox_override(st, UiTheme.button_box(tt_col.lightened(0.08 if st == "hover" else 0.0), r_tt, st == "pressed"))
		else:
			b.add_theme_stylebox_override(st, _box(classic_col.lightened(0.1 if st == "hover" else 0.0), r_classic, 5))

func _text_color(b: Button, c: Color) -> void:
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, c)

## Main-action (yellow) button: dark text on 뚜까펫 yellow, outlined white text on classic orange.
func _skin_yellow(b: Button) -> void:
	_skin_button(b, UiTheme.YELLOW, Color("ff9f1c"), 20, 24)
	if UiTheme.tt():
		_text_color(b, Color("3a2400"))
	else:
		_text_color(b, Color.WHITE)
		b.add_theme_color_override("font_outline_color", INK)
		b.add_theme_constant_override("outline_size", 8)

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

## Fresh tween on c that replaces its previous press tween (rapid clicks would otherwise stack tweens
## fighting over the same property; the entry _pop tween is a different one and is left alone).
func _press_tween(c: Control) -> Tween:
	var old: Tween = c.get_meta("press_tw") if c.has_meta("press_tw") else null
	if old and old.is_valid():
		old.kill()
	var tw := c.create_tween()
	c.set_meta("press_tw", tw)
	return tw

## Rebuild the lobby (fresh currencies, badges, worn gear on the stage) without replaying the entrance pop.
func _reload_quiet() -> void:
	_quiet_reload = true
	get_tree().reload_current_scene.call_deferred()

func _pop(c: Control, delay: float) -> void:
	if _quiet:
		return
	c.scale = Vector2.ZERO
	var tw := c.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(c, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
