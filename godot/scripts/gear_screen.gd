class_name GearScreen
extends Control
## Lobby [장비] screen: the permanent gear meta (Meta).
##   - hero tabs; each hero's weapon / armor / accessory slot shows what it wears and its slot level.
##     [강화] raises the slot level with banked gold + 강화석 (Gear.upgrade_cost, capped by the worn grade);
##     holding it repeats (faster and faster) until released or out of gold / 강화석 / grade cap. Each level pops
##     the slot (punch, flash, ray burst, sparkles, rising "Lv.N"). The card updates in place, so the held button lives on.
##     Tapping the worn piece shows it in the detail bar, where [해제] takes it off (back to storage).
##     The level belongs to the slot: whatever is worn there in a run (even a piece picked up mid-run) gets it.
##   - storage grid: tap a piece to see it, then [장착] (onto the selected hero) or [판매].
##     [모두 합성] merges every group of three (same slot + grade -> next grade, Meta.merge_all), then the
##     MergeFx cutscene plays each merge (RelicScreen, the lobby [유물] screen, reuses this screen's helpers).
## Built over the lobby on its own canvas layer; closes with X / Esc.

signal closed

var font: Font
var INK: Color = UiTheme.ink()
var cls := "warrior"
var picked := {}          # storage entry (or the worn piece, see picked_slot) shown in the detail bar
var picked_slot := ""     # slot of the selected hero whose worn piece is shown ("" = a storage piece)
var _cards := {}          # slot -> {card, ib, lvl, bonus, btn} (updated in place on upgrade)
var _gold_l: Label
var _stone_l: Label
var _hold_slot := ""      # [강화] held down on this slot: repeats while held
var _hold_wait := 0.0
var _hold_n := 0          # levels gained in this hold (speeds the repeat up, raises the chime)
var _body: Control
var _toast_l: Label
var _toast_tw: Tween
var _fx: MergeFx          # merge cutscene (while it plays)

const CLASS_COL := {"warrior": Color("ff7a5a"), "ranger": Color("5fcf5a"), "mage": Color("a77aff")}
const SLOT_KO := {"weapon": "무기", "armor": "방어구", "accessory": "장신구"}
const W := 720.0
const HOLD_DELAY := 0.38   # first repeat after the press
const HOLD_STEP := 0.13    # repeat interval, shrinking toward HOLD_MIN as the hold goes on
const HOLD_MIN := 0.05

func open(p_font: Font) -> void:
	font = p_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.14, 0.92)
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body = Control.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_body)
	_body.anchor_left = 0.5
	_body.anchor_right = 0.5
	_body.offset_left = -W * 0.5
	_body.offset_right = W * 0.5
	_body.offset_top = 0.0
	_body.offset_bottom = 1280.0
	_rebuild()
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.18)

func close() -> void:
	Sfx.play("click", -6.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.15)
	tw.tween_callback(func():
		closed.emit()
		queue_free())

func _input(ev: InputEvent) -> void:
	# a held [강화] stops on any release, even off the button
	if _hold_slot != "" and ((ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT) or (ev is InputEventScreenTouch and not ev.pressed)):
		_hold_stop()

func _process(delta: float) -> void:
	if _hold_slot == "":
		return
	_hold_wait -= delta
	if _hold_wait <= 0.0 and _try_upgrade(_hold_slot, false):
		_hold_wait = maxf(HOLD_MIN, HOLD_STEP - _hold_n * 0.008)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if _fx == null:
			close()

# ---------------------------------------------------------------- layout
func _rebuild() -> void:
	_hold_stop()
	_cards.clear()
	for c in _body.get_children():
		c.queue_free()
	var title := _label("장비", 60, UiTheme.TXT_YELLOW if UiTheme.tt() else Color("ffd23f"), 14)
	title.position = Vector2(0, 22)
	title.size = Vector2(W, 80)
	_body.add_child(title)
	var x := _button("X", Color("8a8aa0"), Rect2(W - 92, 28, 70, 66), 34)
	x.pressed.connect(close)
	_body.add_child(x)
	# banked currencies
	_gold_l = _pill(Rect2(40, 112, 300, 60), Hud.CoinIcon.new(), str(Meta.gold), Defs.COL_GOLD)
	_stone_l = _pill(Rect2(380, 112, 300, 60), Hud.StoneIcon.new(), str(Meta.stones), ItemIcon.STONE_COL)
	# hero tabs
	var i := 0
	for c in Defs.HERO_ORDER:
		var on: bool = c == cls
		var b := _button(Defs.HEROES[c]["name"], CLASS_COL[c] if on else Color("5a5478"), Rect2(40 + i * 220, 192, 200, 70), 30)
		var cc: String = c
		b.pressed.connect(func():
			cls = cc
			picked_slot = ""
			Sfx.play("click", -6.0)
			_rebuild())
		_body.add_child(b)
		i += 1
	# slots
	for si in Meta.SLOTS.size():
		_slot_card(Meta.SLOTS[si], Rect2(28 + si * 226, 282, 212, 330))
	_storage(Rect2(28, 632, W - 56, 470))
	_detail(Rect2(28, 1112, W - 56, 150))
	_toast_l = _label("", 26, Color("fff2b0"), 8)
	_toast_l.position = Vector2(0, 1060)
	_toast_l.size = Vector2(W, 40)
	_body.add_child(_toast_l)

func _slot_card(slot: String, r: Rect2) -> void:
	var e = Meta.worn(cls, slot)
	var card := Panel.new()
	card.position = r.position
	card.size = r.size
	card.add_theme_stylebox_override("panel", UiTheme.night_card(22) if UiTheme.tt() else _box(Color("4c467b"), 22, 5))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(card)
	var sl := _label(SLOT_KO[slot], 24, Color.WHITE, 8)
	sl.position = Vector2(0, 8)
	sl.size = Vector2(r.size.x, 34)
	card.add_child(sl)
	var sel: bool = e != null and picked_slot == slot
	var ib := Panel.new()
	ib.position = Vector2(r.size.x * 0.5 - 56, 46)
	ib.size = Vector2(112, 104)
	ib.pivot_offset = ib.size * 0.5
	var ist: StyleBox = _rarity_box(Inventory.rarity_of(e)) if e else UiTheme.empty_slot(16)
	if sel:
		var hi := (ist as StyleBoxFlat).duplicate() as StyleBoxFlat
		hi.border_color = Color("fff27a")
		hi.set_border_width_all(6)
		ist = hi
	ib.add_theme_stylebox_override("panel", ist)
	ib.mouse_filter = Control.MOUSE_FILTER_STOP
	card.add_child(ib)
	if e:
		var ic := ItemIcon.new(e)
		ic.position = Vector2(8, 6)
		ic.size = Vector2(96, 92)
		ib.add_child(ic)
		ib.gui_input.connect(func(ev: InputEvent):   # tap the worn piece: show it in the detail bar ([해제] there)
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				Sfx.play("click", -8.0, 1.3)
				if picked_slot == slot:
					picked_slot = ""
					picked = {}
				else:
					picked_slot = slot
					picked = e
				_rebuild())
	var nm := _label(Inventory.name_of(e) if e else "비어 있음", 20, Color.WHITE if e else Color("a9a4cb"), 7 if e else 0)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(6, 152)
	nm.size = Vector2(r.size.x - 12, 50)
	card.add_child(nm)
	var lvl := _label("", 24, ItemIcon.STONE_COL.lightened(0.3), 8)
	lvl.position = Vector2(0, 202)
	lvl.size = Vector2(r.size.x, 32)
	lvl.pivot_offset = lvl.size * 0.5
	card.add_child(lvl)
	var bl := _label("", 18, Color("cfe8ff"), 6)
	bl.position = Vector2(0, 232)
	bl.size = Vector2(r.size.x, 26)
	bl.pivot_offset = bl.size * 0.5
	card.add_child(bl)
	var ub := _button("", Color("27c6b0"), Rect2(10, 266, r.size.x - 20, 54), 26)
	ub.button_down.connect(func(): _hold_start(slot))
	ub.button_up.connect(_hold_stop)
	card.add_child(ub)
	_cards[slot] = {"card": card, "ib": ib, "lvl": lvl, "bonus": bl, "btn": ub}
	_refresh_slot(slot)

## Level, bonus and [강화] button of one slot card, from Meta (no rebuild: a held button must survive).
func _refresh_slot(slot: String) -> void:
	var cd: Dictionary = _cards[slot]
	var e = Meta.worn(cls, slot)
	var lv := Meta.slot_level(cls, slot)
	var cap := Gear.slot_cap(e)
	(cd["lvl"] as Label).text = "칸 Lv.%d%s" % [lv, (" / %d" % cap) if e else ""]
	var bonus := Gear.slot_bonus(slot, mini(lv, cap))
	var parts := []
	for k in bonus:
		parts.append("%s +%d" % ["공격력" if k == "atk" else "체력", int(bonus[k])])
	(cd["bonus"] as Label).text = " · ".join(parts) if not parts.is_empty() else "강화 보너스 없음"
	var why := Meta.can_upgrade(cls, slot)
	var c := Gear.upgrade_cost(lv)
	var txt := "강화"
	match why:
		"empty": txt = "장비 없음"
		"cap": txt = "등급 한계"
		_: txt = "%dG · ◆%d" % [int(c["gold"]), int(c["stones"])]
	var ub: Button = cd["btn"]
	ub.text = txt
	ub.add_theme_font_size_override("font_size", 22 if txt.length() > 6 else 26)
	var col := Color("27c6b0") if why == "" else Color("6e6a8c")
	if ub.get_meta("col", Color.BLACK) != col:
		ub.set_meta("col", col)
		_paint(ub, col)

# ---------------------------------------------------------------- [강화] (tap = +1, hold = repeat)
func _hold_start(slot: String) -> void:
	if _fx != null:
		return
	_hold_slot = slot
	_hold_n = 0
	_hold_wait = HOLD_DELAY
	_try_upgrade(slot, true)

func _hold_stop() -> void:
	_hold_slot = ""

## One level on `slot`; false (and the hold ends) when it can't. The reason is told on a fresh press
## or when a hold runs dry, not again for every repeat.
func _try_upgrade(slot: String, first: bool) -> bool:
	if not Meta.upgrade(cls, slot):
		if first or _hold_n > 0:
			Sfx.play("click", -6.0, 0.7)
			_say({"gold": "골드가 부족해요", "stones": "강화석이 부족해요", "cap": "장비 등급을 올려야 더 강화할 수 있어요", "empty": "먼저 장비를 끼워 주세요"}.get(Meta.can_upgrade(cls, slot), ""))
		_hold_stop()
		return false
	_hold_n += 1
	Sfx.play("chime", -4.0, 1.15 + minf(_hold_n - 1, 12) * 0.035)
	for sl in _cards:
		_refresh_slot(sl)   # gold / 강화석 dropped: other buttons may grey out
	_gold_l.text = str(Meta.gold)
	_stone_l.text = str(Meta.stones)
	_level_fx(slot)
	_say("%s 칸 Lv.%d!" % [SLOT_KO[slot], Meta.slot_level(cls, slot)])
	return true

## Short level-up burst on the slot card: item punch + white flash, ray burst behind, sparkles,
## "Lv.N" rising from the icon, level / bonus text pop, spent currencies tick.
func _level_fx(slot: String) -> void:
	var cd: Dictionary = _cards[slot]
	var card: Panel = cd["card"]
	var ib: Panel = cd["ib"]
	var c := ib.position + ib.size * 0.5
	ib.scale = Vector2.ONE * 1.28
	Hud.retween(ib).tween_property(ib, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# white flash over the item box (one per slot, softer while a hold repeats so the icon stays visible)
	var oldfl = cd.get("flash")
	if oldfl != null and is_instance_valid(oldfl):
		oldfl.queue_free()
	var fl := Panel.new()
	cd["flash"] = fl
	fl.add_theme_stylebox_override("panel", UiTheme.flat(Color(1, 1, 1, 0.85 if _hold_n <= 1 else 0.45), 16, 0, Color(0, 0, 0, 0)))
	fl.size = ib.size
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.add_child(fl)
	var ft := fl.create_tween()
	ft.tween_property(fl, "modulate:a", 0.0, 0.28).set_ease(Tween.EASE_OUT)
	ft.tween_callback(fl.queue_free)
	# ray burst behind the box (one per slot: a rapid repeat restarts it)
	var old = cd.get("ray")
	if old != null and is_instance_valid(old):
		old.queue_free()
	var ray := Hud.RayBurst.new()
	ray.col = Color("8ff0ff")
	ray.size = Vector2(230, 230)
	ray.position = c - ray.size * 0.5
	ray.pivot_offset = ray.size * 0.5
	ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ray.scale = Vector2.ONE * 0.35
	card.add_child(ray)
	card.move_child(ray, ib.get_index())
	cd["ray"] = ray
	var rt := ray.create_tween().set_parallel(true)
	rt.tween_property(ray, "scale", Vector2.ONE * 1.05, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rt.tween_property(ray, "rotation", 0.6, 0.5)
	rt.tween_property(ray, "modulate:a", 0.0, 0.25).set_delay(0.25)
	rt.chain().tween_callback(ray.queue_free)
	# sparkles (fewer while a hold is racing)
	var n := 6 if _hold_n <= 1 else 3
	for i in n:
		var sp := Hud.Sparkle.new()
		sp.size = Vector2(22, 22)
		sp.pivot_offset = sp.size * 0.5
		sp.position = c - sp.size * 0.5
		sp.col = [UiTheme.TXT_YELLOW, Color.WHITE, Color("8ff0ff")][i % 3]
		sp.scale = Vector2.ZERO
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(sp)
		var a := TAU * (i + randf() * 0.6) / n
		var dest := sp.position + Vector2(cos(a), sin(a)) * randf_range(62.0, 96.0)
		var st := sp.create_tween().set_parallel(true)
		st.tween_property(sp, "scale", Vector2.ONE * randf_range(0.7, 1.1), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		st.tween_property(sp, "position", dest, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		st.tween_property(sp, "rotation", randf_range(-2.5, 2.5), 0.5)
		st.tween_property(sp, "modulate:a", 0.0, 0.2).set_delay(0.3)
		st.chain().tween_callback(sp.queue_free)
	# "Lv.N" rising from the icon (one per slot)
	var oldf = cd.get("float")
	if oldf != null and is_instance_valid(oldf):
		oldf.queue_free()
	var up := _label("Lv.%d" % Meta.slot_level(cls, slot), 32, UiTheme.TXT_YELLOW if UiTheme.tt() else Color("ffd23f"), 10)
	up.size = Vector2(card.size.x, 40)
	up.position = Vector2(0, ib.position.y + 10)
	up.pivot_offset = up.size * 0.5
	up.scale = Vector2.ONE * 0.5
	card.add_child(up)
	cd["float"] = up
	var ut := up.create_tween().set_parallel(true)
	ut.tween_property(up, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	ut.tween_property(up, "position:y", ib.position.y - 36, 0.55).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	ut.tween_property(up, "modulate:a", 0.0, 0.2).set_delay(0.45)
	ut.chain().tween_callback(up.queue_free)
	# level / bonus text pop with a yellow flash
	for k in ["lvl", "bonus"]:
		var l: Label = cd[k]
		l.scale = Vector2.ONE * (1.4 if k == "lvl" else 1.2)
		l.modulate = Color(1.0, 0.95, 0.45)
		var lt := Hud.retween(l).set_parallel(true)
		lt.tween_property(l, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		lt.tween_property(l, "modulate", Color.WHITE, 0.35)
	for l in [_gold_l, _stone_l]:
		l.pivot_offset = l.size * 0.5
		l.scale = Vector2.ONE * 0.85
		Hud.retween(l).tween_property(l, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _storage(r: Rect2) -> void:
	var box := Panel.new()
	box.position = r.position
	box.size = r.size
	box.add_theme_stylebox_override("panel", UiTheme.deck_panel(22, 64.0) if UiTheme.tt() else _box(Color("3a3560"), 22, 5))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(box)
	var t := _label("보관함 %d" % Meta.storage.size(), 30, Color.WHITE, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	t.position = Vector2(22, 8)
	t.size = Vector2(300, 50)
	box.add_child(t)
	var ready := Meta.merge_ready()
	var mb := _button("모두 합성 (%d)" % ready if ready > 0 else "합성할 것 없음", Color("ff9f1c") if ready > 0 else Color("6e6a8c"), Rect2(r.size.x - 290, 6, 274, 54), 26)
	mb.pressed.connect(func():
		var steps := Meta.merge_all()
		if steps.is_empty():
			Sfx.play("click", -6.0, 0.7)
			_say("같은 부위·같은 등급 3개가 모이면 합성할 수 있어요")
			return
		picked = steps[-1]["out"]
		_play_merge(steps))
	box.add_child(mb)
	var sc := ScrollContainer.new()
	sc.position = Vector2(14, 72)
	sc.size = Vector2(r.size.x - 28, r.size.y - 84)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(sc)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)
	var list: Array = Meta.storage.duplicate()
	var order := {"weapon": 0, "armor": 1, "accessory": 2}
	list.sort_custom(func(a, b):
		var sa: int = order.get(Defs.item(a["key"]).get("slot", ""), 3)
		var sb: int = order.get(Defs.item(b["key"]).get("slot", ""), 3)
		if sa != sb:
			return sa < sb
		return Inventory.tier_of(a) > Inventory.tier_of(b))
	if list.is_empty():
		var em := _label("비어 있어요 — 원정에서 얻은 장비가 여기에 모입니다", 20, Color("a9a4cb"), 0)
		em.position = Vector2(0, 160)
		em.size = Vector2(r.size.x, 40)
		box.add_child(em)
	for e in list:
		var cell := Panel.new()
		cell.custom_minimum_size = Vector2(98, 92)
		var sel: bool = e == picked
		var st := _rarity_box(Inventory.rarity_of(e))
		if sel:
			st.border_color = Color("fff27a")
			st.set_border_width_all(6)
		cell.add_theme_stylebox_override("panel", st)
		cell.mouse_filter = Control.MOUSE_FILTER_STOP
		var ic := ItemIcon.new(e)
		ic.position = Vector2(7, 5)
		ic.size = Vector2(84, 80)
		cell.add_child(ic)
		var ee: Dictionary = e
		cell.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				picked = ee
				Sfx.play("click", -8.0, 1.3)
				_rebuild())
		grid.add_child(cell)

func _detail(r: Rect2) -> void:
	var box := Panel.new()
	box.position = r.position
	box.size = r.size
	box.add_theme_stylebox_override("panel", UiTheme.cream_card(22) if UiTheme.tt() else _box(Color("fff4e0"), 22, 5))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(box)
	var worn_view: bool = picked_slot != "" and not picked.is_empty() and Meta.worn(cls, picked_slot) == picked
	if not worn_view:
		picked_slot = ""
	if picked.is_empty() or not (worn_view or Meta.storage.has(picked)):
		picked = {}
		var h := _label("장비를 눌러 정보를 보세요 (장착한 장비는 여기서 해제)", 21, Color("6a5a48"), 0)
		h.size = r.size
		box.add_child(h)
		return
	var e := picked
	var ib := Panel.new()
	ib.position = Vector2(14, 14)
	ib.size = Vector2(122, 122)
	ib.add_theme_stylebox_override("panel", _rarity_box(Inventory.rarity_of(e)))
	box.add_child(ib)
	var ic := ItemIcon.new(e)
	ic.position = Vector2(8, 8)
	ic.size = Vector2(106, 106)
	ib.add_child(ic)
	var def := Defs.item(e["key"])
	var nm := _label(Inventory.label_of(e), 26, Defs.RARITY_COL[Inventory.rarity_of(e)].darkened(0.35), 0)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(150, 8)
	nm.size = Vector2(300, 40)
	box.add_child(nm)
	var info := HudPanels.equip_detail(e)
	var sl := _label("%s · %s" % [SLOT_KO.get(def.get("slot", ""), "?"), "  ".join(info["stats"])], 18, Color("4a3a30"), 0)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sl.position = Vector2(150, 50)
	sl.size = Vector2(300, 90)
	box.add_child(sl)
	var more := []
	for n in info["notes"]:
		more.append("·  " + n)
	for x in info["effects"]:
		more.append("◆ %s — %s" % [x[0], x[1].replace("\n", " ")])
	_grow_detail(box, r, more)
	if worn_view:   # the selected hero wears it: only [해제]
		var tag := _label("장착 중 · %s" % Defs.HEROES[cls]["name"], 18, CLASS_COL[cls].darkened(0.3), 0)
		tag.position = Vector2(r.size.x - 200, 84)
		tag.size = Vector2(186, 40)
		box.add_child(tag)
		var ob := _button("해제", Color("ff7a5a"), Rect2(r.size.x - 200, 14, 186, 66), 28)
		var ps := picked_slot
		ob.pressed.connect(func():
			Meta.take_off(cls, ps)
			picked_slot = ""   # keep it picked: it now sits in storage, ready to [장착] / [판매]
			Sfx.play("pop", -6.0, 0.9)
			_rebuild()
			_say("%s 해제" % Inventory.name_of(e)))
		box.add_child(ob)
		return
	var eb := _button("장착", Color("27c6b0"), Rect2(r.size.x - 200, 14, 186, 60), 28)
	eb.pressed.connect(func():
		Meta.wear(cls, e)
		picked = {}
		Sfx.play("chime", -6.0, 1.4)
		_rebuild()
		_say("%s → %s" % [Inventory.name_of(e), Defs.HEROES[cls]["name"]]))
	box.add_child(eb)
	var price := Inventory.sell_price(null, e)
	var sb := _button("판매 %dG" % price, Color("ff7a5a"), Rect2(r.size.x - 200, 80, 186, 56), 24)
	sb.pressed.connect(func():
		var g := Meta.sell(e)
		picked = {}
		Sfx.play("tick", -4.0, 1.4)
		_rebuild()
		_say("+%dG" % g))
	box.add_child(sb)

## The merges already happened (Meta); the screen behind is rebuilt with the results and the cutscene plays on top.
func _play_merge(steps: Array) -> void:
	_rebuild()
	_fx = MergeFx.play(self, font, steps)
	_fx.finished.connect(func():
		_fx = null
		var last: Dictionary = steps[-1]["out"]
		var nm := Inventory.name_of(last)
		if last["kind"] == "relic":
			nm += "  ★%d" % int(last["star"])
		_say("합성 %d회! %s" % [steps.size(), nm]))

func _say(t: String) -> void:
	if _toast_l == null or not is_instance_valid(_toast_l):
		return
	_toast_l.text = t
	_toast_l.modulate.a = 1.0
	if _toast_tw:
		_toast_tw.kill()   # a fresh toast restarts the hold instead of being faded by the previous one
	_toast_tw = _toast_l.create_tween()
	_toast_tw.tween_interval(1.4)
	_toast_tw.tween_property(_toast_l, "modulate:a", 0.0, 0.4)

# ---------------------------------------------------------------- style helpers
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

## Detail bar (anchored to the bottom of `r`): when the picked item has more to say than the 150 px header holds
## (special stats, effects, relic mechanics), list every line under the header and grow the bar upward to fit.
func _grow_detail(box: Panel, r: Rect2, lines: Array, fsize := 18) -> void:
	if lines.is_empty():
		return
	var tw := r.size.x - 36.0
	var h := 0.0
	for ln in lines:
		h += font.get_multiline_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, tw, fsize).y + 4.0
	var l := _label("\n".join(lines), fsize, Color("5a3a8a"), 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.label_settings.line_spacing = 4.0
	l.position = Vector2(18, 146)
	l.size = Vector2(tw, h)
	box.add_child(l)
	var full := 146.0 + h + 14.0
	box.size = Vector2(r.size.x, maxf(r.size.y, full))
	box.position = Vector2(r.position.x, r.end.y - box.size.y)
	box.mouse_filter = Control.MOUSE_FILTER_STOP   # covers the bottom of the grid: taps must not reach hidden cells

func _box(color: Color, radius := 12, border := 4) -> StyleBoxFlat:
	return UiTheme.flat(color, radius, border, INK)

func _rarity_box(rarity: String) -> StyleBoxFlat:
	var c: Color = Defs.RARITY_COL.get(rarity, Color("c8ccd8"))
	return UiTheme.flat(c.darkened(0.15), 16, 4, INK)

func _button(text: String, col: Color, r: Rect2, fsize := 28) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.text = text
	b.position = r.position
	b.size = r.size
	b.add_theme_font_override("font", font)
	b.add_theme_font_size_override("font_size", fsize)
	_paint(b, col)
	return b

func _paint(b: Button, col: Color) -> void:
	var tt := UiTheme.tt()
	for st in ["normal", "hover", "pressed"]:
		if tt:
			b.add_theme_stylebox_override(st, UiTheme.button_box(col.lightened(0.08 if st == "hover" else 0.0), 18, st == "pressed"))
		else:
			b.add_theme_stylebox_override(st, _box(col.lightened(0.1 if st == "hover" else 0.0), 20, 5))
	# 뚜까펫: role text colour (dark on yellow, white elsewhere). text_color() maps cream-card text colours, so it
	# returned the button's own colour here and the label vanished into the button.
	var dark := tt and UiTheme.button_role(col) == "yellow"
	var tc := UiTheme.button_text("yellow") if dark else Color.WHITE
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, tc)
	if not dark:
		b.add_theme_color_override("font_outline_color", INK)
		b.add_theme_constant_override("outline_size", 8)
	else:
		b.remove_theme_color_override("font_outline_color")
		b.remove_theme_constant_override("outline_size")

func _pill(r: Rect2, icon: Control, text: String, col: Color) -> Label:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.add_theme_stylebox_override("panel", UiTheme.capsule(int(r.size.y * 0.5)))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(p)
	icon.position = Vector2(8, (r.size.y - 46) * 0.5)
	icon.size = Vector2(46, 46)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(icon)
	var l := _label(text, 34, col, 8)
	l.position = Vector2(56, 0)
	l.size = Vector2(r.size.x - 66, r.size.y)
	p.add_child(l)
	return l
