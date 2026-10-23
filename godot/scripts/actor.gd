class_name Actor
extends Node3D
## Battle unit shared by heroes and enemies: targeting, free movement, attacks, status effects.
## Damage math lives in Combat; motion & VFX live in UnitModel / Vfx / Hud / Sfx.

signal died(a: Actor)

const RADIUS := 0.34
const MODEL_SCALE := 1.45
static var BOARD_X := 2.95   # arena half extents (March mode widens them for boss fields)
static var BOARD_Z := 3.95
static var clamp_fn := Callable()   # March mode: keep units on the winding field instead of the board rectangle
const RANGE_PAD := 0.15
## Hit stagger (monsters): a flinch halts the unit in place this long; after it ends the next ordinary hit can't
## re-stagger for HITSTUN_GAP, so fast hero attacks can't pin a monster down for good. Knockback always staggers.
const HITSTUN := 0.26
const HITSTUN_GAP := 0.45
const HITSTUN_KNOCK := 0.42

var kind := ""
var cls := ""             # hero class, "" for enemies
var team := 0
var def := {}
var game: Node
var model: UnitModel
var ring: MeshInstance3D
var blob: MeshInstance3D
var ring_mat: StandardMaterial3D
var stun_fx: Node3D

var alive := true
var hp := 1.0
var max_hp := 1.0
var atk := 1.0
var body_r := RADIUS

# hero progression
var level := 1
var exp := 0
var learned: Array = []   # skills from skill books this run: [{"id", "level"}] (max Defs.SKILL_SLOTS)
var equipment := {"weapon": null, "armor": null, "accessory": null}
var mana := 0.0
var ult_ready_at := 0.0
var attack_count := 0
var home := Vector2i.ZERO

# enemy flags
var is_illusion := false
var knockback_immune := false
var corpse := false        # hydra: stays on the board while dead
var dead_at := 0.0
var special_t := -99.0     # ninja leap / sprinter dash timer (game clock)
var endless := false       # boss raid line-up: an emptied bar fills again, the damage goes to game.raid_hit

# combat state
var target: Actor
var retarget_t := 0.0
var last_attack := -99.0
var attacking := false
var busy := false          # leaping / channeling: no AI
var knock := Vector3.ZERO
var stun_until := 0.0
var hitstun_until := 0.0   # flinch halt (game clock): no moving / no new swing
var _restagger_at := 0.0
var slow_until := 0.0
var frozen_until := 0.0
var guard_until := 0.0
var lifted := false
var _lift := 0.0
var _t := 0.0

func setup(p_kind: String, p_team: int, p_game: Node, mult := 1.0) -> Actor:
	kind = p_kind
	team = p_team
	game = p_game
	if team == Defs.TEAM_HERO:
		cls = kind
		def = Defs.HEROES[kind]
		atk = def["atk"]
		max_hp = def["hp"] + floorf(def["hp"] * Stats.g(Stats.talent_fx(self), "hpMult"))
	else:
		def = Defs.ENEMIES[kind]
		var m := 1.0 if def.get("flat", false) else mult
		max_hp = floorf(def["hp"] * m)
		atk = floorf(def["atk"] * m)
		knockback_immune = def.get("knockback_immune", false)
		if def.get("size", 1) > 1:
			body_r = RADIUS * def["size"]
	hp = max_hp
	_build_visual()
	return self

func is_hero() -> bool:
	return team == Defs.TEAM_HERO

func color() -> Color:
	return Defs.COL_HERO if is_hero() else Defs.COL_ENEMY

func _build_visual() -> void:
	# shadow blob / ring meshes and the blob material are shared; ring_mat stays per unit (selection tint)
	blob = MeshInstance3D.new()
	blob.mesh = Mats.shared("actor/blob", func() -> Mesh:
		var pm := PlaneMesh.new()
		pm.size = Vector2(0.9, 0.9)
		return pm)
	blob.material_override = Mats.shared("actor/blob_mat", func() -> Material:
		return Mats.ground("blob", Color(0.23, 0.2, 0.44, 0.45), false))
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.015
	add_child(blob)
	ring = MeshInstance3D.new()
	ring.mesh = Mats.shared("actor/ring", func() -> Mesh:
		var tm := TorusMesh.new()
		tm.inner_radius = 0.3
		tm.outer_radius = 0.37
		tm.rings = 32
		tm.ring_segments = 6
		return tm)
	ring_mat = Mats.glow(color(), 1.15)
	ring.material_override = ring_mat
	ring.position.y = 0.03
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ring)
	model = UnitModel.new().build(kind, team)
	add_child(model)
	model.rotation.y = 0.0 if is_hero() else PI
	var s: float = def["scale"] * MODEL_SCALE
	model.scale = Vector3.ONE * s
	var rs := minf(s * 0.62, 1.05) * (body_r / RADIUS if body_r > RADIUS else 1.0)
	ring.scale = Vector3(rs, 0.25, rs)
	blob.scale = Vector3.ONE * rs * 1.1

# ---------------------------------------------------------------- toy motion
## Toy drop: fall in, squash on landing, dust ring.
func drop_in(height := 1.4, delay := 0.0) -> void:
	model.position.y = height
	var tw := create_tween()
	if delay > 0.0:
		tw.tween_interval(delay)
	tw.tween_property(model, "position:y", 0.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(_land)

func _land() -> void:
	model.punch_scale(1.35, 0.62, 0.45)
	Vfx.dust_ring(global_position, 0.8 * (body_r / RADIUS))
	Sfx.play("pop", -5.0, 1.0 + randf() * 0.2)

## Arcing hop to a point (used for returning home, leaps, dashes).
func hop_to(p: Vector3, dur := 0.35, height := 0.8, land := true) -> Tween:
	var start := position
	var end := Vector3(p.x, 0, p.z)
	_face(end - start, 1.0, 100.0)
	var step := func(k: float) -> void:
		position = start.lerp(end, k) + Vector3(0, sin(k * PI) * height, 0)
	var tw := create_tween()
	tw.tween_method(step, 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if land:
		tw.tween_callback(func():
			position.y = 0.0
			model.punch_scale(1.3, 0.65, 0.35))
	return tw

func set_lifted(on: bool) -> void:
	lifted = on

func set_selected(on: bool) -> void:
	ring_mat.albedo_color = (Defs.COL_GOLD if on else color()) * 1.15

func _process(delta: float) -> void:
	_t += delta
	var goal := 1.0 if lifted else 0.0
	_lift = lerpf(_lift, goal, 1.0 - exp(-delta * 18.0))
	if _lift > 0.001 or lifted:
		model.position.y = _lift * 0.55
		model.rotation.z = sin(_t * 9.0) * 0.12 * _lift
		model.rotation.x = -0.25 * _lift
	if game == null:
		return
	# status tint & stun stars (game clock based)
	var now: float = game.now
	if not alive:
		return
	if now < frozen_until:
		model.tint = Color(0.25, 0.55, 0.9)
	elif now < slow_until:
		model.tint = Color(0.12, 0.3, 0.55)
	elif is_hero() and now < guard_until:
		model.tint = Color(0.45, 0.4, 0.1)
	else:
		model.tint = Color(0, 0, 0)
	var stunned: bool = now < stun_until and now >= frozen_until
	if stunned and stun_fx == null:
		_make_stun_fx()
	if stun_fx:
		stun_fx.visible = stunned and not model.is_shocked()   # the electrocution shudder already says it
		stun_fx.rotation.y += delta * 6.0
		stun_fx.position.y = (1.05 * model.scale.y / MODEL_SCALE) + 0.25

func _make_stun_fx() -> void:
	stun_fx = Node3D.new()
	add_child(stun_fx)
	var q: Mesh = Mats.shared("actor/stun_star", func() -> Mesh:
		var qm := QuadMesh.new()
		qm.size = Vector2(0.22, 0.22)
		return qm)
	var mat: Material = Mats.shared("actor/stun_mat", func() -> Material:
		return Mats.sprite("star5", Color(1.6, 1.4, 0.4), true))
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		var a := TAU * i / 3.0
		mi.position = Vector3(cos(a) * 0.28, 0, sin(a) * 0.28)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stun_fx.add_child(mi)

# ---------------------------------------------------------------- battle AI
static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)

func _face(dir: Vector3, delta: float, rate := 12.0) -> void:
	if dir.length() < 0.001:
		return
	var yaw := atan2(-dir.x, -dir.z)
	model.rotation.y = lerp_angle(model.rotation.y, yaw, 1.0 - exp(-delta * rate))

## Edge-to-edge distance in tiles (big bodies reach further / are easier to reach).
func reach_to(o: Actor) -> float:
	return _flat(o.global_position - global_position).length() - (o.body_r - RADIUS) - (body_r - RADIUS)

func foes() -> Array:
	return game.alive_enemies() if is_hero() else game.alive_heroes()

func pick_target() -> Actor:
	var far: bool = kind == "ninja"
	var best: Actor = null
	var best_d := -1.0 if far else INF
	for u in foes():
		var d := _flat(u.global_position - global_position).length()
		if (far and d > best_d) or (not far and d < best_d):
			best_d = d
			best = u
	return best

func attack_range() -> float:
	return Stats.attack_range(game, self) if is_hero() else float(def["range"])

func attack_interval() -> float:
	if is_hero():
		return Stats.attack_interval(game, self)
	var s: float = def["speed"] / 1000.0
	return s * 2.0 if game.now < slow_until else s

func move_speed() -> float:
	if is_hero():
		return Stats.move_speed(game, self)
	var v: float = 1000.0 / def["move"]
	return v * 0.5 if game.now < slow_until else v

func battle_tick(delta: float) -> void:
	if not alive:
		return
	if knock.length() > 0.01:
		position += knock * delta
		knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-delta * 9.0))
		_clamp()
	if busy:
		return
	if game.now < stun_until or game.now < hitstun_until:
		model.walk = lerpf(model.walk, 0.0, 1.0 - exp(-delta * (24.0 if game.now < hitstun_until else 12.0)))
		return
	retarget_t -= delta
	if target == null or not target.alive or retarget_t <= 0.0:
		target = pick_target()
		retarget_t = 0.3
	if target == null:
		model.walk = lerpf(model.walk, 0.0, delta * 8.0)
		return
	if game.special_move(self, delta):
		_clamp()
		return
	var to := _flat(target.global_position - global_position)
	if reach_to(target) > attack_range() + RANGE_PAD:
		if not attacking:
			var v := to.normalized() * move_speed() + _separation() * 3.2
			position += v * delta
			_face(to, delta)
			model.walk = lerpf(model.walk, 1.0, 1.0 - exp(-delta * 10.0))
	else:
		model.walk = lerpf(model.walk, 0.0, 1.0 - exp(-delta * 12.0))
		_face(to, delta, 18.0)
		position += _separation() * delta * 2.0
		if not attacking and game.now - last_attack >= attack_interval():
			_attack()
	_clamp()

func _clamp() -> void:
	position = field_clamp(position, body_r - RADIUS)

## Nearest point on the playable field (March: the winding road minus the strip under the bag; else the board).
static func field_clamp(p: Vector3, m := 0.0) -> Vector3:
	if clamp_fn.is_valid():
		return clamp_fn.call(p, m)
	return Vector3(clampf(p.x, -BOARD_X + m, BOARD_X - m), p.y, clampf(p.z, -BOARD_Z + m, BOARD_Z - m))

func _separation() -> Vector3:
	var push := Vector3.ZERO
	for u in game.all_alive():
		if u == self:
			continue
		var d := _flat(global_position - u.global_position)
		var l := d.length()
		var minr: float = body_r + u.body_r
		if l < minr and l > 0.0001:
			push += d / l * (minr - l) / minr
		elif l <= 0.0001:
			push += Vector3(randf() - 0.5, 0, randf() - 0.5)
	return push

func fwd() -> Vector3:
	return -model.global_transform.basis.z.normalized()

func _attack() -> void:
	attacking = true
	last_attack = game.now
	var t := target
	if is_hero():
		await Combat.hero_attack(game, self, t)
	else:
		await Combat.enemy_attack(game, self, t)
	if not is_inside_tree():   # removed mid-swing (wave cleared / scene left)
		attacking = false
		return
	await get_tree().create_timer(0.1, false).timeout
	attacking = false

# ---------------------------------------------------------------- damage / healing
## Returns true when this hit takes hp from >0 to <=0. Death itself is resolved by the caller.
func apply_damage(amount: float, from: Actor, crit := false, show := true, push := 1.0) -> bool:
	if not alive or hp <= 0.0:
		return false
	hp -= amount
	if endless:
		game.raid_hit(amount, crit, self)
		while hp <= 0.0:
			hp += max_hp
			game.raid_bar_broken(self)
	model.flash()
	model.punch_scale(1.22, 0.78, 0.35)
	var away := _flat(global_position - from.global_position).normalized() if from else Vector3.ZERO
	if from and push > 0.0 and not knockback_immune:
		knock += away * 1.0 * push
	if hp > 0.0:
		flinch(away)
	if show:
		game.hud.damage_number(global_position + Vector3(0, 0.9 * model.scale.y / MODEL_SCALE * 1.2, 0), amount, team, crit)
	return hp <= 0.0

## Big bodies (2x2 mid-bosses, boss-role chiefs) don't stagger on ordinary hits — only knockback halts them.
func is_heavy() -> bool:
	return body_r > RADIUS or Defs.role(kind) == "boss"

## Monster hit reaction: flinch animation away from the blow + a brief halt in place. Heavy monsters only
## rock a little on ordinary hits and keep going; a knockback (knock_back) staggers everyone.
func flinch(away: Vector3, knockback := false) -> void:
	if is_hero() or not alive or game == null:
		return
	var heavy := is_heavy()
	if heavy and not knockback:
		model.play_hit(away, 0.3)
		return
	model.play_hit(away, 1.25 if knockback else 1.0)
	var now: float = game.now
	if knockback or now >= _restagger_at:
		var dur := HITSTUN_KNOCK if knockback else HITSTUN
		hitstun_until = maxf(hitstun_until, now + dur)
		_restagger_at = hitstun_until + HITSTUN_GAP

## Knockback blow from a hero at `from`: shoves (unless immune) and always staggers, even big bodies.
func knock_back(from: Vector3, force: float) -> void:
	if not alive:
		return
	var away := _flat(global_position - from).normalized()
	if not knockback_immune:
		knock += away * force
	flinch(away, true)

func heal(amount: float, show := false) -> void:
	if not alive or amount <= 0.0:
		return
	var before := hp
	hp = minf(max_hp, hp + amount)
	if show and hp > before:
		game.hud.heal_number(global_position + Vector3(0, 1.0, 0), hp - before)

func add_mana(v: float) -> void:
	if is_hero():
		mana = minf(Defs.MAX_MANA, mana + v)

func die() -> void:
	alive = false
	hp = 0.0
	attacking = false
	busy = false
	ring.visible = false
	blob.visible = false
	if stun_fx:
		stun_fx.visible = false
	model.tint = Color(0, 0, 0)
	Sfx.play("poof", -5.0)
	var tw := create_tween().set_parallel(true)
	var fall_dir := 1.0 if randf() < 0.5 else -1.0
	tw.tween_property(model, "rotation:z", 1.4 * fall_dir, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(model, "position:y", 0.25, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if corpse:
		tw.chain().tween_callback(func(): model.set_ghost(true))
	else:
		tw.chain().tween_callback(_vanish)
	died.emit(self)

func _vanish() -> void:
	Vfx.death_poof(global_position)
	visible = false

## Bring back to life (hydra revive / feather / talents).
func revive(ratio := 1.0) -> void:
	alive = true
	visible = true
	hp = maxf(1.0, floorf(max_hp * ratio))
	ring.visible = true
	blob.visible = true
	model.set_ghost(false)
	model.rotation = Vector3(0, model.rotation.y, 0)
	model.position = Vector3.ZERO
	model.punch_scale(1.4, 0.6, 0.5)
	Vfx.upgrade_pillar(global_position)
	Sfx.play("chime", -5.0, 1.2)

func reset_status() -> void:
	target = null
	attacking = false
	busy = false
	knock = Vector3.ZERO
	stun_until = 0.0
	hitstun_until = 0.0
	_restagger_at = 0.0
	slow_until = 0.0
	frozen_until = 0.0
	guard_until = 0.0
	model.walk = 0.0
	model.position = Vector3.ZERO
	model.rotation = Vector3(0, 0.0 if is_hero() else PI, 0)
