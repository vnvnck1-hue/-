class_name UnitModel
extends Node3D
## Procedurally built 2~2.5 head-tall toy figure. Faces -Z.
## Owns all "juice" motion: breathing, hop-walk, attack swings, squash & stretch, hit flash.

const SKIN := Color("f4ad7a")

var kind := ""
var team := 0
var squash: Node3D        # squash & stretch + lean pivot (at feet)
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var weapon: Node3D
var mats: Array[StandardMaterial3D] = []

var walk := 0.0           # 0..1 blend of hop cycle
var _t := 0.0
var _phase := 0.0
var _squash_v := Vector2.ONE  # extra scale from impulses (x,y)
var _sq_tween: Tween
var _flash_tween: Tween
var attack_lean := 0.0    # forward lean from attacks (radians)
var hop_offset := 0.0
var quad_legs: Array[Node3D] = []   # four-legged bodies: FL, FR, BL, BR (diagonal pairs stride together)
var hover := 0.0                    # floaters (eye bat, abyss lord) bob above their shadow
var _wiggles: Array = []            # secondary motion: tails, ears, wings, tentacles, banners
var _spins: Array = []              # constantly turning parts (rune crowns, vortex)
var _hit_k := 0.0                   # flinch blend 0..1 (play_hit)
var _hit_amp := 0.0                 # strength of the flinch in progress
var _hit_dir := Vector2.ZERO        # blow direction in model space (x = side, y = back)
var _hit_tween: Tween

func build(p_kind: String, p_team: int) -> UnitModel:
	kind = p_kind
	team = p_team
	_phase = randf() * TAU
	squash = _node(self, Vector3.ZERO)
	torso = _node(squash, Vector3.ZERO)
	match kind:
		# heroes
		"warrior": _build_warrior()
		"ranger": _build_archer()
		"mage": _build_wizard()
		# enemies
		"normal": _build_grunt()
		"fast": _build_thief()
		"tank": _build_knight()
		"boss": _build_chief()
		"goblin": _build_goblin()
		"ninja": _build_ninja()
		"splitter", "splitling": _build_slime()
		"sprinter": _build_runner()
		"giant": _build_golem()
		"hydra": _build_hydra()
		"illusionist", "illusion": _build_illusionist()
		"tut_easy", "tut_tough": _build_dummy()
		"slinger": _build_slinger()
		"crossbow": _build_crossbow()
		"shaman": _build_shaman()
		# march field creatures (beasts / monsters) and their mid-bosses
		"wolf": _build_wolf()
		"hornbunny": _build_hornbunny()
		"boar": _build_boar()
		"bear": _build_bear()
		"imp": _build_imp()
		"eyebat": _build_eyebat()
		"mimic": _build_mimic()
		"horror": _build_horror()
		"mammoth": _build_mammoth()
		"abyss": _build_abyss()
		# Toy Clash originals (kept for reference)
		"king": _build_king()
		"queen": _build_queen()
		"brawler": _build_brawler()
		"archer": _build_archer()
		"wizard": _build_wizard()
		"valkyrie": _build_valkyrie()
	return self

# ------------------------------------------------------------------ helpers
func _node(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n

func _mat(color: Color) -> StandardMaterial3D:
	var m := Mats.toy(color)
	mats.append(m)
	return m

func _mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scl := Vector3.ONE, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(color)
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi

# Part meshes are shared between every model (keyed by their exact dimensions, which are all code
# constants), so spawning a wave no longer rebuilds hundreds of identical primitive meshes.
static func _sphere_mesh(r: float, segs := 24, rings := 12) -> Mesh:
	return Mats.shared("um/s%.4f/%d/%d" % [r, segs, rings], func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r * 2.0
		s.radial_segments = segs
		s.rings = rings
		return s)

func _sphere(parent: Node3D, r: float, color: Color, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	return _mesh(parent, _sphere_mesh(r), color, pos, scl)

func _hemi(parent: Node3D, r: float, color: Color, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var m: Mesh = Mats.shared("um/h%.4f" % r, func() -> Mesh:
		var s := SphereMesh.new()
		s.radius = r
		s.height = r
		s.is_hemisphere = true
		s.radial_segments = 24
		s.rings = 8
		return s)
	return _mesh(parent, m, color, pos, scl)

func _capsule(parent: Node3D, r: float, h: float, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m: Mesh = Mats.shared("um/c%.4f/%.4f" % [r, h], func() -> Mesh:
		var c := CapsuleMesh.new()
		c.radius = r
		c.height = maxf(h, r * 2.0)
		c.radial_segments = 16
		c.rings = 6
		return c)
	return _mesh(parent, m, color, pos, scl, rot)

func _cyl(parent: Node3D, rt: float, rb: float, h: float, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m: Mesh = Mats.shared("um/y%.4f/%.4f/%.4f" % [rt, rb, h], func() -> Mesh:
		var c := CylinderMesh.new()
		c.top_radius = rt
		c.bottom_radius = rb
		c.height = h
		c.radial_segments = 20
		c.rings = 1
		return c)
	return _mesh(parent, m, color, pos, scl, rot)

static func _box_mesh(size: Vector3) -> Mesh:
	return Mats.shared("um/b%.4f/%.4f/%.4f" % [size.x, size.y, size.z], func() -> Mesh:
		var b := BoxMesh.new()
		b.size = size
		return b)

func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	return _mesh(parent, _box_mesh(size), color, pos, Vector3.ONE, rot)

func _torus(parent: Node3D, ri: float, ro: float, color: Color, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m: Mesh = Mats.shared("um/t%.4f/%.4f" % [ri, ro], func() -> Mesh:
		var t := TorusMesh.new()
		t.inner_radius = ri
		t.outer_radius = ro
		t.rings = 24
		t.ring_segments = 10
		return t)
	return _mesh(parent, m, color, pos, scl, rot)

## Unlit glow material, shared per colour / energy (glow parts never flash, tint or fade).
static func _glow_mat(col: Color, energy: float) -> Material:
	return Mats.shared("um/g%s/%.2f" % [col, energy], func() -> Material: return Mats.glow(col, energy))

func _team_col() -> Color:
	return Defs.COL_HERO if team == Defs.TEAM_HERO else Defs.COL_ENEMY

## Standard chibi skeleton: legs, egg body, big head, stubby arms with fists.
func _base(body_col: Color, skin := SKIN, body_r := 0.2, head_r := 0.21, leg_col := Color("6b4a2f"), fist_r := 0.075, eyes := true) -> void:
	leg_l = _node(torso, Vector3(-0.09, 0.13, 0))
	leg_r = _node(torso, Vector3(0.09, 0.13, 0))
	_capsule(leg_l, 0.065, 0.2, leg_col, Vector3(0, -0.06, 0))
	_capsule(leg_r, 0.065, 0.2, leg_col, Vector3(0, -0.06, 0))
	_sphere(leg_l, 0.075, leg_col.darkened(0.25), Vector3(0, -0.12, -0.03), Vector3(1, 0.7, 1.3))
	_sphere(leg_r, 0.075, leg_col.darkened(0.25), Vector3(0, -0.12, -0.03), Vector3(1, 0.7, 1.3))
	_sphere(torso, body_r, body_col, Vector3(0, 0.27, 0), Vector3(1.0, 0.95, 0.9))
	# team belt
	_torus(torso, body_r * 0.86, body_r * 1.02, _team_col(), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 1.2, 0.92))
	head = _node(torso, Vector3(0, 0.36 + body_r * 0.7 + head_r * 0.55, 0))
	_sphere(head, head_r, skin, Vector3.ZERO)
	if eyes:   # eyes (face -Z)
		var eye_col := Color("2a1d1a")
		_sphere(head, head_r * 0.13, eye_col, Vector3(-head_r * 0.36, head_r * 0.08, -head_r * 0.92), Vector3(0.8, 1.2, 0.5))
		_sphere(head, head_r * 0.13, eye_col, Vector3(head_r * 0.36, head_r * 0.08, -head_r * 0.92), Vector3(0.8, 1.2, 0.5))
		_sphere(head, head_r * 0.16, skin.darkened(0.06), Vector3(0, -head_r * 0.12, -head_r * 0.98))
	arm_l = _node(torso, Vector3(-body_r * 1.0, 0.36, 0))
	arm_r = _node(torso, Vector3(body_r * 1.0, 0.36, 0))
	_capsule(arm_l, 0.055, 0.2, body_col.darkened(0.08), Vector3(-0.02, -0.08, 0), Vector3(0, 0, -0.35))
	_capsule(arm_r, 0.055, 0.2, body_col.darkened(0.08), Vector3(0.02, -0.08, 0), Vector3(0, 0, 0.35))
	_sphere(arm_l, fist_r, skin, Vector3(-0.06, -0.17, 0))
	_sphere(arm_r, fist_r, skin, Vector3(0.06, -0.17, 0))
	weapon = _node(arm_r, Vector3(0.06, -0.17, 0))

# ------------------------------------------------------------------ characters
func _build_king() -> void:
	var gold := Color("f2b632")
	_base(Color("e2a431"), SKIN, 0.23, 0.23, Color("7a3b2a"), 0.1)
	# cape
	_sphere(torso, 0.24, Color("c9362f"), Vector3(0, 0.27, 0.15), Vector3(1.05, 1.15, 0.45))
	_sphere(torso, 0.2, Color("f3ead8"), Vector3(0, 0.43, 0.1), Vector3(1.25, 0.35, 0.8))  # fur collar
	# shoulder pads
	_sphere(torso, 0.1, gold.lightened(0.1), Vector3(-0.21, 0.42, 0), Vector3(1, 0.7, 1))
	_sphere(torso, 0.1, gold.lightened(0.1), Vector3(0.21, 0.42, 0), Vector3(1, 0.7, 1))
	# hair, beard & mustache
	var hair := Color("9a4f2a")
	_sphere(head, 0.235, hair, Vector3(0, 0.03, 0.05), Vector3(1.05, 0.95, 1.02))
	_sphere(head, 0.17, hair, Vector3(0, -0.12, -0.1), Vector3(1.1, 0.9, 0.8))
	_capsule(head, 0.05, 0.28, hair.lightened(0.1), Vector3(0, -0.04, -0.2), Vector3(0, 0, PI * 0.5))
	_capsule(head, 0.03, 0.12, hair.darkened(0.2), Vector3(-0.08, 0.08, -0.2), Vector3(0, 0, 1.3))
	_capsule(head, 0.03, 0.12, hair.darkened(0.2), Vector3(0.08, 0.08, -0.2), Vector3(0, 0, -1.3))
	# crown
	_cyl(head, 0.2, 0.19, 0.12, gold, Vector3(0, 0.22, 0))
	for i in 5:
		var a := TAU * i / 5.0
		_sphere(head, 0.04, gold.lightened(0.2), Vector3(cos(a) * 0.19, 0.31, sin(a) * 0.19))
	_sphere(head, 0.045, Color("e63d5c"), Vector3(0, 0.22, -0.195))
	# gold gauntlets (big fists)
	_sphere(arm_r, 0.12, gold, Vector3(0.06, -0.17, 0))
	_sphere(arm_l, 0.12, gold, Vector3(-0.06, -0.17, 0))

func _build_queen() -> void:
	var purple := Color("8e4fc4")
	_base(Color("6b3aa0"), SKIN, 0.2, 0.21, Color("3d2466"))
	_sphere(head, 0.23, purple, Vector3(0, 0.05, 0.05), Vector3(1.05, 1.0, 1.05))  # hair bob
	_sphere(head, 0.12, purple.darkened(0.15), Vector3(0, -0.05, 0.19))
	_cyl(head, 0.11, 0.1, 0.07, Color("f2b632"), Vector3(0, 0.23, 0))
	_sphere(head, 0.03, Color("ff5fa2"), Vector3(0, 0.24, -0.1))
	# crossbow
	_box(weapon, Vector3(0.05, 0.05, 0.34), Color("7a4a26"), Vector3(0, 0, -0.1))
	_torus(weapon, 0.14, 0.17, Color("5a5a66"), Vector3(0, 0, -0.24), Vector3(0, 0, 0), Vector3(1, 0.4, 0.45))
	_sphere(torso, 0.08, Color("ff5fa2"), Vector3(0, 0.3, -0.17))

func _build_brawler() -> void:
	var hair := Color("ffd23f")
	_base(Color("9a6034"), SKIN, 0.19, 0.21, Color("5b3a22"))
	# hair mop + mustache
	_sphere(head, 0.2, hair, Vector3(0, 0.07, 0.05), Vector3(1.1, 0.85, 1.05))
	_capsule(head, 0.045, 0.26, hair.darkened(0.05), Vector3(0, -0.07, -0.2), Vector3(0, 0, PI * 0.5))
	# horned helmet
	_hemi(head, 0.18, Color("b8bfcc"), Vector3(0, 0.1, 0))
	_cyl(head, 0.0, 0.05, 0.16, Color("fff5e0"), Vector3(-0.19, 0.2, 0), Vector3(0, 0, 0.7))
	_cyl(head, 0.0, 0.05, 0.16, Color("fff5e0"), Vector3(0.19, 0.2, 0), Vector3(0, 0, -0.7))
	# big sword
	_box(weapon, Vector3(0.07, 0.42, 0.025), Color("dfe6ee"), Vector3(0, 0.24, 0))
	_box(weapon, Vector3(0.18, 0.04, 0.05), Color("f2b632"), Vector3(0, 0.03, 0))
	_capsule(weapon, 0.025, 0.1, Color("6b4a2f"), Vector3(0, -0.03, 0))

func _build_archer() -> void:
	var pink := Color("ff6fae")
	_base(Color("4fae55"), SKIN, 0.18, 0.2, Color("3d6b3a"))
	_sphere(head, 0.22, pink, Vector3(0, 0.04, 0.05), Vector3(1.05, 1.02, 1.05))  # hood
	_cyl(head, 0.0, 0.08, 0.14, pink, Vector3(0, 0.1, 0.23), Vector3(-1.9, 0, 0))  # hood tip
	_sphere(head, 0.1, Color("ff9f5a"), Vector3(0, 0.1, -0.14), Vector3(1.2, 0.5, 0.6))  # bangs
	# bow in left hand
	var bow := _node(arm_l, Vector3(-0.06, -0.17, 0))
	_torus(bow, 0.2, 0.23, Color("8a5a2b"), Vector3.ZERO, Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.35))
	# quiver
	_cyl(torso, 0.05, 0.05, 0.26, Color("8a5a2b"), Vector3(0.08, 0.36, 0.17), Vector3(0.4, 0, -0.3))

func _build_goblin() -> void:
	var skin := Color("8fd14f")
	_base(Color("7a5230"), skin, 0.17, 0.2, Color("5a3a20"), 0.07)
	_cyl(head, 0.0, 0.07, 0.24, skin, Vector3(-0.23, 0.04, 0), Vector3(0, 0, 1.3))
	_cyl(head, 0.0, 0.07, 0.24, skin, Vector3(0.23, 0.04, 0), Vector3(0, 0, -1.3))
	_sphere(head, 0.07, skin.darkened(0.1), Vector3(0, -0.04, -0.2), Vector3(1, 0.8, 1))  # big nose
	_hemi(head, 0.17, Color("3fa0d8"), Vector3(0, 0.08, 0.02))  # blue bandana
	_box(weapon, Vector3(0.04, 0.2, 0.02), Color("dfe6ee"), Vector3(0, 0.12, 0))

func _build_wizard() -> void:
	var robe := Color("3d72d9")
	_base(robe, SKIN, 0.19, 0.2, robe.darkened(0.3))
	_cyl(torso, 0.14, 0.24, 0.3, robe, Vector3(0, 0.18, 0))  # robe skirt
	_sphere(head, 0.11, Color("6b4a2f"), Vector3(0, -0.13, -0.08), Vector3(1.2, 0.6, 0.8))  # beard stub
	_cyl(head, 0.3, 0.3, 0.035, Color("5b2da0"), Vector3(0, 0.13, 0))  # brim
	_cyl(head, 0.0, 0.17, 0.36, Color("6f3ac0"), Vector3(0, 0.3, 0.04), Vector3(-0.25, 0, 0))
	# fire orb
	var orb := MeshInstance3D.new()
	orb.mesh = _sphere_mesh(0.07, 64, 32)
	orb.material_override = _glow_mat(Color("ffb13b"), 2.2)
	orb.position = Vector3(0, 0.05, -0.02)
	weapon.add_child(orb)

func _build_valkyrie() -> void:
	var hair := Color("ff8a2a")
	_base(Color("b5452f"), SKIN, 0.2, 0.21, Color("6b3a22"))
	_sphere(head, 0.21, hair, Vector3(0, 0.07, 0.04), Vector3(1.08, 0.9, 1.05))
	_capsule(head, 0.06, 0.26, hair, Vector3(-0.17, -0.12, 0.05), Vector3(0.2, 0, 0.3))
	_capsule(head, 0.06, 0.26, hair, Vector3(0.17, -0.12, 0.05), Vector3(0.2, 0, -0.3))
	_hemi(head, 0.16, Color("c9ced8"), Vector3(0, 0.12, 0))
	# double axe
	_capsule(weapon, 0.025, 0.46, Color("6b4a2f"), Vector3(0, 0.12, 0))
	_cyl(weapon, 0.14, 0.14, 0.03, Color("dfe6ee"), Vector3(0.09, 0.3, 0), Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.8))
	_cyl(weapon, 0.14, 0.14, 0.03, Color("dfe6ee"), Vector3(-0.09, 0.3, 0), Vector3(0, 0, PI * 0.5), Vector3(1, 1, 0.8))

func _build_giant() -> void:
	_base(Color("8a5a34"), SKIN, 0.24, 0.19, Color("4e3420"), 0.12)
	_sphere(torso, 0.13, SKIN, Vector3(-0.23, 0.42, 0), Vector3(1.1, 0.9, 1))  # shoulders
	_sphere(torso, 0.13, SKIN, Vector3(0.23, 0.42, 0), Vector3(1.1, 0.9, 1))
	_sphere(head, 0.09, Color("c98a4a"), Vector3(0, -0.1, -0.12), Vector3(1.4, 0.6, 0.8))  # stubble
	_capsule(torso, 0.05, 0.5, Color("5b3a22"), Vector3(0, 0.33, 0), Vector3(0, 0, 0.9), Vector3(1, 1, 1))  # strap
	_capsule(head, 0.03, 0.12, Color("5b3a22"), Vector3(-0.08, 0.1, -0.17), Vector3(0, 0, 1.4))  # angry brows
	_capsule(head, 0.03, 0.12, Color("5b3a22"), Vector3(0.08, 0.1, -0.17), Vector3(0, 0, -1.4))

# ------------------------------------------------------------------ trio chess cast
func _build_warrior() -> void:
	# brawler silhouette + team-blue cape and round shield
	_build_brawler()
	_sphere(torso, 0.2, Color("2f7fd0"), Vector3(0, 0.27, 0.14), Vector3(1.05, 1.15, 0.4))
	var sh := _node(arm_l, Vector3(-0.08, -0.15, -0.02))
	_cyl(sh, 0.13, 0.13, 0.04, Color("c8894a"), Vector3.ZERO, Vector3(0, 0, PI * 0.5))
	_cyl(sh, 0.05, 0.05, 0.05, Color("dfe6ee"), Vector3(-0.01, 0, 0), Vector3(0, 0, PI * 0.5))

func _build_grunt() -> void:
	# goblin-ish bandit with red bandana and wooden club
	var skin := Color("a6d65a")
	_base(Color("8a5a3a"), skin, 0.18, 0.2, Color("5a3a24"))
	_cyl(head, 0.0, 0.06, 0.18, skin, Vector3(-0.21, 0.03, 0), Vector3(0, 0, 1.3))
	_cyl(head, 0.0, 0.06, 0.18, skin, Vector3(0.21, 0.03, 0), Vector3(0, 0, -1.3))
	_hemi(head, 0.18, Color("d83a3a"), Vector3(0, 0.07, 0.02))
	_sphere(head, 0.05, Color("d83a3a"), Vector3(0.05, 0.1, 0.19))
	_capsule(weapon, 0.04, 0.3, Color("9a6034"), Vector3(0, 0.14, 0))
	_sphere(weapon, 0.075, Color("8a5430"), Vector3(0, 0.3, 0))

func _build_thief() -> void:
	# small hooded thief with a dagger
	var hood := Color("4a4a6a")
	_base(Color("5a5a7a"), SKIN, 0.16, 0.19, Color("3a3a50"))
	_sphere(head, 0.21, hood, Vector3(0, 0.04, 0.05), Vector3(1.05, 1.02, 1.05))
	_cyl(head, 0.0, 0.07, 0.14, hood, Vector3(0, 0.22, 0.06), Vector3(-0.4, 0, 0))
	_box(head, Vector3(0.3, 0.06, 0.04), Color("2a2a3a"), Vector3(0, -0.06, -0.18))  # face mask
	_box(weapon, Vector3(0.035, 0.18, 0.02), Color("dfe6ee"), Vector3(0, 0.1, 0))
	_box(weapon, Vector3(0.1, 0.03, 0.04), Color("6b4a2f"), Vector3(0, 0.01, 0))

func _build_knight() -> void:
	# chunky armored knight: bucket helm, plate body, big tower shield
	var steel := Color("aab3c2")
	_base(steel, SKIN, 0.22, 0.2, Color("5a6070"), 0.09)
	_cyl(head, 0.21, 0.22, 0.3, steel.lightened(0.05), Vector3(0, 0.02, 0))
	_box(head, Vector3(0.26, 0.03, 0.04), Color("2a2a3a"), Vector3(0, 0.04, -0.215))
	_sphere(head, 0.05, Color("d83a3a"), Vector3(0, 0.2, 0))
	_capsule(head, 0.03, 0.18, Color("d83a3a"), Vector3(0, 0.22, 0.08), Vector3(PI * 0.5, 0, 0))
	var sh := _node(arm_l, Vector3(-0.1, -0.12, -0.04))
	_box(sh, Vector3(0.05, 0.42, 0.3), Color("8a5a34"), Vector3.ZERO)
	_box(sh, Vector3(0.06, 0.36, 0.06), Color("d83a3a"), Vector3(-0.005, 0, 0))
	_box(weapon, Vector3(0.05, 0.3, 0.02), Color("dfe6ee"), Vector3(0, 0.16, 0))

func _build_chief() -> void:
	# ogre chief: big purple body, spiked crown, spiked club
	var skin := Color("9a7ad8")
	_base(Color("6b3a2a"), skin, 0.24, 0.22, Color("4a2a20"), 0.1)
	_sphere(torso, 0.12, Color("e8d6a8"), Vector3(-0.22, 0.42, 0), Vector3(1.2, 0.7, 1))  # bone pads
	_sphere(torso, 0.12, Color("e8d6a8"), Vector3(0.22, 0.42, 0), Vector3(1.2, 0.7, 1))
	_cyl(head, 0.0, 0.04, 0.12, Color("fff5e0"), Vector3(-0.08, -0.12, -0.17), Vector3(-0.3, 0, 0.2))  # tusks
	_cyl(head, 0.0, 0.04, 0.12, Color("fff5e0"), Vector3(0.08, -0.12, -0.17), Vector3(-0.3, 0, -0.2))
	_capsule(head, 0.03, 0.14, Color("3a2050"), Vector3(-0.08, 0.1, -0.19), Vector3(0, 0, 1.3))
	_capsule(head, 0.03, 0.14, Color("3a2050"), Vector3(0.08, 0.1, -0.19), Vector3(0, 0, -1.3))
	var gold := Color("f2b632")
	_cyl(head, 0.19, 0.2, 0.1, gold, Vector3(0, 0.2, 0))
	for i in 6:
		var a := TAU * i / 6.0
		_cyl(head, 0.0, 0.04, 0.12, gold.lightened(0.15), Vector3(cos(a) * 0.18, 0.3, sin(a) * 0.18))
	_capsule(weapon, 0.05, 0.4, Color("7a4a26"), Vector3(0, 0.18, 0))
	_sphere(weapon, 0.11, Color("6a3a1e"), Vector3(0, 0.4, 0))
	for i in 4:
		var a2 := TAU * i / 4.0
		_cyl(weapon, 0.0, 0.03, 0.09, Color("dfe6ee"), Vector3(cos(a2) * 0.11, 0.42, sin(a2) * 0.11), Vector3(sin(a2) * 1.5, 0, -cos(a2) * 1.5))

func _build_ninja() -> void:
	var cloth := Color("2a2a3a")
	_base(cloth, SKIN, 0.17, 0.2, Color("1e1e2a"))
	_sphere(head, 0.215, cloth, Vector3(0, 0.02, 0.02), Vector3(1.04, 1.02, 1.04))
	_box(head, Vector3(0.3, 0.07, 0.05), SKIN, Vector3(0, 0.05, -0.19))  # eye slit
	_sphere(head, 0.035, Color("2a1d1a"), Vector3(-0.07, 0.05, -0.215))
	_sphere(head, 0.035, Color("2a1d1a"), Vector3(0.07, 0.05, -0.215))
	_torus(head, 0.19, 0.225, Color("e03a4a"), Vector3(0, 0.12, 0), Vector3(0.15, 0, 0), Vector3(1, 0.6, 1))  # headband
	_capsule(head, 0.025, 0.2, Color("e03a4a"), Vector3(0.06, 0.1, 0.24), Vector3(0.6, 0, 0.4))
	_box(weapon, Vector3(0.03, 0.4, 0.015), Color("e8eef6"), Vector3(0, 0.22, 0))
	_box(weapon, Vector3(0.09, 0.025, 0.06), Color("f2b632"), Vector3(0, 0.02, 0))

func _build_runner() -> void:
	# orange runner with goggles and winged shoes
	_base(Color("f08a2a"), SKIN, 0.17, 0.2, Color("4a3a6a"))
	_sphere(head, 0.2, Color("ffd23f"), Vector3(0, 0.08, 0.05), Vector3(1.08, 0.8, 1.05))  # spiky hair base
	for i in 4:
		_cyl(head, 0.0, 0.05, 0.16, Color("ffd23f"), Vector3(-0.09 + i * 0.06, 0.16, 0.12), Vector3(0.9, 0, 0))
	_torus(head, 0.07, 0.09, Color("3a3a50"), Vector3(-0.08, 0.06, -0.18), Vector3(PI * 0.5, 0, 0))
	_torus(head, 0.07, 0.09, Color("3a3a50"), Vector3(0.08, 0.06, -0.18), Vector3(PI * 0.5, 0, 0))
	for leg in [leg_l, leg_r]:
		_box(leg, Vector3(0.14, 0.02, 0.08), Color("ffffff"), Vector3(0.06 if leg == leg_r else -0.06, -0.1, 0.04), Vector3(0, 0, 0.4 if leg == leg_r else -0.4))

func _build_golem() -> void:
	# stone golem: Toy Clash giant proportions in mossy stone
	var stone := Color("9aa0aa")
	_base(stone, stone.lightened(0.1), 0.25, 0.19, stone.darkened(0.25), 0.13)
	_sphere(torso, 0.14, stone.darkened(0.08), Vector3(-0.24, 0.42, 0), Vector3(1.2, 0.95, 1))
	_sphere(torso, 0.14, stone.darkened(0.08), Vector3(0.24, 0.42, 0), Vector3(1.2, 0.95, 1))
	_sphere(torso, 0.09, Color("6fbf4a"), Vector3(-0.24, 0.52, 0), Vector3(1.2, 0.5, 1))  # moss
	_sphere(head, 0.12, Color("6fbf4a"), Vector3(0, 0.15, 0.04), Vector3(1.5, 0.5, 1.3))
	_capsule(head, 0.03, 0.14, Color("4a4e58"), Vector3(-0.08, 0.08, -0.17), Vector3(0, 0, 1.4))
	_capsule(head, 0.03, 0.14, Color("4a4e58"), Vector3(0.08, 0.08, -0.17), Vector3(0, 0, -1.4))
	var gem := MeshInstance3D.new()
	gem.mesh = _sphere_mesh(0.06, 64, 32)
	gem.material_override = _glow_mat(Color("ff5f6a"), 1.8)
	gem.position = Vector3(0, 0.3, -0.21)
	torso.add_child(gem)

func _build_illusionist() -> void:
	# stage magician: purple cape, mask, top hat
	var robe := Color("6a3aa0")
	_base(robe, SKIN, 0.18, 0.2, Color("3a2050"))
	_cyl(torso, 0.13, 0.23, 0.3, robe.darkened(0.1), Vector3(0, 0.18, 0))
	_sphere(torso, 0.22, Color("2a1a40"), Vector3(0, 0.3, 0.13), Vector3(1.1, 1.1, 0.4))
	_box(head, Vector3(0.3, 0.08, 0.05), Color("f2f0ff"), Vector3(0, 0.05, -0.19))
	_cyl(head, 0.24, 0.24, 0.03, Color("1e1e2a"), Vector3(0, 0.15, 0))
	_cyl(head, 0.14, 0.15, 0.26, Color("1e1e2a"), Vector3(0, 0.3, 0))
	_cyl(head, 0.152, 0.152, 0.05, Color("c84ad8"), Vector3(0, 0.2, 0))
	_capsule(weapon, 0.02, 0.32, Color("1e1e2a"), Vector3(0, 0.14, 0))
	_sphere(weapon, 0.035, Color("ffffff"), Vector3(0, 0.3, 0))

func _build_dummy() -> void:
	# straw training dummy
	var straw := Color("e8c060")
	_base(Color("b8894a"), straw, 0.18, 0.19, Color("8a6a3a"))
	_sphere(head, 0.2, straw.darkened(0.08), Vector3(0, 0.12, 0.02), Vector3(1.1, 0.4, 1.1))
	_cyl(head, 0.24, 0.24, 0.025, Color("c89a4a"), Vector3(0, 0.15, 0))
	_cyl(head, 0.11, 0.13, 0.12, Color("c89a4a"), Vector3(0, 0.22, 0))

## Jelly blob without limbs; attacks with a body bounce.
func _build_slime() -> void:
	var jelly := Color("7ed957")
	_sphere(torso, 0.3, jelly, Vector3(0, 0.24, 0), Vector3(1.0, 0.85, 1.0))
	_sphere(torso, 0.12, jelly.lightened(0.35), Vector3(-0.1, 0.4, -0.12), Vector3(1, 0.6, 1))  # shine
	_torus(torso, 0.25, 0.3, _team_col(), Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 1.4, 1))
	head = _node(torso, Vector3(0, 0.3, 0))
	var eye_col := Color("2a1d1a")
	_sphere(head, 0.05, Color.WHITE, Vector3(-0.1, 0.03, -0.26), Vector3(1, 1.2, 0.6))
	_sphere(head, 0.05, Color.WHITE, Vector3(0.1, 0.03, -0.26), Vector3(1, 1.2, 0.6))
	_sphere(head, 0.028, eye_col, Vector3(-0.1, 0.03, -0.29))
	_sphere(head, 0.028, eye_col, Vector3(0.1, 0.03, -0.29))
	_capsule(head, 0.015, 0.1, eye_col, Vector3(0, -0.07, -0.27), Vector3(0, 0, PI * 0.5))

## Three-headed serpent coiled on the ground.
func _build_hydra() -> void:
	var scale_col := Color("3fb8a0")
	_sphere(torso, 0.3, scale_col, Vector3(0, 0.18, 0), Vector3(1.1, 0.6, 1.0))
	_torus(torso, 0.22, 0.32, scale_col.darkened(0.12), Vector3(0, 0.08, 0.05), Vector3.ZERO, Vector3(1, 1.2, 1))
	_torus(torso, 0.26, 0.31, _team_col(), Vector3(0, 0.2, 0), Vector3.ZERO, Vector3(1, 1.2, 0.95))
	head = _node(torso, Vector3(0, 0.35, 0))
	for i in 3:
		var x := (i - 1) * 0.16
		var neck := _node(head, Vector3(x, 0, 0))
		neck.rotation = Vector3(0.25, 0, -(i - 1) * 0.35)
		_capsule(neck, 0.06, 0.34, scale_col, Vector3(0, 0.14, 0))
		var hd := _node(neck, Vector3(0, 0.32, -0.03))
		_sphere(hd, 0.1, scale_col.lightened(0.08), Vector3.ZERO, Vector3(1, 0.85, 1.25))
		_sphere(hd, 0.025, Color("ffe04a"), Vector3(-0.05, 0.04, -0.09))
		_sphere(hd, 0.025, Color("ffe04a"), Vector3(0.05, 0.04, -0.09))
		_cyl(hd, 0.0, 0.025, 0.08, Color("fff5e0"), Vector3(0, 0.08, 0.02), Vector3(-0.4, 0, 0))

# ------------------------------------------------------------------ march field creatures
## Two rosters share the classic roles: beasts (wolf / horned bunny / iron-tusk boar / chief bear) and
## monsters (one-eyed imp / eye bat / treasure mimic / tentacle fiend). Mid-bosses step out of both lines:
## a siege-armoured war mammoth and a floating abyss lord — bigger, armoured, glowing, ornamented.

## Unlit glowing bit (eyes, cores, runes): never flashes or tints.
func _glow(parent: Node3D, r: float, col: Color, energy: float, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _sphere_mesh(r, 16, 8)
	mi.material_override = _glow_mat(col, energy)
	mi.position = pos
	mi.scale = scl
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

func _glow_box(parent: Node3D, size: Vector3, col: Color, energy: float, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(size)
	mi.material_override = _glow_mat(col, energy)
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

## Secondary sway: rotation = base + axis * sin(t*f) * (amp + walk_amp * walk).
func _wiggle(n: Node3D, axis: Vector3, amp: float, f: float, walk_amp := 0.0, ph := -1.0) -> void:
	_wiggles.append({"n": n, "axis": axis, "a": amp, "f": f, "wa": walk_amp, "p": randf() * TAU if ph < 0.0 else ph, "base": n.rotation})

func _spin(n: Node3D, v: float) -> void:
	_spins.append({"n": n, "v": v})

## Four legs hanging from hip height h (pivot at the hip, paw on the ground).
func _quad_legs(col: Color, paw: Color, hx: float, fz: float, bz: float, r: float, h: float) -> void:
	for p in [Vector3(-hx, h, -fz), Vector3(hx, h, -fz), Vector3(-hx, h, bz), Vector3(hx, h, bz)]:
		var leg := _node(torso, p)
		_capsule(leg, r, h, col, Vector3(0, -h * 0.5, 0))
		_sphere(leg, r * 1.2, paw, Vector3(0, -h + r * 0.6, -r * 0.3), Vector3(1, 0.7, 1.3))
		quad_legs.append(leg)

## Angry slanted brows over a pair of eyes at (+-x, y, z).
func _brows(parent: Node3D, x: float, y: float, z: float, col: Color, len := 0.1, r := 0.022) -> void:
	_capsule(parent, r, len, col, Vector3(-x, y, z), Vector3(0, 0, 1.25))
	_capsule(parent, r, len, col, Vector3(x, y, z), Vector3(0, 0, -1.25))

## --- ranged support (원거리) -----------------------------------------------------
## Slinger goblin: little green rascal in a leather cap, a pouch of stones on the hip, sling twirled overhead.
func _build_slinger() -> void:
	var skin := Color("9ad458")
	var leather := Color("8a5a34")
	_base(Color("a8743e"), skin, 0.16, 0.2, Color("5a3a20"), 0.065)
	for sx in [-1.0, 1.0]:
		_cyl(head, 0.0, 0.065, 0.22, skin, Vector3(sx * 0.22, 0.04, 0), Vector3(0, 0, -sx * 1.25))   # long ears
	_sphere(head, 0.06, skin.darkened(0.1), Vector3(0, -0.05, -0.2), Vector3(1, 0.8, 1))   # nose
	_hemi(head, 0.19, leather, Vector3(0, 0.07, 0.01))   # leather cap
	_cyl(head, 0.0, 0.04, 0.1, _team_col(), Vector3(0, 0.25, 0.02), Vector3(-0.3, 0, 0))   # cap tuft
	_sphere(torso, 0.07, leather.darkened(0.15), Vector3(-0.17, 0.17, -0.05), Vector3(1, 1.1, 0.9))   # stone pouch
	for i in 2:
		_sphere(torso, 0.03, Color("8f8478"), Vector3(-0.17 + i * 0.03, 0.24, -0.06))
	# sling: cord hanging from the fist, stone cradle at the end, swinging
	var sling := _node(weapon, Vector3.ZERO)
	_capsule(sling, 0.012, 0.3, Color("d8c09a"), Vector3(0, 0.15, 0))
	_sphere(sling, 0.05, leather, Vector3(0, 0.3, 0), Vector3(1, 0.6, 1))
	_sphere(sling, 0.035, Color("8f8478"), Vector3(0, 0.33, 0))
	_wiggle(sling, Vector3(0, 0, 1), 0.5, 9.0, 0.3)

## Crossbow sniper: hooded marksman with a single brass scope-goggle, scarf mask and a heavy crossbow.
func _build_crossbow() -> void:
	var cloak := Color("3e5a5a")
	_base(Color("4e6e64"), SKIN, 0.17, 0.2, Color("2e3e3a"))
	_sphere(head, 0.215, cloak, Vector3(0, 0.04, 0.05), Vector3(1.05, 1.03, 1.05))   # hood
	_cyl(head, 0.0, 0.07, 0.16, cloak, Vector3(0, 0.12, 0.22), Vector3(-1.8, 0, 0))   # hood tip
	_box(head, Vector3(0.3, 0.07, 0.04), _team_col(), Vector3(0, -0.07, -0.18))   # scarf mask
	_cyl(head, 0.045, 0.045, 0.06, Color("c8a040"), Vector3(0.07, 0.03, -0.19), Vector3(PI * 0.5, 0, 0))   # scope goggle
	_glow(head, 0.03, Color("ff5a3a"), 1.6, Vector3(0.07, 0.03, -0.225), Vector3(1, 1, 0.4))
	_cyl(torso, 0.05, 0.05, 0.26, Color("5a3a24"), Vector3(-0.08, 0.36, 0.17), Vector3(0.4, 0, 0.3))   # bolt case
	for i in 3:
		_box(torso, Vector3(0.05, 0.01, 0.04), Defs.COL_ENEMY, Vector3(-0.12 + i * 0.03, 0.5, 0.21))
	# crossbow: stock forward, limbs across the front
	_box(weapon, Vector3(0.05, 0.05, 0.36), Color("6b4428"), Vector3(0, 0.02, -0.12))
	_torus(weapon, 0.15, 0.18, Color("5a5a66"), Vector3(0, 0.02, -0.27), Vector3.ZERO, Vector3(1, 0.4, 0.45))
	_box(weapon, Vector3(0.3, 0.008, 0.008), Color("e8e0d0"), Vector3(0, 0.02, -0.22))   # string

## Fire shaman: bone-masked caster in a flame-red robe with a feather crest and a skull staff that burns violet.
func _build_shaman() -> void:
	var robe := Color("b0402e")
	var bone := Color("f0e6cc")
	_base(robe, Color("c88a5a"), 0.19, 0.2, robe.darkened(0.35), 0.07, false)
	_cyl(torso, 0.13, 0.25, 0.3, robe.darkened(0.08), Vector3(0, 0.17, 0))   # robe skirt
	for i in 5:   # hem tassels
		var a := -1.2 + i * 0.6
		_box(torso, Vector3(0.05, 0.06, 0.02), Defs.COL_GOLD, Vector3(sin(a) * 0.24, 0.04, -cos(a) * 0.24), Vector3(0, a, 0))
	_sphere(head, 0.17, bone, Vector3(0, 0.0, -0.08), Vector3(1.05, 1.1, 0.7))   # bone mask
	for sx in [-1.0, 1.0]:
		_glow(head, 0.03, Color("ff6a2a"), 2.0, Vector3(sx * 0.07, 0.03, -0.2), Vector3(1, 1.2, 0.4))
		_cyl(head, 0.0, 0.035, 0.12, bone, Vector3(sx * 0.14, 0.14, -0.05), Vector3(0, 0, -sx * 0.5))   # mask horns
	_box(head, Vector3(0.1, 0.02, 0.02), Color("5a2a20"), Vector3(0, -0.08, -0.205))
	for i in 5:   # feather crest
		var f := _node(head, Vector3((i - 2) * 0.06, 0.17, 0.06))
		f.rotation = Vector3(-0.35, 0, (i - 2) * -0.28)
		_capsule(f, 0.028, 0.2, [_team_col(), Defs.COL_GOLD, Color("ff8a2a")][i % 3], Vector3(0, 0.1, 0), Vector3.ZERO, Vector3(1, 1, 0.4))
		_wiggle(f, Vector3(1, 0, 0), 0.06, 4.0, 0.2)
	# skull staff
	_capsule(weapon, 0.022, 0.55, Color("5a3a24"), Vector3(0, 0.14, 0))
	_sphere(weapon, 0.065, bone, Vector3(0, 0.44, 0), Vector3(1, 0.95, 1.1))
	_glow(weapon, 0.085, Color("c27aff"), 2.0, Vector3(0, 0.5, 0))
	for sx in [-1.0, 1.0]:
		_sphere(weapon, 0.016, Color("1a0d1a"), Vector3(sx * 0.025, 0.45, -0.055))

## --- beasts (동물형) ------------------------------------------------------------
## Grey wolf: lean four-legged hunter, pale ruff, yellow eyes, red team collar, wagging tail.
func _build_wolf() -> void:
	var fur := Color("8e98ab")
	var pale := Color("e6e9f0")
	var dark := Color("525a6c")
	_quad_legs(fur.darkened(0.06), dark, 0.1, 0.16, 0.16, 0.05, 0.24)
	_sphere(torso, 0.2, fur, Vector3(0, 0.35, 0.03), Vector3(0.85, 0.8, 1.35))
	_sphere(torso, 0.15, pale, Vector3(0, 0.31, -0.17), Vector3(0.95, 1.05, 0.8))   # chest ruff
	for i in 3:
		_cyl(torso, 0.0, 0.045, 0.13, dark, Vector3(0, 0.5 - i * 0.025, -0.08 + i * 0.12), Vector3(0.7, 0, 0))   # back ridge
	_torus(torso, 0.1, 0.135, _team_col(), Vector3(0, 0.44, -0.25), Vector3(0.9, 0, 0))
	head = _node(torso, Vector3(0, 0.52, -0.31))
	_sphere(head, 0.15, fur, Vector3.ZERO, Vector3(1.0, 0.92, 1.0))
	_sphere(head, 0.085, pale, Vector3(0, -0.05, -0.13), Vector3(0.95, 0.75, 1.4))   # muzzle
	_sphere(head, 0.034, Color("2a1d1a"), Vector3(0, -0.02, -0.25))
	for sx in [-1.0, 1.0]:
		_cyl(head, 0.0, 0.06, 0.14, fur, Vector3(sx * 0.08, 0.15, 0.03), Vector3(0, 0, -sx * 0.25))
		_cyl(head, 0.0, 0.035, 0.09, Color("f2a6b4"), Vector3(sx * 0.08, 0.14, 0.0), Vector3(0, 0, -sx * 0.25))
		_sphere(head, 0.07, pale, Vector3(sx * 0.1, -0.04, -0.03), Vector3(0.7, 0.9, 1))   # cheek fluff
		_glow(head, 0.027, Color("ffd23f"), 1.4, Vector3(sx * 0.062, 0.03, -0.135), Vector3(1.3, 0.8, 0.5))
		_cyl(head, 0.0, 0.016, 0.05, Color.WHITE, Vector3(sx * 0.03, -0.1, -0.21), Vector3(PI, 0, 0))   # fangs
	_brows(head, 0.06, 0.07, -0.135, dark, 0.07, 0.016)
	var tail := _node(torso, Vector3(0, 0.42, 0.28))
	tail.rotation.x = 0.9
	_capsule(tail, 0.05, 0.26, fur, Vector3(0, 0.11, 0))
	_sphere(tail, 0.05, pale, Vector3(0, 0.23, 0))
	_wiggle(tail, Vector3(0, 0, 1), 0.3, 7.0, 0.2)

## Horned bunny (jackalope): round, big hind feet, long twitching ears, a golden horn to butt with.
func _build_hornbunny() -> void:
	var fur := Color("f4ead8")
	var pink := Color("ff9fb8")
	leg_l = _node(torso, Vector3(-0.09, 0.08, 0))
	leg_r = _node(torso, Vector3(0.09, 0.08, 0))
	for leg in [leg_l, leg_r]:
		_sphere(leg, 0.075, fur.darkened(0.1), Vector3(0, -0.035, -0.05), Vector3(1, 0.6, 1.8))
	_sphere(torso, 0.19, fur, Vector3(0, 0.26, 0), Vector3(1, 1, 0.95))
	_sphere(torso, 0.12, Color.WHITE, Vector3(0, 0.23, -0.1), Vector3(1, 1.1, 0.6))
	_sphere(torso, 0.075, Color.WHITE, Vector3(0, 0.19, 0.19))   # cotton tail
	for sx in [-1.0, 1.0]:
		_sphere(torso, 0.045, fur.darkened(0.06), Vector3(sx * 0.12, 0.3, -0.13))   # tiny paws
	_torus(torso, 0.1, 0.14, _team_col(), Vector3(0, 0.41, 0), Vector3.ZERO, Vector3(1, 1.3, 1))   # scarf
	var tail := _node(torso, Vector3(0.07, 0.4, 0.12))
	_capsule(tail, 0.035, 0.18, _team_col(), Vector3(0, -0.06, 0.04), Vector3(0.6, 0, 0.3), Vector3(1.2, 1, 0.5))
	_wiggle(tail, Vector3(1, 0, 0), 0.25, 9.0, 0.4)
	head = _node(torso, Vector3(0, 0.53, -0.02))
	_sphere(head, 0.19, fur, Vector3.ZERO, Vector3(1.05, 0.95, 1))
	for sx in [-1.0, 1.0]:
		_sphere(head, 0.035, pink, Vector3(sx * 0.11, -0.06, -0.14), Vector3(1, 0.6, 0.5))
		_sphere(head, 0.033, Color("2a1d1a"), Vector3(sx * 0.075, 0.02, -0.168), Vector3(1, 1.2, 0.6))
		_glow(head, 0.01, Color.WHITE, 1.2, Vector3(sx * 0.07, 0.035, -0.19))
		var ear := _node(head, Vector3(sx * 0.08, 0.14, 0.03))
		ear.rotation = Vector3(0.15, 0, -sx * 0.22)
		_capsule(ear, 0.05, 0.34, fur, Vector3(0, 0.16, 0), Vector3.ZERO, Vector3(1, 1, 0.55))
		_capsule(ear, 0.028, 0.25, pink, Vector3(0, 0.16, -0.022), Vector3.ZERO, Vector3(1, 1, 0.4))
		_wiggle(ear, Vector3(1, 0, sx * 0.4), 0.1, 5.0, 0.35)
	_brows(head, 0.075, 0.08, -0.16, Color("b88a6a"), 0.06, 0.013)
	_sphere(head, 0.024, pink, Vector3(0, -0.04, -0.19))
	_box(head, Vector3(0.05, 0.045, 0.02), Color.WHITE, Vector3(0, -0.09, -0.175))   # buck teeth
	var horn := Color("e9b85a")
	_cyl(head, 0.0, 0.05, 0.24, horn, Vector3(0, 0.19, -0.1), Vector3(-0.5, 0, 0))
	_torus(head, 0.035, 0.05, horn.darkened(0.25), Vector3(0, 0.14, -0.08), Vector3(-0.5, 0, 0))

## Iron-tusk boar: heavy hunched charger in a red war cloth and an iron brow plate.
func _build_boar() -> void:
	var hide := Color("7a4e36")
	var dark := Color("3e2a22")
	var steel := Color("aab3c2")
	_quad_legs(hide.darkened(0.12), dark, 0.13, 0.17, 0.19, 0.062, 0.2)
	_sphere(torso, 0.26, hide, Vector3(0, 0.33, 0.04), Vector3(1, 0.88, 1.3))
	_sphere(torso, 0.2, hide.lightened(0.08), Vector3(0, 0.36, -0.18), Vector3(1.05, 1, 0.8))   # shoulder hump
	for i in 5:
		_cyl(torso, 0.0, 0.05, 0.15, dark, Vector3(0, 0.56 - i * 0.02, -0.22 + i * 0.1), Vector3(0.6, 0, 0))   # bristles
	_hemi(torso, 0.2, _team_col(), Vector3(0, 0.46, 0.12), Vector3(1.15, 0.55, 1.2))   # war cloth
	for sx in [-1.0, 1.0]:
		_sphere(torso, 0.03, steel, Vector3(sx * 0.17, 0.48, 0.12))
		_sphere(torso, 0.03, steel, Vector3(sx * 0.12, 0.52, 0.28))
	_torus(torso, 0.03, 0.05, hide.darkened(0.2), Vector3(0, 0.38, 0.34), Vector3(0.4, 0, 0))   # curly tail
	head = _node(torso, Vector3(0, 0.37, -0.36))
	_sphere(head, 0.16, hide, Vector3.ZERO, Vector3(1.05, 0.95, 1.0))
	_cyl(head, 0.075, 0.085, 0.12, Color("d88f7e"), Vector3(0, -0.04, -0.15), Vector3(-PI * 0.5, 0, 0))   # snout
	for sx in [-1.0, 1.0]:
		_sphere(head, 0.02, dark, Vector3(sx * 0.03, -0.04, -0.212))
		_glow(head, 0.024, Color("ff4a3a"), 1.5, Vector3(sx * 0.085, 0.035, -0.125))
		_cyl(head, 0.0, 0.05, 0.1, dark, Vector3(sx * 0.12, 0.11, 0.04), Vector3(0, 0, -sx * 0.7))   # ears
		var tusk := _node(head, Vector3(sx * 0.07, -0.08, -0.17))
		tusk.rotation = Vector3(-0.45, 0, -sx * 0.4)
		_cyl(tusk, 0.0, 0.032, 0.17, Color("fff3dc"), Vector3(0, 0.08, 0))
		_torus(tusk, 0.025, 0.04, Defs.COL_GOLD, Vector3(0, 0.015, 0))
	_hemi(head, 0.135, steel, Vector3(0, 0.05, -0.02), Vector3(1.12, 0.75, 1.12))   # iron brow plate
	_brows(head, 0.07, 0.07, -0.135, dark, 0.07, 0.018)

## Chief bear: upright, broad, claws out — scarred war paint, tooth necklace, one spiked pauldron.
func _build_bear() -> void:
	var fur := Color("8a5a3a")
	var tan := Color("e0b080")
	_base(fur, fur, 0.25, 0.22, fur.darkened(0.25), 0.1, false)
	_sphere(torso, 0.17, tan, Vector3(0, 0.27, -0.12), Vector3(1, 1.05, 0.6))   # belly
	_sphere(head, 0.1, tan, Vector3(0, -0.06, -0.17), Vector3(1.1, 0.8, 0.9))   # muzzle
	_sphere(head, 0.04, Color("2a1d1a"), Vector3(0, -0.02, -0.255), Vector3(1.2, 0.8, 0.8))
	for sx in [-1.0, 1.0]:
		_sphere(head, 0.075, fur, Vector3(sx * 0.16, 0.16, 0.0), Vector3(1, 1, 0.6))   # round ears
		_sphere(head, 0.04, tan, Vector3(sx * 0.16, 0.16, -0.035), Vector3(1, 1, 0.4))
		_sphere(head, 0.028, Color("2a1d1a"), Vector3(sx * 0.085, 0.04, -0.19), Vector3(1, 1.1, 0.6))
		_box(head, Vector3(0.04, 0.12, 0.02), _team_col(), Vector3(sx * 0.13, -0.03, -0.165), Vector3(0, sx * 0.5, 0))   # war paint
	_brows(head, 0.085, 0.09, -0.19, fur.darkened(0.45), 0.08, 0.02)
	for arm in [arm_l, arm_r]:
		var sx := -1.0 if arm == arm_l else 1.0
		for i in 3:
			_cyl(arm, 0.0, 0.022, 0.08, Color("fff5e0"), Vector3(sx * 0.06 + (i - 1) * 0.035, -0.25, -0.05), Vector3(-2.6, 0, 0))   # claws
	# tooth necklace + spiked pauldron
	_torus(torso, 0.17, 0.19, Color("5b3a22"), Vector3(0, 0.47, -0.02), Vector3(0.25, 0, 0))
	for i in 5:
		var a := -0.9 + i * 0.45
		_cyl(torso, 0.0, 0.022, 0.07, Color("fff5e0"), Vector3(sin(a) * 0.18, 0.44 - cos(a) * 0.01, -cos(a) * 0.16), Vector3(PI, 0, 0))
	_hemi(torso, 0.12, Color("8a8f9e"), Vector3(-0.25, 0.47, 0), Vector3(1.1, 0.8, 1.1))
	for i in 3:
		_cyl(torso, 0.0, 0.025, 0.1, Color("dfe6ee"), Vector3(-0.25 + (i - 1) * 0.06, 0.55, 0), Vector3(0, 0, 0.3))
	_box(head, Vector3(0.025, 0.14, 0.02), Color("c98a6a"), Vector3(0.07, 0.07, -0.205), Vector3(0, 0, 0.5))   # scar

## --- monsters (괴물형) ----------------------------------------------------------
## One-eyed imp: purple cyclops with tiny horns, a big grin, a spade tail and a pitchfork.
func _build_imp() -> void:
	var skin := Color("b764e0")
	_base(Color("4a2a5a"), skin, 0.17, 0.22, Color("3a2048"), 0.07, false)
	_sphere(head, 0.11, Color("fbf6ee"), Vector3(0, 0.04, -0.15), Vector3(1, 1, 0.6))
	_glow(head, 0.055, Color("ffcf3a"), 1.4, Vector3(0, 0.04, -0.205), Vector3(1, 1, 0.4))
	_sphere(head, 0.027, Color("1a0d1a"), Vector3(0, 0.04, -0.228), Vector3(0.5, 1.3, 0.5))
	_capsule(head, 0.032, 0.24, skin.darkened(0.3), Vector3(0, 0.15, -0.17), Vector3(0.0, 0, PI * 0.5))   # heavy brow
	_box(head, Vector3(0.18, 0.045, 0.02), Color("3a1030"), Vector3(0, -0.11, -0.19))   # grin
	for sx in [-1.0, 1.0]:
		_cyl(head, 0.0, 0.016, 0.05, Color.WHITE, Vector3(sx * 0.05, -0.1, -0.205), Vector3(PI, 0, 0))
		_cyl(head, 0.0, 0.045, 0.17, Color("fff0d0"), Vector3(sx * 0.12, 0.19, 0.0), Vector3(0, 0, -sx * 0.45))   # horns
		_cyl(head, 0.0, 0.05, 0.17, skin, Vector3(sx * 0.22, 0.0, 0), Vector3(0, 0, -sx * 1.3))   # pointy ears
	var tail := _node(torso, Vector3(0, 0.2, 0.16))
	tail.rotation.x = 1.0
	_capsule(tail, 0.022, 0.26, skin.darkened(0.15), Vector3(0, 0.12, 0))
	_cyl(tail, 0.0, 0.06, 0.08, _team_col(), Vector3(0, 0.27, 0), Vector3.ZERO, Vector3(1, 1, 0.4))
	_wiggle(tail, Vector3(0, 0, 1), 0.4, 6.0)
	# pitchfork
	_capsule(weapon, 0.02, 0.5, Color("5a3a24"), Vector3(0, 0.12, 0))
	_box(weapon, Vector3(0.14, 0.025, 0.025), Color("c8ced8"), Vector3(0, 0.37, 0))
	for i in 3:
		_cyl(weapon, 0.0, 0.016, 0.1, Color("dfe6ee"), Vector3((i - 1) * 0.06, 0.43, 0))

## Eye bat: a floating eyeball with a heavy lid, leathery wings beating fast, little dangling claws.
func _build_eyebat() -> void:
	hover = 0.26
	var hide := Color("5a3a7a")
	head = _node(torso, Vector3(0, 0.42, 0))
	_sphere(head, 0.2, Color("fbf6ee"), Vector3.ZERO)
	for i in 3:   # veins
		_capsule(head, 0.008, 0.12, Color("ff8a9a"), Vector3(-0.12 + i * 0.12, -0.08, -0.15), Vector3(0.4, 0, 0.5 - i * 0.5))
	_glow(head, 0.095, Color("ff7a2a"), 1.3, Vector3(0, 0, -0.16), Vector3(1, 1, 0.45))
	_sphere(head, 0.045, Color("1a0d1a"), Vector3(0, 0, -0.2), Vector3(1, 1.25, 0.4))
	_glow(head, 0.018, Color.WHITE, 1.3, Vector3(0.035, 0.04, -0.215))
	var lid := _hemi(head, 0.212, hide, Vector3(0, 0.0, 0.0))
	lid.rotation.x = 0.55
	_torus(head, 0.195, 0.222, _team_col(), Vector3(0, 0.0, 0.0), Vector3(0.55, 0, 0), Vector3(1, 0.6, 1))   # lid rim
	for sx in [-1.0, 1.0]:
		_cyl(head, 0.0, 0.035, 0.11, Color("fff0d0"), Vector3(sx * 0.1, 0.2, 0.05), Vector3(0.3, 0, -sx * 0.35))
		var w := _node(head, Vector3(sx * 0.17, 0.04, 0.04))
		_sphere(w, 0.16, hide, Vector3(sx * 0.16, 0.02, 0), Vector3(1.35, 0.7, 0.16))
		_sphere(w, 0.08, hide.lightened(0.15), Vector3(sx * 0.12, -0.06, 0), Vector3(1.2, 0.6, 0.12))
		_capsule(w, 0.014, 0.3, hide.darkened(0.3), Vector3(sx * 0.15, 0.05, -0.01), Vector3(0, 0, sx * 1.35))   # wing bone
		_cyl(w, 0.0, 0.02, 0.07, Color("fff0d0"), Vector3(sx * 0.3, 0.1, 0), Vector3(0, 0, -sx * 0.8))   # claw tip
		_wiggle(w, Vector3(0, 0, sx), 0.55, 15.0, 0.0, 0.0)
		_cyl(head, 0.0, 0.02, 0.08, hide.darkened(0.3), Vector3(sx * 0.05, -0.22, 0.0), Vector3(PI, 0, 0))   # dangling claws

## Treasure mimic: a gold-banded chest whose lid is a jaw — teeth, lolling team-red tongue, glinting eyes.
func _build_mimic() -> void:
	var wood := Color("a8642e")
	var band := Color("f2b632")
	var maw := Color("2a1020")
	leg_l = _node(torso, Vector3(-0.13, 0.12, 0.0))
	leg_r = _node(torso, Vector3(0.13, 0.12, 0.0))
	for leg in [leg_l, leg_r]:
		_capsule(leg, 0.05, 0.14, Color("5a3a20"), Vector3(0, -0.05, 0))
		for i in 3:
			_cyl(leg, 0.0, 0.016, 0.05, Color("fff0d0"), Vector3((i - 1) * 0.03, -0.11, -0.06), Vector3(-PI * 0.5, 0, 0))
	_box(torso, Vector3(0.52, 0.26, 0.38), wood, Vector3(0, 0.26, 0))
	_box(torso, Vector3(0.54, 0.045, 0.4), band, Vector3(0, 0.15, 0))
	for sx in [-1.0, 1.0]:
		_box(torso, Vector3(0.05, 0.27, 0.4), band, Vector3(sx * 0.19, 0.26, 0))
	_box(torso, Vector3(0.1, 0.11, 0.03), band.lightened(0.1), Vector3(0, 0.3, -0.2))   # lock plate
	_box(torso, Vector3(0.025, 0.045, 0.01), maw, Vector3(0, 0.29, -0.217))
	_box(torso, Vector3(0.46, 0.03, 0.32), maw, Vector3(0, 0.39, 0))
	for i in 6:
		_cyl(torso, 0.0, 0.028, 0.075, Color("fff5e0"), Vector3(-0.19 + i * 0.076, 0.42, -0.16))
	for i in 3:
		_cyl(torso, 0.04, 0.04, 0.015, Defs.COL_GOLD, Vector3(-0.1 + i * 0.1, 0.41, 0.06 - i * 0.03), Vector3(0.3 * i, 0, 0.2))
	var tongue := _node(torso, Vector3(0, 0.41, -0.06))
	_capsule(tongue, 0.05, 0.3, _team_col(), Vector3(0, 0, -0.13), Vector3(PI * 0.5 + 0.25, 0, 0), Vector3(1.4, 1, 0.5))
	_wiggle(tongue, Vector3(1, 0, 0), 0.2, 7.0, 0.2)
	head = _node(torso, Vector3(0, 0.39, 0.19))   # lid hinge at the back
	_box(head, Vector3(0.52, 0.13, 0.38), wood.lightened(0.06), Vector3(0, 0.065, -0.19))
	_box(head, Vector3(0.54, 0.035, 0.4), band, Vector3(0, 0.1, -0.19))
	for sx in [-1.0, 1.0]:
		_box(head, Vector3(0.05, 0.14, 0.4), band, Vector3(sx * 0.19, 0.065, -0.19))
		_glow(head, 0.035, Color("ffe04a"), 1.6, Vector3(sx * 0.09, 0.07, -0.385), Vector3(1.2, 0.8, 0.4))
	_brows(head, 0.09, 0.115, -0.385, maw, 0.09, 0.016)
	for i in 6:
		_cyl(head, 0.0, 0.028, 0.075, Color("fff5e0"), Vector3(-0.19 + i * 0.076, -0.03, -0.35), Vector3(PI, 0, 0))
	head.rotation.x = 0.6
	_wiggle(head, Vector3(1, 0, 0), 0.16, 8.0, 0.2)

## Tentacle fiend: a squat mantle on a skirt of tentacles, one great green eye, horns, two lashing whip-arms.
func _build_horror() -> void:
	var hide := Color("3f7fa8")
	var under := Color("9fd6d0")
	for i in 6:
		var a := TAU * i / 6.0 + 0.5
		var t := _node(torso, Vector3(cos(a) * 0.15, 0.17, sin(a) * 0.15))
		t.rotation = Vector3(-sin(a) * 0.95, 0, cos(a) * 0.95)
		_capsule(t, 0.06, 0.26, hide.darkened(0.12), Vector3(0, -0.1, 0))
		_sphere(t, 0.045, under, Vector3(0, -0.2, 0))
		_wiggle(t, Vector3(sin(a), 0, -cos(a)) * 0.6 + Vector3(0, 1, 0) * 0.3, 0.18, 5.0, 0.25)
	_sphere(torso, 0.28, hide, Vector3(0, 0.42, 0), Vector3(1, 1.05, 0.95))
	_sphere(torso, 0.2, under, Vector3(0, 0.33, -0.13), Vector3(1.05, 0.9, 0.6))
	for p in [Vector3(-0.15, 0.6, 0.12), Vector3(0.12, 0.66, 0.08), Vector3(0.2, 0.48, 0.15), Vector3(-0.05, 0.5, 0.24), Vector3(-0.22, 0.42, 0.06)]:
		_sphere(torso, 0.035, Color("ff7ab8"), p)
	_torus(torso, 0.25, 0.29, _team_col(), Vector3(0, 0.22, 0), Vector3.ZERO, Vector3(1, 1.3, 1))
	head = _node(torso, Vector3(0, 0.5, 0))
	_sphere(head, 0.12, Color("fbf6ee"), Vector3(0, 0.04, -0.2), Vector3(1, 1, 0.55))
	_glow(head, 0.065, Color("8fff6a"), 1.4, Vector3(0, 0.04, -0.255), Vector3(1, 1, 0.4))
	_sphere(head, 0.03, Color("102010"), Vector3(0, 0.04, -0.282), Vector3(0.45, 1.5, 0.5))
	_capsule(head, 0.035, 0.28, hide.darkened(0.35), Vector3(0, 0.17, -0.2), Vector3(0, 0, PI * 0.5))
	_box(head, Vector3(0.22, 0.05, 0.03), Color("1a0d1a"), Vector3(0, -0.12, -0.24))
	for i in 5:
		_cyl(head, 0.0, 0.018, 0.055, Color.WHITE, Vector3(-0.08 + i * 0.04, -0.105, -0.25), Vector3(PI, 0, 0))
	for sx in [-1.0, 1.0]:
		var hn := _node(head, Vector3(sx * 0.17, 0.2, 0.0))
		hn.rotation.z = -sx * 0.5
		_capsule(hn, 0.04, 0.16, Color("e8dcc4"), Vector3(0, 0.06, 0))
		_cyl(hn, 0.0, 0.035, 0.1, Color("e8dcc4"), Vector3(sx * 0.03, 0.17, 0), Vector3(0, 0, sx * 0.6))
	arm_l = _node(torso, Vector3(-0.26, 0.44, -0.02))
	arm_r = _node(torso, Vector3(0.26, 0.44, -0.02))
	for arm in [arm_l, arm_r]:
		var sx := -1.0 if arm == arm_l else 1.0
		_capsule(arm, 0.055, 0.38, hide.darkened(0.08), Vector3(sx * 0.06, -0.15, 0), Vector3(0, 0, sx * 0.35))
		_sphere(arm, 0.07, under, Vector3(sx * 0.12, -0.31, 0), Vector3(1, 1.2, 1))
		for i in 3:
			_sphere(arm, 0.017, Color("ff7ab8"), Vector3(sx * 0.07 + sx * 0.02 * i, -0.12 - i * 0.07, -0.05))   # suckers
	weapon = _node(arm_r, Vector3(0.12, -0.31, 0))

## --- mid-bosses ----------------------------------------------------------------
## War mammoth: a shaggy titan dressed for siege — steel face plate with a blazing gem, gold-ringed tusks,
## curling trunk, side armour, red war blanket and a wooden howdah flying the war banner with torches.
func _build_mammoth() -> void:
	var fur := Color("8a5236")
	var fur_d := Color("6e4030")
	var ivory := Color("fff1d6")
	var gold := Defs.COL_GOLD
	var steel := Color("a0aabb")
	var red := _team_col()
	for p in [Vector3(-0.17, 0.3, -0.17), Vector3(0.17, 0.3, -0.17), Vector3(-0.17, 0.3, 0.2), Vector3(0.17, 0.3, 0.2)]:
		var leg := _node(torso, p)
		_cyl(leg, 0.085, 0.1, 0.3, fur_d, Vector3(0, -0.15, 0))
		_torus(leg, 0.085, 0.115, gold, Vector3(0, -0.2, 0))
		_cyl(leg, 0.11, 0.115, 0.06, Color("e8d6b0"), Vector3(0, -0.27, 0))
		for i in 3:
			_sphere(leg, 0.03, ivory, Vector3((i - 1) * 0.055, -0.27, -0.1))
		quad_legs.append(leg)
	_sphere(torso, 0.34, fur, Vector3(0, 0.5, 0.03), Vector3(1.0, 0.92, 1.22))
	for i in 12:   # shaggy skirt
		var a := TAU * i / 12.0
		_sphere(torso, 0.085, fur_d, Vector3(cos(a) * 0.29, 0.36, sin(a) * 0.36 + 0.03), Vector3(1, 1.5, 1))
	_sphere(torso, 0.25, fur.lightened(0.05), Vector3(0, 0.64, -0.15))   # shoulder hump
	_hemi(torso, 0.3, red, Vector3(0, 0.6, 0.1), Vector3(1.1, 0.75, 1.1))   # war blanket
	_torus(torso, 0.3, 0.34, gold, Vector3(0, 0.6, 0.1), Vector3.ZERO, Vector3(1.1, 1, 1.1))
	for sx in [-1.0, 1.0]:
		_box(torso, Vector3(0.035, 0.22, 0.32), steel, Vector3(sx * 0.36, 0.5, 0.04), Vector3(0, 0, sx * 0.18))
		for zz in [-0.08, 0.16]:
			_sphere(torso, 0.025, gold, Vector3(sx * 0.38, 0.58, zz))
	# howdah + banner + torches
	var tower := _node(torso, Vector3(0, 0.8, 0.12))
	_box(tower, Vector3(0.34, 0.14, 0.3), Color("8a5a2e"), Vector3(0, 0.05, 0))
	_box(tower, Vector3(0.36, 0.03, 0.32), gold, Vector3(0, 0.12, 0))
	for cx in [-0.15, 0.0, 0.15]:
		for cz in [-0.13, 0.13]:
			_box(tower, Vector3(0.06, 0.07, 0.04), Color("9a6a3a"), Vector3(cx, 0.17, cz))
	_capsule(tower, 0.018, 0.5, Color("5a3a22"), Vector3(0.13, 0.3, 0.1))
	_sphere(tower, 0.03, gold, Vector3(0.13, 0.56, 0.1))
	var flag := _node(tower, Vector3(0.13, 0.46, 0.1))
	_box(flag, Vector3(0.2, 0.14, 0.012), red, Vector3(-0.1, 0, 0))
	_box(flag, Vector3(0.2, 0.025, 0.014), gold, Vector3(-0.1, 0.06, 0))
	_sphere(flag, 0.03, ivory, Vector3(-0.1, -0.01, 0), Vector3(1, 1, 0.5))   # skull mark
	_wiggle(flag, Vector3(0, 1, 0), 0.3, 3.0)
	for sx in [-1.0, 1.0]:
		_capsule(tower, 0.012, 0.3, Color("5a3a22"), Vector3(sx * 0.12, 0.25, -0.12), Vector3(-0.3, 0, sx * 0.25))   # spears
		_cyl(tower, 0.0, 0.025, 0.07, Color("dfe6ee"), Vector3(sx * 0.155, 0.4, -0.165), Vector3(-0.3, 0, sx * 0.25))
		_capsule(tower, 0.012, 0.1, Color("5a3a22"), Vector3(sx * 0.17, 0.2, -0.15))
		_glow(tower, 0.035, Color("ffb13b"), 2.0, Vector3(sx * 0.17, 0.27, -0.15), Vector3(1, 1.4, 1))   # torches
	# head
	head = _node(torso, Vector3(0, 0.66, -0.4))
	_sphere(head, 0.235, fur, Vector3.ZERO, Vector3(1, 1, 0.95))
	_sphere(head, 0.15, fur_d, Vector3(0, 0.15, 0.04))
	_box(head, Vector3(0.2, 0.22, 0.04), steel, Vector3(0, 0.04, -0.195), Vector3(-0.2, 0, 0))   # face plate
	_box(head, Vector3(0.22, 0.03, 0.05), gold, Vector3(0, 0.15, -0.17), Vector3(-0.2, 0, 0))
	_glow(head, 0.04, Color("ff3a4a"), 2.2, Vector3(0, 0.07, -0.225))
	_cyl(head, 0.0, 0.04, 0.13, steel.lightened(0.15), Vector3(0, 0.2, -0.17), Vector3(-0.6, 0, 0))   # brow spike
	for sx in [-1.0, 1.0]:
		_glow(head, 0.03, Color("ffb13b"), 1.8, Vector3(sx * 0.13, 0.0, -0.16), Vector3(1.2, 0.7, 0.5))
		_capsule(head, 0.022, 0.1, fur_d.darkened(0.3), Vector3(sx * 0.13, 0.05, -0.17), Vector3(0, 0, -sx * 1.15))
		var ear := _node(head, Vector3(sx * 0.2, 0.0, 0.05))
		_sphere(ear, 0.13, fur_d, Vector3(sx * 0.02, 0, 0), Vector3(0.35, 1.0, 0.9))
		_wiggle(ear, Vector3(0, sx, 0), 0.15, 2.2)
		var tk := _node(head, Vector3(sx * 0.11, -0.12, -0.12))
		tk.rotation = Vector3(-2.4, 0, -sx * 0.3)
		_capsule(tk, 0.055, 0.18, ivory, Vector3(0, 0.07, 0))
		var tk2 := _node(tk, Vector3(0, 0.15, 0))
		tk2.rotation.x = 1.1
		_capsule(tk2, 0.046, 0.2, ivory, Vector3(0, 0.08, 0))
		_torus(tk2, 0.042, 0.065, gold, Vector3(0, 0.02, 0))
		var tk3 := _node(tk2, Vector3(0, 0.17, 0))
		tk3.rotation.x = 1.0
		_cyl(tk3, 0.0, 0.042, 0.15, ivory, Vector3(0, 0.07, 0))
	var t1 := _node(head, Vector3(0, -0.1, -0.18))
	t1.rotation.x = 0.15
	_cyl(t1, 0.06, 0.075, 0.2, fur, Vector3(0, -0.1, 0))
	_torus(t1, 0.055, 0.08, gold, Vector3(0, -0.12, 0))
	var t2 := _node(t1, Vector3(0, -0.2, 0))
	t2.rotation.x = 0.5
	_cyl(t2, 0.045, 0.06, 0.17, fur, Vector3(0, -0.085, 0))
	var t3 := _node(t2, Vector3(0, -0.17, 0))
	t3.rotation.x = 0.8
	_cyl(t3, 0.035, 0.045, 0.1, fur, Vector3(0, -0.05, 0))
	_sphere(t3, 0.04, fur_d, Vector3(0, -0.1, 0))
	_wiggle(t1, Vector3(1, 0, 0.3), 0.12, 2.4, 0.15)
	_wiggle(t2, Vector3(1, 0, 0), 0.18, 2.4, 0.2, 0.6)
	var tail := _node(torso, Vector3(0, 0.55, 0.42))
	tail.rotation.x = 2.6
	_capsule(tail, 0.025, 0.18, fur_d, Vector3(0, 0.08, 0))
	_sphere(tail, 0.045, fur_d.darkened(0.2), Vector3(0, 0.18, 0))
	_wiggle(tail, Vector3(0, 0, 1), 0.3, 4.0)

## Abyss lord: an obsidian demon king hovering over a violet vortex — great ram horns, three burning eyes,
## an orbiting crown of runes, a cracked chest around a magenta heart, spiked pauldrons and shackled claws.
func _build_abyss() -> void:
	hover = 0.1
	var obs := Color("33284a")
	var obs_l := Color("4d3d6e")
	var bone := Color("efe2c6")
	var core := Color("ff4fd8")
	var violet := Color("9a6bff")
	var vortex := _node(torso, Vector3(0, 0.04, 0))
	var vt := _torus(vortex, 0.22, 0.36, obs.darkened(0.3), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.25, 1))
	vt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 4:
		var a := TAU * i / 4.0
		_glow_box(vortex, Vector3(0.22, 0.012, 0.04), violet, 1.6, Vector3(cos(a) * 0.27, 0.03, sin(a) * 0.27), Vector3(0, -a + 0.6, 0))
	_spin(vortex, 2.5)
	_cyl(torso, 0.26, 0.09, 0.36, obs, Vector3(0, 0.24, 0))   # smoke-robe tail
	for i in 8:
		var a := TAU * i / 8.0
		_cyl(torso, 0.0, 0.05, 0.12, obs.darkened(0.2), Vector3(cos(a) * 0.12, 0.08, sin(a) * 0.12), Vector3(PI + sin(a) * 0.4, 0, cos(a) * 0.4))
	_sphere(torso, 0.3, Color("5a1f3a"), Vector3(0, 0.55, 0.17), Vector3(1.15, 1.25, 0.35))   # tattered cape
	_sphere(torso, 0.3, obs, Vector3(0, 0.56, 0), Vector3(1.15, 0.95, 0.85))
	_torus(torso, 0.22, 0.26, _team_col(), Vector3(0, 0.38, 0), Vector3.ZERO, Vector3(1.05, 1.3, 0.9))   # sash
	_glow(torso, 0.085, core, 2.2, Vector3(0, 0.56, -0.235))
	_glow(torso, 0.13, Color(core.r, core.g, core.b, 0.35), 1.0, Vector3(0, 0.56, -0.22))
	for sx in [-1.0, 1.0]:
		for i in 3:   # rib bones around the heart
			_capsule(torso, 0.018, 0.14, bone, Vector3(sx * 0.12, 0.64 - i * 0.07, -0.22), Vector3(0, sx * 0.4, PI * 0.5))
		_glow_box(torso, Vector3(0.015, 0.16, 0.01), core, 1.8, Vector3(sx * 0.2, 0.5, -0.2), Vector3(0, sx * 0.5, sx * 0.5))   # cracks
		_sphere(torso, 0.15, obs_l, Vector3(sx * 0.33, 0.73, 0), Vector3(1.1, 0.8, 1))   # pauldrons
		for i in 3:
			_cyl(torso, 0.0, 0.035, 0.15, bone, Vector3(sx * (0.28 + i * 0.06), 0.84 - i * 0.02, -0.04 + i * 0.04), Vector3(0, 0, -sx * (0.2 + i * 0.3)))
	head = _node(torso, Vector3(0, 0.88, -0.04))
	_sphere(head, 0.15, obs_l, Vector3.ZERO, Vector3(1, 1.05, 1))
	_box(head, Vector3(0.19, 0.07, 0.13), obs, Vector3(0, -0.12, -0.06))   # jaw
	for i in 4:
		_cyl(head, 0.0, 0.016, 0.05, bone, Vector3(-0.06 + i * 0.04, -0.075, -0.125))
	_glow(head, 0.028, core, 2.4, Vector3(-0.06, 0.02, -0.13), Vector3(1.3, 0.7, 0.5))
	_glow(head, 0.028, core, 2.4, Vector3(0.06, 0.02, -0.13), Vector3(1.3, 0.7, 0.5))
	_glow(head, 0.022, violet, 2.4, Vector3(0, 0.09, -0.135), Vector3(0.7, 1.2, 0.5))
	_brows(head, 0.06, 0.06, -0.14, Color("1a1028"), 0.08, 0.02)
	for sx in [-1.0, 1.0]:
		var h1 := _node(head, Vector3(sx * 0.12, 0.09, 0.0))
		h1.rotation.z = -sx * 1.0
		_capsule(h1, 0.055, 0.24, bone, Vector3(0, 0.1, 0))
		var h2 := _node(h1, Vector3(0, 0.21, 0))
		h2.rotation = Vector3(-0.5, 0, sx * 1.1)
		_capsule(h2, 0.045, 0.2, bone.darkened(0.08), Vector3(0, 0.08, 0))
		var h3 := _node(h2, Vector3(0, 0.17, 0))
		h3.rotation = Vector3(-0.4, 0, sx * 0.9)
		_cyl(h3, 0.0, 0.04, 0.14, bone.darkened(0.15), Vector3(0, 0.06, 0))
	var crown := _node(head, Vector3(0, 0.3, 0.02))
	for i in 5:
		var a := TAU * i / 5.0
		_glow_box(crown, Vector3(0.05, 0.08, 0.02), violet, 2.0, Vector3(cos(a) * 0.2, sin(a * 2.0) * 0.015, sin(a) * 0.2), Vector3(0, -a, 0.785))
	_spin(crown, 1.4)
	var halo := _torus(head, 0.25, 0.27, violet, Vector3(0, 0.12, 0.13), Vector3(PI * 0.5, 0, 0))
	halo.material_override = _glow_mat(violet, 1.5)
	arm_l = _node(torso, Vector3(-0.38, 0.72, 0))
	arm_r = _node(torso, Vector3(0.38, 0.72, 0))
	for arm in [arm_l, arm_r]:
		var sx := -1.0 if arm == arm_l else 1.0
		_capsule(arm, 0.075, 0.34, obs_l, Vector3(sx * 0.03, -0.15, 0), Vector3(0, 0, sx * 0.2))
		_sphere(arm, 0.1, obs, Vector3(sx * 0.06, -0.34, 0))
		_torus(arm, 0.075, 0.11, Color("8a8f9e"), Vector3(sx * 0.05, -0.26, 0), Vector3.ZERO, Vector3(1, 1.4, 1))   # shackle
		_torus(arm, 0.03, 0.05, Color("8a8f9e"), Vector3(sx * 0.1, -0.33, 0.07), Vector3(PI * 0.5, 0, 0))   # broken chain
		for i in 3:
			_cyl(arm, 0.0, 0.025, 0.12, bone, Vector3(sx * 0.06 + (i - 1) * 0.05, -0.44, -0.05), Vector3(-2.7, 0, 0))   # claws
	weapon = _node(arm_r, Vector3(0.06, -0.34, 0))

# ------------------------------------------------------------------ animation
func _process(delta: float) -> void:
	_t += delta
	var breath := sin(_t * 5.0 + _phase) * 0.035 * (1.0 - walk)
	var hop := absf(sin(_t * 12.0 + _phase)) * walk
	hop_offset = hop * 0.11
	var land := (1.0 - hop) * walk * 0.12
	var sy := (1.0 + breath - land + hop * 0.06) * _squash_v.y
	var sx := (1.0 - breath * 0.6 + land * 0.8) * _squash_v.x
	emphasis = lerpf(emphasis, emphasis_target, 1.0 - exp(-delta * 16.0))
	squash.scale = Vector3(sx, sy, sx) * emphasis
	squash.position.y = hop_offset
	var hk := _hit_k * _hit_amp
	squash.rotation.x = -walk * 0.18 - attack_lean + _hit_dir.y * hk * 0.42
	squash.rotation.z = sin(_t * 6.0 + _phase) * 0.06 * walk - _hit_dir.x * hk * 0.42
	# flinch: knocked back off the feet a touch, plus a quick decaying jitter
	var jit := sin(_t * 90.0) * 0.035 * hk
	squash.position.x = _hit_dir.x * hk * 0.07 + jit
	squash.position.z = _hit_dir.y * hk * 0.07
	if leg_l:
		leg_l.rotation.x = sin(_t * 12.0 + _phase) * 0.7 * walk
		leg_r.rotation.x = -sin(_t * 12.0 + _phase) * 0.7 * walk
	if arm_l and not _arm_busy:
		arm_l.rotation.x = -sin(_t * 12.0 + _phase) * 0.6 * walk + sin(_t * 5.0 + _phase) * 0.05
		arm_r.rotation.x = sin(_t * 12.0 + _phase) * 0.6 * walk - sin(_t * 5.0 + _phase) * 0.05
		if hk > 0.001:   # arms jerk up in front, guarding
			arm_l.rotation.x -= hk * 1.0
			arm_r.rotation.x -= hk * 1.0
	for i in quad_legs.size():
		var sgn := 1.0 if i == 0 or i == 3 else -1.0
		quad_legs[i].rotation.x = sin(_t * 12.0 + _phase) * 0.65 * walk * sgn
	for w in _wiggles:
		var a: float = sin(_t * w["f"] + _phase + w["p"]) * (w["a"] + w["wa"] * walk)
		(w["n"] as Node3D).rotation = w["base"] + (w["axis"] as Vector3) * a
	for sp in _spins:
		(sp["n"] as Node3D).rotation.y += delta * sp["v"]
	if hover > 0.0:
		squash.position.y += hover + sin(_t * 3.2 + _phase) * 0.035

var _arm_busy := false

## Squash impulse: goes to (sx, sy) then springs back with overshoot.
func punch_scale(sx: float, sy: float, dur := 0.35) -> void:
	if _sq_tween:
		_sq_tween.kill()
	_squash_v = Vector2(sx, sy)
	_sq_tween = create_tween()
	_sq_tween.tween_property(self, "_squash_v", Vector2.ONE, dur).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

## Attack animation. Returns seconds until the impact frame.
func play_attack(style: String) -> float:
	if arm_r == null:
		return _play_bounce()
	_arm_busy = true
	var tw := create_tween()
	var wind := 0.13
	var strike := 0.06
	match style:
		"melee":
			tw.set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3(-2.6, 0, 0.3), wind).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", -0.3, wind)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3(0.9, 0, -0.2), strike).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
			tw.tween_property(self, "attack_lean", 0.45, strike)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3.ZERO, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"arrow":
			tw.set_parallel(true)
			tw.tween_property(arm_l, "rotation", Vector3(-1.5, 0, 0), wind)
			tw.tween_property(arm_r, "rotation", Vector3(-1.3, 0, 0.6), wind)
			tw.tween_property(self, "attack_lean", -0.25, wind)
			tw.chain().set_parallel(true)
			tw.tween_property(self, "attack_lean", -0.1, strike)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_l, "rotation", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(arm_r, "rotation", Vector3.ZERO, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", 0.0, 0.25)
		"fireball":
			wind = 0.2
			tw.set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3(-3.0, 0, 0.2), wind).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", -0.35, wind)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3(-1.2, 0, 0), strike)
			tw.tween_property(self, "attack_lean", 0.3, strike)
			tw.chain().set_parallel(true)
			tw.tween_property(arm_r, "rotation", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(self, "attack_lean", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		"spin":
			wind = 0.12
			tw.tween_property(squash, "rotation:y", -0.6, wind).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(squash, "rotation:y", TAU, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_callback(func(): squash.rotation.y = 0.0)
			strike = 0.05
	tw.chain().tween_callback(func(): _arm_busy = false)
	if style != "spin":
		punch_scale(0.9, 1.12, 0.4)
	return wind + strike

## Hit reaction: snap away from the blow (world-space `away`), then sway back upright with a small overshoot.
## strength 1 = ordinary flinch, >1 knockback stagger, <1 the barely-there rock of a heavy body. A weaker hit
## never cuts short a stronger flinch still in progress.
func play_hit(away: Vector3, strength := 1.0) -> void:
	if _hit_k * _hit_amp > strength:
		return
	var local := Vector3.BACK
	if away.length() > 0.001:
		local = (global_transform.basis.orthonormalized().inverse() * away)
	var d := Vector2(local.x, local.z)
	_hit_dir = d.normalized() if d.length() > 0.001 else Vector2(0, 1)
	_hit_amp = strength
	if _hit_tween:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(self, "_hit_k", 1.0, 0.05).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_interval(0.06 * strength)
	_hit_tween.tween_property(self, "_hit_k", 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if strength > 1.0:   # knockback: a harder squash on top of the hit punch
		punch_scale(1.32, 0.68, 0.42)

## Limbless body slam (slime / hydra): crouch, lunge forward, spring back.
func _play_bounce() -> float:
	var tw := create_tween()
	tw.tween_property(self, "attack_lean", -0.35, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "attack_lean", 0.55, 0.06).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "attack_lean", 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	punch_scale(1.25, 0.7, 0.2)
	return 0.2

func flash(col := Color(1, 1, 1), energy := 1.4, dur := 0.12) -> void:
	if _flash_tween:
		_flash_tween.kill()
	_flash_col = col
	_set_flash(energy)
	_flash_tween = create_tween()
	_flash_tween.tween_method(_set_flash, energy, 0.0, dur)

var _flash_col := Color(1, 1, 1)
var _flash_v := 0.0
## Persistent status tint (frozen / slowed / guard) added under the hit flash.
var tint := Color(0, 0, 0):
	set(v):
		if v == tint:
			return
		tint = v
		if _flash_v <= 0.001 and not _ghost:
			for m in mats:
				m.emission = tint

func _set_flash(v: float) -> void:
	_flash_v = v
	if _ghost:
		return
	for m in mats:
		m.emission = tint + _flash_col * v

var _ghost := false

# ------------------------------------------------------------------ hover / drag emphasis
const OUTLINE_SHADER := preload("res://scripts/outline.gdshader")
var emphasis := 1.0
var emphasis_target := 1.0
var _outline_mat: ShaderMaterial

## Outline + scale-up highlight. col.a == 0 removes it.
func set_highlight(col: Color, scale_k := 1.15, width := 2.5, energy := 1.8) -> void:
	if col.a <= 0.0:
		emphasis_target = 1.0
		for m in mats:
			m.next_pass = null
		return
	if _outline_mat == null:
		_outline_mat = ShaderMaterial.new()
		_outline_mat.shader = OUTLINE_SHADER
	_outline_mat.set_shader_parameter("color", col)
	_outline_mat.set_shader_parameter("width_px", width)
	_outline_mat.set_shader_parameter("energy", energy)
	emphasis_target = scale_k
	for m in mats:
		m.next_pass = _outline_mat

func set_ghost(on: bool) -> void:
	_ghost = on
	for m in mats:
		if on:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color.a = 0.35
			m.emission = Color(0.25, 0.3, 0.45)
		else:
			m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			m.albedo_color.a = 1.0
			m.emission = Color(0, 0, 0)
