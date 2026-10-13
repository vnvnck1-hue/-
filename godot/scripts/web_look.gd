class_name WebLook
extends Node
## The web build (WebGL2) runs the Compatibility renderer: no SSAO, no ambient specular, lights land ~2x brighter
## than in Forward+, glow has no HDR headroom, and the glow pass blows the flat background color out.
## These corrections keep its look close to the desktop build; on desktop (Forward+) nothing here does anything.
## Factors were matched against Forward+ screenshots of the same frames (tools/web_look_probe.gd).
## Autoload "WebLookHook": scales every Light3D once when it enters the tree. Code that sets a light color later
## at runtime goes through WebLook.light_color() / ambient() so the correction is not lost.

const LIGHT_K := 0.5                  # direct light (linear energy factor)
const AMBIENT_K := 0.5                # ambient color light
const CONTRAST_MUL := 0.91            # its tonemap curve already has more contrast (desktop 1.1 -> 1.0)
const BG_MUL := 0.26                  # with glow on, the flat background color blows out to white without this
const GLOW_MUL := 2.5                 # what can bloom gets a stronger push to match the desktop halos
const GLOW_THRESHOLD := 0.99          # values clamp at 1: only near-white pixels may bloom
const SEA_SHEEN := Vector3(0.36, 0.34, 0.48)   # world map sea: stands in for the missing ambient specular

static var _compat := -1

static func compat() -> bool:
	if _compat < 0:
		_compat = 1 if RenderingServer.get_current_rendering_method() == "gl_compatibility" else 0
	return _compat == 1

## Linear-energy scale of an sRGB color (light colors are converted to linear by the renderer).
static func _scaled(c: Color, k: float) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r * k, l.g * k, l.b * k, c.a).linear_to_srgb()

## Set a light's color (use for colors changed after the light entered the tree).
static func light_color(l: Light3D, c: Color) -> void:
	l.set_meta("web_look", true)
	l.light_color = _scaled(c, LIGHT_K) if compat() else c

## Ambient light color for an Environment.
static func ambient(c: Color) -> Color:
	return _scaled(c, AMBIENT_K) if compat() else c

## Lit materials that differ only in rim / emission being switched on compile to separate shaders, and each lit
## shader costs the web build seconds of compile. Switch both on with no effect (rim 0, black emission) so they share
## one. Call after configuring a lit StandardMaterial3D.
static func unify(m: StandardMaterial3D) -> StandardMaterial3D:
	if compat():
		if not m.rim_enabled:
			m.rim_enabled = true
			m.rim = 0.0
		if not m.emission_enabled:
			m.emission_enabled = true
			m.emission = Color.BLACK
	return m

## glow_intensity value for the current renderer (also for values set at runtime).
static func glow(v: float) -> float:
	return v * GLOW_MUL if compat() else v

## Call once on a freshly configured Environment (before it is used).
static func apply(e: Environment) -> void:
	if not compat():
		return
	e.ambient_light_color = ambient(e.ambient_light_color)
	e.adjustment_contrast *= CONTRAST_MUL
	e.background_energy_multiplier *= BG_MUL
	e.glow_intensity = glow(e.glow_intensity)
	e.glow_hdr_threshold = GLOW_THRESHOLD
	if not perf.get("glow", true):
		e.glow_enabled = false
	var sw := (Engine.get_main_loop() as SceneTree).root.get_node_or_null("ShaderWarmup")
	if sw:
		sw.warm(e)

func _enter_tree() -> void:
	if compat():
		get_tree().node_added.connect(_on_node_added)
		_perf_setup()

## Render cost knobs (web). Phones are handled in the HTML shell instead: export_presets.cfg's head_include caps
## the canvas pixel ratio at 2 on phones (iPhone 3x: 1179x2556 -> 786x1704 px, 2.25x fewer pixels for 3D, UI and
## post). Lowering scaling_3d_scale instead looked worse here: the Compatibility upscale drops the MSAA edges.
## Dev overrides: ?s3d=0.6&msaa=0&glow=1&shadow=1024&batch=0 on the web build; ?fps=1 shows a frame meter, --perf-s3d=0.6 etc. on desktop.
static var perf := {}

func _perf_setup() -> void:
	var q := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--perf-") and a.contains("="):
			q[a.substr(7).get_slice("=", 0)] = a.get_slice("=", 1)
	if OS.has_feature("web"):
		for kv in str(JavaScriptBridge.eval("location.search")).trim_prefix("?").split("&", false):
			var p := kv.split("=")
			if p.size() == 2:
				q[p[0]] = p[1]
	var mobile: bool = OS.has_feature("web_ios") or OS.has_feature("web_android") or q.get("mobile", "") == "1"
	perf = {
		"mobile": mobile,
		"s3d": float(q.get("s3d", 1.0)),
		"msaa": int(q.get("msaa", 2)),
		"glow": q.get("glow", "1") != "0",
		"shadow": int(q.get("shadow", 2048)),
		"batch": q.get("batch", "1") != "0",
		"fps": q.get("fps", "") == "1",
	}
	var vp := get_tree().root
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = perf["s3d"]
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][clampi(perf["msaa"], 0, 4)]
	RenderingServer.directional_shadow_atlas_set_size(perf["shadow"], true)
	print("[WebLook] perf ", perf)
	if perf["fps"]:
		_meter()

## ?fps=1: frames per second and the slowest frame of the last second, top left (for checking on a phone).
var _meter_label: Label
var _frames := 0
var _worst := 0.0
var _acc := 0.0

func _meter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 127
	add_child(layer)
	_meter_label = Label.new()
	_meter_label.position = Vector2(8, 4)
	_meter_label.add_theme_font_size_override("font_size", 22)
	_meter_label.add_theme_constant_override("outline_size", 6)
	_meter_label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(_meter_label)

func _process(delta: float) -> void:
	if _meter_label == null:
		return
	_frames += 1
	_acc += delta
	_worst = maxf(_worst, delta)
	if _acc >= 1.0:
		_meter_label.text = "%d fps  worst %d ms" % [roundi(_frames / _acc), roundi(_worst * 1000.0)]
		_frames = 0
		_acc = 0.0
		_worst = 0.0

func _on_node_added(n: Node) -> void:
	if n is Light3D and not n.has_meta("web_look"):
		_scale_light.call_deferred(n)   # deferred: creators often set the color right after add_child

func _scale_light(l: Light3D) -> void:
	if is_instance_valid(l) and not l.has_meta("web_look"):
		l.set_meta("web_look", true)
		l.light_color = _scaled(l.light_color, LIGHT_K)
