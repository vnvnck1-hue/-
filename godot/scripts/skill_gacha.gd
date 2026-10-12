class_name SkillGacha
extends Control
## 스킬북 룰렛 (콩콩던전 스킬 뽑기식) — presentation and the pick. Rules live in Main: roll_book_offers (what the
## reels land on, capped by the book's grade), learn_skill (what the kept skill does). Opened by Main.use_book
## over a paused field; the book is already spent.
##   intro  : the book drops onto a backdrop in its grade colour; the grade plate and the odds chips slam in.
##   spin   : three reels spin together ("촤르르륵", ticking), then one by one each slows down and lands on its
##            skill. A reel about to land on 영웅 / 전설 slows longer while its frame throbs in that colour.
##   reveal : the landing grows with the skill's grade — 일반 a pop, 희귀 a blue ring and sparks, 영웅 a flash,
##            purple rays, a shake and an "영웅!" stamp, 전설 a whiteout, a gold backdrop, giant rays, a hard
##            shake, a "전설 스킬!" banner and confetti. Every card's back plate (백판) is its grade's colour.
##   pick   : tap a card to learn it (a hero with every slot taken first picks a skill to forget), or [건너뛰기].
## A tap while the reels spin lands the rest right away. Registered as hud.overlay (closing unpauses the field).

const REEL := Vector2(200, 300)
const REEL_GAP := 22.0
const REEL_Y := 110.0            # reel centre, relative to the screen centre
const SPIN_SPEED := 16.0         # cells / s
const STAMP := {2: "희귀!", 3: "영웅!", 4: "전설!"}
const BG_GOLD := 3               # ChestGacha.BG index of the 전설 backdrop

var hud: Hud
var game: Node
var grade := 1
var offers: Array = []
var state := ""                  # intro / spin / pick / slot / done
var fast := false                # tapped while spinning: the remaining reels land at once

var _stage: Control
var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _bg_now: Array = []
var _rays: Hud.RayBurst
var _fx: Control
var _flash: ColorRect
var _hint: Label
var _skip_b: Button
var _reels: Array[Reel] = []
var _frames: Array[Panel] = []
var _faces: Array = []           # landed face per reel
var _spin_rays: Array[Control] = []
var _slot_box: Control
var _t := 0.0
var _spin := 0.0
var _tick_t := -1.0
var _face_pool := {}             # skill grade -> ids that flash past on the reels
static var _bg_shader: Shader

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
	for id in Defs.SKILL_BOOKS:
		var sg: int = Defs.SKILL_BOOKS[id]["grade"]
		if sg <= grade:
			if not _face_pool.has(sg):
				_face_pool[sg] = []
			_face_pool[sg].append(id)
	hud.close_overlays()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(self)
	hud.overlay = self
	_build()
	_run()

func _build() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _bg_shader == null:
		_bg_shader = Shader.new()
		_bg_shader.code = ChestGacha.SHADER
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = _bg_shader
	_bg.material = _bg_mat
	add_child(_bg)
	_set_bg(grade - 1, 0.0)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_rays = Hud.RayBurst.new()
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rays.col = (ChestGacha.BG[grade - 1][0] as Color).lerp(ChestGacha.BG[grade - 1][1], 0.3)
	_stage.add_child(hud.place(_rays, Vector2(0.5, 0.5), Vector2(-520, REEL_Y - 520), Vector2(1040, 1040)))
	_rays.pivot_offset = Vector2(520, 520)
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
	_spin += dt * 0.6
	if _bg_mat:
		_bg_mat.set_shader_parameter("phase", _spin)
		_bg_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
		_bg_mat.set_shader_parameter("center", Vector2(0.5, (size.y * 0.5 + REEL_Y) / maxf(1.0, size.y)))
	if _rays:
		_rays.rotation += dt * 0.22
	for r in _spin_rays:
		if is_instance_valid(r):
			r.rotation += dt * 0.9
	for r in _reels:
		if r.spinning:
			r.pos += r.speed * dt
	if _hint and (state == "spin" or state == "pick"):
		var s := 1.0 + sin(_t * 6.0) * 0.05
		_hint.scale = Vector2(s, s)

func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tap()

## A tap on the background: hurries the reels.
func tap() -> void:
	if state == "spin" and not fast:
		fast = true
		Sfx.play("click", -6.0, 1.4)

# ---------------------------------------------------------------- the show
func _run() -> void:
	state = "intro"
	var rc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(grade)])
	var title := hud.label("스킬 뽑기", 56, Color.WHITE, 16)
	_stage.add_child(hud.place(title, Vector2(0.5, 0.0), Vector2(-300, 54), Vector2(600, 80)))
	_slam(title, 2.2)
	# the book drops in
	var book := ItemIcon.new({"kind": "skillbook", "grade": grade})
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(hud.place(book, Vector2(0.5, 0.5), Vector2(-66, REEL_Y - 530), Vector2(132, 132)))
	book.pivot_offset = Vector2(66, 120)
	var by := book.position.y
	book.position.y -= 420.0
	var bt := _twn(book)
	bt.tween_property(book, "position:y", by, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	bt.tween_property(book, "scale", Vector2(1.25, 0.75), 0.07)
	bt.tween_property(book, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Sfx.play("whoosh", -6.0, 0.9)
	await _sleep(0.34)
	Sfx.play("thud", -3.0, 1.0)
	_ring(book.position + book.size * 0.5, rc, 70.0, 0.4)
	# grade plate + "최대 n등급" + odds chips
	var plate := Panel.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_stylebox_override("panel", hud.box(rc, 26, 5, UiTheme.ink()))
	_stage.add_child(hud.place(plate, Vector2(0.5, 0.5), Vector2(-170, REEL_Y - 390), Vector2(340, 68)))
	var pl := hud.label("%s 스킬북" % Defs.book_grade_name(grade), 40, Color.WHITE, 12)
	pl.size = plate.size
	plate.add_child(pl)
	_slam(plate, 2.0)
	Sfx.play("pop", -4.0, 0.9 + 0.1 * grade)
	var cap := hud.label("최대 %s 스킬까지 등장!" % Defs.book_grade_name(grade), 26, Color("fff4c0"), 9)
	_stage.add_child(hud.place(cap, Vector2(0.5, 0.5), Vector2(-300, REEL_Y - 316), Vector2(600, 40)))
	var odds: Array = Defs.BOOK_ROLL.get(grade, [1.0])
	var cw := 122.0
	var x0 := -(odds.size() * cw + (odds.size() - 1) * 8.0) * 0.5
	for k in odds.size():
		var oc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(k + 1)])
		var chip := hud.panel(oc.darkened(0.15), Rect2(0, 0, cw, 36), 18, 3)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cl := hud.label("%s %d%%" % [Defs.book_grade_name(k + 1), roundi(float(odds[k]) * 100.0)], 19, Color.WHITE, 6)
		cl.size = chip.size
		chip.add_child(cl)
		_stage.add_child(hud.place(chip, Vector2(0.5, 0.5), Vector2(x0 + k * (cw + 8.0), REEL_Y - 270), Vector2(cw, 36)))
		hud.pop_in(chip, 0.2, 0.3)
	# the three reels pop in
	for i in offers.size():
		_add_reel(i)
	_hint = hud.label("탭하면 빨리 멈춰요", 26, Color.WHITE, 9)
	_stage.add_child(hud.place(_hint, Vector2(0.5, 0.5), Vector2(-300, REEL_Y + REEL.y * 0.5 + 34), Vector2(600, 44)))
	_hint.pivot_offset = Vector2(300, 22)
	await _sleep(0.35)
	# spin: all together, then they land one by one
	state = "spin"
	for r in _reels:
		r.speed = SPIN_SPEED
		r.spinning = true
	Sfx.play("rise", -9.0, 1.4)
	await _sleep(0.15 if fast else 0.75)
	for i in _reels.size():
		await _land(i)
		await _sleep(0.05 if fast else 0.22)
	_ready_to_pick()

func _reel_x(i: int) -> float:
	var n := offers.size()
	var w := n * REEL.x + (n - 1) * REEL_GAP
	return -w * 0.5 + i * (REEL.x + REEL_GAP)

func _add_reel(i: int) -> void:
	var frame := Panel.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", hud.box(Color("2a2140"), 26, 6, UiTheme.ink()))
	var pad := 10.0
	_stage.add_child(hud.place(frame, Vector2(0.5, 0.5), Vector2(_reel_x(i) - pad, REEL_Y - REEL.y * 0.5 - pad), REEL + Vector2(pad, pad) * 2.0))
	frame.pivot_offset = frame.size * 0.5
	_frames.append(frame)
	var r := Reel.new()
	r.g = self
	r.position = Vector2(pad, pad)
	r.size = REEL
	r.pos = randf() * 3.0
	frame.add_child(r)
	_reels.append(r)
	_faces.append(null)
	frame.scale = Vector2.ZERO
	var tw := _twn(frame)
	tw.tween_interval(0.07 * i)
	tw.tween_property(frame, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A random face for the tape (weighted by the book's odds, so the high grades only flash by now and then).
func _random_face() -> String:
	var odds: Array = Defs.BOOK_ROLL.get(grade, [1.0])
	var x := randf()
	var g := 1
	for k in odds.size():
		x -= float(odds[k])
		g = k + 1
		if x <= 0.0:
			break
	var list: Array = _face_pool.get(g, _face_pool.get(1, []))
	return list[randi() % list.size()] if not list.is_empty() else offers[0]

## One reel slows down and lands on its skill: a longer slowdown, a throbbing frame for 영웅 / 전설.
func _land(i: int) -> void:
	var r := _reels[i]
	var id: String = offers[i]
	var sg := int(Defs.book(id)["grade"])
	var big := sg >= 3 and not fast
	var extra := 2 if fast else (5 if sg <= 2 else (8 if sg == 3 else 11))
	var target := ceili(r.pos) + extra
	r.tape[target] = id
	if big:   # near misses: high-grade faces flash right before the stop
		for k in [2, 4]:
			var tease: Array = _face_pool.get(sg, [])
			if not tease.is_empty():
				r.tape[target - k] = tease[randi() % tease.size()]
	r.spinning = false
	var trans := Tween.TRANS_QUART if big else Tween.TRANS_CUBIC
	var dur := (4.0 if big else 3.0) * (float(target) - r.pos) / SPIN_SPEED
	if big:
		_suspense(i, sg, dur)
	var tw := _tw()
	tw.tween_property(r, "pos", float(target) + 0.12, dur).set_trans(trans).set_ease(Tween.EASE_OUT)
	tw.tween_property(r, "pos", float(target), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tw.finished
	_faces[i] = r.face_at(target)
	await _reveal(i, id, sg)

## Before a big stop: the frame throbs in the grade colour, the light rises; 전설 also dims the room.
func _suspense(i: int, sg: int, dur: float) -> void:
	var frame := _frames[i]
	var gc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(sg)])
	frame.add_theme_stylebox_override("panel", hud.box(Color("2a2140"), 26, 8, gc))
	var beats := maxi(2, int(dur / 0.32))
	var tw := _twn(frame)
	for k in beats:
		tw.tween_property(frame, "scale", Vector2(1.05, 1.05), 0.08)
		tw.tween_property(frame, "scale", Vector2.ONE, 0.2)
	Sfx.play("rise", -6.0, 0.7 if sg >= 4 else 0.9)
	if sg >= 4:
		var dim := ColorRect.new()
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dim.color = Color(0.03, 0.01, 0.08, 0.0)
		_stage.add_child(dim)
		_stage.move_child(dim, frame.get_index())
		var dt := _twn(dim)
		dt.tween_property(dim, "color:a", 0.55, dur * 0.6)
		dt.tween_interval(dur * 0.4)
		dt.tween_property(dim, "color:a", 0.0, 0.25)
		dt.tween_callback(dim.queue_free)
		for k in beats:
			_sleep(k * 0.32).connect(func(): Sfx.play("thud", -8.0, 0.7 + 0.04 * k))

# ---------------------------------------------------------------- reveal
## The landing, louder with the skill's grade.
func _reveal(i: int, id: String, sg: int) -> void:
	var frame := _frames[i]
	var at := frame.position + frame.size * 0.5
	var gc := Hud._vivid(Defs.RARITY_COL[Defs.book_rarity(sg)])
	frame.add_theme_stylebox_override("panel", hud.box(gc.darkened(0.2), 26, 8, UiTheme.ink() if sg <= 1 else gc.lightened(0.35)))
	var face: Control = _faces[i]
	if face:
		_status_tag(face, id)
	var tw := _twn(frame)
	tw.tween_property(frame, "scale", Vector2(1.1 + 0.06 * sg, 1.1 + 0.06 * sg), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(frame, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	match sg:
		1:
			Sfx.play("pop", -3.0, 1.0 + 0.1 * i)
			_ring(at, Color.WHITE, 90.0, 0.4, 6)
			await _sleep(0.12)
		2:
			Sfx.play("pop", -2.0, 1.1)
			Sfx.play("chime", -7.0, 1.25)
			_ring(at, gc, 110.0, 0.45, 10)
			for k in 8:
				_spark(at, gc if k % 2 == 0 else Color.WHITE, randf_range(140.0, 210.0), 0.55)
			_stamp(frame, sg, gc)
			await _sleep(0.3)
		3:
			_flash_screen(Color(1, 1, 1), 0.55, 0.3)
			_card_rays(frame, gc, 460.0)
			_aura_loop(frame, gc)
			_shake(10.0, 0.3)
			Sfx.play("boom", -8.0, 1.4)
			Sfx.play("chime", -3.0, 1.35)
			Sfx.play("sparkle", -4.0, 1.1)
			_ring(at, gc, 130.0, 0.5, 12)
			hud._sparkles(_fx, at, 16)
			_stamp(frame, sg, gc)
			await _sleep(0.6)
		_:
			_flash_screen(Color(1, 0.97, 0.85), 0.95, 0.5)
			_set_bg(BG_GOLD, 0.4)
			_rays.col = Color("fff2a8")
			_rays.queue_redraw()
			_rays.scale = Vector2(0.4, 0.4)
			_twn(_rays).tween_property(_rays, "scale", Vector2(1.35, 1.35), 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			_card_rays(frame, gc, 620.0)
			_aura_loop(frame, gc)
			_shine_loop(face)
			_shake(20.0, 0.55)
			Sfx.play("boom", -3.0, 0.8)
			Sfx.play("fanfare", -3.0, 1.0)
			Sfx.play("sparkle", -2.0, 1.3)
			_ring(at, gc, 160.0, 0.6, 16)
			_ring(at, Color.WHITE, 220.0, 0.8, 10)
			for k in 26:
				_spark(at, [gc, Color.WHITE, Color("fff27a"), Color("ff9ad8")][k % 4], randf_range(220.0, 420.0), 0.9)
			hud._sparkles(_fx, at, 24)
			_stamp(frame, sg, gc)
			_banner("전설 스킬!", gc)
			for k in _frames.size():   # the 전설 card stands alone in the light
				if k != i:
					_twn(_frames[k]).tween_property(_frames[k], "modulate", Color(0.72, 0.72, 0.78), 0.3)
			await _sleep(1.1)

## The status of a landed skill: NEW (free slot) / Lv.n→n+1 / 교체 (its hero's slots are full).
func _status_tag(face: Control, id: String) -> void:
	var bd := Defs.book(id)
	var h: Actor = game.hero(bd["cls"]) if game else null
	var text := "NEW"
	var col := Color("3fbf4a")
	if h:
		var li: int = game.learned_index(h, id)
		if li >= 0:
			var lv := int(h.learned[li]["level"])
			text = "Lv.%d→%d" % [lv, lv + 1]
			col = Color("2f78d0")
		elif game.needs_slot(id):
			text = "교체"
			col = Color("e0543a")
	var tag := hud.panel(col, Rect2(REEL.x - 104, -4, 108, 34), 17, 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.rotation = 0.12
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

## Rotating light rays behind a landed 영웅 / 전설 card (kept until the pick).
func _card_rays(frame: Control, gc: Color, d: float) -> void:
	var rays := Hud.RayBurst.new()
	rays.col = gc.lightened(0.45)
	rays.size = Vector2(d, d)
	rays.position = frame.position + frame.size * 0.5 - rays.size * 0.5
	rays.pivot_offset = rays.size * 0.5
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.scale = Vector2.ZERO
	_stage.add_child(rays)
	_stage.move_child(rays, frame.get_index())
	_spin_rays.append(rays)
	_twn(rays).tween_property(rays, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## A glow breathing behind the card for as long as it is on screen.
func _aura_loop(frame: Control, gc: Color) -> void:
	var aura := hud._fly_burst("aura", gc, frame.size.y * 0.62, frame.size * 0.5)
	aura.show_behind_parent = true
	aura.modulate.a = 0.0
	frame.add_child(aura)
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
	_fx.add_child(hud.place(l, Vector2(0.5, 0.5), Vector2(-360, REEL_Y - 420), Vector2(720, 120)))
	_slam(l, 3.2)
	var tw := _twn(l)
	tw.tween_interval(0.75)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)

# ---------------------------------------------------------------- pick
func _ready_to_pick() -> void:
	state = "pick"
	_hint.text = "배울 스킬을 하나 고르세요"
	for i in _frames.size():
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.size = _frames[i].size
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		for st in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
		var idx := i
		b.pressed.connect(func(): _pick(idx))
		b.mouse_entered.connect(func(): _hover(idx, true))
		b.mouse_exited.connect(func(): _hover(idx, false))
		_frames[i].add_child(b)
	_skip_b = hud.juicy_button("건너뛰기", Color("8a8aa0"), Rect2(0, 0, 200, 56), 24)
	_skip_b.pressed.connect(func():
		if state == "pick":
			_close(-1, -1))
	_stage.add_child(hud.place(_skip_b, Vector2(0.5, 0.5), Vector2(-100, REEL_Y + REEL.y * 0.5 + 100), Vector2(200, 56)))
	hud.pop_in(_skip_b, 0.3, 0.3)
	if game and game.get("autoplay"):
		await _sleep(0.6)
		var best: Array = game.best_offer(offers)
		var bi := offers.find(best[0])
		if bi >= 0:
			_finish(bi, best[1])
		else:
			_close(-1, -1)

func _hover(i: int, on: bool) -> void:
	if state == "pick" or not on:
		Hud.retween(_frames[i]).tween_property(_frames[i], "scale", Vector2(1.05, 1.05) if on else Vector2.ONE, 0.12)

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
		var f := _frames[k]
		var tw := _twn(f)
		if k == i:
			_stage.move_child(f, _stage.get_child_count() - 1)
			tw.tween_property(f, "scale", Vector2(1.25, 1.25), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
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
	root.size = REEL
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_stylebox_override("panel", hud.box(rc, 20, 5, UiTheme.ink()))
	var inner := Panel.new()
	inner.position = Vector2(9, 9)
	inner.size = REEL - Vector2(18, 18)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", hud.box(rc.lightened(0.3 if sg <= 1 else 0.2), 15, 3, rc.darkened(0.3)))
	root.add_child(inner)
	var cls: String = bd.get("cls", "warrior")
	var hc: Color = Hud.HERO_COL.get(cls, Color.WHITE)
	var tag := hud.panel(hc, Rect2(REEL.x * 0.5 - 56, 20, 112, 34), 17, 3)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := hud.label(Defs.HEROES[cls]["name"], 19, Color.WHITE, 6)
	tl.size = tag.size
	tag.add_child(tl)
	root.add_child(tag)
	var em := Emblem.new()
	em.grade = sg
	em.col = rc
	em.hero_col = hc
	em.position = Vector2(REEL.x * 0.5 - 46, 60)
	em.size = Vector2(92, 92)
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(em)
	var nt: String = bd.get("name", "?")
	var nm := hud.label(nt, 27 if nt.length() <= 5 else (23 if nt.length() <= 7 else 19), Color.WHITE, 9)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(8, 152)
	nm.size = Vector2(REEL.x - 16, 46)
	root.add_child(nm)
	var ds := hud.label(bd.get("desc", ""), 15, UiTheme.ink(), 0)
	ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ds.position = Vector2(14, 198)
	ds.size = Vector2(REEL.x - 28, 54)
	root.add_child(ds)
	var gp := hud.panel(rc.darkened(0.45), Rect2(REEL.x * 0.5 - 58, 256, 116, 30), 15, 2)
	gp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gl := hud.label(Defs.book_grade_name(sg), 18, Color.WHITE, 5)
	gl.size = gp.size
	gp.add_child(gl)
	root.add_child(gp)
	return root

# ---------------------------------------------------------------- fx helpers
func _set_bg(t: int, dur: float) -> void:
	var to: Array = ChestGacha.BG[clampi(t, 0, ChestGacha.BG.size() - 1)]
	if _bg_now.is_empty() or dur <= 0.0:
		_bg_now = to.duplicate()
		_apply_bg(_bg_now)
		return
	var from := _bg_now.duplicate()
	var blend := func(k: float) -> void:
		for i in 3:
			_bg_now[i] = (from[i] as Color).lerp(to[i], k)
		_apply_bg(_bg_now)
	_tw().tween_method(blend, 0.0, 1.0, dur)

func _apply_bg(c: Array) -> void:
	_bg_mat.set_shader_parameter("c_in", c[0])
	_bg_mat.set_shader_parameter("c_out", c[1])
	_bg_mat.set_shader_parameter("c_low", c[2])

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

## Reel tick ("촤르르륵"): one click per card passing, never two on the same frame.
func _tick() -> void:
	if _t - _tick_t < 0.04:
		return
	_tick_t = _t
	Sfx.play("tick", -13.0, randf_range(1.25, 1.5))

# ---------------------------------------------------------------- drawn pieces
## One slot-machine reel: an endless tape of skill faces (virtual index n; n increases as it spins, so the faces
## roll downward). `pos` is the tape position in cells; face n sits at y = (pos - n) * height.
class Reel extends Control:
	var g: SkillGacha
	var speed := 0.0
	var spinning := false
	var tape := {}                 # n -> skill id (rolled lazily)
	var _cells: Array = [null, null, null]
	var _cell_n: Array = [-999999, -999999, -999999]
	var pos := 0.0:
		set(v):
			if floori(v) != floori(pos) and g:
				g._tick()
			pos = v
			_layout()

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _ready() -> void:
		_layout()

	func id_at(n: int) -> String:
		if not tape.has(n):
			tape[n] = g._random_face()
		return tape[n]

	func face_at(n: int) -> Control:
		var k := posmod(n, 3)
		return _cells[k] if _cell_n[k] == n else null

	func _layout() -> void:
		if g == null or not is_inside_tree():
			return
		var base := floori(pos)
		for j in 3:
			var n := base - 1 + j
			var k := posmod(n, 3)
			if _cell_n[k] != n:
				if _cells[k]:
					_cells[k].queue_free()
				_cells[k] = g._face(id_at(n))
				add_child(_cells[k])
				_cell_n[k] = n
			(_cells[k] as Control).position = Vector2(0, (pos - n) * size.y)

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
