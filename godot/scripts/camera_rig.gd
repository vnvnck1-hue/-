class_name CameraRig
extends Camera3D
## Trauma-based screen shake + hitstop (time freeze) + gentle punch zoom + cinematic focus dolly.

var base_pos := Vector3.ZERO
var base_rot := Vector3.ZERO
var base_look := Vector3.ZERO
var base_fov := 34.0
var trauma := 0.0
var _t := 0.0
var _stop_left := 0.0
var _fov_kick := 0.0
var focus_target := Vector3.ZERO
var focus_k := 0.0        # 0 = gameplay framing, 1 = full close-up on focus_target
var _focus_goal := 0.0
var focus_amount := 1.0   # how far the cinematic dolly goes toward the focus target (0..1)
var base_scale := 1.0     # time scale outside hitstops (item-drag slow motion lowers it)
var sky_k := 0.0          # 0..1 "pull up into the sky" (world map transition): back + up, tilt toward the sky, wider fov
const SKY_PULL := 6.0
const SKY_RISE := 4.5
const SKY_TILT := 0.36
const SKY_FOV := 10.0
# group framing (item drag): ease in until every node in group_nodes fits on screen with a margin
var group_nodes: Array = []
var group_k := 0.0
var _group_goal := 0.0
var _group_look := Vector3.ZERO
var _group_ratio := 1.0
const GROUP_MARGIN := 1.3     # world units kept free around the group (models + bars)
const GROUP_MIN_RATIO := 0.5  # never closer than half the gameplay distance

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func setup(pos: Vector3, look: Vector3, fov_deg: float) -> void:
	base_fov = fov_deg
	fov = fov_deg
	position = pos
	look_at(look, Vector3.UP)
	base_pos = position
	base_rot = rotation
	base_look = look

## Move the gameplay framing (March mode follows the road / pulls back for boss fields).
func set_base(pos: Vector3, look: Vector3) -> void:
	base_pos = pos
	base_look = look
	base_rot = Basis.looking_at(look - pos, Vector3.UP).get_euler()

func add_trauma(v: float) -> void:
	trauma = clampf(trauma + v, 0.0, 1.0)

func kick_fov(v: float) -> void:
	_fov_kick = v

func hitstop(dur: float) -> void:
	Engine.time_scale = 0.04
	_stop_left = maxf(_stop_left, dur)

func cancel_hitstop() -> void:
	_stop_left = 0.0
	Engine.time_scale = base_scale

func in_hitstop() -> bool:
	return _stop_left > 0.0

## Ease the camera in so all `nodes` fill the screen (heroes while dragging gear). on=false returns.
func group_focus(nodes: Array, on: bool) -> void:
	if on:
		group_nodes = nodes
	_group_goal = 1.0 if on and not nodes.is_empty() else 0.0

## Look point + distance ratio that frames group_nodes from the gameplay viewing direction.
func _group_frame() -> void:
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	var live := false
	for n in group_nodes:   # runs every frame while framing: no filtered copy of the list
		if not is_instance_valid(n):
			continue
		live = true
		var q: Vector3 = n.global_position
		lo = Vector3(minf(lo.x, q.x), 0, minf(lo.z, q.z))
		hi = Vector3(maxf(hi.x, q.x), 0, maxf(hi.z, q.z))
	if not live:
		return
	_group_look = (lo + hi) * 0.5 + Vector3(0, 0.5, 0)
	var dist := (base_pos - base_look).length()
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	# fov spans the width (KEEP_WIDTH) or the height (KEEP_HEIGHT)
	var half_w := tan(deg_to_rad(base_fov) * 0.5)
	var half_h := half_w / aspect
	if keep_aspect == Camera3D.KEEP_HEIGHT:
		half_h = half_w
		half_w = half_h * aspect
	# width is the tight axis in portrait; depth spread is foreshortened by the pitch
	var pitch := absf((base_look - base_pos).normalized().y)
	var need_w := (hi.x - lo.x) + GROUP_MARGIN * 2.0
	var need_h := (hi.z - lo.z) * pitch + GROUP_MARGIN * 2.0 + 1.2
	var d := maxf(need_w / (2.0 * half_w), need_h / (2.0 * half_h))
	_group_ratio = clampf(d / maxf(dist, 0.01), GROUP_MIN_RATIO, 1.0)

## Dolly toward a point (ultimate cinematics). on=false returns to gameplay framing.
func focus(target: Vector3, on: bool) -> void:
	if on:
		focus_target = target
	_focus_goal = focus_amount if on else 0.0

func _process(delta: float) -> void:
	# delta is scaled by time_scale; use real time for camera feel.
	var real := delta / maxf(Engine.time_scale, 0.001)
	real = minf(real, 0.05)
	_t += real
	if _stop_left > 0.0:
		_stop_left -= real
		if _stop_left <= 0.0:
			_stop_left = 0.0
			Engine.time_scale = base_scale
	trauma = maxf(trauma - real * 1.6, 0.0)
	var s := trauma * trauma
	var off := Vector3(
		sin(_t * 47.0) + sin(_t * 31.0) * 0.5,
		sin(_t * 53.0 + 1.3) * 0.6,
		cos(_t * 41.0) * 0.5) * 0.18 * s
	focus_k = lerpf(focus_k, _focus_goal, 1.0 - exp(-real * (7.0 if _focus_goal > focus_k else 5.0)))
	group_k = lerpf(group_k, _group_goal, 1.0 - exp(-real * (6.0 if _group_goal > group_k else 5.0)))
	var bpos := base_pos
	var blook := base_look
	if group_k > 0.002:
		if _group_goal > 0.0:
			_group_frame()
		blook = base_look.lerp(_group_look, group_k)
		bpos = blook + (base_pos - base_look) * lerpf(1.0, _group_ratio, group_k)
	if focus_k > 0.002:
		var look := blook.lerp(focus_target + Vector3(0, 0.5, 0), focus_k)
		var p := bpos + (focus_target - blook) * focus_k * 0.85
		p = p.lerp(look, 0.42 * focus_k)
		position = p + off
		look_at(look, Vector3.UP)
		rotation.z += sin(_t * 37.0) * 0.02 * s
	elif group_k > 0.002:
		position = bpos + off
		look_at(blook, Vector3.UP)
		rotation.z += sin(_t * 37.0) * 0.02 * s
	else:
		position = base_pos + off
		rotation = base_rot + Vector3(0, 0, sin(_t * 37.0) * 0.02 * s)
	_fov_kick = lerpf(_fov_kick, 0.0, 1.0 - exp(-real * 8.0))
	fov = base_fov + _fov_kick
	if sky_k > 0.001:
		position += (position - base_look).normalized() * SKY_PULL * sky_k + Vector3(0, SKY_RISE * sky_k, 0)
		rotation.x += SKY_TILT * sky_k
		fov += SKY_FOV * sky_k
