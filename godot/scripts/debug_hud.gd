class_name DebugHud
extends Node
## Small debug menu on the battle screen (left edge, under the hero status column).
## Tap the tiny "DBG" pill to fold out a column of quick buttons. Add new debug actions to ACTIONS
## and handle them in _run().

const ACTIONS := [
	{"id": "loot_fly", "text": "아이템 획득 연출"},
]
const BTN := Vector2(56, 30)
const ITEM := Vector2(190, 46)

var hud: Hud
var game: Node
var btn: Panel
var _menu: Control

func build(y: float) -> void:
	btn = hud.panel(Color(0.1, 0.08, 0.2, 0.5), Rect2(Vector2.ZERO, BTN), 15, 0)
	btn.add_theme_stylebox_override("panel", UiTheme.capsule(15))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	hud.root.add_child(hud.place(btn, Vector2(0, 0), Vector2(16, y), BTN))
	var l := hud.label("DBG", 15, Color("8ff0ff"), 5)
	l.size = BTN
	btn.add_child(l)
	btn.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			Sfx.play("click", -8.0, 1.4)
			hud.bump(btn, 1.1)
			toggle())

func is_open() -> bool:
	return _menu != null and is_instance_valid(_menu)

func toggle() -> void:
	if is_open():
		_menu.queue_free()
		_menu = null
		return
	var h := 10.0 + ACTIONS.size() * (ITEM.y + 6.0)
	_menu = hud.panel(Color(0.1, 0.08, 0.2, 0.85), Rect2(0, 0, ITEM.x + 16, h), 14, 0)
	_menu.add_theme_stylebox_override("panel", hud.box(Color(0.08, 0.06, 0.16, 0.88), 14, 3, Color("3a2f66")))
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	var base := btn.get_global_rect()
	hud.root.add_child(hud.place(_menu, Vector2(0, 0), Vector2(16, base.position.y + BTN.y + 6), Vector2(ITEM.x + 16, h)))
	for i in ACTIONS.size():
		var a: Dictionary = ACTIONS[i]
		var b := hud.juicy_button(a["text"], Color("4c467b"), Rect2(8, 8 + i * (ITEM.y + 6.0), ITEM.x, ITEM.y), 20)
		var id: String = a["id"]
		b.pressed.connect(func(): _run(id))
		_menu.add_child(b)
	hud.pop_in(_menu, 0.6, 0.2)

func _run(id: String) -> void:
	match id:
		"loot_fly":
			_loot_fly()

## A random gear item drops on the field in front of the heroes (Diablo-style drop + name plate),
## then flies into the bag like a group-clear pickup.
func _loot_fly() -> void:
	var hs: Array = game.alive_heroes()
	var c := Vector3.ZERO
	for h in hs:
		c += h.global_position
	c = c / maxf(1.0, hs.size())
	var at := Vector3(c.x + randf_range(-0.8, 0.8), 0, c.z - 2.6 + randf_range(-0.3, 0.3))
	var e: Dictionary = Inventory.make("equip", Inventory.random_item_key(maxi(1, game.wave + randi_range(0, 30))))
	game._give(e, at)
	print("[Debug] loot drop ", e["key"], " -> bag")
	game.get_tree().create_timer(1.3).timeout.connect(func():
		if is_instance_valid(game) and game.phase != 4:   # not on the game-over screen
			game._collect_loot())
