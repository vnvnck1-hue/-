class_name SkillGacha
extends Control
## 스킬북 카드 뽑기 — presentation and the pick. Rules live in Main: roll_book_offers (which skills come up, capped
## by the book's grade), learn_skill (what the kept skill does). Opened by Main.use_book over a paused field that
## stays in view behind a thin dim; the book is already spent.
##   intro  : the book pops up where it sat in the bag and shakes; three card backs shoot up out of it, off the
##            top of the screen, then drop into a fan in the middle, a little apart, where they idle (slow weave).
##   flip   : the player taps the cards to turn them over, in any order. Whichever card is tapped, the skills come
##            up from the lowest grade to the highest (the n-th flip shows the n-th lowest offer), so the best one
##            is always last. Before a 희귀 / 영웅 / 전설 flip the back glows and shakes in that grade's colour.
##   ascend : a card of the book's top grade (희귀 book and up) shoots off along its fan direction (its head) with
##            speed lines in that grade's tones filling the background, turns over off screen and slams back in.
##   reveal : around the card, louder with the skill's grade — 일반 a ring, 희귀 a blue ring, sparks and a stamp,
##            영웅 a soft flash, purple rays, an aura and a shake, 전설 a gold flash, big rays, a shine, a harder
##            shake, confetti and a "전설 스킬!" banner. Glows sit on a layer under all the cards, so no card is ever
##            covered or dimmed by another one's effects. Every card's back plate (백판) is its grade's colour.
##   pick   : tap a card to learn it (a hero with every slot taken first picks a skill to forget), or [건너뛰기].
## A tap on the background hurries the intro. Registered as hud.overlay (closing unpauses the field).

const CARD := Vector2(200, 300)
const CARD_Y := -120.0           # middle card's centre, relative to the screen centre
const PAD := 10.0                # frame around a card face
const FAN_GAP := 216.0           # centre to centre of neighbouring cards on the fan
const FAN_STEP := 0.07           # tilt between neighbouring cards (rad) — kept small so the text stays readable
const FAN_DROP := 12.0           # outer cards sit this much lower (k² x), giving the arc
const FAN_SCALE := 0.92
const ASCEND := 1500.0           # how far the top-grade card flies off along its head direction
const STAMP := {2: "희귀!", 3: "영웅!", 4: "전설!"}
const BACK_COL := Color("232a5c")
const BACK_RIM := Color("e8c25a")
const DIM_A := 0.35

var hud: Hud
var game: Node
var grade := 1
var offers: Array = []           # card i's skill (the order is fixed card by card as they are flipped)
var from_pos := Vector2.ZERO     # the book's bag slot (global canvas position); zero = bottom centre
var state := ""                  # intro / flip / pick / slot / done
var fast := false                # tapped during the intro: it hurries

var _stage: Control
var _glow_layer: Control         # under every card: the glows / rays / auras behind them (never over another card)
var _behind: Array[Control] = [] # card i's holder on _glow_layer, synced to its centre, rotation, scale and alpha
var _dim: ColorRect
var _lines: SpeedLines
var _fx: Control
var _flash: ColorRect
var _hint: Label
var _skip_b: Button
var _frames: Array[Panel] = []
var _faces: Array = []           # revealed face per card (null while face down)
var _deck: Array = []            # the offers, lowest grade first: the order they come up in
var _flipped: Array[bool] = []
var _busy: Array[bool] = []      # card under a tween (no idle weave, no hover)
var _idle_w: Array[float] = []   # idle weave weight, eases in after a tween
var _base_pos: Array[Vector2] = []
var _base_rot: Array[float] = []
var _flips := 0
var _flipping := false
var _spin_rays: Array[Control] = []
var _slot_box: Control
var _t := 0.0

func _tw() -> Tween:
	return create_tween().set_ignore_time_scale(true)

func _twn(n: Node) -> Tween:
	return n.create_tween().set_ignore_time_scale(true)

func _sleep(t: float) -> Signal:
	var tw := _tw()
	tw.tween_interval(t)
	return tw.finished

# ---------------------------------------------------------------- build
## Builds the screen on top of the HUD (as its overlay) and starts the show for a grade-g book.
func start(g: int, picks: Array) -> void:
	grade = clampi(g, 1, Defs.BOOK_TOP)
	offers = picks.duplicate()
	_deck = picks.duplicate()
	_deck.sort_custom(func(a, b): return int(Defs.book(a)["grade"]) < int(Defs.book(b)["grade"]))
	hud.close_overlays()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(self)
	hud.overlay = self
	_build()
	_run()

func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = Color(0.03, 0.02, 0.08, 0.0)
	add_child(_dim)
	_twn(_dim).tween_property(_dim, "color:a", DIM_A, 0.2)
	_lines = SpeedLines.new()
	_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.visible = false
	add_child(_lines)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_glow_layer = Control.new()
	_glow_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_glow_layer)
	_fx = Control.new()
	_fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fx)
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)
	gui_input.connect(_on_input)

func _process(delta: float) -> void:
	var dt := delta / Engine.time_scale if Engine.time_scale > 0.05 else delta
	_t += dt
	for r in _spin_rays:
		if is_instance_valid(r):
			r.rotation += dt * 0.9
	if _lines.visible:
		_lines.t += dt
		_lines.queue_redraw()
	if _hint and (state == "flip" or state == "pick"):
		var s := 1.0 + sin(_t * 6.0) * 0.05
		_hint.scale = Vector2(s, s)
	# the effects behind each card follow it on the layer under all the cards
	for i in _behind.size():
		var f := _frames[i]
		var h := _behind[i]
		h.position = f.position + f.pivot_offset
		h.rotation = f.rotation
		h.scale = f.scale
		h.modulate.a = f.modulate.a
	# idle: the cards weave slowly, each on its own phase
	var idle := state == "flip" or state == "pick" or state == "slot"
	for i in _frames.size():
		if _busy[i] or not idle:
			_idle_w[i] = 0.0
			continue
		_idle_w[i] = minf(1.0, _idle_w[i] + dt * 2.0)
		var w := _idle_w[i] * _idle_w[i] * (3.0 - 2.0 * _idle_w[i])
		var f := _frames[i]
		f.position = _base_pos[i] + Vector2(sin(_t * 0.9 + i * 2.1) * 5.0, sin(_t * 1.25 + i * 1.7) * 8.0) * w
		f.rotation = _base_rot[i] + sin(_t * 0.8 + i * 2.4) * 0.02 * w

func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tap()

## A tap on the background: hurries the intro.
func tap() -> void:
	if state == "intro" and not fast:
		fast = true
		Sfx.play("click", -6.0, 1.4)

# ---------------------------------------------------------------- the show
func _run() -> void:
	state = "intro"
	var view := _stage.size if _stage.size.x > 0.0 else get_viewport_rect().size
	var mid := view * 0.5
	var src := mid + Vector2(0, view.y * 0.36)
	if from_pos != Vector2.ZERO:
		src = _stage.get_global_transform().affine_inverse() * from_pos
	var rc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(grade)])
	# the book pops up out of its bag slot and shakes
	var book := ItemIcon.new({"kind": "skillbook", "grade": grade})
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	book.size = Vector2(96, 96)
	book.pivot_offset = book.size * 0.5
	book.position = src - book.size * 0.5
	book.scale = Vector2(0.5, 0.5)
	_stage.add_child(book)
	var bt := _twn(book)
	bt.tween_property(book, "scale", Vector2(1.3, 1.3), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for k in 3:
		bt.tween_property(book, "rotation", 0.14 if k % 2 == 0 else -0.14, 0.04)
	bt.tween_property(book, "rotation", 0.0, 0.03)
	Sfx.play("pop", -4.0, 0.9 + 0.1 * grade)
	_ring(src, rc, 70.0, 0.35, 8)
	await _sleep(0.25)
	# three card backs shoot up out of the book, off the top of the screen
	for i in offers.size():
		_add_card(i, src, mid)
	Sfx.play("whoosh", -4.0, 1.2)
	var fade := _twn(book)
	fade.tween_property(book, "scale", Vector2(0.2, 0.2), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade.parallel().tween_property(book, "modulate:a", 0.0, 0.22)
	fade.tween_callback(book.queue_free)
	for i in _frames.size():
		_launch(i, src, mid.x)
	await _sleep(0.3 + 0.05 * (offers.size() - 1))
	# ... and drop into a fan in the middle
	for i in _frames.size():
		_line_up(i)
	await _sleep(0.42 + 0.06 * (offers.size() - 1))
	Sfx.play("thud", -5.0, 1.1)
	for i in _frames.size():
		_busy[i] = false
	_hint = hud.label("카드를 터치해서 뒤집어요", 26, Color.WHITE, 9)
	_stage.add_child(hud.place(_hint, Vector2(0.5, 0.5), Vector2(-300, CARD_Y + 220), Vector2(600, 44)))
	_hint.pivot_offset = Vector2(300, 22)
	state = "flip"
	if game and game.get("autoplay"):
		for i in _frames.size():
			await _sleep(0.3)
			await flip(i)

## Card i's resting place on the fan: top-left position and rotation (pivot at the card centre).
func _fan(i: int, mid: Vector2, pivot: Vector2) -> Array:
	var k := i - (offers.size() - 1) * 0.5
	var c := mid + Vector2(k * FAN_GAP, CARD_Y + k * k * FAN_DROP)
	return [c - pivot, k * FAN_STEP]

## Card i, face down: a dark navy card with a gold rim and a "?" (its grade stays hidden until the tease), and the
## touch area that flips it (later: picks it).
func _add_card(i: int, at: Vector2, mid: Vector2) -> void:
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size = CARD + Vector2(PAD, PAD) * 2.0
	frame.pivot_offset = frame.size * 0.5
	frame.position = at - frame.pivot_offset
	frame.scale = Vector2(0.4, 0.4)
	_card_back(frame)
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size = frame.size
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	for st in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	b.pressed.connect(func(): _on_card(i))
	b.mouse_entered.connect(func(): _hover(i, true))
	b.mouse_exited.connect(func(): _hover(i, false))
	frame.add_child(b)
	_stage.add_child(frame)
	_frames.append(frame)
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_layer.add_child(holder)
	_behind.append(holder)
	_faces.append(null)
	_flipped.append(false)
	_busy.append(true)
	_idle_w.append(0.0)
	var rest := _fan(i, mid, frame.pivot_offset)
	_base_pos.append(rest[0])
	_base_rot.append(rest[1])

func _card_back(frame: Panel) -> void:
	frame.add_theme_stylebox_override("panel", hud.box(BACK_COL, 26, 6, BACK_RIM))
	var inner := Panel.new()
	inner.name = "Back"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.position = Vector2(PAD + 8, PAD + 8)
	inner.size = CARD - Vector2(16, 16)
	inner.add_theme_stylebox_override("panel", hud.box(BACK_COL.lightened(0.08), 16, 3, BACK_RIM.darkened(0.2)))
	frame.add_child(inner)
	var q := hud.label("?", 110, BACK_RIM, 14)
	q.add_theme_color_override("font_outline_color", BACK_COL.darkened(0.6))
	q.size = inner.size
	inner.add_child(q)
	for c in [Vector2(14, 14), Vector2(inner.size.x - 14, 14), Vector2(14, inner.size.y - 14), inner.size - Vector2(14, 14)]:
		var dot := hud.panel(BACK_RIM, Rect2(c - Vector2(6, 6), Vector2(12, 12)), 6, 0)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(dot)

## Shoots card i up out of the book, a little spread and spin, with two fading ghosts trailing it.
func _launch(i: int, src: Vector2, cx: float) -> void:
	var f := _frames[i]
	var d := 0.05 * i
	var spread := (i - (offers.size() - 1) * 0.5)
	var to := Vector2(cx + spread * 120.0 + (src.x - cx) * 0.4, -260.0) - f.pivot_offset
	var rot := spread * 0.35 + randf_range(-0.15, 0.15)
	for k in 2:
		var ghost := Panel.new()
		ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ghost.size = f.size
		ghost.pivot_offset = f.pivot_offset
		ghost.position = f.position
		ghost.scale = f.scale
		ghost.add_theme_stylebox_override("panel", hud.box(BACK_RIM, 26, 0))
		ghost.modulate.a = 0.0
		_stage.add_child(ghost)
		_stage.move_child(ghost, f.get_index())
		var gt := _twn(ghost)
		gt.tween_interval(d + 0.035 * (k + 1))
		gt.tween_property(ghost, "modulate:a", 0.4 - 0.15 * k, 0.01)
		gt.tween_property(ghost, "position", to, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		gt.parallel().tween_property(ghost, "rotation", rot, 0.3)
		gt.parallel().tween_property(ghost, "modulate:a", 0.0, 0.3)
		gt.tween_callback(ghost.queue_free)
	var tw := _twn(f)
	tw.tween_interval(d)
	tw.tween_property(f, "position", to, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(f, "rotation", rot, 0.3)
	tw.parallel().tween_property(f, "scale", Vector2(0.55, 0.55), 0.3)

## Drops card i from above the screen onto its place on the fan.
func _line_up(i: int) -> void:
	var f := _frames[i]
	var to := _base_pos[i]
	f.position = Vector2(to.x, -f.size.y - 40.0)
	f.scale = Vector2(0.8, 0.8)
	f.rotation = _base_rot[i] + randf_range(-0.4, 0.4)
	var tw := _twn(f)
	tw.tween_interval(0.06 * i)
	tw.tween_property(f, "position", to, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "rotation", _base_rot[i], 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(f, "scale", Vector2.ONE * FAN_SCALE, 0.34)

func _on_card(i: int) -> void:
	if state == "flip":
		flip(i)
	elif state == "pick":
		_pick(i)

## The player turns card i over. It shows the next skill of the deck (lowest grade first), so the best one comes
## last whatever the order of the taps. One card at a time; when all are up, the pick starts.
func flip(i: int) -> void:
	if state != "flip" or _flipping or i < 0 or i >= _frames.size() or _flipped[i]:
		return
	_flipping = true
	_flipped[i] = true
	_busy[i] = true
	var id: String = _deck[_flips]
	_flips += 1
	offers[i] = id
	var sg := int(Defs.book(id)["grade"])
	var f := _frames[i]
	Sfx.play("click", -5.0, 1.2)
	var settle := _twn(f)   # out of the weave, back to its fan pose
	settle.tween_property(f, "position", _base_pos[i], 0.04)
	settle.parallel().tween_property(f, "rotation", _base_rot[i], 0.04)
	settle.parallel().tween_property(f, "scale", Vector2.ONE * FAN_SCALE, 0.04)
	await settle.finished
	await _tease(i, sg)
	var ascend := sg >= grade and grade >= 2
	if ascend:
		await _ascend(i, id, sg)
	else:
		var tw := _twn(f)
		Sfx.play("whoosh", -10.0, 1.6)
		tw.tween_property(f, "scale", Vector2(0.0, 1.06) * FAN_SCALE, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		await tw.finished
		_turn_face(i, id, sg)
		var back := _twn(f)
		back.tween_property(f, "scale", Vector2(1.08, 1.0) * FAN_SCALE, 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		back.tween_property(f, "scale", Vector2.ONE * FAN_SCALE, 0.06)
		await back.finished
	await _reveal(i, id, sg, ascend)
	_busy[i] = false
	_flipping = false
	if _flips >= _frames.size():
		_ready_to_pick()

## Swaps card i's back for the face of skill id (the touch area stays on top).
func _turn_face(i: int, id: String, sg: int) -> void:
	var f := _frames[i]
	for c in [f.get_node_or_null("Back"), _behind[i].get_node_or_null("Glow")]:
		if c:
			c.get_parent().remove_child(c)
			c.queue_free()
	var face := _face(id)
	face.position = Vector2(PAD, PAD)
	f.add_child(face)
	f.move_child(face, 0)
	_faces[i] = face
	var gc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(sg)])
	f.add_theme_stylebox_override("panel", hud.box(gc.darkened(0.2), 26, 8, UiTheme.ink() if sg <= 1 else gc.lightened(0.35)))

## The book's top grade: the card crouches, shoots off along its fan direction (its head) while speed lines in
## the grade's tones sweep the background, turns over off screen and slams back into its place.
func _ascend(i: int, id: String, sg: int) -> void:
	var f := _frames[i]
	var r := _base_rot[i]
	var dir := Vector2(sin(r), -cos(r))
	var home := _base_pos[i]
	var gc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(sg)])
	_stage.move_child(f, _stage.get_child_count() - 1)
	var crouch := _twn(f)
	crouch.tween_property(f, "position", home - dir * 30.0, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	crouch.parallel().tween_property(f, "scale", Vector2(1.14, 0.84) * FAN_SCALE, 0.07)
	await crouch.finished
	_lines.begin(dir, gc)
	Sfx.play("whoosh", -2.0, 0.9)
	Sfx.play("rise", -5.0, 1.5)
	var out := _twn(f)
	out.tween_property(f, "position", home + dir * ASCEND, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	out.parallel().tween_property(f, "scale", Vector2(0.8, 1.5) * FAN_SCALE, 0.11)
	await out.finished
	_turn_face(i, id, sg)
	await _sleep(0.1)
	f.position = home + dir * ASCEND
	f.rotation = r + 0.6
	f.scale = Vector2.ONE * FAN_SCALE * 1.9
	Sfx.play("whoosh", -2.0, 1.3)
	var back := _twn(f)
	back.tween_property(f, "position", home, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	back.parallel().tween_property(f, "rotation", r, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	back.parallel().tween_property(f, "scale", Vector2.ONE * FAN_SCALE * 1.25, 0.1)
	await back.finished
	# impact: a hard squash, a short hit-stop, then the bounce
	var at := f.position + f.size * 0.5
	f.scale = Vector2(1.32, 0.8) * FAN_SCALE
	_shake(24.0, 0.35)
	_flash_screen(gc.lightened(0.7), 0.75, 0.22)
	Sfx.play("boom", 0.0, 0.85)
	Sfx.play("thud", 0.0, 0.75)
	_ring(at, Color.WHITE, 230.0, 0.35, 16)
	_ring(at, gc.lightened(0.3), 170.0, 0.3, 12)
	for k in 14:
		_spark(at, Color.WHITE if k % 2 == 0 else gc.lightened(0.4), randf_range(200.0, 340.0), 0.4)
	await _sleep(0.05)
	_lines.end(0.22)
	var land := _twn(f)
	land.tween_property(f, "scale", Vector2.ONE * FAN_SCALE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await _sleep(0.06)

## Before a 희귀+ flip the back glows and shakes in the grade colour — longer for higher grades; 전설 also dims
## the room a little more.
func _tease(i: int, sg: int) -> void:
	if sg <= 1:
		return
	var f := _frames[i]
	var r := _base_rot[i]
	var gc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(sg)])
	if sg == 2:
		f.add_theme_stylebox_override("panel", hud.box(BACK_COL, 26, 8, gc))
		await _sleep(0.04)
		f.add_theme_stylebox_override("panel", hud.box(BACK_COL, 26, 6, BACK_RIM))
		await _sleep(0.03)
		f.add_theme_stylebox_override("panel", hud.box(BACK_COL, 26, 8, gc))
		await _sleep(0.03)
		return
	var dur := 0.24 if sg == 3 else 0.4
	var beats := 2 if sg == 3 else 3
	f.add_theme_stylebox_override("panel", hud.box(BACK_COL.lerp(gc, 0.25), 26, 9, gc.lightened(0.2)))
	var glow := hud._fly_burst("aura", gc, f.size.y * 0.6, Vector2.ZERO)
	glow.name = "Glow"
	glow.modulate.a = 0.0
	_behind[i].add_child(glow)
	_twn(glow).tween_property(glow, "modulate:a", 1.0, dur * 0.7)
	Sfx.play("rise", -6.0, 0.9 if sg == 3 else 0.7)
	if sg >= 4:
		_twn(_dim).tween_property(_dim, "color:a", 0.55, dur * 0.8)
	var tw := _twn(f)
	var beat := dur / beats
	for k in beats:
		tw.tween_property(f, "rotation", r + 0.06, beat * 0.25)
		tw.parallel().tween_property(f, "scale", Vector2.ONE * FAN_SCALE * 1.06, beat * 0.25)
		tw.tween_property(f, "rotation", r - 0.06, beat * 0.25)
		tw.tween_property(f, "rotation", r, beat * 0.2)
		tw.parallel().tween_property(f, "scale", Vector2.ONE * FAN_SCALE, beat * 0.5)
		tw.tween_interval(beat * 0.05)
		if sg >= 4:
			_sleep(k * beat).connect(func(): Sfx.play("thud", -8.0, 0.7 + 0.06 * k))
	await tw.finished
	if sg >= 4:
		_twn(_dim).tween_property(_dim, "color:a", DIM_A + 0.08, 0.3)

# ---------------------------------------------------------------- reveal
## The reveal around the card, louder with the skill's grade (after an ascend the card already bounced).
func _reveal(i: int, id: String, sg: int, ascended := false) -> void:
	var frame := _frames[i]
	var at := frame.position + frame.size * 0.5
	var gc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(sg)])
	var face: Control = _faces[i]
	if face:
		_status_tag(face, id)
	if not ascended:
		var tw := _twn(frame)
		tw.tween_property(frame, "scale", Vector2.ONE * FAN_SCALE * (1.06 + 0.04 * sg), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(frame, "scale", Vector2.ONE * FAN_SCALE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	match sg:
		1:
			Sfx.play("pop", -3.0, 1.0 + 0.1 * i)
			_ring(at, Color.WHITE, 90.0, 0.4, 6)
			await _sleep(0.1)
		2:
			Sfx.play("pop", -2.0, 1.1)
			Sfx.play("chime", -7.0, 1.25)
			_ring(at, gc, 110.0, 0.45, 10)
			for k in 8:
				_spark(at, gc if k % 2 == 0 else Color.WHITE, randf_range(130.0, 190.0), 0.5)
			_stamp(frame, sg, gc)
			await _sleep(0.3)
		3:
			if not ascended:
				_flash_screen(Color(1, 1, 1), 0.35, 0.25)
			_card_rays(i, gc, 380.0)
			_aura_loop(i, gc)
			_shake(6.0, 0.25)
			Sfx.play("boom", -9.0, 1.4)
			Sfx.play("chime", -3.0, 1.35)
			Sfx.play("sparkle", -4.0, 1.1)
			_ring(at, gc, 130.0, 0.5, 12)
			hud._sparkles(_fx, at, 14)
			_stamp(frame, sg, gc)
			await _sleep(0.35)
		_:
			if not ascended:
				_flash_screen(Color(1, 0.95, 0.75), 0.6, 0.45)
			_card_rays(i, gc, 540.0)
			_aura_loop(i, gc)
			_shine_loop(face)
			_shake(12.0, 0.45)
			Sfx.play("boom", -4.0, 0.8)
			Sfx.play("fanfare", -3.0, 1.0)
			Sfx.play("sparkle", -2.0, 1.3)
			_ring(at, gc, 150.0, 0.6, 16)
			_ring(at, Color.WHITE, 200.0, 0.8, 10)
			for k in 20:
				_spark(at, [gc, Color.WHITE, Color("fff27a"), Color("ff9ad8")][k % 4], randf_range(200.0, 360.0), 0.85)
			_confetti(at, 34)
			hud._sparkles(_fx, at, 20)
			_stamp(frame, sg, gc)
			_banner("전설 스킬!", gc)
			await _sleep(0.6)

## The status of a revealed skill, centred just under the card: NEW (free slot) / Lv.n+1 (the level it goes to) /
## 교체 (its hero's slots are full).
func _status_tag(face: Control, id: String) -> void:
	var bd := Defs.book(id)
	var h: Actor = game.hero(bd["cls"]) if game else null
	var text := "NEW"
	var col := Color("3fbf4a")
	if h:
		var li: int = game.learned_index(h, id)
		if li >= 0:
			var lv := int(h.learned[li]["level"])
			text = "Lv.%d" % (lv + 1)
			col = Color("2f78d0")
		elif game.needs_slot(id):
			text = "교체"
			col = Color("e0543a")
	var tag := hud.panel(col, Rect2(CARD.x * 0.5 - 54, CARD.y + PAD + 6, 108, 34), 17, 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := hud.label(text, 19, Color.WHITE, 6)
	tl.size = tag.size
	tag.add_child(tl)
	face.add_child(tag)
	hud.pop_in(tag, 0.2, 0.3)

func _stamp(frame: Control, sg: int, gc: Color) -> void:
	var s := hud.label(STAMP.get(sg, ""), 34 + 6 * sg, Color("fff27a") if sg >= 3 else Color.WHITE, 10 + sg)
	s.size = Vector2(220, 60)
	s.position = Vector2(frame.size.x * 0.5 - 110, -58)
	s.rotation = -0.16
	s.add_theme_color_override("font_outline_color", gc.darkened(0.5))
	frame.add_child(s)
	_slam(s, 2.6 + 0.3 * sg)

## Rotating light rays behind a revealed 영웅 / 전설 card (kept until the pick; they weave with it, under every card).
func _card_rays(i: int, gc: Color, d: float) -> void:
	var rays := Hud.RayBurst.new()
	rays.col = gc.lightened(0.45)
	rays.size = Vector2(d, d)
	rays.position = -rays.size * 0.5
	rays.pivot_offset = rays.size * 0.5
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.scale = Vector2.ZERO
	_behind[i].add_child(rays)
	_spin_rays.append(rays)
	_twn(rays).tween_property(rays, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A glow breathing behind the card for as long as it is on screen (under every card).
func _aura_loop(i: int, gc: Color) -> void:
	var aura := hud._fly_burst("aura", gc, _frames[i].size.y * 0.62, Vector2.ZERO)
	aura.modulate.a = 0.0
	_behind[i].add_child(aura)
	var tw := _twn(aura).set_loops()
	tw.tween_property(aura, "modulate:a", 0.95, 0.45)
	tw.parallel().tween_property(aura, "scale", Vector2(1.08, 1.08), 0.45)
	tw.tween_property(aura, "modulate:a", 0.45, 0.45)
	tw.parallel().tween_property(aura, "scale", Vector2.ONE, 0.45)

## 전설: a white shine sweeping over the card again and again.
func _shine_loop(face: Control) -> void:
	if face == null:
		return
	var clip := Control.new()
	clip.clip_contents = true
	clip.size = face.size
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.add_child(clip)
	var bar := ColorRect.new()
	bar.color = Color(1, 1, 1, 0.45)
	bar.size = Vector2(46, face.size.y * 1.8)
	bar.rotation = 0.45
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(bar)
	var tw := _twn(bar).set_loops()
	tw.tween_callback(func(): bar.position = Vector2(-140, -face.size.y * 0.4))
	tw.tween_property(bar, "position:x", face.size.x + 80.0, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	tw.tween_interval(0.9)

func _banner(text: String, gc: Color) -> void:
	var l := hud.label(text, 84, Color("fff27a"), 20)
	l.add_theme_color_override("font_outline_color", gc.darkened(0.55))
	_fx.add_child(hud.place(l, Vector2(0.5, 0.5), Vector2(-360, CARD_Y - 330), Vector2(720, 120)))
	_slam(l, 3.2)
	var tw := _twn(l)
	tw.tween_interval(0.75)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)

# ---------------------------------------------------------------- pick
func _ready_to_pick() -> void:
	state = "pick"
	_hint.text = "배울 스킬을 하나 고르세요"
	_skip_b = hud.juicy_button("건너뛰기", Color("8a8aa0"), Rect2(0, 0, 200, 56), 24)
	_skip_b.pressed.connect(func():
		if state == "pick":
			_close(-1, -1))
	_stage.add_child(hud.place(_skip_b, Vector2(0.5, 0.5), Vector2(-100, CARD_Y + 266), Vector2(200, 56)))
	hud.pop_in(_skip_b, 0.3, 0.3)
	if game and game.get("autoplay"):
		await _sleep(0.6)
		var best: Array = game.best_offer(offers)
		var bi := offers.find(best[0])
		if bi >= 0:
			_finish(bi, best[1])
		else:
			_close(-1, -1)

## A card under the pointer lifts a little (face down while flipping, face up while picking).
func _hover(i: int, on: bool) -> void:
	if _busy[i] or not (state == "pick" or (state == "flip" and not _flipped[i]) or not on):
		return
	Hud.retween(_frames[i]).tween_property(_frames[i], "scale", Vector2.ONE * FAN_SCALE * (1.06 if on else 1.0), 0.12)

func _pick(i: int) -> void:
	if state != "pick":
		return
	Sfx.play("click", -4.0, 1.1)
	if game and game.needs_slot(offers[i]):
		_ask_slot(i)
	else:
		_finish(i, -1)

## The hero of skill i already knows Defs.SKILL_SLOTS skills: which one to forget (or back to the cards).
func _ask_slot(i: int) -> void:
	state = "slot"
	var id: String = offers[i]
	var bd := Defs.book(id)
	var h: Actor = game.hero(bd["cls"])
	_slot_box = Control.new()
	_slot_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slot_box.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_slot_box)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.02, 0.1, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slot_box.add_child(dim)
	var n: int = h.learned.size()
	var cs := Vector2(620, 250 + n * 82)
	var card := Panel.new()
	card.add_theme_stylebox_override("panel", UiTheme.cream_card(28))
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	_slot_box.add_child(hud.place(card, Vector2(0.5, 0.5), -cs * 0.5, cs))
	hud.pop_in(card, 0.5, 0.3)
	var t := hud.label("%s의 스킬 칸이 가득 찼어요" % Defs.HEROES[bd["cls"]]["name"], 34, Color("c84ad8"), 0)
	t.position = Vector2(0, 20)
	t.size = Vector2(cs.x, 52)
	card.add_child(t)
	var q := hud.label("%s 대신 잊을 스킬을 고르세요 (그 스킬의 레벨은 사라져요)" % bd["name"], 19, Color("8a6a50"), 0)
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.position = Vector2(24, 76)
	q.size = Vector2(cs.x - 48, 56)
	card.add_child(q)
	for k in n:
		var cur: Dictionary = h.learned[k]
		var cd := Defs.book(cur["id"])
		var b := hud.juicy_button("%s  Lv.%d" % [cd.get("name", "?"), int(cur["level"])], Defs.RARITY_COL[Defs.book_rarity(int(cd.get("grade", 1)))].darkened(0.15), Rect2(60, 140 + k * 82, 500, 70), 26)
		var slot := k
		b.pressed.connect(func():
			_slot_box.queue_free()
			_finish(i, slot))
		card.add_child(b)
	var back := hud.juicy_button("뒤로", Color("8a8aa0"), Rect2(210, 150 + n * 82, 200, 56), 24)
	back.pressed.connect(func():
		_slot_box.queue_free()
		state = "pick")
	card.add_child(back)

## The kept card swells and flies up, the others drop away; then the screen closes and the skill is learned.
func _finish(i: int, slot: int) -> void:
	if state == "done":
		return
	state = "done"
	_hint.visible = false
	if _skip_b:
		_skip_b.visible = false
	var sg := int(Defs.book(offers[i])["grade"])
	var gc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(sg)])
	for k in _frames.size():
		_busy[k] = true
		var f := _frames[k]
		var tw := _twn(f)
		if k == i:
			_stage.move_child(f, _stage.get_child_count() - 1)
			tw.tween_property(f, "rotation", 0.0, 0.16)
			tw.parallel().tween_property(f, "scale", Vector2(1.2, 1.2), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_interval(0.2)
			tw.tween_property(f, "position:y", f.position.y - 260.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(f, "scale", Vector2(0.3, 0.3), 0.3)
			tw.parallel().tween_property(f, "modulate:a", 0.0, 0.3)
		else:
			tw.tween_property(f, "modulate:a", 0.0, 0.25)
			tw.parallel().tween_property(f, "position:y", f.position.y + 120.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	Sfx.play("chime", -3.0, 1.0 + 0.1 * sg)
	_ring(_frames[i].position + _frames[i].size * 0.5, gc, 120.0, 0.45, 10)
	await _sleep(0.72)
	_close(i, slot)

func _close(i: int, slot: int) -> void:
	state = "done"
	var g := game
	var id: String = offers[i] if i >= 0 else ""
	hud.close_overlays()
	if id != "" and g:
		g.learn_skill(id, slot)

# ---------------------------------------------------------------- faces
## A skill card: back plate (백판) and frame in the skill's grade colour, hero tag, emblem with grade stars,
## name, per-level effect and the grade line.
func _face(id: String) -> Control:
	var bd := Defs.book(id)
	var sg := int(bd.get("grade", 1))
	var rc: Color = Defs.RARITY_COL[Defs.book_rarity(sg)]
	var root := Panel.new()
	root.size = CARD
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_stylebox_override("panel", hud.box(rc, 20, 5, UiTheme.ink()))
	var inner := Panel.new()
	inner.position = Vector2(9, 9)
	inner.size = CARD - Vector2(18, 18)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", hud.box(rc.lightened(0.3 if sg <= 1 else 0.2), 15, 3, rc.darkened(0.3)))
	root.add_child(inner)
	var cls: String = bd.get("cls", "warrior")
	var hc: Color = Hud.HERO_COL.get(cls, Color.WHITE)
	var tag := hud.panel(hc, Rect2(CARD.x * 0.5 - 56, 20, 112, 34), 17, 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := hud.label(Defs.HEROES[cls]["name"], 19, Color.WHITE, 6)
	tl.size = tag.size
	tag.add_child(tl)
	root.add_child(tag)
	var em := Emblem.new()
	em.grade = sg
	em.col = rc
	em.hero_col = hc
	em.position = Vector2(CARD.x * 0.5 - 46, 60)
	em.size = Vector2(92, 92)
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(em)
	var nt: String = bd.get("name", "?")
	var nm := hud.label(nt, 27 if nt.length() <= 5 else (23 if nt.length() <= 7 else 19), Color.WHITE, 9)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(8, 152)
	nm.size = Vector2(CARD.x - 16, 46)
	root.add_child(nm)
	var ds := hud.label(bd.get("desc", ""), 15, UiTheme.ink(), 0)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.position = Vector2(14, 198)
	ds.size = Vector2(CARD.x - 28, 54)
	root.add_child(ds)
	var gp := hud.panel(rc.darkened(0.45), Rect2(CARD.x * 0.5 - 58, 256, 116, 30), 15, 2)
	gp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gl := hud.label(Defs.book_grade_name(sg), 18, Color.WHITE, 5)
	gl.size = gp.size
	gp.add_child(gl)
	root.add_child(gp)
	return root

# ---------------------------------------------------------------- fx helpers
func _flash_screen(col: Color, a: float, dur: float) -> void:
	_flash.color = Color(col, a)
	_tw().tween_property(_flash, "color:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _shake(px: float, dur := 0.3) -> void:
	var jolt := func(k: float) -> void:
		_stage.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * px * (1.0 - k)
	var tw := _tw()
	tw.tween_method(jolt, 0.0, 1.0, dur)
	tw.tween_callback(func(): _stage.position = Vector2.ZERO)

func _slam(c: Control, from := 2.4) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2.ONE * from
	var rot := c.rotation
	c.rotation = rot - 0.2
	c.modulate.a = 0.0
	var tw := _twn(c)
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.06)
	tw.tween_property(c, "scale", Vector2(1.12, 0.86), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "rotation", rot, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(c, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## 전설: confetti bursting out of the card and fluttering down.
func _confetti(at: Vector2, n: int) -> void:
	var cols := [Color("ffd84a"), Color("ff6fa8"), Color("6fd3ff"), Color("8fe36a"), Color.WHITE]
	for k in n:
		var c := ColorRect.new()
		c.color = cols[k % cols.size()]
		c.size = Vector2(randf_range(8, 14), randf_range(14, 22))
		c.pivot_offset = c.size * 0.5
		c.position = at - c.pivot_offset
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx.add_child(c)
		var a := randf_range(-PI * 0.9, -PI * 0.1)
		var up := at + Vector2(cos(a), sin(a)) * randf_range(160.0, 320.0)
		var tw := _twn(c)
		tw.set_parallel(true)
		tw.tween_property(c, "position", up - c.pivot_offset, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(c, "rotation", randf_range(-8.0, 8.0), 1.3)
		tw.chain().tween_property(c, "position:y", up.y + randf_range(260.0, 420.0), 0.95).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(c, "modulate:a", 0.0, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(c.queue_free)

func _ring(at: Vector2, col: Color, r: float, dur: float, dots := 6) -> void:
	var ring := hud._fly_burst("ring", col, r, at)
	ring.dots = dots
	ring.thick = 1.6
	_fx.add_child(ring)
	var tw := _twn(ring)
	tw.tween_property(ring, "t", 1.0, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ring.queue_free)

func _spark(at: Vector2, col: Color, dist: float, dur: float) -> void:
	var sp := Hud.Sparkle.new()
	sp.col = col
	sp.size = Vector2(26, 26)
	sp.pivot_offset = sp.size * 0.5
	sp.position = at - sp.size * 0.5
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(sp)
	var a := randf() * TAU
	var tw := _twn(sp)
	tw.set_parallel(true)
	tw.tween_property(sp, "position", sp.position + Vector2(cos(a), sin(a) * 0.75) * dist, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "rotation", randf_range(-3.0, 3.0), dur)
	tw.tween_property(sp, "scale", Vector2(0.2, 0.2), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(sp.queue_free)

# ---------------------------------------------------------------- drawn pieces
## Speed lines for the top-grade ascend: the background fills with a gradient and streaks rushing against the
## card's flight, all in one clean tonal family of the grade's colour (mid tone -> light -> pale tint, a few deep
## strokes for contrast).
class SpeedLines extends Control:
	var dir := Vector2.UP          # the card's flight; the streaks rush the other way
	var t := 0.0
	var bg_a := Color.BLACK        # behind (where it flies from)
	var bg_b := Color.BLACK        # ahead
	var cols: Array[Color] = []
	var streaks: Array = []        # [lateral, phase, length, width, speed, colour index]

	func begin(d: Vector2, gc: Color) -> void:
		dir = d.normalized()
		var h := gc.h
		var s := clampf(gc.s, 0.45, 1.0)
		bg_a = Color.from_hsv(h, s * 0.95, 0.82)
		bg_b = Color.from_hsv(h, s * 0.45, 1.0)
		cols = [Color.from_hsv(h, s * 0.1, 1.0, 0.95), Color.from_hsv(h, s * 0.3, 1.0, 0.85),
			Color.from_hsv(h, s, 0.62, 0.75)]
		var d2 := size.length() * 0.5 + 60.0
		streaks.clear()
		for k in 46:
			streaks.append([randf_range(-d2, d2), randf() * 20000.0, randf_range(320.0, 1000.0), randf_range(6.0, 30.0),
				randf_range(6500.0, 10000.0), k % 3])
		t = 0.0
		visible = true
		modulate.a = 0.0
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_property(self, "modulate:a", 1.0, 0.08)
		queue_redraw()

	func end(dur: float) -> void:
		var tw := create_tween().set_ignore_time_scale(true)
		tw.tween_property(self, "modulate:a", 0.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): visible = false)

	func _draw() -> void:
		var c := size * 0.5
		var u := dir
		var v := Vector2(-u.y, u.x)
		var d2 := size.length() * 0.5 + 60.0
		draw_polygon(PackedVector2Array([c - u * d2 - v * d2, c - u * d2 + v * d2, c + u * d2 + v * d2, c + u * d2 - v * d2]),
			PackedColorArray([bg_a, bg_a, bg_b, bg_b]))
		for st in streaks:
			var span: float = d2 * 2.0 + st[2]
			var p: float = d2 - fposmod(st[1] + t * st[4], span)   # rushes towards -u
			var base := c + v * float(st[0]) + u * p
			var l: float = st[2]
			var w: float = st[3] * 0.5
			draw_colored_polygon(PackedVector2Array([base, base + u * l * 0.3 + v * w, base + u * l, base + u * l * 0.3 - v * w]),
				cols[int(st[5])])

## Skill emblem: a round badge in the hero's colour ringed with the grade colour, grade stars on top.
class Emblem extends Control:
	var grade := 1
	var col := Color.WHITE
	var hero_col := Color.WHITE

	func _draw() -> void:
		var ink := UiTheme.ink()
		var c := size * 0.5
		var r := size.x * 0.44
		draw_circle(c, r + 4.0, ink)
		draw_circle(c, r, col.darkened(0.25))
		draw_circle(c, r * 0.78, hero_col)
		draw_circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.22, Color(1, 1, 1, 0.45))
		var n := grade
		for i in n:
			var a := -PI * 0.5 + (i - (n - 1) * 0.5) * 0.5
			_star(c + Vector2(cos(a), sin(a)) * r * 0.42 + Vector2(0, r * 0.25), r * (0.3 if n == 1 else 0.24), ink)

	func _star(p: Vector2, rr: float, ink: Color) -> void:
		var pts := PackedVector2Array()
		var big := PackedVector2Array()
		for i in 10:
			var a := -PI * 0.5 + i * PI / 5.0
			var k := rr if i % 2 == 0 else rr * 0.45
			pts.append(p + Vector2(cos(a), sin(a)) * k)
			big.append(p + Vector2(cos(a), sin(a)) * (k + 3.0))
		draw_colored_polygon(big, ink)
		draw_colored_polygon(pts, Color("ffe14a"))
