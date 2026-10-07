class_name PerkHud
extends Node
## Run perk button on the right edge: a small round star button with the stacked count tucked in its corner.
## Tapping it unfolds a list of every perk gathered this run (rarity, name, effect); tapping again folds it.
## Perks are lost when the whole team is wiped out, so the count drops back to 0 then.

const W := 46.0
const H := 46.0
const LIST_W := 380.0
const ROW_H := 66.0
const LIST_MAX_H := 560.0

var hud: Hud
var game: Node
var btn: Panel
var count_label: Label
var _icon: Control
var _list: Control
var _y := 146.0

func build(y: float) -> void:
	_y = y
	btn = hud.panel(Color(0.1, 0.08, 0.2, 0.5), Rect2(0, 0, W, H), 23, 0)
	btn.add_theme_stylebox_override("panel", UiTheme.capsule(23))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(hud.place(btn, Vector2(1, 0), Vector2(-W - 16, y), Vector2(W, H)))
	btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click", -6.0)
			hud.bump(btn, 1.1)
			toggle())
	_icon = StarIcon.new()
	_icon.position = Vector2(7, 6)
	_icon.size = Vector2(32, 32)
	_icon.pivot_offset = _icon.size * 0.5
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(_icon)
	count_label = hud.label("0", 15, Color.WHITE, 5)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count_label.position = Vector2(W - 26, H - 22)
	count_label.size = Vector2(26, 22)
	count_label.pivot_offset = count_label.size * 0.5
	btn.add_child(count_label)

## Update the count (and the open list). gained = a perk was just won: the button pops.
func refresh(gained := false) -> void:
	if count_label == null:
		return
	count_label.text = str(game.perks.size())
	if gained:
		hud.bump(btn, 1.25)
		hud.bump(count_label, 1.5)
		var tw := _icon.create_tween()
		tw.tween_property(_icon, "rotation", TAU, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func(): _icon.rotation = 0.0)
	if is_open():
		_close()
		_open()

func is_open() -> bool:
	return _list != null and is_instance_valid(_list)

func toggle() -> void:
	if is_open():
		_close()
	else:
		_open()

func _close() -> void:
	if is_open():
		var l := _list
		_list = null
		var tw := l.create_tween().set_ignore_time_scale(true)
		tw.tween_property(l, "scale", Vector2(1.0, 0.05), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(l.queue_free)

## The list unfolds downward from the button (rarest first, then in the order they were won).
func _open() -> void:
	var order := {"legendary": 0, "rare": 1, "common": 2}
	var ids: Array = game.perks.duplicate()
	var idx := {}
	for i in ids.size():
		idx[ids[i]] = i
	ids.sort_custom(func(a, b):
		var ra: int = order[Defs.PERKS[a]["rarity"]]
		var rb: int = order[Defs.PERKS[b]["rarity"]]
		return ra < rb if ra != rb else idx[a] < idx[b])
	var body_h := maxf(ROW_H, minf(LIST_MAX_H, ids.size() * (ROW_H + 6.0)))
	var h := 58.0 + body_h + 14.0
	var card := hud.panel(Color.WHITE, Rect2(0, 0, LIST_W, h), 22, 0)
	card.add_theme_stylebox_override("panel", UiTheme.deck_panel(22, 50.0) if UiTheme.tt() else hud.box(Color(0.1, 0.08, 0.2, 0.92), 22, 4, Color("3a2f66")))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(hud.place(card, Vector2(1, 0), Vector2(-LIST_W - 16, _y + H + 8), Vector2(LIST_W, h)))
	card.pivot_offset = Vector2(LIST_W - W * 0.5, 0)
	_list = card
	var title := hud.label("누적 특성 %d개" % ids.size(), 24, Color("fff4e0"), 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.position = Vector2(20, 6)
	title.size = Vector2(LIST_W - 80, 40)
	card.add_child(title)
	var x := hud.juicy_button("X", Color("ff6b8a"), Rect2(LIST_W - 56, 6, 44, 40), 22)
	x.pressed.connect(_close)
	card.add_child(x)
	if ids.is_empty():
		var when := "중간 보스를 처치하면" if game.mode_id() == "march" else "3웨이브마다"
		var e := hud.label("아직 특성이 없어요.\n%s 룰렛이 돌아가요!" % when, 20, Color("d8d2f0"), 6)
		e.position = Vector2(0, 58)
		e.size = Vector2(LIST_W, ROW_H)
		card.add_child(e)
	else:
		var sc := ScrollContainer.new()
		sc.position = Vector2(12, 58)
		sc.size = Vector2(LIST_W - 24, body_h)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		card.add_child(sc)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		col.custom_minimum_size = Vector2(LIST_W - 24, 0)
		sc.add_child(col)
		for id in ids:
			col.add_child(_row(id))
	card.scale = Vector2(1.0, 0.05)
	var tw := card.create_tween().set_ignore_time_scale(true)
	tw.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _row(id: String) -> Control:
	var p: Dictionary = Defs.PERKS[id]
	var rc: Color = Defs.RARITY_COL[p["rarity"]] if p["rarity"] != "common" else Color("a9b2c6")
	var row := hud.panel(Color.WHITE, Rect2(0, 0, LIST_W - 24, ROW_H), 14, 0)
	row.add_theme_stylebox_override("panel", hud.box(UiTheme.inset(), 14, 0))
	row.custom_minimum_size = Vector2(LIST_W - 24, ROW_H)
	var strip := hud.panel(rc, Rect2(0, 0, 70, ROW_H), 14, 3)
	row.add_child(strip)
	var st := hud.label(HudPanels.PERK_STARS[p["rarity"]], 18 if p["rarity"] == "legendary" else 22, Color.WHITE, 6)
	st.size = Vector2(70, ROW_H)
	strip.add_child(st)
	var nm := hud.label(p["name"], 22, rc.lightened(0.2) if p["rarity"] != "common" else Color.WHITE, 7)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(82, 2)
	nm.size = Vector2(LIST_W - 120, 32)
	row.add_child(nm)
	var ds := hud.label(p["desc"], 16, Color("e8e2ff"), 5)
	ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	ds.position = Vector2(82, 32)
	ds.size = Vector2(LIST_W - 120, 30)
	ds.clip_text = true
	row.add_child(ds)
	return row

## Five-point star (same toy style as the nav icons).
class StarIcon extends Control:
	func _draw() -> void:
		var c := size * 0.5
		var s := size.x
		var o := PackedVector2Array()
		var i := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + TAU * k / 10.0
			var rr := s * (0.4 if k % 2 == 0 else 0.18)
			o.append(c + Vector2(cos(a), sin(a)) * (rr + s * 0.06))
			i.append(c + Vector2(cos(a), sin(a)) * rr)
		draw_colored_polygon(o, UiTheme.ink())
		draw_colored_polygon(i, Color("ffd23f"))
