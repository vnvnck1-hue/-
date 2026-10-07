class_name CloudFly
extends Control
## Screen transition: flat 2D clouds rushing from left to right in three layers (ref: Ttukkapet Survival).
## No shading or drop shadows - each layer is one flat tone, darker at the back and lighter in front, with
## thin crescent creases on its lobes in a slightly deeper tone of the same layer.
## Every layer enters and leaves within the same pass but covers a very different distance, so the speeds
## differ sharply (back : mid : front ~ 1 : 1.7 : 2.6) and the pass reads with depth:
##   back  - lavender (#d1d8f0), slowest; the bank that covers the whole screen mid-pass
##   mid   - pale (#eff1f9), a long fast train of masses over the lower part of the screen
##   front - white, a very long, fastest train along the top of the screen
## Speed FX on top: thin wind streaks and a screen-space lens pass (horizontal motion blur, bulge,
## chromatic fringes, vignette) peaking mid-flight.
## The screen is fully inside the cloud halfway through (on_cover fires there: swap the view underneath).
## band coordinate (screen half-widths): a cloud sits at s = u + S_layer(t), u in [-band, 0]; S runs from
## -(1 + REACH) to band + 1 + REACH, so each band starts just off the left edge and ends just off the right.

const REACH := 1.25          # how far a cloud spills past its anchor (half-widths)
const LAYERS := [
	{"body": Color("d1d8f0"), "line": Color("b0c4e9"), "band": 2.8, "lobe": Vector2(0.55, 0.8), "cell": 0.95, "crease": 0.45, "edge": -9.0, "vmin": -9.0},
	{"body": Color("eff1f9"), "line": Color("cbd8f1"), "band": 8.0, "lobe": Vector2(0.45, 0.68), "cell": 1.0, "crease": 0.35, "edge": -9.0, "vmin": 0.2},
	{"body": Color("ffffff"), "line": Color("d9e5fd"), "band": 14.0, "lobe": Vector2(0.4, 0.62), "cell": 0.9, "crease": 0.25, "edge": 0.6, "vmin": -9.0},
]
const STREAKS := 46

const LENS_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float k = 0.0;
void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float r2 = dot(c, c);
	// lens bulge: the centre swells toward the viewer, edges stretch
	vec2 uv = 0.5 + c * (1.0 - 0.07 * k + 0.16 * k * r2);
	// horizontal motion blur, stronger toward the sides
	float spread = 0.07 * k * (0.35 + r2 * 2.5);
	vec3 col = vec3(0.0);
	for (int i = 0; i < 12; i++) {
		float t = float(i) / 11.0 - 0.5;
		col += texture(screen_tex, uv + vec2(t * spread, 0.0)).rgb;
	}
	col /= 12.0;
	// chromatic fringes
	float ca = 0.012 * k * (0.2 + r2 * 3.0);
	col.r = mix(col.r, texture(screen_tex, uv + vec2(ca, 0.0)).r, 0.7);
	col.b = mix(col.b, texture(screen_tex, uv - vec2(ca, 0.0)).b, 0.7);
	// tunnel vignette (cool tint, no black)
	float v = smoothstep(0.08, 0.45, r2) * k;
	col = mix(col, col * vec3(0.78, 0.82, 0.95), v * 0.55);
	COLOR = vec4(col, 1.0);
}
"""

var _clouds: Array = []     # per layer: Array of {u, v, lobes: [[offset, r]], creases: [[offset, r, a0, a1, w]]}
var _streaks: Array = []    # {u, y, len, w}
var _half := 360.0          # screen half width (px)
var _x := 0.0               # 0..1 progress
var _dur := 0.66
var _covered := false
var _on_cover: Callable
var _done := false
var _lens: ShaderMaterial

func setup(sz: Vector2) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	_half = sz.x * 0.5
	var aspect := sz.y / maxf(sz.x, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	for L in LAYERS:
		var arr: Array = []
		var band: float = L["band"]
		var cell: float = L["cell"]
		var cols := ceili(band / cell) + 1
		var rows := ceili(2.3 * aspect / cell) + 1
		var lr: Vector2 = L["lobe"]
		for col in cols:
			for row in rows:
				var u := -band + (col + 0.5 * (row % 2) + rng.randf_range(-0.2, 0.2)) * band / (cols - 0.5)
				var v := -1.15 * aspect + (row + rng.randf_range(-0.2, 0.2)) * 2.3 * aspect / (rows - 1)
				if v > -float(L["edge"]) * aspect or v < float(L["vmin"]) * aspect:
					continue   # edge: keep only clouds above -edge (white top band), vmin: keep only below (pale bottom mass)
				arr.append(_make_cloud(rng, clampf(u, -band, 0.0), v, lr, L["crease"]))
		_clouds.append(arr)
	for i in STREAKS:
		_streaks.append({"u": rng.randf_range(-14.0, 0.0), "y": rng.randf_range(0.04, 0.96) * sz.y,
			"len": rng.randf_range(0.35, 1.1) * _half, "w": rng.randf_range(2.0, 6.0)})
	# lens pass over everything drawn below it (the view and the clouds)
	var fx := ColorRect.new()
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = LENS_SHADER
	_lens.shader = sh
	fx.material = _lens
	add_child(fx)

## A cloud: a big base puff with smaller lobes heaped on its upper side; a few lobes get a crease
## (thin tapered crescent along the underside of their outline, like the ref).
func _make_cloud(rng: RandomNumberGenerator, u: float, v: float, lr: Vector2, crease: float) -> Dictionary:
	var base := rng.randf_range(lr.x, lr.y) * 1.25
	var lobes: Array = [[Vector2.ZERO, base]]
	var creases: Array = []
	var n := rng.randi_range(2, 4)
	for i in n:
		var t := (i + 0.5) / n
		var off := Vector2(lerpf(-0.95, 0.95, t) * base + rng.randf_range(-0.08, 0.08), -base * rng.randf_range(0.25, 0.6))
		var r := rng.randf_range(lr.x, lr.y) * 0.85
		lobes.append([off, r])
		if rng.randf() < crease:
			creases.append([off, r, deg_to_rad(rng.randf_range(25.0, 50.0)), deg_to_rad(rng.randf_range(160.0, 185.0)), r * rng.randf_range(0.12, 0.18)])
	return {"u": u, "v": v, "lobes": lobes, "creases": creases}

# ---------------------------------------------------------------- animation
## Runs the whole pass; on_cover is called once while the screen is inside the cloud.
func play(dur: float, on_cover := Callable()) -> void:
	_dur = dur
	_x = 0.0
	_on_cover = on_cover
	_covered = false
	_done = false
	while not _done:
		await get_tree().process_frame

## Speed FX strength: ramps in, peaks inside the cloud, ramps out.
func intensity() -> float:
	return pow(sin(PI * _x), 0.7)

func _process(delta: float) -> void:
	if _done:
		return
	var real := minf(delta / maxf(Engine.time_scale, 0.001), 1.0 / 30.0)   # no jump after the swap hitch
	_x = minf(_x + real / _dur, 1.0)
	refresh()
	if not _covered and _x >= 0.5:
		_covered = true
		if _on_cover.is_valid():
			_on_cover.call()
	if _x >= 1.0:
		_done = true

func refresh() -> void:
	_lens.set_shader_parameter("k", intensity())
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	for li in LAYERS.size():
		var L: Dictionary = LAYERS[li]
		var band: float = L["band"]
		var S := lerpf(-(1.0 + REACH), band + 1.0 + REACH, _x)   # constant speed: distance differs per layer
		var body: Color = L["body"]
		var line: Color = L["line"]
		# one flat tone per layer: all bodies first, then the creases on top (nothing of the layer hides them)
		for pass_i in 2:
			for cl in _clouds[li]:
				var at: Vector2 = c + Vector2(cl["u"] + S, cl["v"]) * _half
				var reach: float = (cl["lobes"][0][1] as float) * 2.2 * _half
				if at.x < -reach or at.x > size.x + reach:
					continue
				if pass_i == 0:
					for lb in cl["lobes"]:
						draw_circle(at + (lb[0] as Vector2) * _half, (lb[1] as float) * _half, body, true, -1.0, true)
				else:
					for cr in cl["creases"]:
						_crescent(at + (cr[0] as Vector2) * _half, (cr[1] as float) * _half, cr[2], cr[3], (cr[4] as float) * _half, line)
	# wind streaks: much faster than any cloud layer
	var a := intensity()
	var Sw := lerpf(-1.5, 26.0, _x)
	for st in _streaks:
		var x0: float = c.x + (st["u"] + Sw) * _half
		var ln: float = st["len"]
		if x0 < 0.0 or x0 - ln > size.x:
			continue
		var y: float = st["y"]
		var w: float = st["w"]
		draw_colored_polygon(PackedVector2Array([Vector2(x0 - ln, y), Vector2(x0 - ln * 0.15, y - w * 0.5), Vector2(x0, y), Vector2(x0 - ln * 0.15, y + w * 0.5)]),
			Color(1, 1, 1, 0.8 * a) if st["w"] > 4.0 else Color(0.62, 0.72, 0.9, 0.7 * a))

## Tapered crescent just inside a lobe's outline, thickest in the middle.
func _crescent(o: Vector2, r: float, a0: float, a1: float, w: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 14
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(o + Vector2(cos(a), sin(a)) * r)
	for i in range(n, -1, -1):
		var t := float(i) / n
		var a := lerpf(a0, a1, t)
		pts.append(o + Vector2(cos(a), sin(a)) * (r - w * sin(PI * t)))
	draw_colored_polygon(pts, col)
