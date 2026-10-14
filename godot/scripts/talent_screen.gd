class_name TalentScreen
extends GearScreen
## Lobby [탤런트] screen: the Archero-style gold talents (Meta.GOLD_TALENTS).
##   - six talent cards (level / max, current effect, progress bar).
##   - [강화] pays Meta.gold_talent_cost() and raises one random unmaxed talent: a frame races over the cards,
##     slows down and lands on the winner, which pops with its new level. The cost climbs with every level bought.
## Shares GearScreen's open / close / style helpers; only the layout differs.

const COLS := 2
const CARD_SZ := Vector2(322, 172)
const GRID_Y := 236.0

var _tcards := {}          # talent id -> {"card", "lv", "eff", "bar"}
var _frame: Panel         # roulette highlight
var _buy: Button
var _cost_l: Label
var _total_l: Label
var _spinning := false

func _rebuild() -> void:
	_tcards.clear()
	for c in _body.get_children():
		c.queue_free()
	var tt := UiTheme.tt()
	var title := _label("골드 탤런트", 60, UiTheme.TXT_YELLOW if tt else Color("ffd23f"), 14)
	title.position = Vector2(0, 22)
	title.size = Vector2(W, 80)
	_body.add_child(title)
	var x := _button("X", Color("8a8aa0"), Rect2(W - 92, 28, 70, 66), 34)
	x.pressed.connect(func():
		if not _spinning:
			close())
	_body.add_child(x)
	_gold_l = _pill(Rect2(40, 112, 300, 60), Hud.CoinIcon.new(), str(Meta.gold), Defs.COL_GOLD)
	_total_l = _label("", 26, Color("cfe8ff"), 8)
	_total_l.position = Vector2(370, 112)
	_total_l.size = Vector2(320, 60)
	_body.add_child(_total_l)
	var sub := _label("누를 때마다 무작위 능력치 하나가 올라요 · 모든 판에 적용", 22, Color("a9a4cb"), 6)
	sub.position = Vector2(0, 186)
	sub.size = Vector2(W, 34)
	_body.add_child(sub)
	for i in Meta.GOLD_TALENTS.size():
		_card(Meta.GOLD_TALENTS[i], _card_pos(i))
	_frame = Panel.new()
	var fb := UiTheme.flat(Color(0, 0, 0, 0), 22, 7, Color("fff26a"))
	_frame.add_theme_stylebox_override("panel", fb)
	_frame.size = CARD_SZ + Vector2(12, 12)
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.visible = false
	_body.add_child(_frame)
	_buy = _button("강화", UiTheme.YELLOW, Rect2(W * 0.5 - 260, 856, 520, 104), 44)
	_buy.pressed.connect(_press)
	_body.add_child(_buy)
	_cost_l = _label("", 26, Defs.COL_GOLD, 8)
	_cost_l.position = Vector2(0, 966)
	_cost_l.size = Vector2(W, 40)
	_body.add_child(_cost_l)
	_toast_l = _label("", 30, Color("fff2b0"), 8)
	_toast_l.position = Vector2(0, 1030)
	_toast_l.size = Vector2(W, 48)
	_body.add_child(_toast_l)
	_refresh()

func _card_pos(i: int) -> Vector2:
	return Vector2(W * 0.5 - CARD_SZ.x - 8 + (i % COLS) * (CARD_SZ.x + 16), GRID_Y + int(i / COLS) * (CARD_SZ.y + 16))

func _card(t: Dictionary, pos: Vector2) -> void:
	var card := Panel.new()
	card.position = pos
	card.size = CARD_SZ
	card.pivot_offset = CARD_SZ * 0.5
	card.add_theme_stylebox_override("panel", UiTheme.night_card(22) if UiTheme.tt() else _box(Color("4c467b"), 22, 5))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(card)
	var ic := Panel.new()   # round badge with the talent's first letter (no emoji on the web build's fonts)
	ic.position = Vector2(16, 18)
	ic.size = Vector2(72, 72)
	ic.add_theme_stylebox_override("panel", UiTheme.flat(t["col"], 36, 4, INK))
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ic)
	var il := _label(t["short"], 38, Color.WHITE, 8)
	il.size = ic.size
	ic.add_child(il)
	var nm := _label(t["name"], 28, Color.WHITE, 8)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.position = Vector2(100, 14)
	nm.size = Vector2(212, 40)
	card.add_child(nm)
	var lv := _label("", 24, Color("fff2b0"), 7)
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lv.position = Vector2(100, 54)
	lv.size = Vector2(212, 36)
	card.add_child(lv)
	var eff := _label("", 21, Color("cfe8ff"), 6)
	eff.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	eff.position = Vector2(18, 98)
	eff.size = Vector2(CARD_SZ.x - 36, 32)
	card.add_child(eff)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = t["max"]
	bar.position = Vector2(18, 136)
	bar.size = Vector2(CARD_SZ.x - 36, 20)
	bar.add_theme_stylebox_override("background", UiTheme.flat(UiTheme.BAR_TRACK, 10, 3, INK))
	bar.add_theme_stylebox_override("fill", UiTheme.flat(t["col"], 10, 3, INK))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(bar)
	_tcards[t["id"]] = {"card": card, "lv": lv, "eff": eff, "bar": bar}

## hide: the talent just bought while the roulette still spins (shown one level lower until it lands).
func _refresh(hide := "") -> void:
	for t in Meta.GOLD_TALENTS:
		var c: Dictionary = _tcards[t["id"]]
		var lv := Meta.gold_talent_level(t["id"]) - (1 if t["id"] == hide else 0)
		c["lv"].text = "MAX" if lv >= t["max"] else "Lv.%d / %d" % [lv, t["max"]]
		c["eff"].text = Meta.gold_talent_text(t["id"], lv)
		c["bar"].value = lv
	_gold_l.text = str(Meta.gold)
	_total_l.text = "총 레벨 %d" % (Meta.gold_talent_total() - (1 if hide != "" else 0))
	var why := Meta.can_gold_talent()
	_cost_l.text = "모두 최대 레벨이에요" if why == "max" else "비용: 골드 %d%s" % [Meta.gold_talent_cost(), "  (골드 부족)" if why == "gold" else ""]
	_buy.disabled = why != "" or _spinning
	_buy.modulate = Color(1, 1, 1, 0.55) if _buy.disabled else Color.WHITE

func _press() -> void:
	if _spinning:
		return
	var id := Meta.buy_gold_talent()
	if id == "":
		return
	_spinning = true
	_refresh(id)
	Sfx.play("click", -6.0)
	# the frame hops card to card, slowing down, and stops on the winner (at least ~2 laps)
	var ids: Array = Meta.GOLD_TALENTS.map(func(t): return t["id"])
	var win := ids.find(id)
	var steps := ids.size() * 2 + win + 1
	var at := randi() % ids.size()
	_frame.visible = true
	var tw := create_tween()
	for s in steps:
		var i := (at + s) % ids.size()
		if s == steps - 1:
			i = win
		var wait := 0.04 + 0.22 * pow(float(s) / steps, 3.0)
		tw.tween_callback(func():
			_frame.position = _card_pos(i) - Vector2(6, 6)
			Sfx.play("pop", -14.0, 1.0 + 0.4 * float(s) / steps))
		tw.tween_interval(wait)
	tw.tween_callback(func(): _land(id))

func _land(id: String) -> void:
	var t := Meta.gold_talent_def(id)
	var card: Panel = _tcards[id]["card"]
	Sfx.play("chime", -6.0, 1.2)
	var tw := card.create_tween()
	tw.tween_property(card, "scale", Vector2(1.12, 1.12), 0.08)
	tw.tween_property(card, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var burst := Hud.RayBurst.new()
	burst.size = CARD_SZ * 1.6
	burst.position = card.position + CARD_SZ * 0.5 - burst.size * 0.5
	burst.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(burst)
	_body.move_child(burst, card.get_index())
	var bt := burst.create_tween()
	bt.tween_property(burst, "modulate:a", 0.0, 0.7)
	bt.tween_callback(burst.queue_free)
	_spinning = false
	_refresh()
	_say("%s Lv.%d! %s" % [t["name"], Meta.gold_talent_level(id), Meta.gold_talent_text(id, Meta.gold_talent_level(id))])

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not _spinning:
			close()
