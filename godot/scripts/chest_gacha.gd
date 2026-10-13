class_name ChestGacha
extends Control
## 보물상자 상자깡 화면 — presentation only. Reference: Squad Busters chest "Tap to Power Up!"
## (ArtStation, Octopo VFX "Chest Jackpot / Rarity Swap / Lucky Find"). Rules live in ChestLoot,
## bag / gold changes in Main.chest_reward / chest_take.
##   intro   : the chest drops onto a swirling tier-coloured backdrop, squashes and bounces.
##   tap x4  : every tap squashes the chest and lights a pip; a lucky tap charges it up (shake, speed lines
##             rushing in, sparkles sucked in, a golden comet ring sweeping round), whites out, and the chest
##             comes back one tier higher — new colours, new backdrop, the rarity plate slams in, confetti.
##   open    : anticipation squash + shake, a jump, the lid flies open in a light pillar; item cards shoot out
##             of the chest, land in a row and flip one by one (rarity ring + stars, "대박!" for the best).
##   collect : [받기] the cards fly into the bag; [다음 상자] they drop into the bag and the next chest arrives.
## Registered as hud.overlay: closing it (hud.close_overlays) unpauses the field (Main.open_chests).

const CHEST_Y := -80.0          # chest view centre, relative to the screen centre
const VIEW := 900.0              # 3D view is wider than the chest so pops / jumps never clip
const CARD := Vector2(150, 204)
const CARD_Y := 250.0
## Backdrop per tier: centre glow, outer, lower tint (일반 sky / 희귀 blue / 영웅 purple / 전설 gold).
const BG := [
	[Color("f2fdff"), Color("4cc0ff"), Color("d7a8ff")],
	[Color("e2f2ff"), Color("2266ee"), Color("27b4ff")],
	[Color("fbe8ff"), Color("8a2cf0"), Color("ff66d2")],
	[Color("fffbe2"), Color("ff8f12"), Color("ffd84a")],
]
const SHADER := """
shader_type canvas_item;
uniform vec4 c_in : source_color = vec4(1.0);
uniform vec4 c_out : source_color = vec4(0.3, 0.75, 1.0, 1.0);
uniform vec4 c_low : source_color = vec4(0.85, 0.65, 1.0, 1.0);
uniform float phase = 0.0;
uniform float lines = 0.0;
uniform float glow = 1.0;
uniform vec2 center = vec2(0.5, 0.44);
uniform float aspect = 0.5625;

float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }

void fragment() {
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float r = length(p);
	float a = atan(p.y, p.x);
	vec3 col = mix(c_in.rgb, c_out.rgb, smoothstep(0.03, 0.6, r));
	col = mix(col, c_low.rgb, smoothstep(0.02, 0.5, UV.y - center.y) * 0.8);
	// soft toon swirl arms turning round the chest
	float s = sin(a * 4.0 - log(r + 0.03) * 5.5 + phase);
	float band = smoothstep(0.3, 0.8, s) * smoothstep(0.05, 0.32, r);
	col = mix(col, col * vec3(0.8, 0.85, 0.94), band * 0.42);
	// concentric glow rings + hot centre
	col += vec3(1.0) * glow * (exp(-r * r * 26.0) * 0.6 + exp(-r * r * 7.0) * 0.14);
	float ring = 1.0 - smoothstep(0.0, 0.035, abs(fract(r * 3.2 - phase * 0.08) - 0.5));
	col = mix(col, vec3(1.0), ring * 0.08 * (1.0 - smoothstep(0.2, 0.7, r)));
	// speed lines rushing into the centre while the chest charges
	float seg = (a + 3.14159) / 6.28318 * 90.0;
	float h = hash(floor(seg));
	float flow = fract(r * 1.4 + phase * (0.5 + h) * 0.6 + h * 9.0);
	float streak = step(0.6, h) * smoothstep(0.0, 0.06, flow) * (1.0 - smoothstep(0.18, 0.42, flow));
	streak *= (1.0 - smoothstep(0.1, 0.42, abs(fract(seg) - 0.5))) * smoothstep(0.1, 0.3, r);
	col = mix(col, vec3(1.0), streak * lines * 0.9);
	col *= 1.0 - smoothstep(0.55, 1.15, r) * 0.28;
	COLOR = vec4(col, 1.0);
}
"""

var hud: Hud
var game: Node
var tier := 0
var taps_left := ChestLoot.TAPS
var state := ""                # intro / tap / open / opening / result / busy
var force: Array = []          # dev: forced tap outcomes (true = tier up)
var reward := {}

var _stage: Control
var _bg: ColorRect
var _bg_mat: ShaderMaterial
var _rays: Hud.RayBurst
var _pillar: Pillar
var _vp: SubViewport
var _cam3: Camera3D
var _rim: OmniLight3D
var _view: TextureRect
var chest: ChestModel
var _plate: Panel
var _plate_l: Label
var _title: Label
var _count: Label
var _tap_l: Label
var _hint_l: Label
var _pips: Array[Pip] = []
var _fx: Control
var _flash: ColorRect
var _cards: Array[Control] = []
var _extras: Array[Control] = []   # result-phase nodes (gold pill, buttons, card auras) cleared per chest
var _gold_l: Label
var _spin := 0.0
var _spin_boost := 0.0
var _lines := 0.0
var _t := 0.0
var _idle := true
var _bg_now: Array = []
static var _bg_shader: Shader   # compiled once per session, not per chest screen

# ---------------------------------------------------------------- build
func _tw() -> Tween:
	return create_tween().set_ignore_time_scale(true)

func _twn(n: Node) -> Tween:
	return n.create_tween().set_ignore_time_scale(true)

func _sleep(t: float) -> Signal:
	var tw := _tw()
	tw.tween_interval(t)
	return tw.finished

## Builds the screen on top of the HUD (as its overlay) and drops in the first chest.
func start(t: int) -> void:
	hud.close_overlays()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(self)
	hud.overlay = self
	_build()
	_begin(t)

func _build() -> void:
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _bg_shader == null:
		_bg_shader = Shader.new()
		_bg_shader.code = SHADER
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = _bg_shader
	_bg.material = _bg_mat
	add_child(_bg)
	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_rays = Hud.RayBurst.new()
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(hud.place(_rays, Vector2(0.5, 0.5), Vector2(-480, CHEST_Y - 480), Vector2(960, 960)))
	_pillar = Pillar.new()
	_pillar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(hud.place(_pillar, Vector2(0.5, 0.5), Vector2(-150, CHEST_Y - 700), Vector2(300, 700)))
	_pillar.pivot_offset = Vector2(150, 700)
	_pillar.visible = false
	# 3D chest in its own little world
	_vp = SubViewport.new()
	_vp.size = Vector2i(int(VIEW), int(VIEW))
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d8dcff")
	env.ambient_light_energy = 0.75
	WebLook.apply(env)
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.light_energy = 1.25
	key.light_color = Color("fff4e4")
	_vp.add_child(key)
	key.rotation = Vector3(-0.75, 0.55, 0)
	var fill := DirectionalLight3D.new()
	fill.light_energy = 0.35
	fill.light_color = Color("c8d8ff")
	_vp.add_child(fill)
	fill.rotation = Vector3(-0.3, -1.3, 0)
	_rim = OmniLight3D.new()
	_rim.position = Vector3(0, 1.3, -1.3)
	_rim.omni_range = 4.0
	_rim.light_energy = 2.2
	_vp.add_child(_rim)
	chest = ChestModel.new(0)
	_vp.add_child(chest)
	_cam3 = Camera3D.new()
	_cam3.fov = 30.0
	_vp.add_child(_cam3)
	_cam3.position = Vector3(0, 2.3, 5.1)
	_cam3.look_at(Vector3(0, 0.6, 0), Vector3.UP)
	_cam3.current = true
	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(hud.place(_view, Vector2(0.5, 0.5), Vector2(-VIEW * 0.5, CHEST_Y - VIEW * 0.5), Vector2(VIEW, VIEW)))
	# texts
	_title = hud.label("보물상자", 60, Color.WHITE, 16)
	_stage.add_child(hud.place(_title, Vector2(0.5, 0), Vector2(-300, 60), Vector2(600, 84)))
	_count = hud.label("", 26, Color("fff4c0"), 9)
	_stage.add_child(hud.place(_count, Vector2(0.5, 0), Vector2(-260, 140), Vector2(520, 40)))
	_plate = Panel.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(hud.place(_plate, Vector2(0.5, 0.5), Vector2(-150, CHEST_Y - 318), Vector2(300, 86)))
	_plate_l = hud.label("", 50, Color.WHITE, 14)
	_plate_l.size = Vector2(300, 86)
	_plate.add_child(_plate_l)
	_tap_l = hud.label("탭해서 강화!", 46, Color.WHITE, 14)
	_stage.add_child(hud.place(_tap_l, Vector2(0.5, 0.5), Vector2(-300, 200), Vector2(600, 70)))
	var pw := ChestLoot.TAPS * 50.0 + (ChestLoot.TAPS - 1) * 22.0
	for i in ChestLoot.TAPS:
		var p := Pip.new()
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stage.add_child(hud.place(p, Vector2(0.5, 0.5), Vector2(-pw * 0.5 + i * 72.0, 284), Vector2(50, 50)))
		_pips.append(p)
	_hint_l = hud.label("", 25, Color.WHITE, 9)
	_stage.add_child(hud.place(_hint_l, Vector2(0.5, 0.5), Vector2(-330, 352), Vector2(660, 44)))
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

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	var dt := delta / Engine.time_scale if Engine.time_scale > 0.05 else delta
	_t += dt
	_spin += dt * (0.55 + _spin_boost)
	if _bg_mat:
		_bg_mat.set_shader_parameter("phase", _spin)
		_bg_mat.set_shader_parameter("lines", _lines)
		_bg_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))
		var cy := (size.y * 0.5 + CHEST_Y + 30.0) / maxf(1.0, size.y)
		_bg_mat.set_shader_parameter("center", Vector2(0.5, cy))
	if _rays:
		_rays.rotation += dt * (0.25 + _spin_boost * 0.3)
	if chest and _idle:
		chest.position.y = lerpf(chest.position.y, 0.05 + sin(_t * 2.6) * 0.05, 1.0 - exp(-dt * 10.0))
		chest.rotation.y = sin(_t * 0.9) * 0.22
		if state == "open":   # itching to open: little rattles
			var k := fmod(_t, 1.1)
			chest.rotation.z = sin(_t * 40.0) * 0.07 if k < 0.28 else lerpf(chest.rotation.z, 0.0, 0.3)
			chest.lid.rotation.x = -absf(sin(_t * 40.0)) * 0.12 if k < 0.28 else 0.0
	_ambient(dt)
	if _tap_l and (state == "tap" or state == "open"):
		var s := 1.0 + sin(_t * 6.5) * 0.06
		_tap_l.scale = Vector2(s, s)

## Waiting chest: stars twinkle around it (more at higher tiers). Open chest: a fountain of sparkles rises out.
var _amb := 0.0
func _ambient(dt: float) -> void:
	_amb -= dt
	if _amb > 0.0 or chest == null:
		return
	if state == "tap" or state == "open":
		_amb = 0.42 - 0.07 * tier
		var at := _chest_pt(0.45) + Vector2.from_angle(randf() * TAU) * Vector2(randf_range(150.0, 240.0), randf_range(110.0, 190.0))
		_star(at, Hud._vivid(ChestLoot.tier_color(tier)) if randf() < 0.6 else Color.WHITE, 0.0)
	elif (state == "result" or state == "opening") and chest.inner.visible:
		_amb = 0.07
		var sp := Hud.Sparkle.new()
		sp.col = [Color("fff27a"), Color.WHITE, Hud._vivid(ChestLoot.tier_color(tier))][randi() % 3]
		sp.size = Vector2(22, 22) * randf_range(0.7, 1.3)
		sp.pivot_offset = sp.size * 0.5
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var from := _chest_pt(0.72) + Vector2(randf_range(-90.0, 90.0) * _view.scale.x, 0)
		sp.position = from - sp.size * 0.5
		_stage.add_child(sp)
		_stage.move_child(sp, _view.get_index() + 1)
		var tw := _twn(sp)
		tw.set_parallel(true)
		tw.tween_property(sp, "position:y", sp.position.y - randf_range(160.0, 300.0), 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(sp, "position:x", sp.position.x + randf_range(-40.0, 40.0), 1.1)
		tw.tween_property(sp, "rotation", randf_range(-3.0, 3.0), 1.1)
		tw.tween_property(sp, "modulate:a", 0.0, 0.5).set_delay(0.6)
		tw.chain().tween_callback(sp.queue_free)

func _on_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		tap()

## A tap anywhere on the screen.
func tap() -> void:
	match state:
		"tap":
			_power_tap()
		"open":
			_open()

# ---------------------------------------------------------------- chest setup / intro
func _begin(t: int) -> void:
	state = "intro"
	tier = t
	taps_left = ChestLoot.TAPS
	reward = {}
	for c in _cards:
		if is_instance_valid(c):
			c.queue_free()
	_cards.clear()
	for x in _extras:
		if is_instance_valid(x):
			x.queue_free()
	_extras.clear()
	chest.set_tier(tier)
	chest.set_flash(0.0)
	chest.lid.rotation = Vector3.ZERO
	chest.inner.visible = false
	chest.scale = Vector3.ONE
	chest.rotation = Vector3.ZERO
	chest.position = Vector3(0, 3.2, 0)
	WebLook.light_color(_rim, ChestLoot.tier_color(tier))
	_view.scale = Vector2.ONE
	hud.place(_view, Vector2(0.5, 0.5), Vector2(-VIEW * 0.5, CHEST_Y - VIEW * 0.5), Vector2(VIEW, VIEW))   # back home
	_view.modulate.a = 1.0
	_pillar.visible = false
	_set_bg(tier, 0.0)
	_style_plate()
	_plate.modulate.a = 1.0
	_plate.scale = Vector2.ZERO
	_tap_l.text = "탭해서 강화!"
	_tap_l.scale = Vector2.ZERO
	_tap_l.visible = true
	_hint_l.text = ChestLoot.preview(tier)
	_hint_l.modulate.a = 0.0
	_hint_l.visible = true
	for p in _pips:
		p.state = 0
		p.queue_redraw()
		p.scale = Vector2.ZERO
		p.visible = true
	_update_count()
	_idle = false
	if not has_meta("shown"):   # first chest: the whole screen fades in
		modulate.a = 0.0
		set_meta("shown", true)
	var fade := _tw()
	fade.tween_property(self, "modulate:a", 1.0, 0.18)
	Sfx.play("whoosh", -6.0, 0.8)
	# drop in, slam, squash and bounce
	var tw := _twn(chest)
	tw.tween_interval(0.12)
	tw.tween_property(chest, "position:y", 0.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(chest, "scale", Vector3(0.85, 1.2, 0.85), 0.3)
	tw.tween_callback(_landed)
	tw.tween_property(chest, "scale", Vector3(1.38, 0.62, 1.38), 0.07)
	tw.tween_property(chest, "scale", Vector3(0.9, 1.15, 0.9), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(chest, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await _sleep(0.75)
	_idle = true
	state = "tap"
	if game and game.get("autoplay"):
		_autoplay()

func _landed() -> void:
	Sfx.play("thud", -2.0, 0.8)
	Sfx.play("boom", -14.0, 1.4)
	_shake(10.0, 0.25)
	var at := _chest_pt(0.0)
	var dust := hud._fly_burst("ring", Color(1, 1, 1, 0.9), 70.0, at)
	dust.scale = Vector2(1.6, 0.55)
	dust.dots = 8
	_fx.add_child(dust)
	var dt := _twn(dust)
	dt.tween_property(dust, "t", 1.0, 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	dt.tween_callback(dust.queue_free)
	_slam(_plate, 1.8)
	var t2 := _twn(_tap_l)
	t2.tween_interval(0.15)
	t2.tween_property(_tap_l, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in _pips.size():
		var p := _pips[i]
		var pt := _twn(p)
		pt.tween_interval(0.22 + 0.06 * i)
		pt.tween_property(p, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var ht := _twn(_hint_l)
	ht.tween_interval(0.35)
	ht.tween_property(_hint_l, "modulate:a", 1.0, 0.25)

func _update_count() -> void:
	var left: int = game.chests.size() if game else 0
	_count.text = "남은 상자 %d개" % left if left > 0 else "마지막 상자"

func _style_plate() -> void:
	var c := ChestLoot.tier_color(tier)
	var sb := hud.box(c.lightened(0.05) if tier > 0 else Color("8a92a8"), 28, 6, UiTheme.ink())
	sb.shadow_size = 1
	sb.shadow_offset = Vector2(0, 7)
	sb.shadow_color = Color(0.08, 0.04, 0.18, 0.45)
	_plate.add_theme_stylebox_override("panel", sb)
	_plate_l.text = ChestLoot.tier_name(tier)

# ---------------------------------------------------------------- tap: power up
func _power_tap() -> void:
	state = "busy"
	var i := ChestLoot.TAPS - taps_left
	taps_left -= 1
	var up := ChestLoot.roll_up(tier)
	if not force.is_empty():
		up = bool(force.pop_front()) and tier < 3
	if up:
		await _upgrade(i)
	else:
		await _nudge(i)
	if taps_left <= 0:
		_tap_l.text = "탭해서 열기!"
		hud.bump(_tap_l, 1.4)
		Sfx.play("chime", -10.0, 0.9)
		state = "open"
	else:
		state = "tap"

## Plain tap: squash, hop, wobble, a few stars and the pip lights up.
func _nudge(i: int) -> void:
	Sfx.play("pop", -3.0, 0.85 + 0.1 * i)
	Sfx.play("thud", -12.0, 1.3)
	_mark_pip(i, 1)
	_spin_boost = 2.5
	_twn(self).tween_property(self, "_spin_boost", 0.0, 0.5)
	_idle = false
	var tw := _twn(chest)
	tw.tween_property(chest, "scale", Vector3(1.32, 0.68, 1.32), 0.06)
	tw.tween_property(chest, "scale", Vector3(0.84, 1.24, 0.84), 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(chest, "position:y", 0.42, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(chest, "rotation:z", 0.16 if i % 2 == 0 else -0.16, 0.13)
	tw.tween_property(chest, "position:y", 0.0, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(chest, "rotation:z", 0.0, 0.12)
	tw.tween_property(chest, "scale", Vector3(1.18, 0.86, 1.18), 0.05)
	tw.tween_property(chest, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	var lt := _twn(chest.lid)
	lt.tween_property(chest.lid, "rotation:x", -0.32, 0.08)
	lt.tween_property(chest.lid, "rotation:x", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var at := _chest_pt(0.75)
	_ring(at, Color.WHITE, 60.0, 0.35)
	for k in 5:
		_spark(at, Color("fff4a0") if k % 2 == 0 else Color.WHITE, randf_range(90.0, 170.0), 0.35)
	hud.bump(_tap_l, 1.18)
	await _sleep(0.5)
	_idle = true

## Lucky tap: charge up -> comet ring -> white-out -> one tier higher.
func _upgrade(i: int) -> void:
	_idle = false
	var next := tier + 1
	var vivid := Hud._vivid(ChestLoot.tier_color(next))
	Sfx.play("pop", -3.0, 0.9)
	Sfx.play("rise", -4.0, 0.9 + 0.12 * tier)
	_mark_pip(i, 2)
	var at := _chest_pt(0.5)
	# 1) charge: the chest trembles and swells, glows white; speed lines and sparkles rush in
	var charge := func(k: float) -> void:
		chest.rotation.z = sin(k * 90.0) * 0.1 * k
		chest.position.x = sin(k * 61.0) * 0.05 * k
		chest.position.y = 0.12 * k
		chest.lid.rotation.x = -absf(sin(k * 75.0)) * 0.22 * k
		chest.scale = Vector3.ONE * (1.0 + 0.14 * k)
		chest.set_flash(k * k * 0.85)
		_lines = k
		_spin_boost = k * 7.0
	var ch := _tw()
	ch.tween_method(charge, 0.0, 1.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_converge(at, 14, vivid, 0.55)
	var comet := Comet.new()
	comet.col = Color("ffd23f") if next < 3 else Color("fff07a")
	comet.size = Vector2(1000, 1000)
	comet.position = at - comet.size * 0.5
	comet.rotation = -0.25
	comet.pivot_offset = comet.size * 0.5
	comet.a0 = randf() * TAU
	_fx.add_child(comet)
	var ct := _twn(comet)
	ct.tween_interval(0.12)
	ct.tween_callback(func(): Sfx.play("whoosh", -3.0, 0.75))
	ct.tween_property(comet, "t", 1.0, 0.62).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	ct.tween_callback(comet.queue_free)
	await ch.finished
	# 2) white-out: swap tier under the flash
	tier = next
	_flash.color = Color(1, 1, 1, 1)
	_twn(_flash).tween_property(_flash, "color:a", 0.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	chest.set_tier(tier)
	chest.set_flash(1.0)
	WebLook.light_color(_rim, ChestLoot.tier_color(tier))
	_set_bg(tier, 0.25)
	_style_plate()
	_hint_l.text = ChestLoot.preview(tier)
	hud.bump(_hint_l, 1.3)
	Sfx.play("boom", -9.0, 1.25)
	Sfx.play("chime", -2.0, 1.0 + 0.08 * tier)
	Sfx.play("sparkle", -4.0, 1.0)
	_shake(20.0, 0.35)
	_lines = 0.0
	_twn(self).tween_property(self, "_spin_boost", 0.0, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 3) the chest bursts back: pop, full spin, flash fades
	chest.position = Vector3(0, 0.12, 0)
	chest.rotation.z = 0.0
	chest.lid.rotation.x = 0.0
	var pop := _twn(chest)
	pop.set_parallel(true)
	pop.tween_property(chest, "scale", Vector3.ONE * 1.45, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(chest, "rotation:y", chest.rotation.y + TAU, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pop.tween_method(chest.set_flash, 1.0, 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.chain().tween_property(chest, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_slam(_plate, 2.6)
	_ring(at, vivid, 150.0, 0.6, 14)
	_ring(at, Color.WHITE, 100.0, 0.45, 0)
	hud._sparkles(_fx, at, 24 if tier < 3 else 40)
	for k in 6:
		_star(at + Vector2.from_angle(TAU * k / 6.0 + 0.3) * randf_range(150.0, 230.0), vivid if k % 2 == 0 else Color.WHITE, 0.05 * k)
	if tier == 3:
		await _sleep(0.15)
		_jackpot_banner("전설 상자!")
	await _sleep(0.8)
	chest.rotation.y = fmod(chest.rotation.y, TAU)
	_idle = true

# ---------------------------------------------------------------- open
func _open() -> void:
	state = "opening"
	_idle = false
	for n in [_tap_l, _hint_l]:
		_twn(n).tween_property(n, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	for p in _pips:
		_twn(p).tween_property(p, "scale", Vector2.ZERO, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	Sfx.play("rise", -6.0, 1.3)
	# anticipation: squash down hard, shaking, glowing
	var squash := func(k: float) -> void:
		chest.scale = Vector3(1.0 + 0.3 * k, 1.0 - 0.38 * k, 1.0 + 0.3 * k)
		chest.rotation.z = sin(k * 70.0) * 0.06 * k
		chest.position.y = 0.0
		chest.set_flash(k * 0.5)
		_lines = k * 0.6
		_spin_boost = k * 4.0
	var an := _tw()
	an.tween_method(squash, 0.0, 1.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await an.finished
	# jump + lid flies open
	chest.rotation.z = 0.0
	chest.inner.visible = true
	chest.inner.scale = Vector3(0.2, 0.2, 0.2)
	var jp := _twn(chest)
	jp.set_parallel(true)
	jp.tween_property(chest, "scale", Vector3(0.82, 1.3, 0.82), 0.1)
	jp.tween_property(chest, "position:y", 0.55, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jp.tween_property(chest.lid, "rotation:x", -2.15, 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	jp.tween_property(chest.inner, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	jp.tween_method(chest.set_flash, 0.5, 0.0, 0.35)
	jp.chain().tween_property(chest, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	jp.parallel().tween_property(chest, "scale", Vector3(1.25, 0.8, 1.25), 0.16)
	jp.chain().tween_property(chest, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Sfx.play("boom", -6.0, 1.1)
	Sfx.play("chime", -3.0, 1.2)
	if tier >= 2:
		Sfx.play("fanfare", -6.0, 1.0)
	_flash.color = Color(1, 1, 1, 0.85)
	_twn(_flash).tween_property(_flash, "color:a", 0.0, 0.4)
	_shake(16.0, 0.3)
	_twn(self).tween_property(self, "_lines", 0.0, 0.6)
	_twn(self).tween_property(self, "_spin_boost", 1.0, 0.6)
	var mouth := _chest_pt(0.75)
	_pillar.visible = true
	_pillar.col = Color(1.0, 0.97, 0.8).lerp(Hud._vivid(ChestLoot.tier_color(tier)), 0.25)
	_pillar.scale = Vector2(0.3, 0.0)
	_pillar.modulate.a = 1.0
	var pt := _twn(_pillar)
	pt.tween_property(_pillar, "scale", Vector2(1.0, 1.0), 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_ring(mouth, Color.WHITE, 120.0, 0.5, 10)
	_ring(mouth, Hud._vivid(ChestLoot.tier_color(tier)), 190.0, 0.7, 16)
	hud._sparkles(_fx, mouth, 30)
	reward = game.chest_roll(tier) if game else ChestLoot.roll(null, 1, tier)
	await _sleep(0.32)
	# chest backs off up the screen, cards burst out of it
	var back := _twn(_view)
	back.set_parallel(true)
	back.tween_property(_view, "position:y", _view.position.y - 120.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	back.tween_property(_view, "scale", Vector2(0.86, 0.86), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_view.pivot_offset = _view.size * 0.5
	_twn(_plate).tween_property(_plate, "modulate:a", 0.0, 0.25)
	var pf := _twn(_pillar)
	pf.tween_interval(0.5)
	pf.tween_property(_pillar, "modulate:a", 0.6, 0.6)
	await _deal_cards()
	_show_result()

func _deal_cards() -> void:
	var items: Array = reward.get("items", [])
	var n := items.size()
	var gap := 16.0
	var row := n * CARD.x + (n - 1) * gap
	var c := size * 0.5
	for i in n:
		var e: Dictionary = items[i]
		var card := _card(e, bool(reward["lucky"][i]))
		_stage.add_child(card)
		_cards.append(card)
		var dest := Vector2(c.x - row * 0.5 + i * (CARD.x + gap) + CARD.x * 0.5, c.y + CARD_Y)
		var from := _chest_pt(0.8)
		var ctrl := from.lerp(dest, 0.5) + Vector2((dest.x - c.x) * 0.3, -300.0)
		card.position = from - CARD * 0.5
		card.scale = Vector2(0.2, 0.2)
		card.rotation = randf_range(-1.2, 1.2)
		Sfx.play("whoosh", -6.0, 1.2 + 0.08 * i)
		var arc := func(k: float) -> void:
			var p := from.lerp(ctrl, k).lerp(ctrl.lerp(dest, k), k)
			card.position = p - CARD * 0.5
		var tw := _twn(card)
		tw.set_parallel(true)
		tw.tween_method(arc, 0.0, 1.0, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "scale", Vector2.ONE, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(card, "rotation", 0.0, 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(func(): Sfx.play("thud", -10.0, 1.5))
		tw.chain().tween_property(card, "scale", Vector2(1.12, 0.88), 0.06)
		tw.chain().tween_property(card, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		await _sleep(0.16)
	await _sleep(0.45)
	for i in n:
		await _flip(_cards[i], i)

## Card: tier-coloured back with a chest + "?" and the item front (rarity panel, icon, name, grade).
func _card(e: Dictionary, lucky: bool) -> Control:
	var holder := Control.new()
	holder.size = CARD
	holder.pivot_offset = CARD * 0.5
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_meta("entry", e)
	holder.set_meta("lucky", lucky)
	var back := Panel.new()
	back.size = CARD
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bc := ChestLoot.tier_color(tier) if tier > 0 else Color("e0843a")
	back.add_theme_stylebox_override("panel", hud.box(bc, 20, 5, UiTheme.ink()))
	holder.add_child(back)
	var stripe := Panel.new()
	stripe.position = Vector2(10, 10)
	stripe.size = CARD - Vector2(20, 20)
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stripe.add_theme_stylebox_override("panel", hud.box(bc.lightened(0.18), 14, 3, bc.darkened(0.3)))
	back.add_child(stripe)
	var ci := ChestIcon.new()
	ci.tier = tier
	ci.position = Vector2(CARD.x * 0.5 - 46, 40)
	ci.size = Vector2(92, 82)
	ci.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(ci)
	var q := hud.label("?", 44, Color.WHITE, 12)
	q.position = Vector2(0, 124)
	q.size = Vector2(CARD.x, 56)
	back.add_child(q)
	var front := Panel.new()
	front.size = CARD
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.add_theme_stylebox_override("panel", hud.panels.rarity_box(Inventory.rarity_of(e), 20, 5))
	front.visible = false
	holder.add_child(front)
	var ib := Panel.new()
	ib.position = Vector2(14, 12)
	ib.size = Vector2(CARD.x - 28, 104)
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.add_theme_stylebox_override("panel", hud.box(Color(1, 1, 1, 0.28), 14, 0))
	front.add_child(ib)
	var ic := ItemIcon.new(e)
	ic.position = Vector2(8, 4)
	ic.size = Vector2(ib.size.x - 16, 96)
	ib.add_child(ic)
	var nt := Inventory.name_of(e)
	var nm := hud.label(nt, 21 if nt.length() <= 6 else (18 if nt.length() <= 9 else 15), Color.WHITE, 8)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.position = Vector2(6, 118)
	nm.size = Vector2(CARD.x - 12, 50)
	front.add_child(nm)
	var gr := hud.label(_grade_text(e), 18, Color("fff4c0"), 7)
	gr.position = Vector2(0, 168)
	gr.size = Vector2(CARD.x, 30)
	front.add_child(gr)
	if lucky:
		var tag := Panel.new()
		tag.position = Vector2(CARD.x * 0.5 - 62, -18)
		tag.size = Vector2(124, 34)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.add_theme_stylebox_override("panel", hud.box(Color("ffd23f"), 17, 4, UiTheme.ink()))
		var tl := hud.label("합성 완성!", 18, Color("5a3a00"), 0)
		tl.size = tag.size
		tag.add_child(tl)
		front.add_child(tag)
	holder.set_meta("front", front)
	holder.set_meta("back", back)
	return holder

func _grade_text(e: Dictionary) -> String:
	if e["kind"] == "equip" and Gear.is_family(e["key"]):
		return "%s 등급" % Gear.grade_name(Inventory.tier_of(e))
	if e["kind"] == "skillbook":
		return "%s 스킬북" % Defs.book_grade_name(Inventory.book_grade(e))
	if e["kind"] == "stone":
		return "강화 재료"
	return HudPanels.RARITY_NAME.get(Inventory.rarity_of(e), "")

## The best pulls: permanent gear above the stage window's base grade or a unique, 영웅+ skill books.
func _is_jackpot(e: Dictionary) -> bool:
	if e["kind"] == "skillbook":
		return Inventory.book_grade(e) >= 3
	if e["kind"] == "stone":
		return false
	if e["kind"] != "equip":
		return true
	if not Gear.is_family(e["key"]):
		return true
	var k: int = game.wave if game else 1
	return Inventory.tier_of(e) > Gear.base_grade(k)

func _flip(card: Control, i: int) -> void:
	var e: Dictionary = card.get_meta("entry")
	var jack := _is_jackpot(e)
	var vivid := Hud._vivid(Defs.RARITY_COL[Inventory.rarity_of(e)])
	var at := card.position + CARD * 0.5
	if jack:   # a beat of suspense: the card trembles first
		Sfx.play("rise", -10.0, 1.6)
		var tremble := func(k: float) -> void:
			card.rotation = sin(k * 60.0) * 0.06 * k
		var sh := _twn(card)
		sh.tween_method(tremble, 0.0, 1.0, 0.32)
		await sh.finished
		card.rotation = 0.0
	var tw := _twn(card)
	tw.tween_property(card, "scale", Vector2(0.0, 1.12), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		(card.get_meta("back") as Control).visible = false
		(card.get_meta("front") as Control).visible = true
		Sfx.play("pop", -2.0, 1.0 + 0.12 * i)
		_ring(at, vivid, 74.0, 0.42, 8)
		_star(at + Vector2(CARD.x * 0.42, -CARD.y * 0.42), vivid, 0.04)
		_star(at + Vector2(-CARD.x * 0.45, CARD.y * 0.3), Color.WHITE, 0.12))
	tw.tween_property(card, "scale", Vector2(1.18, 1.18), 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await _sleep(0.12)
	if jack:
		_card_jackpot(card, vivid)
		await _sleep(0.45)
	elif bool(card.get_meta("lucky")):
		Sfx.play("chime", -8.0, 1.5)
		await _sleep(0.22)
	else:
		await _sleep(0.12)

## "대박!": rotating rays behind the card, a stamp slams on, confetti, the screen kicks.
func _card_jackpot(card: Control, vivid: Color) -> void:
	var at := card.position + CARD * 0.5
	var rays := Hud.RayBurst.new()
	rays.col = vivid.lightened(0.4)
	rays.size = Vector2(340, 340)
	rays.position = at - rays.size * 0.5
	rays.pivot_offset = rays.size * 0.5
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rays.scale = Vector2.ZERO
	_stage.add_child(rays)
	_stage.move_child(rays, card.get_index())
	_extras.append(rays)
	var rt := _twn(rays)
	rt.tween_property(rays, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	rt.parallel().tween_property(rays, "rotation", TAU, 9.0)
	var stamp := hud.label("대박!", 40, Color("fff27a"), 12)
	stamp.size = Vector2(160, 54)
	stamp.position = Vector2(CARD.x * 0.5 - 80, -50)
	stamp.pivot_offset = stamp.size * 0.5
	stamp.rotation = -0.18
	card.add_child(stamp)
	_slam(stamp, 2.8)
	Sfx.play("chime", -3.0, 1.35)
	Sfx.play("sparkle", -4.0, 1.2)
	_shake(8.0, 0.2)
	hud._sparkles(_fx, at, 14)

# ---------------------------------------------------------------- result / collect
func _show_result() -> void:
	var c := size * 0.5
	var gold: int = reward.get("gold", 0)
	var pill := Panel.new()
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_theme_stylebox_override("panel", UiTheme.capsule(30))
	_stage.add_child(hud.place(pill, Vector2(0.5, 0.5), Vector2(-150, CARD_Y + CARD.y * 0.5 + 34), Vector2(300, 64)))
	_extras.append(pill)
	var coin := Hud.CoinIcon.new()
	coin.position = Vector2(10, 8)
	coin.size = Vector2(48, 48)
	pill.add_child(coin)
	_gold_l = hud.label("+0", 38, Defs.COL_GOLD, 10)
	_gold_l.position = Vector2(56, 0)
	_gold_l.size = Vector2(230, 64)
	pill.add_child(_gold_l)
	hud.pop_in(pill, 0.3, 0.35)
	var count := func(v: float) -> void:
		var nv := int(v)
		if nv != int(_gold_l.text.substr(1)) and nv % 3 == 0:
			Sfx.play("tick", -12.0, 1.4 + v / maxf(1.0, gold) * 0.6)
		_gold_l.text = "+%d" % nv
	var gl := _tw()
	gl.tween_interval(0.1)
	gl.tween_method(count, 0.0, float(gold), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	gl.tween_callback(func(): hud.bump(_gold_l, 1.3))
	var more: bool = game != null and not game.chests.is_empty()
	var by := c.y + CARD_Y + CARD.y * 0.5 + 118.0 - c.y
	if more:
		var nb := hud.juicy_button("다음 상자 (%d)" % game.chests.size(), Color("6f6cf0"), Rect2(0, 0, 290, 92), 32)
		_stage.add_child(hud.place(nb, Vector2(0.5, 0.5), Vector2(-305, by), Vector2(290, 92)))
		nb.pressed.connect(func(): _collect(true))
		_extras.append(nb)
	var ok := hud.juicy_button("받기", Color("27c6b0"), Rect2(0, 0, 290, 92), 40)
	_stage.add_child(hud.place(ok, Vector2(0.5, 0.5), Vector2(15 if more else -145, by), Vector2(290, 92)))
	ok.pressed.connect(func(): _collect(false))
	_extras.append(ok)
	for b in _extras.slice(-2 if more else -1):
		b.scale = Vector2.ZERO
		var bt := _twn(b)
		bt.tween_interval(0.35)
		bt.tween_property(b, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	state = "result"
	if game and game.get("autoplay"):
		_sleep(0.8).connect(func(): _collect(false))

## Hand the rewards over. next = straight into the following chest (the cards drop into the bag below).
func _collect(next: bool) -> void:
	if state != "result":
		return
	state = "busy"
	var pts: Array = []
	for card in _cards:
		pts.append(card.get_global_transform() * (CARD * 0.5))
	if next:
		game.chest_reward(reward, [])
		Sfx.play("whoosh", -4.0, 1.1)
		for i in _cards.size():
			var card := _cards[i]
			var tw := _twn(card)
			tw.tween_interval(0.05 * i)
			tw.tween_property(card, "position:y", size.y + 40.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(card, "rotation", randf_range(-0.6, 0.6), 0.32)
		for x in _extras:
			if is_instance_valid(x):
				_twn(x).tween_property(x, "modulate:a", 0.0, 0.2)
		await _sleep(0.4)
		_begin(game.chest_take())
		return
	var fade := _tw()
	fade.tween_property(self, "modulate:a", 0.0, 0.16)
	await fade.finished
	var g: Node = game
	var r := reward
	hud.close_overlays()
	g.chest_reward(r, pts)

# ---------------------------------------------------------------- fx helpers
## Screen point of the chest at height y (local metres above its base).
func _chest_pt(y := 0.45) -> Vector2:
	var p := _cam3.unproject_position(chest.global_position + Vector3(0, y * chest.scale.y, 0))
	return _view.get_global_transform() * (p * _view.size.x / VIEW)

func _set_bg(t: int, dur: float) -> void:
	var to: Array = BG[t]
	if _bg_now.is_empty() or dur <= 0.0:
		_bg_now = to.duplicate()
		_apply_bg(_bg_now)
		_rays.col = (to[0] as Color).lerp(to[1], 0.3)
		_rays.queue_redraw()
		return
	var from := _bg_now.duplicate()
	var blend := func(k: float) -> void:
		for i in 3:
			_bg_now[i] = (from[i] as Color).lerp(to[i], k)
		_apply_bg(_bg_now)
	_tw().tween_method(blend, 0.0, 1.0, dur)
	_rays.col = (to[0] as Color).lerp(to[1], 0.3)
	_rays.queue_redraw()

func _apply_bg(c: Array) -> void:
	_bg_mat.set_shader_parameter("c_in", c[0])
	_bg_mat.set_shader_parameter("c_out", c[1])
	_bg_mat.set_shader_parameter("c_low", c[2])

func _shake(px: float, dur := 0.3) -> void:
	var jolt := func(k: float) -> void:
		_stage.position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * px * (1.0 - k)
	var tw := _tw()
	tw.tween_method(jolt, 0.0, 1.0, dur)
	tw.tween_callback(func(): _stage.position = Vector2.ZERO)

## Punchy text / plate slam: comes in huge and tilted, lands with a squash.
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

func _star(at: Vector2, col: Color, delay: float) -> void:
	var st := hud._fly_burst("star", col, randf_range(16.0, 26.0), at)
	_fx.add_child(st)
	hud._twinkle(st, 1.0, delay)
	_sleep(delay + 0.8).connect(st.queue_free)

## A sparkle flung outward from `at`.
func _spark(at: Vector2, col: Color, dist: float, dur: float) -> void:
	var sp := Hud.Sparkle.new()
	sp.col = col
	sp.size = Vector2(24, 24)
	sp.pivot_offset = sp.size * 0.5
	sp.position = at - sp.size * 0.5
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.add_child(sp)
	var a := randf() * TAU
	var tw := _twn(sp)
	tw.set_parallel(true)
	tw.tween_property(sp, "position", sp.position + Vector2(cos(a), sin(a) * 0.7) * dist, dur).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(sp, "rotation", randf_range(-3.0, 3.0), dur)
	tw.tween_property(sp, "scale", Vector2(0.2, 0.2), dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(sp.queue_free)

## Sparkles sucked into `at` from a wide ring (charge-up).
func _converge(at: Vector2, n: int, col: Color, dur: float) -> void:
	for i in n:
		var sp := Hud.Sparkle.new()
		sp.col = col if i % 3 != 0 else Color.WHITE
		sp.size = Vector2(28, 28)
		sp.pivot_offset = sp.size * 0.5
		var a := TAU * i / n + randf() * 0.3
		var d := randf_range(300.0, 460.0)
		sp.position = at + Vector2(cos(a), sin(a)) * d - sp.size * 0.5
		sp.modulate.a = 0.0
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fx.add_child(sp)
		var tw := _twn(sp)
		tw.tween_interval(i * dur * 0.04)
		tw.tween_property(sp, "modulate:a", 1.0, 0.06)
		tw.parallel().tween_property(sp, "position", at - sp.size * 0.5, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(sp, "rotation", 4.0, dur)
		tw.parallel().tween_property(sp, "scale", Vector2(0.3, 0.3), dur)
		tw.tween_callback(sp.queue_free)

func _mark_pip(i: int, st: int) -> void:
	if i < 0 or i >= _pips.size():
		return
	var p := _pips[i]
	p.state = st
	p.col = ChestLoot.tier_color(mini(tier + (1 if st == 2 else 0), 3))
	p.queue_redraw()
	hud.bump(p, 1.7)

func _jackpot_banner(text: String) -> void:
	var l := hud.label(text, 76, Color("fff27a"), 18)
	_fx.add_child(hud.place(l, Vector2(0.5, 0.5), Vector2(-360, CHEST_Y - 10), Vector2(720, 110)))
	_slam(l, 3.0)
	var tw := _twn(l)
	tw.tween_interval(0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)
	Sfx.play("fanfare", -4.0, 1.1)

## Dev / autoplay: tap through by itself.
func _autoplay() -> void:
	while is_inside_tree() and state != "result":
		await _sleep(0.35)
		if state == "tap" or state == "open":
			tap()

# ---------------------------------------------------------------- drawn pieces
## Golden comet sweeping round the chest in a shrinking tilted ellipse (t: 0..1).
class Comet extends Control:
	var col := Color("ffd23f")
	var a0 := 0.0
	var r0 := 470.0
	var r1 := 150.0
	var turns := 1.15
	var t := 0.0:
		set(v):
			t = v
			queue_redraw()

	func _pt(k: float) -> Vector2:
		var tt := clampf(k, 0.0, 1.0)
		var a := a0 + tt * TAU * turns
		var r := lerpf(r0, r1, 1.0 - pow(1.0 - tt, 1.6))
		return size * 0.5 + Vector2(cos(a), sin(a) * 0.42) * r

	func _draw() -> void:
		if t <= 0.0 or t >= 1.0:
			return
		var fade := 1.0 - smoothstep(0.82, 1.0, t)
		var n := 46
		for i in n:
			var k := float(i) / n               # 0 = head .. 1 = tail end
			var p := _pt(t - k * 0.38)
			var w := lerpf(30.0, 3.0, k) * fade
			draw_circle(p, w, Color(col, (1.0 - k) * fade), true, -1.0, true)
		for i in n:
			var k := float(i) / n
			var p := _pt(t - k * 0.3)
			draw_circle(p, lerpf(12.0, 1.0, k) * fade, Color(1, 1, 1, (1.0 - k) * fade), true, -1.0, true)
		var hp := _pt(t)
		draw_circle(hp, 34.0 * fade, Color(1, 1, 1, 0.35 * fade), true, -1.0, true)

## Light pillar out of the open chest: layered beams, brightest in the middle, fading upward.
class Pillar extends Control:
	var col := Color(1, 0.97, 0.8)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in 4:
			var k := float(i) / 4.0
			var bw := w * (0.5 - k * 0.11)
			var tw := bw * 1.5
			var pts := PackedVector2Array([Vector2(w * 0.5 - bw * 0.45, h), Vector2(w * 0.5 + bw * 0.45, h), Vector2(w * 0.5 + tw * 0.5, 0), Vector2(w * 0.5 - tw * 0.5, 0)])
			var a := 0.16 + k * 0.14
			draw_polygon(pts, PackedColorArray([Color(col, a), Color(col, a), Color(col, 0.0), Color(col, 0.0)]))

## Tap pip: empty ring -> filled with the chest colour (white star when that tap raised the tier).
class Pip extends Control:
	var state := 0
	var col := Color.WHITE

	func _draw() -> void:
		var c := size * 0.5
		var r := size.x * 0.4
		draw_circle(c + Vector2(0, 3), r + 5.0, Color(UiTheme.ink(), 0.5), true, -1.0, true)
		draw_circle(c, r + 5.0, UiTheme.ink(), true, -1.0, true)
		if state == 0:
			draw_circle(c, r, Color(1, 1, 1, 0.22), true, -1.0, true)
			draw_circle(c, r * 0.42, Color(1, 1, 1, 0.55), true, -1.0, true)
			return
		draw_circle(c, r, col, true, -1.0, true)
		draw_circle(c + Vector2(-r * 0.32, -r * 0.34), r * 0.28, Color(1, 1, 1, 0.65), true, -1.0, true)
		if state == 2:
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				pts.append(c + Vector2.from_angle(a) * (r * 0.78 if i % 2 == 0 else r * 0.34))
			draw_colored_polygon(pts, Color.WHITE)
		else:
			draw_arc(c, r * 0.45, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 4.0, true)

## Flat 2D chest (badge / flying pickup / card backs), tinted by tier like ChestModel.
class ChestIcon extends Control:
	var tier := 0

	func _sb(c: Color, rad: Array, border := 4) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.corner_radius_top_left = rad[0]
		sb.corner_radius_top_right = rad[0]
		sb.corner_radius_bottom_left = rad[1]
		sb.corner_radius_bottom_right = rad[1]
		sb.set_border_width_all(border)
		sb.border_color = UiTheme.ink()
		sb.anti_aliasing = true
		return sb

	func _draw() -> void:
		var p: Array = ChestModel.PALETTE[clampi(tier, 0, 3)]
		var w := size.x
		var h := size.y
		var b := maxi(3, int(w / 22.0))
		var body := Rect2(w * 0.08, h * 0.44, w * 0.84, h * 0.5)
		var lid := Rect2(w * 0.05, h * 0.08, w * 0.9, h * 0.42)
		draw_style_box(_sb(Color(0.05, 0.03, 0.1, 0.45), [int(h * 0.1), int(h * 0.1)], 0), Rect2(body.position + Vector2(0, h * 0.05), body.size))
		draw_style_box(_sb(p[0], [int(h * 0.06), int(h * 0.1)], b), body)
		draw_style_box(_sb(p[1], [int(h * 0.26), int(h * 0.05)], b), lid)
		draw_rect(Rect2(lid.position.x + w * 0.1, lid.position.y + h * 0.07, w * 0.5, h * 0.05), Color(1, 1, 1, 0.45))
		for x in [0.24, 0.66]:
			draw_style_box(_sb(p[2], [int(w * 0.03), int(w * 0.03)], b), Rect2(w * x, lid.position.y + h * 0.02, w * 0.1, h * 0.86))
		var lock := Rect2(w * 0.37, h * 0.36, w * 0.26, h * 0.3)
		draw_style_box(_sb(p[2], [int(w * 0.07), int(w * 0.07)], b), lock)
		var gc := lock.get_center()
		draw_circle(gc, w * 0.075 + b * 0.5, UiTheme.ink(), true, -1.0, true)
		draw_circle(gc, w * 0.075, p[3], true, -1.0, true)
		draw_circle(gc + Vector2(-w * 0.025, -w * 0.03), w * 0.025, Color(1, 1, 1, 0.8), true, -1.0, true)
