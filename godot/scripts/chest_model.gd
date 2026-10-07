class_name ChestModel
extends Node3D
## Chunky toy treasure chest (rounded wood body, thick domed lid, metal bands, big oval gem lock).
## Recolourable by gacha tier (일반 orange wood / 희귀 blue / 영웅 purple / 전설 gold) and able to flash white.
## The node origin is the chest's bottom centre, so scaling it squashes onto the ground.
## Used on the march road (field pickup) and on the chest gacha screen.

## Per tier: body, lid, trim (bands / rims), gem.
const PALETTE := [
	[Color("e07a32"), Color("f08c3c"), Color("8c4424"), Color("ff4fd8")],
	[Color("2f86f0"), Color("4a9cff"), Color("e8eefa"), Color("6ff4ff")],
	[Color("9658ec"), Color("a96cff"), Color("ffb84a"), Color("ff4f9a")],
	[Color("ffc22e"), Color("ffd24a"), Color("ff7a1e"), Color("ff2f5a")],
]

var lid: Node3D      # hinge at the back top edge; rotation.x < 0 opens it
var inner: Node3D    # golden glow inside, shown when the lid opens
var tier := 0
var _mats := {}      # part -> StandardMaterial3D
var _gem_light: OmniLight3D

func _init(t := 0) -> void:
	for part in ["body", "lid", "trim", "gem", "dark"]:
		_mats[part] = Mats.toy(Color.WHITE)
	_mats["gem"].roughness = 0.2
	_mats["gem"].metallic_specular = 0.9
	_mats["trim"].roughness = 0.35
	_mats["trim"].metallic_specular = 0.7
	_build()
	set_tier(t)

func _mi(parent: Node3D, mesh: Mesh, part: String, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = _mats[part]
	m.position = pos
	m.scale = scl
	parent.add_child(m)
	return m

func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 16
	s.rings = 8
	return s

func _build() -> void:
	# body
	_mi(self, MarchProps.rbox_mesh(Vector3(1.04, 0.12, 0.72), 0.35), "dark", Vector3(0, 0.06, 0))
	_mi(self, MarchProps.rbox_mesh(Vector3(1.0, 0.54, 0.68), 0.28), "body", Vector3(0, 0.33, 0))
	_mi(self, MarchProps.rbox_mesh(Vector3(1.06, 0.08, 0.74), 0.4), "trim", Vector3(0, 0.58, 0))       # rim under the lid
	for x in [-0.31, 0.31]:
		_mi(self, MarchProps.rbox_mesh(Vector3(0.13, 0.56, 0.73), 0.3), "trim", Vector3(x, 0.33, 0))    # bands
	for x in [-0.5, 0.5]:
		for z in [-0.34, 0.34]:
			_mi(self, _sph(0.055), "trim", Vector3(x * 0.98, 0.14, z * 0.98))               # foot rivets
	# gem lock on the front
	_mi(self, MarchProps.rbox_mesh(Vector3(0.36, 0.36, 0.1), 0.45), "trim", Vector3(0, 0.36, 0.35))
	_mi(self, _sph(0.125), "gem", Vector3(0, 0.36, 0.4), Vector3(1.0, 1.18, 0.55))
	_mi(self, _sph(0.035), "dark", Vector3(-0.04, 0.42, 0.46)).material_override = MarchProps.glow_mat(Color.WHITE, 1.0)
	# lid on a back hinge
	lid = Node3D.new()
	lid.position = Vector3(0, 0.6, -0.34)
	add_child(lid)
	_mi(lid, MarchProps.rbox_mesh(Vector3(1.0, 0.2, 0.68), 0.35), "lid", Vector3(0, 0.1, 0.34))
	_mi(lid, MarchProps.rbox_mesh(Vector3(0.98, 0.3, 0.66), 0.75), "lid", Vector3(0, 0.2, 0.34))            # dome
	for x in [-0.31, 0.31]:
		_mi(lid, MarchProps.rbox_mesh(Vector3(0.14, 0.34, 0.7), 0.6), "trim", Vector3(x, 0.19, 0.34))
	_mi(lid, MarchProps.rbox_mesh(Vector3(0.22, 0.14, 0.08), 0.5), "trim", Vector3(0, 0.06, 0.7))          # latch tongue
	# inner glow (hidden until opened)
	inner = Node3D.new()
	inner.position = Vector3(0, 0.6, 0)
	inner.visible = false
	add_child(inner)
	var g := MeshInstance3D.new()
	g.mesh = MarchProps.rbox_mesh(Vector3(0.84, 0.06, 0.52), 0.4)
	g.material_override = MarchProps.glow_mat(Color("fff2a0"), 1.6)
	inner.add_child(g)
	_gem_light = OmniLight3D.new()
	_gem_light.position = Vector3(0, 0.45, 0.75)
	_gem_light.omni_range = 1.4
	_gem_light.light_energy = 0.6
	add_child(_gem_light)

func set_tier(t: int) -> void:
	tier = clampi(t, 0, PALETTE.size() - 1)
	var p: Array = PALETTE[tier]
	_mats["body"].albedo_color = p[0]
	_mats["lid"].albedo_color = p[1]
	_mats["trim"].albedo_color = p[2]
	_mats["gem"].albedo_color = p[3]
	_mats["dark"].albedo_color = (p[0] as Color).darkened(0.45)
	_gem_light.light_color = p[3]
	set_flash(0.0)

## 0 = normal, 1 = solid white (upgrade flash). Gem keeps a little glow of its own.
func set_flash(k: float) -> void:
	for part in _mats:
		var m: StandardMaterial3D = _mats[part]
		m.emission = Color(1, 1, 1) * k + (Color(m.albedo_color) * 0.35 if part == "gem" else Color.BLACK)
