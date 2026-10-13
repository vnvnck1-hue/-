class_name HudPanels
extends Node
## Popups and panels built with Hud's Toy Clash style helpers:
## game over, hero detail, inventory, perk choice, merchant, talent tree.

var hud: Hud
var game: Node

## Dimmed full-screen modal with a pop-in card. Registers itself as hud.overlay.
## header_h > 0: 뚜까펫식 보라 체크무늬 머리띠(제목은 그 안에 흰 글자). dark: 어두운 정보 창.
func _modal(card_size: Vector2, y := 0.0, replace := false, header_h := 0.0, dark := false) -> Control:
	if replace and hud.has_overlay():
		hud.overlay.queue_free()
		hud.overlay = null
	else:
		hud.close_overlays()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.1, 0.0) if UiTheme.tt() else Color(0.08, 0.05, 0.2, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	dim.create_tween().tween_property(dim, "color:a", 0.62 if UiTheme.tt() else 0.5, 0.3)
	var card := hud.panel(Color("fff4e0"), Rect2(Vector2.ZERO, card_size), 28, 6)
	card.add_theme_stylebox_override("panel", UiTheme.night_card() if dark else UiTheme.cream_card(28, header_h))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(hud.place(card, Vector2(0.5, 0.5), Vector2(-card_size.x * 0.5, -card_size.y * 0.5 + y), card_size))
	hud.pop_in(card, 0.4, 0.4)
	hud.overlay = root
	return card

func gameover(_w: int) -> void:
	var tt := UiTheme.tt()
	var note: String = game.gameover_note()
	var dy := 44.0 if note != "" else 0.0
	var card := _modal(Vector2(560, 520 + dy), -40, false, 0.0, tt)
	if tt:   # 뚜까펫 패배 창: 어두운 창 위로 보라 리본이 걸친다
		var rib := Hud.Ribbon.new()
		rib.col = Color("7a4ad8")
		rib.position = Vector2(30, -26)
		rib.size = Vector2(500, 112)
		rib.pivot_offset = rib.size * 0.5
		rib.scale = Vector2(0.1, 1.2)
		card.add_child(rib)
		rib.create_tween().tween_property(rib, "scale", Vector2.ONE, 0.35).set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var t := hud.label("패배" if tt else "게임 오버", 84, Color.WHITE if tt else Color("ff6b8a"), 18)
	t.position = Vector2(0, -24) if tt else Vector2(0, 30)
	t.size = Vector2(560, 110)
	card.add_child(t)
	var s := hud.label(game.gameover_text(), 40, Color.WHITE, 10)
	s.position = Vector2(0, 150)
	s.size = Vector2(560, 60)
	card.add_child(s)
	var c := hud.label("시간의 결정 %d개 보유" % Meta.crystals, 28, Defs.COL_CRYSTAL, 8)
	c.position = Vector2(0, 215)
	c.size = Vector2(560, 40)
	card.add_child(c)
	if note != "":
		var n := hud.label(note, 26, Color("ff9ab8"), 8)
		n.position = Vector2(0, 256)
		n.size = Vector2(560, 38)
		card.add_child(n)
	var label: String = game.retry_label()
	var b := hud.juicy_button(label, Color("3fa9f5"), Rect2(90, 280 + dy, 380, 100), 42 if label.length() <= 6 else 34)
	b.pressed.connect(func():
		hud.close_overlays()
		game.retry())
	card.add_child(b)
	var lb := hud.juicy_button("로비로", Color("8a7ad8"), Rect2(160, 400 + dy, 240, 80), 32)
	lb.pressed.connect(func(): game.go_lobby())
	card.add_child(lb)
	for bt in [b, lb]:
		bt.scale = Vector2.ZERO
		var tw: Tween = bt.create_tween()
		tw.tween_interval(0.5)
		tw.tween_property(bt, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- run perk roulette
## Perks are no longer picked by hand: a roulette reel spins through the perk pool and stops on a random one
## (same rarity odds as the old 3-card draw). Tapping skips straight to the result; it closes by itself.
## Perks only last until the whole team is wiped out.
const PERK_LABEL := {"common": "일반", "rare": "희귀", "legendary": "전설"}
const PERK_STARS := {"common": "★", "rare": "★★", "legendary": "★★★"}
const REEL_W := 620.0
const REEL_TILE := Vector2(176, 214)
const REEL_STEP := 188.0
const REEL_COUNT := 22
const REEL_WIN := 18
const REEL_SPIN := 1.45   # spin + settle + hold stays under 3 s in total
const REEL_HOLD := 1.0

func perks() -> bool:
	var opts: Array = game.generate_perks()
	if opts.is_empty():
		return false
	_perk_roulette(opts[randi() % opts.size()])
	return true

func _perk_roulette(win: String) -> void:
	var tt := UiTheme.tt()
	var W := 660.0
	var card := _modal(Vector2(W, 600), -60, false, 84.0)
	var root := hud.overlay
	var t := hud.label("특성 룰렛", 50 if tt else 54, Color.WHITE if tt else Color("ffd27a"), 14)
	t.position = Vector2(0, 8 if tt else 16)
	t.size = Vector2(W, 72 if tt else 70)
	card.add_child(t)
	var sub := hud.label("팀이 전멸하면 모든 특성이 사라져요", 22, Color("8a6a50"), 0)
	sub.position = Vector2(0, 90 if tt else 84)
	sub.size = Vector2(W, 32)
	card.add_child(sub)
	# reel window: tiles slide right-to-left under a fixed centre marker
	var win_box := hud.panel(UiTheme.inset(), Rect2((W - REEL_W) * 0.5, 132, REEL_W, 250), 20, 0)
	win_box.clip_contents = true
	card.add_child(win_box)
	var strip := Control.new()
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	win_box.add_child(strip)
	var pool: Array = Defs.PERKS.keys().filter(func(k): return not game.perks.has(k))
	var tiles: Array = []
	for i in REEL_COUNT:
		var id: String = win if i == REEL_WIN else pool[randi() % pool.size()]
		var tile := _reel_tile(id)
		tile.position = Vector2(i * REEL_STEP, (250 - REEL_TILE.y) * 0.5)
		strip.add_child(tile)
		tiles.append(tile)
	var mk := ReelMarker.new()
	mk.size = Vector2(REEL_W, 250)
	mk.position = win_box.position
	mk.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(mk)
	var res := hud.label("", 30, Color.WHITE, 10)
	res.position = Vector2(0, 396)
	res.size = Vector2(W, 48)
	card.add_child(res)
	var res_d := hud.label("", 24, Color("6a5a48"), 0)
	res_d.position = Vector2(0, 444)
	res_d.size = Vector2(W, 40)
	card.add_child(res_d)
	var hint := hud.label("터치하면 바로 멈춰요", 20, Color("a08a70"), 0)
	hint.position = Vector2(0, 540)
	hint.size = Vector2(W, 34)
	card.add_child(hint)
	var x_of := func(i: float) -> float: return REEL_W * 0.5 - REEL_TILE.x * 0.5 - i * REEL_STEP
	var state := {"last": -1, "done": false}
	var on_move := func(v: float) -> void:
		strip.position.x = v
		var idx := roundi((REEL_W * 0.5 - REEL_TILE.x * 0.5 - v) / REEL_STEP)
		if idx != state["last"]:
			state["last"] = idx
			Sfx.play("tick", -9.0, 1.0 + 0.04 * (idx % 5))
	# spin, coast to a stop a little off-centre, then settle onto the winner
	var stop: float = x_of.call(float(REEL_WIN))
	var near: float = stop + randf_range(-36.0, 36.0)
	var spin := card.create_tween()
	spin.tween_method(on_move, x_of.call(1.0), near, REEL_SPIN).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	spin.tween_method(on_move, near, stop, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var finish := func() -> void:
		if state["done"] or not is_instance_valid(card):
			return
		state["done"] = true
		strip.position.x = x_of.call(float(REEL_WIN))
		var p: Dictionary = Defs.PERKS[win]
		var col: Color = Defs.RARITY_COL[p["rarity"]]
		var tile: Control = tiles[REEL_WIN]
		tile.pivot_offset = tile.size * 0.5
		var pop := tile.create_tween()
		pop.tween_property(tile, "scale", Vector2(1.14, 1.14), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.tween_property(tile, "scale", Vector2(1.06, 1.06), 0.25)
		for k in tiles.size():
			if k != REEL_WIN:
				(tiles[k] as Control).modulate = Color(0.55, 0.55, 0.62)
		res.text = "%s %s · %s" % [PERK_STARS[p["rarity"]], PERK_LABEL[p["rarity"]], p["name"]]
		res.label_settings.font_color = col.lightened(0.15) if p["rarity"] != "common" else Color.WHITE
		res_d.text = p["desc"]
		hud.bump(res, 1.4)
		hud._sparkles(card, win_box.position + Vector2(REEL_W * 0.5, 125), 10)
		hint.text = "특성 획득!"
		game.choose_perk(win)
		game.get_tree().create_timer(REEL_HOLD, true, false, true).timeout.connect(func():
			if hud.overlay == root:
				hud.close_overlays())
	spin.tween_callback(finish)
	# tap: skip to the result, or close once it is shown
	var on_tap := func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if not state["done"]:
				spin.kill()
				finish.call()
			elif hud.overlay == root:
				hud.close_overlays()
	root.gui_input.connect(on_tap)
	card.gui_input.connect(on_tap)

func _reel_tile(id: String) -> Panel:
	var p: Dictionary = Defs.PERKS[id]
	var tile := hud.panel(Color.WHITE, Rect2(Vector2.ZERO, REEL_TILE), 20, 4)
	tile.add_theme_stylebox_override("panel", rarity_box(p["rarity"], 20, 5) if p["rarity"] != "common" else hud.box(Color("a9b2c6"), 20, 5, UiTheme.ink()))
	var st := hud.label(PERK_STARS[p["rarity"]], 30, Color.WHITE, 8)
	st.position = Vector2(0, 10)
	st.size = Vector2(REEL_TILE.x, 40)
	tile.add_child(st)
	var nm := hud.label(p["name"], 28, Color.WHITE, 9)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(8, 52)
	nm.size = Vector2(REEL_TILE.x - 16, 80)
	tile.add_child(nm)
	var ds := hud.label(p["desc"], 17, Color.WHITE, 6)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.position = Vector2(8, 132)
	ds.size = Vector2(REEL_TILE.x - 16, 70)
	tile.add_child(ds)
	return tile

## Centre marker of the roulette reel: yellow pointers top and bottom joined by a thin line.
class ReelMarker extends Control:
	func _draw() -> void:
		var ink := UiTheme.ink()
		var cx := size.x * 0.5
		var yel := Color("ffd23f")
		draw_line(Vector2(cx, 16), Vector2(cx, size.y - 16), Color(1, 0.95, 0.5, 0.55), 3.0)
		for top in [true, false]:
			var y := 0.0 if top else size.y
			var d := 1.0 if top else -1.0
			var o := PackedVector2Array([Vector2(cx - 22, y - 4 * d), Vector2(cx + 22, y - 4 * d), Vector2(cx, y + 30 * d)])
			var i := PackedVector2Array([Vector2(cx - 15, y), Vector2(cx + 15, y), Vector2(cx, y + 22 * d)])
			draw_colored_polygon(o, ink)
			draw_colored_polygon(i, yel)

# ---------------------------------------------------------------- permanent talent tree
const TREE_SCALE := 0.74
var talent_sel := "root"

func talents() -> void:
	if not game.is_placement():
		return
	if not game.tutorial_allows("talent"):
		hud.toast("튜토리얼을 먼저 끝내 주세요")
		return
	_talent_card(false)

func _talent_card(replace := true) -> void:
	var W := 700.0
	var tt := UiTheme.tt()
	var card := _modal(Vector2(W, 1060), -10, replace, 74.0)
	var t := hud.label("시간의 특성", 46 if tt else 50, Color.WHITE if tt else Color("9fc4ff"), 14)
	t.position = Vector2(0, 6 if tt else 12)
	t.size = Vector2(W, 64)
	card.add_child(t)
	var cr := hud.label("시간의 결정 %d" % Meta.crystals, 28, Defs.COL_CRYSTAL, 8)
	cr.position = Vector2(0, 76 if tt else 72)
	cr.size = Vector2(W, 38)
	card.add_child(cr)
	# branch progress
	var bx := 24.0
	for br in ["core", "warrior", "ranger", "mage"]:
		var have := 0
		var total := 0
		for n in Defs.TALENTS:
			if n["branch"] == br:
				total += int(n["max"])
				have += Meta.level(n["id"])
		var col: Color = Defs.TALENT_BRANCH[br]["col"]
		var chip := hud.panel(col, Rect2(bx, 116, 154, 40), 16, 3)
		card.add_child(chip)
		var cl := hud.label("%s %d/%d" % [Defs.TALENT_BRANCH[br]["name"], have, total], 19, Color.WHITE, 6)
		cl.size = Vector2(154, 40)
		chip.add_child(cl)
		bx += 164.0
	# tree canvas
	var tree := TalentTree.new()
	tree.position = Vector2((W - 900 * TREE_SCALE) * 0.5, 166)
	tree.size = Vector2(900, 805) * TREE_SCALE
	tree.scale_k = TREE_SCALE
	card.add_child(tree)
	for n in Defs.TALENTS:
		var id: String = n["id"]
		var lv := Meta.level(id)
		var reason := Meta.can_buy(id)
		var col: Color = Defs.TALENT_BRANCH[n["branch"]]["col"]
		var r := 26.0 if n["max"] > 1 else 30.0
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.size = Vector2(r * 2, r * 2)
		b.position = n["pos"] * TREE_SCALE - b.size * 0.5
		b.pivot_offset = b.size * 0.5
		var fill := col if lv > 0 else (Color("fffaf0") if reason != "locked" else Color("c8c0d0"))
		var border := Color("ffd23f") if id == talent_sel else (col.darkened(0.15) if reason == "locked" else (UiTheme.ink() if lv < n["max"] else col.darkened(0.4)))
		var sb := hud.box(fill, int(r), 5 if id == talent_sel else 4, border)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", hud.box(fill.lightened(0.15), int(r), 5, border))
		b.add_theme_stylebox_override("pressed", sb)
		b.add_theme_font_override("font", hud.font)
		b.add_theme_font_size_override("font_size", 18)
		b.add_theme_color_override("font_color", Color.WHITE if lv > 0 else Color("6a5a70"))
		b.add_theme_color_override("font_outline_color", UiTheme.ink())
		b.add_theme_constant_override("outline_size", 6 if lv > 0 else 0)
		b.text = "%d/%d" % [lv, n["max"]] if n["max"] > 1 else ("✓" if lv > 0 else "")
		b.pressed.connect(func():
			talent_sel = id
			Sfx.play("click", -6.0, 1.2)
			_talent_card())
		tree.add_child(b)
		if reason == "" and lv < n["max"]:
			var tw := b.create_tween().set_loops()
			tw.tween_property(b, "scale", Vector2(1.08, 1.08), 0.45).set_trans(Tween.TRANS_SINE)
			tw.tween_property(b, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
	# selected node info
	var n2 := Defs.talent(talent_sel)
	var info := hud.panel(UiTheme.inset(), Rect2(20, 770, W - 40, 172), 20, 0)
	card.add_child(info)
	var lv2 := Meta.level(talent_sel)
	var nm := hud.label("%s  %d/%d" % [n2["name"], lv2, n2["max"]], 32, Defs.TALENT_BRANCH[n2["branch"]]["col"].darkened(0.2), 0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(20, 8)
	nm.size = Vector2(W - 80, 46)
	info.add_child(nm)
	var ds := hud.label(n2["desc"] + ("  (레벨당)" if n2["max"] > 1 else ""), 22, Color("4a3a30"), 0)
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ds.position = Vector2(20, 54)
	ds.size = Vector2(W - 80, 34)
	info.add_child(ds)
	var reqs: Array = n2["req"].map(func(r): return Defs.talent(r)["name"])
	var rq := hud.label("선행: " + (", ".join(reqs) if not reqs.is_empty() else "없음") + " (모두 최대 레벨)", 18, Color("8a7a60"), 0)
	rq.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	rq.position = Vector2(20, 88)
	rq.size = Vector2(W - 80, 28)
	info.add_child(rq)
	var why := Meta.can_buy(talent_sel)
	var btxt := "최대 레벨" if why == "max" else ("잠김" if why == "locked" else "해금  ◆ %d" % n2["costs"][lv2])
	var buy := hud.juicy_button(btxt, Color("3fa9f5") if why == "" else Color("a0a0b0"), Rect2(W - 40 - 260, 116, 240, 50), 24)
	buy.pressed.connect(_buy_talent)
	info.add_child(buy)
	var close := hud.juicy_button("닫기", Color("ff9f1c"), Rect2(W * 0.5 - 130, 960, 260, 76), 32)
	close.pressed.connect(func(): hud.close_overlays())
	card.add_child(close)

func _buy_talent() -> void:
	var n2 := Defs.talent(talent_sel)
	match Meta.can_buy(talent_sel):
		"":
			Meta.buy(talent_sel)
			Sfx.play("chime", -4.0, 1.2)
			Vfx.cam.add_trauma(0.1)
			hud.set_crystals(Meta.crystals)
			hud.toast("%s %d/%d 해금!" % [n2["name"], Meta.level(talent_sel), n2["max"]], Color("9fc4ff"))
			_talent_card()
		"locked":
			hud.toast("앞선 특성을 먼저 최대로 올려야 해요")
		"crystal":
			hud.toast("시간의 결정이 %d개 부족해요" % (int(n2["costs"][Meta.level(talent_sel)]) - Meta.crystals))

class TalentTree extends Control:
	var scale_k := 1.0
	func _draw() -> void:
		for n in Defs.TALENTS:
			for r in n["req"]:
				var a: Vector2 = Defs.talent(r)["pos"] * scale_k
				var b: Vector2 = n["pos"] * scale_k
				var done := Meta.level(r) >= int(Defs.talent(r)["max"])
				draw_line(a, b, UiTheme.ink(), 9.0, true)
				draw_line(a, b, Defs.TALENT_BRANCH[n["branch"]]["col"] if done else Color("d8d0c8"), 5.0, true)

# ---------------------------------------------------------------- inventory panel
const STAT_NAME := {"atk": ["공격력", false], "hp": ["체력", false], "critChance": ["치명타", true], "range": ["사거리", false],
	"atkSpeedBonus": ["공격 속도", true], "dmgBonus": ["주는 피해", true], "explosionChance": ["폭발 확률", true],
	"dmgReduce": ["받는 피해 감소", true], "counterChance": ["반격 확률", true], "moveSpeedBonus": ["이동 속도", true],
	"lifeSteal": ["흡혈", true], "doubleAttackChance": ["추가 공격", true], "manaGainMult": ["마나 획득", true],
	"dropBonus": ["드랍률", true], "goldMult": ["골드", true], "freezeChance": ["빙결 확률", true], "pierceChance": ["관통 확률", true],
	"dodgeChance": ["회피", true], "activeMult": ["고유 스킬 피해", true], "ultDamageBonus": ["궁극기 피해", true],
	"ultCooldownReduce": ["궁극기 쿨타임 감소", true], "bonusHp": ["체력", false], "activeCount": ["추가 화살", false],
	"ultBounces": ["추가 튕김", false]}
const EFFECT_NAME := {"sharedMana": "마나 공유", "killMana": "처치 시 마나 충전", "knockback": "공격 시 넉백",
	"swap": "공격 시 위치 교환", "lightning": "3타마다 번개"}
const RARITY_NAME := {"common": "일반", "uncommon": "고급", "rare": "희귀", "epic": "영웅", "legendary": "전설", "mythic": "신화",
	"ancient": "고대", "primal": "태초", "transcendent": "초월"}
const SPECIAL_DETAIL := {
	"revive": "가장 먼저 쓰러진 동료 1명을 체력 100%로 되살립니다.\n배치 중에는 원래 칸에서, 전투 중에는 쓰러진 자리에서 일어납니다.\n쓰러진 동료가 없으면 쓸 수 없습니다. 언제든 사용 가능.",
	"fullHeal": "살아 있는 모든 영웅의 체력을 즉시 최대치까지 회복합니다.\n전투 중에도 사용할 수 있어 위기 탈출에 좋습니다.",
	"massKill": "전투 중에만 사용 가능. 필드의 모든 적을 즉시 없앱니다.\n단, 골드·경험치·아이템·결정 보상은 전혀 없습니다(히드라 포함).",
	"inventoryExpand": "가방을 3칸 늘립니다(이번 런 동안 유지).\n상인에게서 살 수 있습니다.",
	"crown": "무기·방어구와 별개로 장신구 칸에 장착합니다.\n같은 왕관 3개를 모으면 '초월한 왕관'으로 자동 합성됩니다."}
const SLOT_KO := {"weapon": "무기", "armor": "방어구", "accessory": "장신구"}

## Panel fill coloured by rarity (rarity is shown by the whole panel, not only the outline).
func rarity_box(rarity: String, radius := 14, border := 4) -> StyleBoxFlat:
	var c: Color = Defs.RARITY_COL.get(rarity, Color("c8ccd8"))
	return hud.box(c.lightened(0.08), radius, border, UiTheme.ink())
const SLOT_W := 82.0
const SLOT_H := 74.0
var _slot_boxes := {}   # "<rarity>|<theme>" -> StyleBoxFlat shared by the bag slots ("" rarity = empty slot)

## Bag slot style for a rarity ("" = empty), built once instead of on every bag refresh.
func _slot_box(rarity: String) -> StyleBoxFlat:
	var key := "%s|%s" % [rarity, UiTheme.tt()]
	if not _slot_boxes.has(key):
		_slot_boxes[key] = UiTheme.empty_slot(14) if rarity == "" else rarity_box(rarity)
	return _slot_boxes[key]

var inv_panel: Panel
var inv_title: Label
var sell_btn: Button
var inv_slots: Array[Panel] = []
var sell_mode := false
var tip: Control
var tip_entry := {}
var tip_pinned := false
var drag_entry := {}
var drag_ghost: ItemIcon
var _press_slot := -1
var _press_pos := Vector2.ZERO

func build_inventory() -> void:
	var W := 680.0
	var H := 214.0
	inv_panel = hud.panel(Color(0.1, 0.08, 0.2, 0.55), Rect2(0, 0, W, H), 24, 0)
	inv_panel.add_theme_stylebox_override("panel", UiTheme.deck_panel(24, 46.0))
	inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(hud.place(inv_panel, Vector2(0.5, 1), Vector2(-W * 0.5, -342), Vector2(W, H)))
	inv_title = hud.label("가방 0/14", 26, Color("fff4e0"), 8)
	inv_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	inv_title.position = Vector2(22, 4)
	inv_title.size = Vector2(300, 40)
	inv_panel.add_child(inv_title)
	sell_btn = hud.juicy_button("판매", Color("ff7a5a"), Rect2(W - 132, 6, 116, 40), 22)
	sell_btn.pressed.connect(func():
		sell_mode = not sell_mode
		_close_tip()
		_style_sell())
	inv_panel.add_child(sell_btn)
	_build_chest_badge()
	refresh_inventory()

# ---------------------------------------------------------------- treasure chest badge (bag top-left)
var chest_badge: Control
var chest_icon: ChestGacha.ChestIcon
var chest_count: Label
var _badge_glow: Control

## Picked-up treasure chests pile up here (count bubble); tapping opens the chest screen (Main.open_chests).
func _build_chest_badge() -> void:
	var b := Control.new()
	b.size = Vector2(92, 82)
	b.position = Vector2(-8, -46)
	b.pivot_offset = Vector2(46, 60)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.visible = false
	inv_panel.add_child(b)
	chest_badge = b
	_badge_glow = hud._fly_burst("aura", Color("ffd23f"), 50.0, Vector2(46, 46))
	_badge_glow.modulate.a = 0.75
	b.add_child(_badge_glow)
	var gt := _badge_glow.create_tween().set_loops()
	gt.tween_property(_badge_glow, "scale", Vector2(1.15, 1.15), 0.6).set_trans(Tween.TRANS_SINE)
	gt.tween_property(_badge_glow, "scale", Vector2(0.9, 0.9), 0.6).set_trans(Tween.TRANS_SINE)
	chest_icon = ChestGacha.ChestIcon.new()
	chest_icon.position = Vector2(4, 4)
	chest_icon.size = Vector2(84, 74)
	chest_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(chest_icon)
	var bubble := Panel.new()
	bubble.position = Vector2(62, -6)
	bubble.size = Vector2(36, 36)
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_stylebox_override("panel", hud.box(Color("ff3b5c"), 18, 4, UiTheme.ink()))
	b.add_child(bubble)
	chest_count = hud.label("0", 22, Color.WHITE, 6)
	chest_count.size = bubble.size
	bubble.add_child(chest_count)
	b.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and ev.pressed:
			hud.bump(b, 0.8)
			game.open_chests())
	# a little wiggle every couple of seconds: "open me!"
	var wt := b.create_tween().set_loops()
	wt.tween_interval(1.8)
	wt.tween_property(b, "rotation", -0.16, 0.07)
	wt.tween_property(b, "rotation", 0.16, 0.1)
	wt.tween_property(b, "rotation", -0.1, 0.09)
	wt.tween_property(b, "rotation", 0.0, 0.12)

func refresh_chests(arrived := false) -> void:
	if chest_badge == null:
		return
	var n: int = game.chests.size()
	var was := chest_badge.visible
	chest_badge.visible = n > 0
	inv_title.position.x = 90.0 if n > 0 else 22.0
	if n <= 0:
		return
	chest_count.text = str(n)
	var best := 0
	for t in game.chests:
		best = maxi(best, int(t))
	chest_icon.tier = best
	chest_icon.queue_redraw()
	_badge_glow.col = Hud._vivid(ChestLoot.tier_color(best)) if best > 0 else Color("ffd23f")
	_badge_glow.queue_redraw()
	if arrived or not was:
		hud.bump(chest_badge, 1.5)
		hud.bump(chest_count.get_parent(), 1.6)
		Sfx.play("pop", -3.0, 1.2)

func chest_badge_center() -> Vector2:
	if chest_badge == null:
		return hud.root.size * 0.5
	return chest_badge.get_global_transform() * (chest_badge.size * 0.5)

## 2D chest flies from a screen point onto the badge (arc, spin, swell), then on_arrive.
func fly_chest(from: Vector2, t: int, on_arrive: Callable) -> void:
	var ic := ChestGacha.ChestIcon.new()
	ic.tier = t
	ic.size = Vector2(84, 74)
	ic.pivot_offset = ic.size * 0.5
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var aura := hud._fly_burst("aura", Hud._vivid(ChestLoot.tier_color(t)) if t > 0 else Color("ffd23f"), 54.0, ic.size * 0.5)
	aura.show_behind_parent = true
	ic.add_child(aura)
	hud._fly_root().add_child(ic)
	var dest := chest_badge_center()
	var mid := from.lerp(dest, 0.35) + Vector2(randf_range(-70, 70), -230)
	ic.position = from - ic.size * 0.5
	ic.scale = Vector2(0.3, 0.3)
	var step := func(k: float) -> void:
		var a := from.lerp(mid, k)
		var b := mid.lerp(dest, k)
		ic.position = a.lerp(b, k) - ic.size * 0.5
	var tw := ic.create_tween().set_ignore_time_scale(true)
	tw.tween_property(ic, "scale", Vector2(1.45, 1.45), 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(ic, "rotation", -0.3, 0.22)
	tw.tween_method(step, 0.0, 1.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(ic, "scale", Vector2(0.9, 0.9), 0.6)
	tw.parallel().tween_property(ic, "rotation", TAU, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		ic.queue_free()
		_merge_impact(dest, Color("ffd23f"))
		on_arrive.call())

func _style_sell() -> void:
	sell_btn.text = "판매 중" if sell_mode else "판매"
	if UiTheme.tt():
		hud.style_button(sell_btn, UiTheme.YELLOW if sell_mode else UiTheme.RED, 40.0)
	else:
		var c := Color("ffd23f") if sell_mode else Color("ff7a5a")
		sell_btn.add_theme_stylebox_override("normal", hud.box(c, 22, 5))
		sell_btn.add_theme_stylebox_override("hover", hud.box(c.lightened(0.12), 22, 5))

func refresh_inventory(highlight_id := -1) -> void:
	if inv_panel == null:
		return
	var cap: int = game.inv_cap
	inv_title.text = "가방 %d/%d" % [game.inventory.size(), cap]
	var cols := 7
	var rows := int(ceilf(cap / float(cols)))
	var need := rows * cols
	while inv_slots.size() < need:
		var sp := Panel.new()
		sp.size = Vector2(SLOT_W, SLOT_H)
		sp.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := inv_slots.size()
		sp.gui_input.connect(func(ev: InputEvent): _slot_input(idx, ev))
		sp.mouse_entered.connect(func(): _hover_slot(idx, true))
		sp.mouse_exited.connect(func(): _hover_slot(idx, false))
		inv_panel.add_child(sp)
		var ic := ItemIcon.new()
		ic.position = Vector2(8, 4)
		ic.size = Vector2(SLOT_W - 16, SLOT_H - 8)
		sp.add_child(ic)
		inv_slots.append(sp)
	var gap := (inv_panel.size.x - 28 - cols * SLOT_W) / (cols - 1)
	var scroll_rows := mini(rows, 2)
	for i in inv_slots.size():
		var sp := inv_slots[i]
		var r := i / cols
		var c := i % cols
		sp.visible = i < cap and r < scroll_rows
		sp.position = Vector2(14 + c * (SLOT_W + gap), 50 + r * (SLOT_H + 8))
		var e: Dictionary = game.inventory[i] if i < game.inventory.size() else {}
		sp.add_theme_stylebox_override("panel", _slot_box("" if e.is_empty() else Inventory.rarity_of(e)))
		(sp.get_child(0) as ItemIcon).set_entry(e)
		if highlight_id >= 0 and not e.is_empty() and e["id"] == highlight_id:
			hud.bump(sp, 1.35)
	if cap > 14:
		inv_title.text += "  (+%d칸)" % (cap - 14)

# ---------------------------------------------------------------- skill book merge show (in the bag)
## Defs.BOOK_MERGE books of grade g lift out of their slots, rush together onto the first one's slot, flash, and
## the next-grade book pops in (Inventory.merge_books_once -> Main.on_book_merged). Awaited one by one.
func play_merge(g: int, chain := 0) -> void:
	if inv_panel == null or not is_inside_tree():
		var ne0 := Inventory.merge_books_once(game, g)
		if not ne0.is_empty():
			game.on_book_merged(ne0)
		return
	var src := Inventory.book_sources(game, g)
	if src.size() < Defs.BOOK_MERGE:
		return
	var dest := slot_center(src.min())
	var froms: Array[Vector2] = []
	var mats: Array = []
	for i in src:
		mats.append(game.inventory[i])
		froms.append(slot_center(i))
		var sp := inv_slots[i] if i < inv_slots.size() else null
		if sp:   # the copy leaves its slot
			sp.add_theme_stylebox_override("panel", UiTheme.empty_slot(14))
			(sp.get_child(0) as ItemIcon).set_entry({})
	var rc: Color = Defs.RARITY_COL[Defs.book_rarity(g)]
	var vivid := Hud._vivid(rc)
	var layer := hud._fly_root()
	var ghosts: Array[Control] = []
	for fi in froms.size():
		var gh := _merge_ghost(mats[fi], rc)
		layer.add_child(gh)
		gh.position = froms[fi] - gh.size * 0.5
		ghosts.append(gh)
	Sfx.play("whoosh", -9.0, 1.1 + 0.06 * chain)
	# 1) lift out of the slots and wobble
	var lift := create_tween().set_parallel(true).set_ignore_time_scale(true)
	for i in ghosts.size():
		var gh := ghosts[i]
		gh.scale = Vector2(0.75, 0.75)
		lift.tween_property(gh, "scale", Vector2(1.3, 1.3), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.05 * i)
		lift.tween_property(gh, "position:y", gh.position.y - 34.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(0.05 * i)
		lift.tween_property(gh, "rotation", (0.22 if i % 2 == 0 else -0.22), 0.2).set_delay(0.05 * i)
	await lift.finished
	# 2) rush together onto the target slot (slight arc, spinning in, shrinking)
	var rush := create_tween().set_parallel(true).set_ignore_time_scale(true)
	for i in ghosts.size():
		var gh := ghosts[i]
		var a := gh.position + gh.size * 0.5
		var side := (float(i) - (ghosts.size() - 1) * 0.5) * 70.0
		var ctrl := a.lerp(dest, 0.5) + Vector2(side, -70.0)
		var step := func(k: float) -> void:
			var p := a.lerp(ctrl, k).lerp(ctrl.lerp(dest, k), k)
			gh.position = p - gh.size * 0.5
		rush.tween_method(step, 0.0, 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN).set_delay(0.03 * i)
		rush.tween_property(gh, "rotation", gh.rotation + TAU * (1.0 if i % 2 == 0 else -1.0), 0.3).set_delay(0.03 * i)
		rush.tween_property(gh, "scale", Vector2(0.8, 0.8), 0.3).set_delay(0.03 * i)
	await rush.finished
	for gh in ghosts:
		gh.queue_free()
	# 3) impact: white flash disc, grade ring + sparkle dots, corner stars
	var nvivid := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(g + 1)])
	_merge_impact(dest, nvivid)
	Sfx.play("pop", -3.0, 0.8 + 0.08 * chain)
	var ne := Inventory.merge_books_once(game, g)
	if ne.is_empty():   # a copy was read / sold mid-show
		refresh_inventory()
		return
	game.on_book_merged(ne)
	# 4) the merged book pops into its slot (squash & stretch, white shine, a grade aura)
	var at: int = game.inventory.find(ne)
	if at >= 0 and at < inv_slots.size() and inv_slots[at].visible:
		var sp := inv_slots[at]
		sp.pivot_offset = sp.size * 0.5
		sp.scale = Vector2(0.2, 0.2)
		sp.modulate = Color(2.2, 2.2, 2.2)
		sp.z_index = 2
		var pop := create_tween().set_ignore_time_scale(true)
		pop.tween_property(sp, "scale", Vector2(1.55, 1.3), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.parallel().tween_property(sp, "modulate", Color.WHITE, 0.35)
		pop.tween_property(sp, "scale", Vector2(0.92, 1.08), 0.08)
		pop.tween_property(sp, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		pop.tween_callback(func(): sp.z_index = 0)
		_merge_aura(sp, nvivid)
	await get_tree().create_timer(0.38, true, false, true).timeout

## Screen centre of bag slot i (or the bag title when that slot is hidden).
func slot_center(i: int) -> Vector2:
	if i >= 0 and i < inv_slots.size() and inv_slots[i].visible:
		return inv_slots[i].get_global_rect().get_center()
	return inv_title.get_global_rect().get_center()

## Flying copy of a merge source: icon with a grade outline + dark drop shadow (like loot fly-ins).
func _merge_ghost(e: Dictionary, rc: Color) -> Control:
	var holder := Control.new()
	holder.size = Vector2(64, 64)
	holder.pivot_offset = holder.size * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rect := Rect2(3, 3, 58, 58)
	for d in hud._ring(3.0):
		holder.add_child(hud._icon_silhouette(e, rect, d + Vector2(2, 4), Color(0.05, 0.03, 0.1, 1.0)))
	for d in hud._ring(3.0):
		holder.add_child(hud._icon_silhouette(e, rect, d, rc))
	var ic := ItemIcon.new(e)
	ic.position = rect.position
	ic.size = rect.size
	holder.add_child(ic)
	return holder

## Soft grade glow that blooms behind a freshly merged slot and fades out.
func _merge_aura(sp: Control, vivid: Color) -> void:
	var aura := hud._fly_burst("aura", vivid, 58.0, sp.size * 0.5)
	aura.show_behind_parent = true
	aura.modulate.a = 0.0
	aura.scale = Vector2(0.5, 0.5)
	sp.add_child(aura)
	var tw := aura.create_tween().set_ignore_time_scale(true)
	tw.tween_property(aura, "modulate:a", 1.0, 0.08)
	tw.parallel().tween_property(aura, "scale", Vector2(1.2, 1.2), 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(aura, "modulate:a", 0.0, 0.5)
	tw.tween_callback(aura.queue_free)

# ---------------------------------------------------------------- arrival impact
func _merge_impact(at: Vector2, vivid: Color) -> void:
	var fx := Control.new()
	fx.size = Vector2(64, 64)
	fx.position = at - fx.size * 0.5
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud._fly_root().add_child(fx)
	var flash := hud._fly_burst("disc", Color(1, 1, 1, 0.95), 26.0)
	flash.scale = Vector2(0.4, 0.4)
	fx.add_child(flash)
	var ring := hud._fly_burst("ring", vivid, 46.0)
	fx.add_child(ring)
	var s1 := hud._fly_burst("star", vivid, 16.0, Vector2(64, 0))
	var s2 := hud._fly_burst("star", vivid, 12.0, Vector2(0, 60))
	var s3 := hud._fly_burst("star", Color.WHITE, 10.0, Vector2(62, 58))
	for s in [s1, s2, s3]:
		fx.add_child(s)
	hud._twinkle(s1, 1.0, 0.02)
	hud._twinkle(s2, 1.0, 0.08)
	hud._twinkle(s3, 1.0, 0.14)
	var tw := fx.create_tween().set_parallel(true).set_ignore_time_scale(true)
	tw.tween_property(flash, "scale", Vector2(1.6, 1.6), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(flash, "modulate:a", 0.0, 0.22).set_delay(0.06)
	tw.tween_property(ring, "t", 1.0, 0.5).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.25)
	tw.chain().tween_callback(fx.queue_free)

## Screen centre of the slot the next added item will occupy (or the bag title when full).
func next_slot_center(offset := 0) -> Vector2:
	var i: int = game.inventory.size() + offset
	if i < inv_slots.size() and i < game.inv_cap and inv_slots[i].visible:
		return inv_slots[i].get_global_rect().get_center()
	return inv_title.get_global_rect().get_center()

func pulse_first_item(k: float) -> void:
	if inv_slots.is_empty() or game.inventory.is_empty():
		return
	inv_slots[0].pivot_offset = inv_slots[0].size * 0.5
	inv_slots[0].scale = Vector2(k, k)

func _slot_input(i: int, ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press_slot = i
			_press_pos = ev.global_position
		else:
			if drag_ghost:
				_drop(ev.global_position)
			elif _press_slot == i:
				_tap(i)
			_press_slot = -1
	elif ev is InputEventMouseMotion and _press_slot == i:
		if drag_ghost == null and ev.global_position.distance_to(_press_pos) > 12.0:
			_begin_drag(i)
		if drag_ghost:
			drag_ghost.position = ev.global_position - drag_ghost.size * 0.5
			var h: Actor = _drop_target(ev.global_position)
			game.set_drag_target(h)
			_highlight_equip_slot(h == hero_shown and h != null)

func _entry_at(i: int) -> Dictionary:
	return game.inventory[i] if i < game.inventory.size() else {}

## Hovering a bag slot previews its info card; tapping pins it with actions.
func _hover_slot(i: int, on: bool) -> void:
	if drag_ghost or tip_pinned:
		return
	var e := _entry_at(i)
	if on and not e.is_empty():
		_show_tip(e, false)
		var sp := inv_slots[i]
		sp.pivot_offset = sp.size * 0.5
		Hud.retween(sp).tween_property(sp, "scale", Vector2(1.1, 1.1), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		if not tip_pinned:
			_close_tip()
		var sp2 := inv_slots[i]
		Hud.retween(sp2).tween_property(sp2, "scale", Vector2.ONE, 0.12)

func _tap(i: int) -> void:
	var e := _entry_at(i)
	if e.is_empty():
		_close_tip()
		return
	if sell_mode:
		game.sell_item(e)
		_close_tip()
		return
	_show_tip(e, true)

func _begin_drag(i: int) -> void:
	var e := _entry_at(i)
	if e.is_empty() or not _equippable(e):
		return
	_close_tip()
	drag_entry = e
	drag_ghost = ItemIcon.new(e)
	drag_ghost.size = Vector2(92, 92)
	drag_ghost.pivot_offset = drag_ghost.size * 0.5
	hud.root.add_child(drag_ghost)
	var tw := drag_ghost.create_tween().set_loops().set_ignore_time_scale(true)
	tw.tween_property(drag_ghost, "rotation", 0.12, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(drag_ghost, "rotation", -0.12, 0.25).set_trans(Tween.TRANS_SINE)
	inv_slots[i].modulate.a = 0.4
	Sfx.play("click", -5.0, 1.3)
	game.set_slowmo(true, e)

func _equippable(e: Dictionary) -> bool:
	return e["kind"] == "equip" or (e["kind"] == "special" and e["key"] == "crown")

func _drop_target(at: Vector2) -> Actor:
	if hero_card and is_instance_valid(hero_card) and hero_card.get_global_rect().has_point(at):
		return hero_shown
	return game.hero_at_screen(at)

func _highlight_equip_slot(on: bool) -> void:
	if drag_entry.is_empty() or not equip_slot_rects.has(Defs.item(drag_entry["key"]).get("slot", "")):
		return
	var sb: Panel = equip_slot_rects[Defs.item(drag_entry["key"])["slot"]]
	if not is_instance_valid(sb):
		return
	sb.pivot_offset = sb.size * 0.5
	sb.scale = Vector2(1.08, 1.08) if on else Vector2.ONE
	sb.modulate = Color(1.25, 1.25, 1.0) if on else Color.WHITE

func _drop(at: Vector2) -> void:
	var e := drag_entry
	var target := _drop_target(at)
	_highlight_equip_slot(false)
	drag_ghost.queue_free()
	drag_ghost = null
	drag_entry = {}
	for s in inv_slots:
		s.modulate.a = 1.0
	game.set_drag_target(null)
	game.set_slowmo(false)
	if target:
		game.equip_item(target, e)

# ---------------------------------------------------------------- item tooltip
func _stat_lines(stats: Dictionary, sep := "  ") -> String:
	var out := []
	for k in stats:
		if not STAT_NAME.has(k):
			continue
		var n: Array = STAT_NAME[k]
		var v: float = stats[k]
		out.append("%s +%s" % [n[0], ("%d%%" % roundi(v * 100.0)) if n[1] else str(int(v))])
	return sep.join(out)

## Short one/two-line summary (merchant cards).
func describe(e: Dictionary) -> String:
	match e["kind"]:
		"equip":
			var def := Defs.item(e["key"])
			var t := _stat_lines(Stats.entry_stats(e))
			var effs: Array = def.get("effects", [])
			if not effs.is_empty():
				t += "\n" + " · ".join(effs.map(func(x): return EFFECT_NAME.get(x, x)))
			return t
		"special":
			var sd: Dictionary = Defs.SPECIAL[e["key"]]
			if sd.get("equip", false):
				return _stat_lines(sd["stats"])
			return sd["desc"]
		"relic":
			return Defs.relic_desc(e["key"], int(e.get("star", 1)))
		"skillbook":
			return "읽으면 스킬 %d개 중 하나 · 최대 %s 스킬" % [Defs.BOOK_PICKS, Defs.book_grade_name(Inventory.book_grade(e))]
		"stone":
			return "장비 칸 강화 재료 (판이 끝나면 보관)"
	return ""

## Stat categories for the item card: each group gets its own colour so offence / survival / utility read at a glance.
const STAT_GROUP := {"atk": 0, "critChance": 0, "atkSpeedBonus": 0, "dmgBonus": 0, "explosionChance": 0, "doubleAttackChance": 0, "range": 0,
	"hp": 1, "dmgReduce": 1, "counterChance": 1, "lifeSteal": 1,
	"moveSpeedBonus": 2, "manaGainMult": 2, "dropBonus": 2, "goldMult": 2}
const GROUP_COL := ["d8432c", "2f9a4a", "2f78d0"]   # 공격 / 생존 / 보조
const EFFECT_COL := "9a3cc8"
const META_COL := "8a7a60"
const BODY_COL := "3a2a20"
## Effect body for the card (the effect name is its own coloured heading above it). Mirrors Combat.hero_hit /
## main.on_enemy_killed exactly; the same effect on two worn items does not stack.
const EFFECT_BODY := {
	"sharedMana": "다른 아군이 기본 공격으로 마나를 얻을 때마다, 그 양의 50%를 이 영웅도 함께 얻습니다.",
	"killMana": "아군 누가 적을 쓰러뜨려도 그때마다 이 영웅의 마나가 즉시 가득 찹니다.",
	"knockback": "기본 공격에 맞은 적을 뒤로 강하게 밀어냅니다.\n(위치 교환 효과도 함께 지니면 넉백 대신 위치 교환)",
	"swap": "기본 공격 뒤 대상이 살아 있으면 대상과 서로 자리를 맞바꿉니다.",
	"lightning": "기본 공격 3번째마다 다른 적 1명(무작위)에게 그 공격 피해의 80% 번개가 튑니다."}

## What a stat actually does in combat ({v} = formatted value). Only stats whose name alone doesn't say it all.
## party = true: relic / team-wide wording ("파티 전원").
const STAT_NOTE := {
	"critChance": "치명타가 터지면 기본 공격 피해 2배",
	"explosionChance": "기본 공격 시 {v} 확률로 폭발: 주변 적에게 그 피해의 50%",
	"counterChance": "근접 공격을 받으면 {v} 확률로 즉시 반격 (원거리 공격엔 발동 안 함)",
	"dmgBonus": "기본 공격 피해 +{v} (스킬·궁극기 피해엔 적용 안 됨)",
	"range": "공격 사거리 +{v}칸",
	"lifeSteal": "기본 공격으로 가한 피해의 {v}만큼 체력 회복 (흡혈 합계 최대 35%)",
	"doubleAttackChance": "기본 공격 시 {v} 확률로 0.2초 뒤 같은 적을 한 번 더 공격 (추가 공격·반격은 다시 발동 안 함)",
	"manaGainMult": "기본 공격으로 얻는 마나 +{v} → 궁극기를 더 자주 사용",
	"moveSpeedBonus": "이동 속도 +{v} (이동 속도 보너스 합계 최대 75%)",
	"dmgReduce": "받는 피해 {v} 감소 (모든 피해 감소 합계 최대 75%)",
	"atkSpeedBonus": "공격 간격 {v} 단축 (공격 속도 보너스 합계 최대 70%)",
	"dropBonus": "적 처치 시 장비 드랍 확률 +{v}p · 스킬북 드랍 확률 +{h}p",
	"goldMult": "적 처치 골드 +{v}"}
## Equipment notes are shown for these (atk / hp / atk speed / reduce read fine from the stat line itself).
const EQUIP_NOTE_KEYS := ["critChance", "explosionChance", "counterChance", "dmgBonus", "range", "lifeSteal",
	"doubleAttackChance", "manaGainMult", "moveSpeedBonus", "dropBonus", "goldMult"]

static func _pct(v: float) -> String:
	return "%d%%" % roundi(v * 100.0)

static func stat_note(k: String, v: float) -> String:
	var t: String = STAT_NOTE.get(k, "")
	if t == "":
		return ""
	var vs := str(int(v)) if k == "range" else _pct(v)
	return t.replace("{v}", vs).replace("{h}", _pct(v * 0.5))

## Full equipment text: [stat summary line, [note lines], [[effect name, effect body]]]. Used by the lobby gear screen.
static func equip_detail(e: Dictionary) -> Dictionary:
	var es := Stats.entry_stats(e)
	var stats := []
	var notes := []
	for k in es:
		if not STAT_NAME.has(k):
			continue
		var n: Array = STAT_NAME[k]
		stats.append("%s +%s" % [n[0], _pct(es[k]) if n[1] else str(int(es[k]))])
		if k in EQUIP_NOTE_KEYS:
			notes.append(stat_note(k, es[k]))
	var effs := []
	for x in Defs.item(e["key"]).get("effects", []):
		effs.append([EFFECT_NAME.get(x, x), EFFECT_BODY.get(x, "")])
	return {"stats": stats, "notes": notes, "effects": effs}

## Every line a relic's effect means at ★ `star` (party-wide, numbers scaled), e.g. for 가속의 태엽심장:
## "파티 전원 공격 속도 +10%" + how the tempo stacks build up and reset.
static func relic_detail(key: String, star: int) -> Array:
	var out := []
	var fx := Defs.relic_fx(key, star)
	for k in fx:
		var n: Array = Defs.RELIC_FX_NAME.get(k, [k, true, "+"])
		var line := "파티 전원 %s %s%s" % [n[0], n[2], _pct(fx[k])]
		var note := stat_note(k, fx[k])
		if note != "" and k != "atkSpeedBonus":
			line += "\n   └ " + note
		out.append(line)
	if Defs.RELICS[key].get("tempo", false):
		var step := 0.02 * Defs.relic_mult(star)
		out.append("가속: 아군이 기본 공격할 때마다 공격 속도 +%s씩 쌓여 최대 +%s (%d중첩) · 전투가 시작될 때마다 초기화" % [
			"%.1f%%" % (step * 100.0) if roundi(step * 1000.0) % 10 != 0 else _pct(step), _pct(Defs.relic_tempo_cap(star)), 15])
	return out

## Info-card rows: [bbcode, plain text (height estimate), font size, (stat value bbcode)]; size 0 is a section gap.
## Rows carrying a value are laid out as a two-column table so the numbers line up.
func _card_rows(e: Dictionary) -> Array:
	var rows := []
	match e["kind"]:
		"equip":
			var def := Defs.item(e["key"])
			var tier := int(def.get("tier", 1))
			var grade_txt := ("%s 등급" % Gear.grade_name(tier)) if Gear.is_family(e["key"]) else ("%d티어" % tier)
			_text_rows(rows, "%s  ·  %s" % [SLOT_KO.get(def.get("slot", ""), "?"), grade_txt], 18, META_COL)
			_stat_rows(rows, Stats.entry_stats(e))
			_note_rows(rows, Stats.entry_stats(e))
			_effect_rows(rows, def.get("effects", []))
		"special":
			var sd: Dictionary = Defs.SPECIAL[e["key"]]
			if sd.get("equip", false):
				_text_rows(rows, "장신구", 18, META_COL)
				_stat_rows(rows, sd["stats"])
				_note_rows(rows, sd["stats"])
				_effect_rows(rows, sd.get("effects", []))
				rows.append(["", "", 0])
				_text_rows(rows, SPECIAL_DETAIL.get(e["key"], ""), 17, META_COL)
			else:
				_text_rows(rows, SPECIAL_DETAIL.get(e["key"], sd["desc"]))
		"relic":
			var st := int(e.get("star", 1))
			_text_rows(rows, "유물  ·  ★%d / %d" % [st, Defs.RELIC_MAX_STAR], 18, META_COL)
			rows.append(["", "", 0])
			for ln in relic_detail(e["key"], st):
				_text_rows(rows, ln, 20)
			if st < Defs.RELIC_MAX_STAR:
				rows.append(["", "", 0])
				_text_rows(rows, "다음 ★%d: %s" % [st + 1, Defs.relic_desc(e["key"], st + 1)], 18, "2f78d0")
			rows.append(["", "", 0])
			_text_rows(rows, "로비 [유물]에서 장착하면 모든 판에서 파티 전체에 적용됩니다. 같은 유물 3개(같은 ★)를 모으면 합성!", 17, META_COL)
		"skillbook":
			var g := Inventory.book_grade(e)
			_text_rows(rows, "%s 스킬북 · 모든 영웅" % Defs.book_grade_name(g), 18, META_COL)
			_text_rows(rows, "[사용]하면 룰렛 %d칸이 돌아 스킬 %d개가 나오고, 그중 하나를 배웁니다" % [Defs.BOOK_PICKS, Defs.BOOK_PICKS], 21)
			var odds: Array = Defs.BOOK_ROLL.get(g, [1.0])
			var parts := []
			for k in odds.size():
				parts.append("[color=#%s]%s %d%%[/color]" % [Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(k + 1)]).darkened(0.25).to_html(false), Defs.book_grade_name(k + 1), roundi(float(odds[k]) * 100.0)])
			rows.append(["[color=#%s]등장 확률[/color]  " % BODY_COL + " · ".join(parts), "등장 확률  " + "일반 00% · ".repeat(odds.size()), 20])
			if g < Defs.BOOK_TOP:
				_text_rows(rows, "같은 등급 %d권이 모이면 가방에서 자동 합성 → %s 스킬북 (최대 %s 스킬까지)" % [Defs.BOOK_MERGE, Defs.book_grade_name(g + 1), Defs.book_grade_name(g + 1)], 19, "2f78d0")
			else:
				_text_rows(rows, "최고 등급 — 전설 스킬이 나올 수 있어요!", 19, "c87a00")
			rows.append(["", "", 0])
			_text_rows(rows, "아껴 모으면 더 높은 등급으로 · 판이 끝나면 남은 책은 강화석이 됩니다", 17, META_COL)
		"stone":
			_text_rows(rows, "로비 [장비]에서 장비 칸을 강화하는 재료입니다.\n판이 끝나면 모은 만큼 보관됩니다.", 20)
	return rows

## One stat per line, ordered offence → survival → utility; the name is tinted by its group, the value is large.
func _stat_rows(rows: Array, stats: Dictionary) -> void:
	var keys := stats.keys().filter(func(k): return STAT_NAME.has(k))
	if keys.is_empty():
		return
	keys.sort_custom(func(a, b): return STAT_GROUP.get(a, 3) < STAT_GROUP.get(b, 3))
	rows.append(["", "", 0])
	for k in keys:
		var n: Array = STAT_NAME[k]
		var v: float = stats[k]
		var val := ("+%d%%" % roundi(v * 100.0)) if n[1] else ("+%d" % int(v))
		var col: String = GROUP_COL[STAT_GROUP.get(k, 2)]
		rows.append(["[color=#%s]●  %s[/color]" % [col, n[0]], "●  %s   %s" % [n[0], val], 24,
			"[font_size=27][color=#%s]%s[/color][/font_size]" % [BODY_COL, val]])

## What the special stats do (crit / explosion / counter ...), in small text under the stat table.
func _note_rows(rows: Array, stats: Dictionary) -> void:
	var first := true
	for k in stats:
		if k in EQUIP_NOTE_KEYS:
			if first:
				rows.append(["", "", 0])
				first = false
			_text_rows(rows, "·  " + stat_note(k, stats[k]), 18, META_COL)

## Special effects: purple heading, then what it does on its own line in smaller text.
func _effect_rows(rows: Array, effs: Array) -> void:
	for x in effs:
		rows.append(["", "", 0])
		_text_rows(rows, "◆  " + EFFECT_NAME.get(x, x), 23, EFFECT_COL)
		if EFFECT_BODY.has(x):
			_text_rows(rows, EFFECT_BODY[x], 19)

func _text_rows(rows: Array, text: String, size := 20, col := BODY_COL) -> void:
	for ln in text.split("\n"):
		rows.append(["[color=#%s]%s[/color]" % [col, ln], ln, size])

func _show_tip(e: Dictionary, pinned: bool, shop := false) -> void:
	_close_tip()
	tip_entry = e
	tip_pinned = pinned
	var W := 600.0
	var rows := _card_rows(e)
	var bb := []
	var body_h := 12.0
	var text_w := W - 160.0
	var cells := ""   # pending stat table
	for r in rows + [["", "", -1]]:
		var fs: int = r[2]
		if r.size() > 3:
			cells += "[cell padding=0,2,28,2][font_size=%d]%s[/font_size][/cell][cell]%s[/cell]" % [fs, r[0], r[3]]
		elif cells != "":
			bb.append("[table=2]%s[/table]" % cells)
			cells = ""
		if fs < 0:
			break
		if fs == 0:   # section gap
			bb.append("[font_size=8] [/font_size]")
			fs = 8
		elif r.size() <= 3:
			bb.append("[font_size=%d]%s[/font_size]" % [fs, r[0]])
		var plain: String = r[1] if r[1] != "" else " "
		body_h += hud.font.get_multiline_string_size(plain, HORIZONTAL_ALIGNMENT_LEFT, text_w, maxi(fs, 27 if plain.begins_with("●") else fs)).y + 4.0
	body_h = maxf(96.0, body_h)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.scroll_active = false
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_override("normal_font", hud.font)
	body.add_theme_constant_override("line_separation", 4)
	body.text = "\n".join(bb)
	# the per-row estimate above misses wrapped lines' spacing: lay the text out at its real width and measure
	# (it needs to sit in the tree for its theme; it moves onto the card below)
	body.size = Vector2(W - 156, body_h)
	hud.root.add_child(body)
	body_h = maxf(body_h, body.get_content_height() + 10.0)
	hud.root.remove_child(body)
	var H := 70.0 + body_h + (74.0 if pinned else 40.0)
	var rarity := Inventory.rarity_of(e)
	var col: Color = Defs.RARITY_COL[rarity]
	var card := hud.panel(Color("fff4e0"), Rect2(0, 0, W, H), 22, 5)
	card.mouse_filter = Control.MOUSE_FILTER_STOP if pinned else Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(hud.place(card, Vector2(0.5, 1), Vector2(-W * 0.5, -342 - H - 12), Vector2(W, H)))
	tip = card
	# rarity-coloured header strip with the name
	var head := Panel.new()
	head.add_theme_stylebox_override("panel", rarity_box(rarity, 22, 5))
	head.size = Vector2(W, 62)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(head)
	var nm := hud.label(Inventory.name_of(e), 30, Color.WHITE, 9)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(140, 6)
	nm.size = Vector2(W - 270, 50)
	card.add_child(nm)
	var rl := hud.label(RARITY_NAME.get(rarity, ""), 22, Color.WHITE, 7)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rl.position = Vector2(W - 160 - (56 if pinned else 0), 6)
	rl.size = Vector2(140, 50)
	card.add_child(rl)
	var ib := Panel.new()
	ib.add_theme_stylebox_override("panel", rarity_box(rarity, 18, 5))
	ib.position = Vector2(14, 14)
	ib.size = Vector2(112, 104)
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ib)
	var ic := ItemIcon.new(e)
	ic.position = Vector2(8, 6)
	ic.size = Vector2(96, 92)
	ib.add_child(ic)
	body.position = Vector2(140, 70)
	body.size = Vector2(W - 156, body_h)
	card.add_child(body)
	var price := Inventory.sell_price(game, e)
	if pinned:
		var x := W - 16.0
		var sb := hud.juicy_button("판매 %dG" % price, Color("ff7a5a"), Rect2(0, 0, 170, 52), 22)
		x -= 170
		sb.position = Vector2(x, H - 64)
		sb.pressed.connect(func():
			game.sell_item(e)
			_close_tip())
		card.add_child(sb)
		if e["kind"] == "special" and not Defs.SPECIAL[e["key"]].get("equip", false) or e["kind"] == "skillbook":
			var ub := hud.juicy_button("사용", Color("27c6b0"), Rect2(0, 0, 130, 52), 24)
			x -= 142
			ub.position = Vector2(x, H - 64)
			ub.pressed.connect(func():
				_close_tip()
				game.use_item(e))
			card.add_child(ub)
		elif _equippable(e):
			var hint := hud.label("영웅에게 끌어다 놓아 장착", 18, Color("8a7a60"), 0)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			hint.position = Vector2(18, H - 60)
			hint.size = Vector2(x - 24, 44)
			card.add_child(hint)
		var cb := hud.juicy_button("X", Color("8a8aa0"), Rect2(W - 56, 9, 44, 42), 22)
		cb.pressed.connect(_close_tip)
		card.add_child(cb)
	else:
		var pl := hud.label("상인 판매 물품 · 아이콘을 다시 누르면 닫힘" if shop else "판매가 %dG · 눌러서 고정" % price, 16, Color("8a7a60"), 0)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		pl.position = Vector2(16, H - 32)
		pl.size = Vector2(W - 32, 26)
		card.add_child(pl)
	hud.pop_in(card, 0.85, 0.16)

## An item card or hero card is on screen: the field holds still while the player reads it (main._info_pause_tick).
func info_open() -> bool:
	return (tip != null and is_instance_valid(tip)) or (hero_card != null and is_instance_valid(hero_card))

func _close_tip() -> void:
	if tip and is_instance_valid(tip):
		tip.queue_free()
	tip = null
	tip_entry = {}
	tip_pinned = false

# ---------------------------------------------------------------- run settlement
## End of a run: what is kept forever (gear, gold, 강화석), then [로비로] / the mode's next step.
func settlement(r: Dictionary) -> void:
	if r.is_empty():
		return
	var tt := UiTheme.tt()
	var cleared: bool = r.get("cleared", false)
	var gear: Array = r.get("gear", [])
	var rows_h := 0.0 if gear.is_empty() else 120.0
	var card := _modal(Vector2(600, 600 + rows_h), -30, false, 0.0, tt and not cleared)
	if tt:
		var rib := Hud.Ribbon.new()
		rib.col = UiTheme.ORANGE if cleared else Color("7a4ad8")
		rib.position = Vector2(50, -26)
		rib.size = Vector2(500, 112)
		rib.pivot_offset = rib.size * 0.5
		rib.scale = Vector2(0.1, 1.2)
		card.add_child(rib)
		rib.create_tween().tween_property(rib, "scale", Vector2.ONE, 0.35).set_delay(0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var t := hud.label("원정 성공!" if cleared else ("원정 종료" if r.get("left", false) else "패배"), 76, Color.WHITE if tt else (Color("ffd23f") if cleared else Color("ff6b8a")), 18)
	t.position = Vector2(0, -24) if tt else Vector2(0, 24)
	t.size = Vector2(600, 110)
	card.add_child(t)
	var dark: bool = tt and not cleared
	var body_col := Color.WHITE if dark else Color("4a3a30")
	var sub := hud.label(str(r.get("title", "")), 32, body_col, 8 if dark else 0)
	sub.position = Vector2(0, 112)
	sub.size = Vector2(600, 50)
	card.add_child(sub)
	var head := hud.label("이번 판에서 보관한 것", 24, Color("8a7a60") if not dark else Color("c8c0e0"), 0)
	head.position = Vector2(0, 166)
	head.size = Vector2(600, 34)
	card.add_child(head)
	# gold / 강화석 chips
	var chips := [[Hud.CoinIcon.new(), "+%d" % int(r.get("gold", 0)), Defs.COL_GOLD], [Hud.StoneIcon.new(), "+%d" % int(r.get("stones", 0)), ItemIcon.STONE_COL]]
	for i in chips.size():
		var chip := hud.panel(UiTheme.inset(), Rect2(40 + i * 270, 206, 250, 70), 20, 0)
		card.add_child(chip)
		var ic: Control = chips[i][0]
		ic.position = Vector2(12, 11)
		ic.size = Vector2(48, 48)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(ic)
		var v := hud.label(chips[i][1], 38, chips[i][2], 8)
		v.position = Vector2(64, 0)
		v.size = Vector2(176, 70)
		chip.add_child(v)
	var note := []
	if int(r.get("books", 0)) > 0:
		note.append("남은 스킬북 %d권 → 강화석 %d" % [int(r["books"]), int(r["book_stones"])])
	if int(r.get("chests", 0)) > 0:
		note.append("열지 않은 상자 %d개 자동 개봉" % int(r["chests"]))
	if r.get("kept", false):
		note = ["가방(%d칸)%s은 다음 챕터로 그대로 이어져요" % [int(r.get("bag", 0)), " · 상자 %d개" % int(r["chests"]) if int(r.get("chests", 0)) > 0 else ""]]
	var nl := hud.label(" · ".join(note) if not note.is_empty() else "배운 스킬과 특성은 판이 끝나면 사라져요", 19, Color("8a7a60") if not dark else Color("c8c0e0"), 0)
	nl.position = Vector2(20, 284)
	nl.size = Vector2(560, 30)
	card.add_child(nl)
	var y := 322.0
	if not gear.is_empty():
		var gl := hud.label(("로비로 가면 장비 %d개 → 보관함" if r.get("kept", false) else "장비 %d개 → 보관함") % gear.size(), 22, body_col, 8 if dark else 0)
		gl.position = Vector2(0, y)
		gl.size = Vector2(600, 30)
		card.add_child(gl)
		var n_show := mini(gear.size(), 6)
		for i in n_show:
			var slot := Panel.new()
			slot.add_theme_stylebox_override("panel", rarity_box(Inventory.rarity_of(gear[i]), 14, 4))
			slot.position = Vector2(300 - n_show * 44 + i * 88, y + 36)
			slot.size = Vector2(80, 76)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card.add_child(slot)
			var ic := ItemIcon.new(gear[i])
			ic.position = Vector2(6, 4)
			ic.size = Vector2(68, 68)
			slot.add_child(ic)
		y += rows_h
	var label: String = game.retry_label()
	var b := hud.juicy_button(label, Color("3fa9f5"), Rect2(80, y + 24, 440, 96), 40 if label.length() <= 8 else 32)
	b.pressed.connect(func():
		hud.close_overlays()
		game.retry())
	card.add_child(b)
	var lb := hud.juicy_button("로비로", Color("8a7ad8"), Rect2(170, y + 136, 260, 80), 32)
	lb.pressed.connect(func(): game.go_lobby())
	card.add_child(lb)
	for bt in [b, lb]:
		bt.scale = Vector2.ZERO
		var tw: Tween = bt.create_tween()
		tw.tween_interval(0.5)
		tw.tween_property(bt, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- merchant
var merchant_stock: Array = []

func merchant(reuse := false) -> bool:
	if not reuse or merchant_stock.is_empty():
		merchant_stock = game.merchant_items()
	_merchant_card(false)
	# keep the bag usable for selling while shopping
	hud.root.move_child(inv_panel, -1)
	hud.overlay_closed.connect(func():
		if is_instance_valid(inv_panel):
			hud.root.move_child(inv_panel, 1), CONNECT_ONE_SHOT)
	if game.autoplay:
		game.get_tree().create_timer(1.0).timeout.connect(func(): hud.close_overlays())
	return true

func _merchant_card(replace := true) -> void:
	_close_tip()
	var tt := UiTheme.tt()
	var card := _modal(Vector2(660, 640), -170, replace, 80.0)
	var t := hud.label("떠돌이 상인", 48 if tt else 52, Color.WHITE if tt else Color("ffd27a"), 14)
	t.position = Vector2(0, 6 if tt else 14)
	t.size = Vector2(660, 70)
	card.add_child(t)
	var g := hud.label("보유 골드 %d" % game.gold, 26, Defs.COL_GOLD, 8)
	g.position = Vector2(0, 84 if tt else 80)
	g.size = Vector2(660, 36)
	card.add_child(g)
	for i in 4:
		var x := 22.0 + (i % 2) * 314.0
		var y := 124.0 + (i / 2) * 200.0
		var slot := hud.panel(UiTheme.inset(), Rect2(x, y, 302, 188), 18, 0)
		card.add_child(slot)
		if i >= merchant_stock.size() or merchant_stock[i] == null:
			var so := hud.label("판매 완료", 26, Color("b0a890"), 0)
			so.size = Vector2(302, 188)
			slot.add_child(so)
			continue
		var it: Dictionary = merchant_stock[i]
		var e: Dictionary = it["entry"]
		var col: Color = Defs.RARITY_COL[Inventory.rarity_of(e)]
		slot.add_theme_stylebox_override("panel", rarity_box(Inventory.rarity_of(e), 18, 4))
		var ic := ItemIcon.new(e)
		ic.position = Vector2(10, 10)
		ic.size = Vector2(84, 84)
		slot.add_child(ic)
		# the card only has room for a summary: hover / tap the icon for the full item card
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		ic.tooltip_text = ""
		ic.mouse_entered.connect(func(): _show_tip(e, false, true))
		ic.mouse_exited.connect(func():
			if tip_entry == e:
				_close_tip())
		ic.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if tip and tip_entry == e:
					_close_tip()
				else:
					_show_tip(e, false, true))
		var info := hud.label("ⓘ 정보", 15, Color.WHITE, 5)
		info.position = Vector2(10, 94)
		info.size = Vector2(84, 24)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(info)
		var nm := hud.label(Inventory.name_of(e), 22, Color.WHITE, 8)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.position = Vector2(100, 8)
		nm.size = Vector2(196, 56)
		slot.add_child(nm)
		var ds := hud.label(describe(e), 15, Color.WHITE, 5)
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		ds.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.position = Vector2(100, 62)
		ds.size = Vector2(196, 60)
		slot.add_child(ds)
		var price: int = it["price"]
		var b := hud.juicy_button("%dG" % price, Color("27c6b0") if game.gold >= price else Color("a0a0b0"), Rect2(60, 128, 182, 52), 26)
		var idx := i
		b.pressed.connect(func():
			if game.buy_merchant(idx):
				_merchant_card())
		slot.add_child(b)
	var rr := hud.juicy_button("새로고침 300G", Color("6f6cf0"), Rect2(40, 540, 270, 76), 26)
	rr.pressed.connect(func():
		if game.gold >= 300:
			game.gold -= 300
			game.hud.set_gold(game.gold)
			merchant_stock = game.merchant_items()
			Sfx.play("whoosh", -6.0, 1.2)
			_merchant_card()
		else:
			hud.toast("골드가 부족해요!"))
	card.add_child(rr)
	var go := hud.juicy_button("떠나기", Color("ff9f1c"), Rect2(350, 540, 270, 76), 30)
	go.pressed.connect(func(): hud.close_overlays())
	card.add_child(go)
	if replace:
		hud.root.move_child(inv_panel, -1)

# ---------------------------------------------------------------- hero detail panel
const CLASS_COL := {"warrior": Color("ff7a5a"), "ranger": Color("5fcf5a"), "mage": Color("a77aff")}
const SLOT_NAME := {"weapon": "무기", "armor": "방어구", "accessory": "장신구"}

var hero_card: Control
var hero_shown: Actor
var equip_slot_rects := {}     # slot -> Rect2 (global) for drag & drop

func hero_panel(h: Actor) -> void:
	if hero_card and is_instance_valid(hero_card):
		hero_card.queue_free()
	hero_card = null
	hero_shown = h
	equip_slot_rects.clear()
	if h == null:
		return
	var W := 680.0
	var H := 452.0
	var card := hud.panel(Color("fff4e0"), Rect2(0, 0, W, H), 26, 5)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(hud.place(card, Vector2(0.5, 0), Vector2(-W * 0.5, 236), Vector2(W, H)))
	hero_card = card
	var col: Color = CLASS_COL[h.cls]
	var head := hud.panel(col, Rect2(0, 0, W, 74), 26, 5)
	card.add_child(head)
	var nm := hud.label(h.def["name"], 40)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(26, 6)
	nm.size = Vector2(220, 62)
	card.add_child(nm)
	var lv := hud.panel(Defs.COL_GOLD, Rect2(200, 16, 96, 42), 14, 4)
	card.add_child(lv)
	var lvl := hud.label("Lv.%d" % h.level, 28, Color("5a3a00"), 0)
	lvl.size = Vector2(96, 42)
	lv.add_child(lvl)
	# exp bar
	var need: int = h.level * 40
	var eb := hud.panel(UiTheme.ink(), Rect2(320, 22, 250, 30), 12, 0)
	card.add_child(eb)
	var ef := hud.panel(Defs.COL_EXP, Rect2(3, 3, 244.0 * clampf(float(h.exp) / need, 0.0, 1.0), 24), 10, 0)
	eb.add_child(ef)
	var el := hud.label("EXP %d/%d" % [h.exp, need], 18, Color.WHITE, 6)
	el.size = Vector2(250, 30)
	eb.add_child(el)
	var close := hud.juicy_button("X", Color("ff6b8a"), Rect2(W - 70, 12, 52, 50), 26)
	close.pressed.connect(func(): game._select(null))
	card.add_child(close)
	# stats
	var stats := [
		["체력", "%d/%d" % [int(ceilf(h.hp)), int(h.max_hp)], Color("ff6b8a")],
		["공격력", str(Stats.attack_power(game, h)), Color("ffb43c")],
		["사거리", str(int(Stats.attack_range(game, h))), Color("5fb4ff")],
		["공속", "%.2f초" % Stats.attack_interval(game, h), Color("8fe36a")],
	]
	for i in stats.size():
		var chip := hud.panel(UiTheme.inset(), Rect2(20 + i * 162, 86, 152, 58), 14, 0)
		card.add_child(chip)
		var k := hud.label(stats[i][0], 18, stats[i][2], 5)
		k.size = Vector2(152, 24)
		k.position = Vector2(0, 2)
		chip.add_child(k)
		var v := hud.label(stats[i][1], 26, Color.WHITE, 7)
		v.size = Vector2(152, 32)
		v.position = Vector2(0, 24)
		chip.add_child(v)
	# equipment
	var x := 20.0
	for slot in ["weapon", "armor", "accessory"]:
		var e = h.equipment[slot]
		var border: Color = Defs.RARITY_COL[Inventory.rarity_of(e)] if e else Color("c8c0b0")
		var sb := hud.panel(Color("ffffff"), Rect2(x, 156, 150, 72), 14, 4)
		sb.add_theme_stylebox_override("panel", rarity_box(Inventory.rarity_of(e)) if e else hud.box(Color("efe6d4"), 14, 4, border))
		if e:
			sb.mouse_filter = Control.MOUSE_FILTER_PASS
			var ee: Dictionary = e
			sb.mouse_entered.connect(func():
				if not tip_pinned and drag_ghost == null:
					_show_tip(ee, false))
			sb.mouse_exited.connect(func():
				if not tip_pinned:
					_close_tip())
		card.add_child(sb)
		var sl := hud.label(SLOT_NAME[slot], 16, Color.WHITE if e else Color("8a7a60"), 5 if e else 0)
		sl.size = Vector2(150, 22)
		sl.position = Vector2(0, 2)
		sb.add_child(sl)
		var it := hud.label(Inventory.name_of(e) if e else "비어 있음", 19, Color.WHITE if e else Color("b0a890"), 7 if e else 0)
		it.size = Vector2(146, 44)
		it.position = Vector2(2, 24)
		it.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sb.add_child(it)
		var slv := Stats.slot_level(h, slot, e) if e else 0
		if slv > 0:   # permanent slot level (lobby 강화)
			var lvb := hud.panel(ItemIcon.STONE_COL, Rect2(96, -12, 58, 28), 12, 3)
			sb.add_child(lvb)
			var lvl2 := hud.label("+%d" % slv, 17, Color.WHITE, 6)
			lvl2.size = Vector2(58, 28)
			lvb.add_child(lvl2)
		equip_slot_rects[slot] = sb
		x += 160.0
	var nb: int = game.books_for(h.cls)
	var spb := hud.panel(Color("c84ad8") if nb > 0 else Color("b0a8c0"), Rect2(510, 156, 150, 72), 16, 4)
	card.add_child(spb)
	var spl := hud.label("스킬북\n%d권" % nb, 22, Color.WHITE, 7)
	spl.size = Vector2(150, 72)
	spb.add_child(spl)
	# skills learned from books (Defs.SKILL_SLOTS slots)
	for i in Defs.SKILL_SLOTS:
		var y := 238.0 + i * 43.0
		var row := hud.panel(UiTheme.inset(), Rect2(20, y, W - 40, 39), 12, 0)
		card.add_child(row)
		if i >= h.learned.size():
			var el2 := hud.label("빈 칸 — 전투에서 스킬북을 얻어 사용하세요", 17, Color("b0a890"), 0)
			el2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			el2.position = Vector2(14, 0)
			el2.size = Vector2(W - 70, 39)
			row.add_child(el2)
			continue
		var cur: Dictionary = h.learned[i]
		var sdef := Defs.book(cur["id"])
		var gcol: Color = Defs.RARITY_COL[Defs.book_rarity(int(sdef["grade"]))]
		var gem := hud.panel(gcol, Rect2(8, 7, 25, 25), 12, 3)
		row.add_child(gem)
		var sn := hud.label(sdef["name"], 21, Color.WHITE, 7)
		sn.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		sn.position = Vector2(42, 0)
		sn.size = Vector2(170, 39)
		row.add_child(sn)
		var lvl3 := hud.label("Lv.%d" % int(cur["level"]), 18, Defs.COL_GOLD, 6)
		lvl3.position = Vector2(196, 0)
		lvl3.size = Vector2(52, 39)
		row.add_child(lvl3)
		for p2 in Defs.BOOK_MAX:
			var pip := hud.panel(Defs.COL_GOLD if p2 < int(cur["level"]) else Color("d8d0c0"), Rect2(250 + p2 * 11, 15, 9, 9), 4, 2)
			row.add_child(pip)
		var sd := hud.label("레벨당 " + sdef["desc"], 15, Color("6a5a48"), 0)
		sd.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		sd.position = Vector2(312, 0)
		sd.size = Vector2(W - 362, 39)
		sd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(sd)
	# active skill & ultimate
	var a: Dictionary = Defs.ACTIVE_SKILLS[h.cls]
	var u: Dictionary = Defs.ULTIMATES[h.cls]
	var al := hud.label("고유 · %s  |  궁극기 · %s (%s)" % [a["name"], u["name"], "자동" if game.mode_id() == "march" else "길게 누르기"], 19, Color("3a6aa0"), 0)
	al.position = Vector2(0, 414)
	al.size = Vector2(W, 30)
	card.add_child(al)
	hud.pop_in(card, 0.85, 0.25)
