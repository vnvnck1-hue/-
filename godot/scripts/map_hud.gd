class_name MapHud
extends Node
## March mode <-> world map:
##   - region chip at the top right under the crystals: map icon, current region name and camps beaten (tap = open map)
##   - the world map overlay: WorldMap diorama rendered in its own SubViewport while the game is paused,
##     speech-bubble name plaques, "CLEAR!" stamps, a title and a card with the current region's progress.
##   - opening / closing transition: CloudFly - low-poly 3D clouds stream fast from left to right, the view
##     dives into the cloud bank, the map / field is swapped while inside, and the view comes out again.
##   - crossing into a new region never opens the map by itself: the region name banner drops in over the field
##     and the chip gets a "!" badge. The next time the player opens the map, the unlock plays once: the region
##     just finished gets a "CLEAR!" stamp, the new one bursts from greyscale into colour and its plaque pops.
## Dev: --test=map taps the chip, captures the map, closes it, then replays the unlock sequence (use --wave=N).

var INK: Color = UiTheme.ink()
const ACCENT := {"meadow": Color("5fbf3c"), "forest": Color("2f9a52"), "desert": Color("e09a3e"),
	"volcano": Color("e2542c"), "mine": Color("8a5ae0"), "frost": Color("4fa6e8")}
const LIFT := 0.32           # field camera pulling up into the sky before the clouds
const FLY := 0.66           # cloud fly-through (in, swap inside the cloud, out)

var hud: Hud
var game: Node
var chip: Panel
var chip_name: Label
var chip_sub: Label
var _r := -1
var _cleared := -1
var _map: WorldMap
var _root: Control
var _plaques: Array = []
var _busy := false            # a cloud transition is running
var _pending_unlock := false  # a region was reached that the map has not shown yet
var _badge: Panel

func build() -> void:
	chip = hud.panel(Color(0.1, 0.08, 0.2, 0.5), Rect2(0, 0, 196, 62), 22, 0)
	chip.add_theme_stylebox_override("panel", UiTheme.capsule(22))
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(hud.place(chip, Vector2(1, 0), Vector2(-212, 146), Vector2(196, 62)))   # top right, under the crystals
	chip.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click", -6.0)
			open_map(_pending_unlock))
	var icon := MapIcon.new()
	icon.position = Vector2(-6, -4)
	icon.size = Vector2(66, 66)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(icon)
	chip_name = hud.label("", 22, Color.WHITE, 8)
	chip_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip_name.position = Vector2(62, 3)
	chip_name.size = Vector2(132, 32)
	chip.add_child(chip_name)
	chip_sub = hud.label("", 17, Color("ffd27a"), 6)
	chip_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	chip_sub.position = Vector2(62, 32)
	chip_sub.size = Vector2(132, 24)
	chip.add_child(chip_sub)
	_badge = hud.panel(Color("ff4f5e"), Rect2(178, -8, 26, 26), 13, 3)
	_badge.visible = false
	chip.add_child(_badge)
	var bl := hud.label("!", 17, Color.WHITE, 4)
	bl.size = Vector2(26, 26)
	_badge.add_child(bl)
	if game.test_mode == "map":
		_test.call_deferred()

# ---------------------------------------------------------------- progress
func region() -> int:
	return game.mw.region_at(game.dist)

func cleared_in(r: int) -> int:
	return clampi(game.wave - 1 - r * Regions.PER_REGION, 0, Regions.PER_REGION)

func _span(r: int) -> Vector2:
	var a: float = 0.0 if r <= 0 else game.mw.region_start(r)
	return Vector2(a, game.mw.region_start(r + 1))

func progress(r: int) -> float:
	var sp := _span(r)
	return clampf((game.dist - sp.x) / (sp.y - sp.x), 0.0, 1.0)

func camps(r: int) -> Array:
	var sp := _span(r)
	var out: Array = []
	for j in Regions.PER_REGION:
		out.append(clampf((game.mw.arena_s(r * Regions.PER_REGION + j + 1) - sp.x) / (sp.y - sp.x), 0.0, 1.0))
	return out

func _process(_delta: float) -> void:
	if game.mw == null:
		return
	var r := region()
	var cl := cleared_in(r)
	if r != _r:
		if _r >= 0 and r > _r:
			print("[Map] enter region ", r, " ", Regions.info(r)["name"], " dist=", int(game.dist))
			_pending_unlock = true
			_badge.visible = true
			_announce(r)
		_r = r
		_cleared = -1
		chip_name.text = Regions.info(r)["name"]
	if cl != _cleared:
		_cleared = cl
		chip_sub.text = "무리 %d / %d" % [cl, Regions.PER_REGION]
	if _map:
		_update_plaques()

## Entering a new region: its name drops in over the field (the march keeps going).
func _announce(r: int) -> void:
	var d := Regions.info(r)
	Sfx.play("chime", -6.0, 0.9)
	if UiTheme.tt():
		hud.ribbon_banner(d["name"], "새로운 지역", ACCENT[d["theme"]], 1.1, -300)
	else:
		hud.banner("새로운 지역", Color("bfe4ff"), 1.1, 38, -360)
		hud.banner(d["name"], ACCENT[d["theme"]].lightened(0.45), 1.1, 92, -290)
	hud.bump(chip, 1.25)

# ---------------------------------------------------------------- open / close with the cloud transition
func open_map(p_unlock := false) -> void:
	if _busy or hud.has_overlay() or game.phase == 4 or Cinematic.active or Skills.aiming or game.drag_stage:   # 4 = P.GAMEOVER
		return
	_busy = true
	if p_unlock:
		_pending_unlock = false
		_badge.visible = false
	var r := region()
	print("[Map] open region=", r, " unlock=", p_unlock)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(root)
	hud.overlay = root
	_root = root
	get_tree().paused = true
	root.tree_exiting.connect(func():
		_map = null
		_root = null
		_plaques.clear()
		if not _busy and game.cam.sky_k > 0.0:   # closed without the cloud pass (Esc): settle back down
			game.cam.create_tween().tween_method(_sky, game.cam.sky_k, 0.0, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		# don't restore a pause captured at open time: an ult intro / skill aim that paused the field may have
		# ended (and unpaused) while the map was up, and restoring it would freeze the battle for good
		if is_inside_tree():
			get_tree().paused = Cinematic.active or Skills.aiming)
	# the field camera pulls back and up toward the sky; the clouds roll in just before it gets there
	var lift: Tween = game.cam.create_tween()
	lift.tween_method(_sky, 0.0, 1.0, LIFT).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await get_tree().create_timer(LIFT * 0.55, true, false, true).timeout
	Sfx.play("whoosh", -6.0, 0.55)
	var fly := CloudFly.new()
	hud.root.add_child(fly)
	fly.setup(hud.root.size)
	await fly.play(FLY, func():
		# inside the cloud: the map takes the field's place underneath
		if is_instance_valid(root):
			_build_map(root, r, p_unlock)
			Sfx.play("poof", -10.0, 0.8))
	fly.queue_free()
	_busy = false
	if p_unlock and is_instance_valid(root):
		_play_unlock(r)

## Field camera pulled up into the sky (0..1) with the fog melting the far ground into the sky.
func _sky(k: float) -> void:
	game.cam.sky_k = k
	game.mw.set_sky_fade(k)

func close_map() -> void:
	if _busy or _root == null or not hud.has_overlay():
		return
	_busy = true
	Sfx.play("whoosh", -6.0, 0.55)
	var fly := CloudFly.new()
	hud.root.add_child(fly)
	fly.setup(hud.root.size)
	await fly.play(FLY, func():
		hud.close_overlays()
		# coming back down out of the sky while the clouds clear
		_sky(1.0)
		game.cam.create_tween().tween_method(_sky, 1.0, 0.0, LIFT * 1.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))
	fly.queue_free()
	_busy = false

func _build_map(root: Control, r: int, p_unlock: bool) -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(hud.root.size)
	svc.add_child(vp)
	_map = WorldMap.new()
	vp.add_child(_map)
	_map.build(r, progress(r), camps(r), cleared_in(r), p_unlock)
	# drag to look around the map
	root.gui_input.connect(func(ev: InputEvent):
		if _map and ev is InputEventMouseMotion and (ev.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_map.pan(ev.relative, root.size.x))
	var vg := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.45)
	gt.fill_to = Vector2(1.1, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.02, 0.1, 0.0))
	g.set_color(1, Color(0.05, 0.02, 0.1, 0.5))
	g.add_point(0.6, Color(0.05, 0.02, 0.1, 0.0))
	gt.gradient = g
	vg.texture = gt
	vg.set_anchors_preset(Control.PRESET_FULL_RECT)
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(vg)
	_build_plaques(root, r, p_unlock)
	_build_title(root, r)
	_build_card(root, r)

func _build_title(root: Control, r: int) -> void:
	var t := hud.label("월드맵", 60, Color.WHITE, 16)
	root.add_child(hud.place(t, Vector2(0.5, 0), Vector2(-200, 26), Vector2(400, 84)))
	var lap := Regions.lap(r)
	if lap > 0:
		var tag := hud.label("%d회차 행군" % (lap + 1), 24, Color("ffd27a"), 8)
		root.add_child(hud.place(tag, Vector2(0.5, 0), Vector2(-100, 102), Vector2(200, 32)))
	var close := hud.juicy_button("X", Color("ff5f6e"), Rect2(0, 0, 78, 78), 40)
	root.add_child(hud.place(close, Vector2(1, 0), Vector2(-100, 26), Vector2(78, 78)))
	close.pressed.connect(close_map)

# ---------------------------------------------------------------- plaques + stamps
func _build_plaques(root: Control, r: int, p_unlock: bool) -> void:
	_plaques.clear()
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(layer)
	for i in Regions.count():
		var d: Dictionary = Regions.LIST[i]
		var st := _map.island_state(i)
		var b := Bubble.new()
		b.font = hud.font
		b.text = "%d. %s" % [i + 1, d["name"]]
		b.kind = "here" if st == "here" else ("done" if st == "done" else ("locked" if st == "locked" else "next"))
		if st == "here" and p_unlock:
			b.kind = "locked"   # turns purple when the region unlocks
		b.fit()
		layer.add_child(b)
		_plaques.append({"node": b, "at": _map.anchors[i], "bubble": true, "i": i})
		if st == "done":
			var just := p_unlock and i == posmod(r - 1, Regions.count())
			var stamp := _stamp(layer)
			stamp.visible = not just
			var c := WorldMap.center(i)
			_plaques.append({"node": stamp, "at": Vector3(c.x - 0.35, _map.top_y(i) + 0.35, c.y - 0.15), "stamp": i})
	# "you are here" tag floating over the trio's map pin
	var tag := hud.panel(Color("ff5f6e"), Rect2(0, 0, 112, 36), 18, 4)
	tag.pivot_offset = Vector2(56, 36)
	tag.visible = not p_unlock
	layer.add_child(tag)
	var tl := hud.label("현재 위치", 21, Color.WHITE, 7)
	tl.size = Vector2(112, 36)
	tag.add_child(tl)
	_plaques.append({"node": tag, "at": _map.marker.position + Vector3(0, 1.75, 0), "tag": true})
	_update_plaques()

## Blue "CLEAR!" stamp (white + navy outline, tilted).
func _stamp(layer: Control) -> Control:
	var box := Control.new()
	box.size = Vector2(200, 80)
	box.pivot_offset = box.size * 0.5
	box.rotation = -0.16
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	var back := hud.label("CLEAR!", 50, Color("1f4fb8"), 26)
	back.label_settings.outline_color = Color("1d2a6a")
	back.size = box.size
	box.add_child(back)
	var front := hud.label("CLEAR!", 50, Color("6fd8ff"), 12)
	front.label_settings.outline_color = Color.WHITE
	front.size = box.size
	box.add_child(front)
	return box

func _update_plaques() -> void:
	if _map == null or _map.cam == null:
		return
	var t := Time.get_ticks_msec() / 1000.0
	for q in _plaques:
		var p: Control = q["node"]
		if not is_instance_valid(p):
			continue
		var sp := _map.cam.unproject_position(q["at"])
		if q.get("bubble", false):
			p.position = sp - Vector2(p.size.x * 0.5, p.size.y)
		elif q.get("tag", false):
			p.position = sp - Vector2(p.size.x * 0.5, p.size.y)
			p.scale = Vector2.ONE * (1.0 + 0.05 * sin(t * 4.0))
		else:
			p.position = sp - p.size * 0.5

## The unlock beat: CLEAR! on the region just finished, then the new region bursts into colour.
func _play_unlock(r: int) -> void:
	var prev := posmod(r - 1, Regions.count())
	var ci := posmod(r, Regions.count())
	await get_tree().create_timer(0.3, true, false, true).timeout
	for q in _plaques:
		if q.get("stamp", -1) == prev and is_instance_valid(q["node"]):
			var s: Control = q["node"]
			s.visible = true
			s.scale = Vector2.ONE * 2.6
			s.modulate.a = 0.0
			var tw := s.create_tween().set_parallel(true)
			tw.tween_property(s, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(s, "modulate:a", 1.0, 0.12)
			Sfx.play("thud", -6.0, 1.2)
	await get_tree().create_timer(0.6, true, false, true).timeout
	if _map == null:
		return
	_map.play_unlock()
	Sfx.play("poof", -4.0, 1.0)
	Sfx.play("fanfare", -10.0, 1.0)
	await get_tree().create_timer(0.18, true, false, true).timeout
	for q in _plaques:
		if not is_instance_valid(q["node"]):
			continue
		if q.get("i", -1) == ci:
			var b: Bubble = q["node"]
			b.kind = "here"
			b.fit()
			b.pivot_offset = Vector2(b.size.x * 0.5, b.size.y)
			b.scale = Vector2.ONE * 1.9
			var tw2 := b.create_tween()
			tw2.tween_property(b, "scale", Vector2.ONE * 2.1, 0.12)
			tw2.tween_interval(0.35)
			tw2.tween_property(b, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN_OUT)
		elif q.get("tag", false):
			var tg: Control = q["node"]
			tg.visible = true
			tg.modulate.a = 0.0
			tg.create_tween().tween_property(tg, "modulate:a", 1.0, 0.3).set_delay(0.7)

## Parchment card: region ribbon, description, ten camp pips (boss last) and march totals.
func _build_card(root: Control, r: int) -> void:
	var d := Regions.info(r)
	var acc: Color = ACCENT[d["theme"]]
	var W := 660.0
	var H := 214.0
	var card := hud.panel(Color("fff4e0"), Rect2(0, 0, W, H), 28, 6)
	root.add_child(hud.place(card, Vector2(0.5, 1), Vector2(-W * 0.5, -H - 22), Vector2(W, H)))
	var rib := hud.panel(acc, Rect2(60, -30, W - 120, 64), 22, 5)
	card.add_child(rib)
	var idx := posmod(r, Regions.count()) + 1
	var nl := hud.label("%d. %s" % [idx, d["name"]], 38, Color.WHITE, 11)
	nl.size = Vector2(W - 120, 64)
	rib.add_child(nl)
	var desc := hud.label(d["desc"], 23, Color("5a4630"), 0)
	desc.position = Vector2(20, 38)
	desc.size = Vector2(W - 40, 40)
	card.add_child(desc)
	var cl := cleared_in(r)
	var pips := PipBar.new()
	pips.cleared = cl
	pips.accent = acc
	pips.position = Vector2(40, 78)
	pips.size = Vector2(W - 80, 52)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pips)
	var left := Regions.PER_REGION - cl
	var s1 := "중간 보스 처치 완료!" if left <= 0 else ("중간 보스와 대결 중!" if left == 1 and game.in_battle() else "중간 보스까지 %d무리" % left)
	var info := hud.label("무리 %d / %d  ·  %s" % [cl, Regions.PER_REGION, s1], 26, INK, 0)
	info.position = Vector2(20, 130)
	info.size = Vector2(W - 40, 40)
	card.add_child(info)
	var nxt := Regions.info(r + 1)
	var foot := hud.label("총 행군 %dm  ·  다음 지역: %s  ·  드래그로 지도 이동" % [int(game.dist), nxt["name"]], 20, Color("8a6a48"), 0)
	foot.position = Vector2(20, 168)
	foot.size = Vector2(W - 40, 36)
	card.add_child(foot)
	card.position.y += 400
	var tw := card.create_tween()
	tw.tween_interval(0.45)
	tw.tween_property(card, "position:y", card.position.y - 400, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- dev
func _test() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	# a real tap on the region chip should open the map
	var at := get_viewport().get_final_transform() * chip.get_global_rect().get_center()
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = at
		Input.parse_input_event(ev)
		await get_tree().process_frame
	await get_tree().process_frame
	print("[Map] chip tap opened map: ", hud.has_overlay(), " paused: ", get_tree().paused)
	for i in 24:
		game._shot_later(0.05 * i, "fly%02d" % i)
	game._shot_later(1.9, "map")
	await get_tree().create_timer(2.2, true, false, true).timeout
	close_map()
	game._shot_later(0.35, "map_close_in")
	game._shot_later(0.95, "map_close_out")
	await get_tree().create_timer(1.4, true, false, true).timeout
	print("[Map] closed: overlay=", hud.has_overlay(), " paused: ", get_tree().paused)
	# replay the unlock of the current region
	open_map(true)
	game._shot_later(1.45, "unlock_clear")
	game._shot_later(2.15, "unlock_burst")
	game._shot_later(2.6, "unlock_pop")
	game._shot_later(3.6, "unlock_done")
	await get_tree().create_timer(4.0, true, false, true).timeout
	Music.quit()

# ---------------------------------------------------------------- drawn widgets
## Speech-bubble plaque: "N. name" with a tail pointing at the island.
##   done = white with a green shield tick, here = purple, locked / next = dark.
class Bubble extends Control:
	var INK: Color = UiTheme.ink()
	var text := ""
	var kind := "locked"
	var font: Font
	var fs := 22

	func fit() -> void:
		fs = 26 if kind == "here" else 22
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 34.0 + (34.0 if kind == "done" else 0.0)
		size = Vector2(w, 46 + 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		var bg := Color("2a2438")
		var fc := Color.WHITE
		match kind:
			"here":
				bg = Color("7a56e8")
			"done":
				bg = Color("fffaf0")
				fc = INK
			"next":
				bg = Color("3a3450")
		var r := Rect2(0, 0, size.x, size.y - 12)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(4)
		sb.border_color = INK
		sb.shadow_color = Color(0, 0, 0, 0.3)
		sb.shadow_offset = Vector2(0, 4)
		sb.shadow_size = 1
		sb.anti_aliasing = true
		draw_style_box(sb, r)
		var cx := size.x * 0.5
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 12, r.end.y - 4), Vector2(cx + 12, r.end.y - 4), Vector2(cx, size.y)]), INK)
		draw_colored_polygon(PackedVector2Array([Vector2(cx - 7, r.end.y - 5), Vector2(cx + 7, r.end.y - 5), Vector2(cx, size.y - 6)]), bg)
		var x := 17.0
		if kind == "done":
			var c := Vector2(x + 12, r.size.y * 0.5)
			var shield := PackedVector2Array([c + Vector2(-12, -13), c + Vector2(12, -13), c + Vector2(12, 2), c + Vector2(0, 14), c + Vector2(-12, 2)])
			draw_colored_polygon(shield, INK)
			var inner := PackedVector2Array()
			for pnt in shield:
				inner.append(c + (pnt - c) * 0.75)
			draw_colored_polygon(inner, Color("7fd23a"))
			draw_polyline(PackedVector2Array([c + Vector2(-5, -1), c + Vector2(-1, 4), c + Vector2(6, -6)]), INK, 3.0, true)
			x += 34.0
		var base := r.size.y * 0.5 + fs * 0.36
		if fc == Color.WHITE:
			draw_string_outline(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, INK)
		draw_string(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, fc)

## Ten camp pips: beaten ones gold with a tick, the next one pulsing, the last one the mid-boss skull.
class PipBar extends Control:
	var INK: Color = UiTheme.ink()
	var cleared := 0
	var accent := Color.WHITE
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta / maxf(Engine.time_scale, 0.001)
		queue_redraw()

	func _draw() -> void:
		var n := Regions.PER_REGION
		var gap := size.x / n
		var cy := size.y * 0.5
		draw_line(Vector2(gap * 0.5, cy), Vector2(size.x - gap * 0.5, cy), Color("d8c4a0"), 8.0)
		if cleared > 0:
			draw_line(Vector2(gap * 0.5, cy), Vector2(gap * (minf(cleared, n - 1) + 0.5), cy), Color("f2b53a"), 8.0)
		for k in n:
			var c := Vector2(gap * (k + 0.5), cy)
			var boss := k == n - 1
			var r := 21.0 if boss else 14.0
			var done := k < cleared
			var nxt := k == cleared
			if nxt:
				r *= 1.0 + 0.12 * sin(_t * 6.0)
			draw_circle(c, r + 4.0, INK)
			var fill := Color("ffcf40") if done else (Color("ff5f6e") if boss else (accent if nxt else Color("efe2c8")))
			draw_circle(c, r, fill)
			if done:
				draw_polyline(PackedVector2Array([c + Vector2(-7, 0), c + Vector2(-2, 6), c + Vector2(8, -6)]), INK, 4.0, true)
			elif boss:
				draw_circle(c + Vector2(0, -2), 10.0, Color("fff4e0"))
				draw_rect(Rect2(c.x - 6, c.y + 4, 12, 6), Color("fff4e0"))
				draw_circle(c + Vector2(-4, -3), 3.0, INK)
				draw_circle(c + Vector2(4, -3), 3.0, INK)
				for sx in [-1.0, 1.0]:
					draw_colored_polygon(PackedVector2Array([c + Vector2(sx * 9, -12), c + Vector2(sx * 17, -24), c + Vector2(sx * 4, -16)]), INK)

## Small folded parchment map with a red X and a dotted route (toy style: thick ink outline).
class MapIcon extends Control:
	var INK: Color = UiTheme.ink()

	func _draw() -> void:
		var s := size.x
		var pts := PackedVector2Array([Vector2(0.12, 0.26), Vector2(0.38, 0.16), Vector2(0.62, 0.26), Vector2(0.88, 0.16),
			Vector2(0.88, 0.74), Vector2(0.62, 0.84), Vector2(0.38, 0.74), Vector2(0.12, 0.84)])
		var outer := PackedVector2Array()
		var inner := PackedVector2Array()
		var c := Vector2(0.5, 0.5)
		for p in pts:
			outer.append((c + (p - c) * 1.14) * s)
			inner.append(p * s)
		draw_colored_polygon(outer, INK)
		draw_colored_polygon(inner, Color("f6e2b0"))
		draw_colored_polygon(PackedVector2Array([inner[1], inner[2], inner[5], inner[6]]), Color("e6cc92"))
		draw_line(inner[1], inner[6], Color("c8a870"), 2.0)
		draw_line(inner[2], inner[5], Color("c8a870"), 2.0)
		var dots := [Vector2(0.22, 0.66), Vector2(0.3, 0.56), Vector2(0.4, 0.5), Vector2(0.5, 0.46), Vector2(0.6, 0.42)]
		for dp in dots:
			draw_circle(dp * s, s * 0.025, Color("3fa9f5"))
		var x := Vector2(0.72, 0.38) * s
		var k := s * 0.07
		draw_line(x - Vector2(k, k), x + Vector2(k, k), Color("e2412c"), s * 0.06)
		draw_line(x + Vector2(-k, k), x + Vector2(k, -k), Color("e2412c"), s * 0.06)
