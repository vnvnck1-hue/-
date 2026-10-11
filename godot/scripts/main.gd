extends Node3D
## Trio Chess flow: PLACEMENT -> SPAWNING -> BATTLE -> TRANSITION -> (PLACEMENT | GAMEOVER).
## Owns run state, waves, rewards and board input. Rules follow docs/html_game_spec.md.

enum P { PLACEMENT, SPAWNING, BATTLE, TRANSITION, GAMEOVER }

const WAVE_HEAL := 50
const SPAWN_GAP := 0.17
const SPAWN_SETTLE := 0.42
const SUBWAVE_DELAY := 0.8
const TRANSITION_DELAY := 0.7
const EXP_PER_KILL := 25

var phase := P.PLACEMENT
var world: World
var cam: CameraRig
var hud: Hud
var sfx: Sfx
var units_root: Node3D
var fx_root: Node3D

var heroes: Array[Actor] = []
var enemies: Array[Actor] = []
var dead_order: Array[Actor] = []
var wave := 1
var sub_wave := 0
var sub_waves := 1
var gimmick := ""
var gold := 0
var now := 0.0
var perks: Array = []
var inventory: Array = []
var chests: Array = []        # unopened treasure chests on the bag badge (their starting tier, ChestLoot)
var inv_cap := Defs.MAX_INVENTORY
var relic_tempo := 0
var coins: Array = []
var revive_used := {}
var tutorial := 0
var _sub_pending := false
var _last_start := -10.0
var _returning := false
var _phase_t := 0.0
var _info_paused := false   # this side froze the field for an open item / hero card

# input
var press_hero: Actor
var press_pos := Vector2.ZERO
var press_t := 0.0
var dragging := false
var selected: Actor

# automation
var autoplay := false
var shots_dir := ""
var quit_after := 0.0
var _shot_n := 0
var _clock := 0.0
var chatter: Chatter
var test_mode := ""
var force_gimmick := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	for a in OS.get_cmdline_user_args():
		if a == "--autoplay":
			autoplay = true
		elif a.begins_with("--shots="):
			shots_dir = a.substr(8)
		elif a.begins_with("--seed="):
			seed(int(a.substr(7)))
		elif a.begins_with("--quit="):
			quit_after = float(a.substr(7))
		elif a.begins_with("--wave="):
			wave = int(a.substr(7))
		elif a.begins_with("--test="):
			test_mode = a.substr(7)
		elif a.begins_with("--gimmick="):
			force_gimmick = a.substr(10)
	if autoplay or test_mode != "" or shots_dir != "":
		Meta.path = "user://trio_save_test.json"
	Meta.load_save()
	Actor.BOARD_X = 2.95
	Actor.BOARD_Z = 3.95
	Actor.clamp_fn = Callable()
	sfx = Sfx.new()
	add_child(sfx)
	Music.play(music_track())
	world = _make_world()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.build()
	cam = CameraRig.new()
	add_child(cam)
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.setup(CAM_POS, CAM_LOOK, 30.0)
	cam.current = true
	units_root = Node3D.new()
	units_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(units_root)
	fx_root = Node3D.new()
	fx_root.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx_root)
	Vfx.root = fx_root
	Vfx.cam = cam
	hud = Hud.new()
	hud.game = self
	add_child(hud)
	hud.cam = cam
	chatter = Chatter.new()   # little speech bubbles over heroes & monsters (under every popup)
	chatter.cam = cam
	chatter.font = hud.font
	chatter.provider = _chatter_list
	chatter.quiet = func() -> bool: return is_instance_valid(hud.overlay)
	hud.root.add_child(chatter)
	hud.root.move_child(chatter, 0)
	hud.fight_pressed.connect(start_battle)
	var start_wave := wave
	start_run(true)
	if start_wave > 1:
		wave = start_wave
		hud.set_wave(wave, 0, 1)
	if test_mode != "":
		_run_test()

const CAM_POS := Vector3(0, 16.0, 9.4)
const CAM_LOOK := Vector3(0, 0, 0.55)

## Mode id for records (Meta.best).
func mode_id() -> String:
	return "classic"

## BGM for this mode (Music.TRACKS key).
func music_track() -> String:
	return "battle"

## Mode hook: the 3D stage (March mode swaps in its endless road).
func _make_world() -> World:
	return World.new()

## Game-over subtitle (mode hook).
func gameover_text() -> String:
	return "웨이브 %d 도달" % wave

## Extra game-over line (mode hook; March mode tells how many perks were lost).
func gameover_note() -> String:
	return ""

## Game-over primary button: label and action (March mode resumes from the region's first group).
func retry_label() -> String:
	return "다시 시작"

func retry() -> void:
	start_run()

## Gear drag stage (until the gear is dropped): near-freeze slow motion, the camera eases in so all three
## heroes fill the screen as drop targets, and — like an ultimate — the stage goes dark while every hero gets
## its own key light and a soft white outline; letterbox bars name the item being dragged.
const SLOWMO := 0.03
const DRAG_DIM := 0.62
const DRAG_LAYER := 1 << 10   # render layer 11: hero meshes lit by the drag key lights only
const DRAG_OUTLINE := Color(1.0, 1.0, 1.0, 0.85)
var drag_stage := false
var _drag_lights: Array = []
var _drag_tw: Tween

func set_slowmo(on: bool, e := {}) -> void:
	cam.base_scale = SLOWMO if on else 1.0
	if not cam.in_hitstop():
		Engine.time_scale = cam.base_scale
	cam.group_focus(alive_heroes() if on else [], on)
	_drag_stage(on, e)

func _drag_stage(on: bool, e := {}) -> void:
	if on == drag_stage:
		return
	drag_stage = on
	if _drag_tw and _drag_tw.is_valid():
		_drag_tw.kill()
	_drag_tw = create_tween().set_ignore_time_scale(true).set_parallel(true)
	_drag_tw.tween_method(world.set_drag_dim, world.dim_drag, DRAG_DIM if on else 0.0, 0.2 if on else 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for l in _drag_lights:
		if is_instance_valid(l):
			l.get_parent().remove_child(l)
			l.queue_free()
	_drag_lights.clear()
	for h in heroes:
		var lit: bool = on and h.alive
		_set_layer_bit(h, DRAG_LAYER, lit)
		if h != _focused:
			h.model.set_highlight(DRAG_OUTLINE if lit else Color(0, 0, 0, 0), 1.06, 2.0, 1.2)
		if lit:
			var l := OmniLight3D.new()
			l.light_cull_mask = DRAG_LAYER   # only the heroes catch this light, the dark stage stays dark
			l.light_color = Color(1.0, 0.96, 0.86)
			l.light_energy = 0.0
			l.omni_range = 2.3
			l.omni_attenuation = 0.7
			h.add_child(l)
			l.position = Vector3(0.25, 1.4, 0.9)
			_drag_tw.tween_property(l, "light_energy", 2.2, 0.2)
			_drag_lights.append(l)
			h.model.punch_scale(1.1, 0.92, 0.2)
	hud.drag_spot(on)
	if on:
		var nm: String = Inventory.name_of(e) if not e.is_empty() else "장비"
		var col: Color = Defs.RARITY_COL[Inventory.rarity_of(e)] if not e.is_empty() else Defs.COL_GOLD
		hud.cinema_bars(true, nm, "장착할 영웅에게 끌어다 놓으세요", col, false)
		Sfx.play("whoosh", -9.0, 0.8)
	else:
		hud.cinema_bars(false, "", "", Color.WHITE)

## Whether gear can be equipped right now (March mode: any time).
func can_equip() -> bool:
	return can_edit()

## Leave the run and go back to the mode select lobby.
func go_lobby() -> void:
	Actor.clamp_fn = Callable()
	Skills.cancel(self)
	Cinematic.reset(self)
	cam.base_scale = 1.0
	cam.group_focus([], false)
	_drag_stage(false)
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/Lobby.tscn")

## Scripted checks for screenshots: --test=panel | aim | items | perks | merchant | talents
func _run_test() -> void:
	await get_tree().create_timer(1.0).timeout
	match test_mode:
		"fx":
			var rt := func(t: float) -> Signal: return get_tree().create_timer(t, true, false, true).timeout
			_update_hover(hero("warrior"))
			_shot_later(0.35, "fx_hover")
			await rt.call(0.7)
			_update_hover(null)
			set_drag_target(hero("mage"))
			_shot_later(0.35, "fx_dragtarget")
			await rt.call(0.7)
			set_drag_target(null)
			for k in ["revive", "massKill"]:
				Inventory.add(self, Inventory.make("special", k))
			Inventory.add(self, Inventory.make("equip", "stormFist"))
			hud.refresh_inventory()
			hud.panels._show_tip(inventory[2], false)
			_shot_later(0.3, "fx_tip_legend")
			await rt.call(0.6)
			hud.panels._show_tip(inventory[0], false)
			_shot_later(0.3, "fx_tip_special")
			await rt.call(0.6)
			hud.panels._close_tip()
			start_battle()
			await rt.call(1.4)
			for e in enemies:
				e.max_hp = 99999.0
				e.hp = 99999.0
			var keys := ["sword2", "royalDecree", "ring3", "thunderHeart"]
			for i in keys.size():
				var src: Actor = enemies[i % enemies.size()]
				_give(Inventory.make("equip", keys[i]), src.global_position)
			_give(Inventory.make("relic", "vampireChalice"), enemies[0].global_position)
			await rt.call(1.5)
			_shot_later(0.0, "fx_loot_field")
			hero("ranger").mana = Defs.MAX_MANA
			await rt.call(0.06)
			_shot_later(0.0, "fx_active_hitstop")
			await rt.call(1.2)
			var w := hero("warrior")
			w.ult_ready_at = 0.0
			Skills.cast_ultimate(self, w, Vector3.ZERO)
			await rt.call(0.5)
			_shot_later(0.0, "fx_ult_intro")
			await rt.call(0.75)
			_shot_later(0.0, "fx_ult_hold")
			await rt.call(1.6)
			var m := hero("mage")
			m.ult_ready_at = 0.0
			Skills.cast_ultimate(self, m, Vector3.ZERO)
			await rt.call(0.45)
			_shot_later(0.0, "fx_ult_intro_mage")
			await rt.call(0.7)
			_shot_later(0.0, "fx_ult_hold_mage")
			await rt.call(1.4)
			for e in alive_enemies():
				e.hp = 1.0
				on_enemy_killed(e, hero("warrior"))
			await rt.call(1.55)
			_shot_later(0.0, "fx_loot_fly")
			await rt.call(1.4)
			_shot_later(0.0, "fx_after")
		"tutorial":
			tut_moved = {}
			_tutorial_set(1)
			_shot_later(0.4, "tut1")
			await get_tree().create_timer(0.8).timeout
			for h in heroes:
				tutorial_event("moved", h)
			_shot_later(0.3, "tut2")
			await get_tree().create_timer(0.8).timeout
			start_battle()
			while phase != P.PLACEMENT:
				await get_tree().process_frame
			await get_tree().create_timer(0.6).timeout
			_shot_later(0.0, "tut3")
			await get_tree().create_timer(0.3).timeout
			_select(hero("warrior"))
			upgrade_skill(hero("warrior"), 0)
			_shot_later(0.4, "tut4")
			await get_tree().create_timer(0.8).timeout
			start_battle()
			await get_tree().create_timer(1.5).timeout
			Skills.cast_ultimate(self, hero("mage"), Vector3.ZERO)
			while phase != P.PLACEMENT:
				await get_tree().process_frame
			await get_tree().create_timer(0.6).timeout
			_shot_later(0.0, "tut5")
			await get_tree().create_timer(0.3).timeout
			equip_item(hero("ranger"), inventory[0])
			_shot_later(0.4, "tut_done")
		"talents":
			Meta.crystals = maxi(Meta.crystals, 40)
			for id in ["root", "startGold", "allAtk", "warAtk"]:
				while Meta.can_buy(id) == "":
					Meta.buy(id)
			hud.set_crystals(Meta.crystals)
			hud.open_talents()
			_shot_later(0.6, "test_talents")
		"perks":
			gold = 1200
			hud.set_gold(gold)
			hud.open_perks()
			_shot_later(0.7, "test_perks")
		"gameover":
			hud.show_gameover(wave)
			_shot_later(1.2, "test_gameover")
		"ribbon":
			hud.ribbon_banner("WAVE CLEAR!", "웨이브 1 돌파", UiTheme.ORANGE, 2.0)
			_shot_later(0.5, "test_ribbon")
		"gimmick":
			start_battle()
			_shot_later(1.8, "test_gimmick_a")
			_shot_later(3.2, "test_gimmick_b")
			_shot_later(4.6, "test_gimmick_c")
		"items":
			gold = 2500
			for k in ["sword1", "sword1", "sword1", "helmet2", "ring3", "bow4", "staff2", "amulet1", "shield3"]:
				Inventory.add(self, Inventory.make("equip", k))
			Inventory.add(self, Inventory.make("equip", "thunderHeart"))
			Inventory.add(self, Inventory.make("relic", "luckyCompass"))
			Inventory.add(self, Inventory.make_skillbook())
			Inventory.add(self, Inventory.make("special", "revive"))
			Inventory.add(self, Inventory.make("special", "crown"))
			hud.refresh_inventory()
			var w := hero("warrior")
			equip_item(w, inventory[0])
			_select(w)
			await get_tree().create_timer(0.5).timeout
			hud.show_tip(inventory[1])
			_shot_later(0.3, "test_items")
			await get_tree().create_timer(0.8).timeout
			hud.close_tip()
			wave = 11
			hud.open_merchant()
			_shot_later(0.5, "test_merchant")
		"merge":   # loot flies in first, then merges play one by one (sword1, ring2 -> ring3 chain, helmet1)
			inventory.clear()
			for k in ["sword1", "sword1", "ring3", "amulet2"]:
				inventory.append(Inventory.make("equip", k))
			hud.refresh_inventory()
			var c := hero("ranger").global_position
			var drops := ["sword1", "ring2", "helmet1", "ring2", "helmet1", "ring2", "ring3", "helmet1"]
			for i in drops.size():
				_give(Inventory.make("equip", drops[i]), c + Vector3(-1.2 + 0.35 * i, 0, 1.0 + 0.2 * (i % 2)))
			await get_tree().create_timer(0.4).timeout
			var t0 := _clock
			_collect_loot()
			for i in 14:
				_shot_later(0.9 + i * 0.22, "merge_%02d" % i)
			await get_tree().create_timer(7.0).timeout
			print("[Merge] after=", inventory.map(func(x): return x["key"]), " t=", snappedf(_clock - t0, 0.1))
		"gear":   # grade ladder: 영웅~초월★ icons, grade tooltip, era-scaled unique, pair-aware merchant
			gold = 30000
			wave = 45
			inventory.clear()   # the test save may carry legendary relics from earlier runs
			for k in ["sword4", "axe5", "bow6", "staff7", "shield8", "helmet9", "ring11", "amulet6", "amulet6", "ring1", "ring1"]:
				Inventory.add(self, Inventory.make("equip", k))
			Inventory.add(self, Inventory.make_found("soulReaper", wave))
			Inventory.add(self, Inventory.make("equip", "ring1"))   # completes ring1 x3 -> 고급
			hud.refresh_inventory()
			print("[Gear] bag=", inventory.map(func(x): return "%s(%s)" % [x["key"], Inventory.rarity_of(x)]))
			print("[Gear] helmet9=", Defs.item("helmet9"), " sword12=", Defs.item("sword12"))
			await get_tree().create_timer(0.5).timeout
			hud.show_tip(inventory.filter(func(x): return x["key"] == "helmet9")[0])
			_shot_later(0.3, "test_gear_tip")
			await get_tree().create_timer(0.8).timeout
			hud.close_tip()
			hud.show_tip(inventory.filter(func(x): return x["key"] == "soulReaper")[0])
			_shot_later(0.3, "test_gear_unique")
			await get_tree().create_timer(0.8).timeout
			hud.close_tip()
			hud.open_merchant()
			print("[Gear] merchant=", hud.merchant_stock().map(func(x): return "%s %dG" % [x["entry"]["key"], x["price"]]))
			_shot_later(0.5, "test_gear_merchant")
		"panel":
			var h := hero("warrior")
			h.sp = 3
			grant_exp(h, 60)
			upgrade_skill(h, 0)
			_select(h)
			_shot_later(0.4, "test_panel")
		"aim":
			start_battle()
			await get_tree().create_timer(1.6).timeout
			for e in enemies:
				e.max_hp = 99999.0
				e.hp = 99999.0
			await get_tree().create_timer(1.2).timeout
			for cls in ["ranger", "mage", "warrior"]:
				var h := hero(cls)
				h.ult_ready_at = 0.0
				Skills.hold_hero = h
				Skills._enter_aim(self)
				var e := nearest_enemy(h.global_position)
				if e:
					Skills.aim_point = e.global_position
					Skills._update_preview(self)
				await get_tree().create_timer(0.3, true, false, true).timeout
				_shot_later(0.0, "test_aim_" + cls)
				await get_tree().create_timer(0.3, true, false, true).timeout
				Skills.end_hold(self, cam.unproject_position(Skills.aim_point))
				await get_tree().create_timer(0.5).timeout
				_shot_later(0.0, "test_ult_" + cls)
				await get_tree().create_timer(0.8).timeout
			for h in alive_heroes():
				h.mana = Defs.MAX_MANA
			await get_tree().create_timer(0.35).timeout
			_shot_later(0.0, "test_active")

# ---------------------------------------------------------------- run
func start_run(first := false) -> void:
	get_tree().paused = false
	cam.base_scale = 1.0
	cam.group_focus([], false)
	_drag_stage(false)
	Engine.time_scale = 1.0
	hud.close_overlays()
	for u in heroes + enemies:
		hud.unregister_unit(u)
		u.queue_free()
	for c in coins:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	heroes.clear()
	enemies.clear()
	coins.clear()
	_discard_loot()
	hovered = null
	drag_target = null
	_focused = null
	_focus_light = null
	if world:
		world.set_focus_dim(0.0)
	dead_order.clear()
	wave = 1
	sub_wave = 0
	gimmick = ""
	now = 0.0
	perks = []
	inventory = []
	chests = []
	inv_cap = Defs.MAX_INVENTORY
	relic_tempo = 0
	revive_used = {}
	hud.refresh_perks()
	gold = int(Stats.g(Meta.fx(""), "startGold"))
	for k in Meta.relics:
		inventory.append(Inventory.make("relic", k))
	if Meta.has_flag("emergencySupply"):
		inventory.append(Inventory.make("equip", Defs.FAMILIES[randi() % Defs.FAMILIES.size()] + "1"))
	var i := 0
	for cls in Defs.HERO_ORDER:
		var h := _spawn(Defs.TEAM_HERO, cls, Defs.HERO_START[cls])
		h.home = Defs.HERO_START[cls]
		h.drop_in(1.6, 0.12 * i)
		i += 1
	hud.set_gold(gold, false)
	hud.set_crystals(Meta.crystals, false)
	hud.refresh_inventory()
	hud.panels.refresh_chests()
	tut_moved = {}
	tut_pending3 = false
	tut_pending5 = false
	enter_placement()
	_tutorial_set(1 if first and not Meta.tutorial_done and not autoplay and test_mode == "" else 0)

func enter_placement() -> void:
	phase = P.PLACEMENT
	_phase_t = 0.0
	gimmick = ""
	world.deploy_glow = 1.0
	hud.set_wave(wave, 0, Defs.sub_wave_count(wave))
	hud.set_enemy_count(0)
	hud.set_gimmick("", "")
	hud.set_phase("영웅을 끌어 배치하고 전투를 시작하세요!" if wave == 1 else "배치를 정비하고 다음 웨이브에 대비하세요!")
	hud.set_fight(true)
	hud.banner("WAVE %d" % wave, Color.WHITE, 0.5, 104, -160)
	_shot_later(1.0, "placement")

func start_battle() -> void:
	if phase != P.PLACEMENT or _returning or hud.has_overlay():
		return
	if _clock - _last_start < 0.6:
		return
	if not tutorial_allows("fight"):
		return
	_last_start = _clock
	var tut_list := _tutorial_wave()
	tutorial_event("fight")
	_end_drag(true)
	_select(null)
	relic_tempo = 0
	for h in alive_heroes():
		h.home = World.pos_to_tile(h.position)
	sub_waves = Defs.sub_wave_count(wave)
	sub_wave = 0
	gimmick = force_gimmick if force_gimmick != "" else Waves.pick_gimmick(wave)
	if not tut_list.is_empty():
		gimmick = ""
	var list: Array
	if not tut_list.is_empty():
		list = tut_list
	elif gimmick != "":
		list = Waves.gimmick(gimmick)
		var info: Dictionary = Waves.GIMMICK_INFO[gimmick]
		hud.set_gimmick(info["title"], info["hint"])
		if UiTheme.tt():
			hud.warn_band(info["title"])
			_shot_later(0.45, "warn_band")
	else:
		list = Waves.normal(wave)
	world.deploy_glow = 0.0
	world.clear_highlights()
	hud.set_fight(false)
	hud.set_phase("")
	_spawn_sequence(list, true)

func _spawn_sequence(list: Array, first: bool) -> void:
	phase = P.SPAWNING
	var mult := Defs.scaling(wave)
	for i in list.size():
		var s: Dictionary = list[i]
		get_tree().create_timer(SPAWN_GAP * i).timeout.connect(func():
			if phase != P.SPAWNING:
				return
			var e := _spawn(Defs.TEAM_ENEMY, s["kind"], s["tile"], mult)
			e.drop_in(2.2)
			hud.set_enemy_count(alive_enemies().size()))
	var total := SPAWN_GAP * maxi(list.size() - 1, 0) + SPAWN_SETTLE
	await get_tree().create_timer(total).timeout
	if phase != P.SPAWNING:
		return
	phase = P.BATTLE
	_phase_t = 0.0
	_sub_pending = false
	hud.set_wave(wave, sub_wave, sub_waves)
	if first:
		hud.banner("FIGHT!", Defs.COL_GOLD, 0.35, 140)
		hud.flash(0.3, 0.25)
		Vfx.clash_flash(Vector3(0, 0, 0.5))
		cam.add_trauma(0.3)
		cam.kick_fov(-2.5)
		Sfx.play("clash", -4.0)
	else:
		hud.banner("%d차 웨이브!" % (sub_wave + 1), Color("ffb070"), 0.4, 96)
		Sfx.play("clash", -8.0, 1.2)
	_shot_later(1.2, "battle_a")
	_shot_later(3.0, "battle_b")

func spawn_enemy_at(kind: String, pos: Vector3, mult: float) -> Actor:
	var u := Actor.new()
	units_root.add_child(u)
	u.setup(kind, Defs.TEAM_ENEMY, self, mult)
	u.position = Vector3(pos.x, 0, pos.z)
	enemies.append(u)
	hud.register_unit(u)
	return u

# ---------------------------------------------------------------- run perks (spec §7.1)
## The draw keeps the original odds (3 cards); the roulette lands on one of them at random.
func generate_perks() -> Array:
	var pool: Array = Defs.PERKS.keys().filter(func(k): return not perks.has(k))
	var by := func(r: String) -> Array: return pool.filter(func(k): return Defs.PERKS[k]["rarity"] == r)
	var out := []
	if randf() < 0.03:
		var leg: Array = by.call("legendary")
		if not leg.is_empty():
			out.append(leg[randi() % leg.size()])
	while out.size() < 3:
		var rare := randf() < 0.25
		var cands: Array = by.call("rare" if rare else "common").filter(func(k): return not out.has(k))
		if cands.is_empty():
			cands = pool.filter(func(k): return not out.has(k))
		if cands.is_empty():
			break
		out.append(cands[randi() % cands.size()])
	var order := {"legendary": 0, "rare": 1, "common": 2}
	out.sort_custom(func(a, b): return order[Defs.PERKS[a]["rarity"]] < order[Defs.PERKS[b]["rarity"]])
	return out

func choose_perk(id: String) -> void:
	perks.append(id)
	var hpm: float = Defs.PERKS[id]["fx"].get("hpMult", 0.0)
	for h in alive_heroes():
		if hpm > 0.0:
			var add := floorf(h.def["hp"] * hpm)
			h.max_hp += add
			h.hp += add
		Vfx.upgrade_pillar(h.global_position)
		h.model.punch_scale(1.3, 0.75, 0.4)
	Sfx.play("chime", -4.0, 1.1)
	hud.refresh_perks(true)   # the roulette card itself announces the result

## Team wiped out: every run perk is lost (max HP bonuses are taken back too). Returns how many were lost.
func clear_perks() -> int:
	var n := perks.size()
	for id in perks:
		var hpm: float = Defs.PERKS[id]["fx"].get("hpMult", 0.0)
		if hpm > 0.0:
			for h in heroes:
				h.max_hp = maxf(1.0, h.max_hp - floorf(h.def["hp"] * hpm))
				h.hp = minf(h.hp, h.max_hp)
	perks = []
	hud.refresh_perks()
	return n

func _spawn(team: int, kind: String, tile: Vector2i, mult := 1.0) -> Actor:
	var u := Actor.new()
	units_root.add_child(u)
	u.setup(kind, team, self, mult)
	var p := World.tile_pos(tile.x, tile.y)
	if u.def.get("size", 1) > 1:
		p += Vector3(0.5, 0, -0.5)
	u.position = p
	if kind == "illusion":
		u.is_illusion = true
	if team == Defs.TEAM_HERO:
		heroes.append(u)
	else:
		enemies.append(u)
	hud.register_unit(u)
	return u

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	_clock += delta / maxf(Engine.time_scale, 0.001)
	_phase_t += delta
	if quit_after > 0.0 and _clock > quit_after:
		Music.quit()
	_info_pause_tick()
	match phase:
		P.PLACEMENT:
			if autoplay and _phase_t > 1.6 and not hud.has_overlay():
				start_battle()
		P.BATTLE:
			Skills.update_hold(self)
			if not get_tree().paused:
				now += delta
				_battle_tick(delta)
				if autoplay:
					_auto_ult()

## Reading an item card or a hero card freezes the field where it stands. Other pausers (chest, map, shop,
## skill aim, ult intro) keep working underneath: on close the pause goes back to whoever still needs it.
func _info_pause_tick() -> void:
	if hud.panels.info_open() and _info_pause_phase():
		_info_paused = true
		if not get_tree().paused:
			get_tree().paused = true
	elif _info_paused and (not hud.has_overlay() or phase == P.GAMEOVER):
		_info_paused = false
		if phase != P.GAMEOVER:
			get_tree().paused = Cinematic.active or Skills.aiming

## Phases where the field runs on its own clock (placement just waits for the player).
func _info_pause_phase() -> bool:
	return phase == P.SPAWNING or phase == P.BATTLE

func _battle_tick(delta: float) -> void:
	if gimmick_tick():
		return
	if alive_heroes().is_empty():
		game_over()
		return
	if alive_enemies().is_empty() and not _sub_pending and gimmick != "hydra":
		if sub_wave + 1 < sub_waves:
			_sub_pending = true
			sub_wave += 1
			await get_tree().create_timer(SUBWAVE_DELAY, false).timeout
			if phase == P.BATTLE:
				_spawn_sequence(Waves.normal(wave), false)
		else:
			finish_wave()
		return
	for h in alive_heroes():
		if h.mana >= Defs.MAX_MANA and not h.busy:
			Skills.cast_active(self, h)
	for u in all_alive():
		u.battle_tick(delta)
	hud.set_enemy_count(alive_enemies().size())

## Gimmick-specific per-tick logic. Returns true when the wave was resolved this tick.
func gimmick_tick() -> bool:
	if gimmick != "hydra":
		return false
	var hydras := enemies.filter(func(e): return e.kind == "hydra")
	if hydras.is_empty():
		return false
	if hydras.all(func(e): return not e.alive):
		for e in hydras:
			_drop_coin(e.global_position, 40)
			e.corpse = false
			e._vanish()
		hud.banner("히드라 클리어!", Color("8fe36a"), 0.6, 96)
		finish_wave()
		return true
	for e in hydras:
		if not e.alive and now - e.dead_at >= 2.0:
			e.revive(1.0)
	return false

## Gimmick movement (ninja leap, sprinter dash). Returns true if it handled movement this tick.
func special_move(a: Actor, _delta: float) -> bool:
	return Specials.move(self, a)

# ---------------------------------------------------------------- wave end
func finish_wave() -> void:
	if phase == P.TRANSITION or phase == P.GAMEOVER:
		return
	Skills.cancel(self)
	Cinematic.reset(self)
	phase = P.TRANSITION
	_returning = true
	var cleared := wave
	print("[Trio] clear wave=", wave, " gimmick=", gimmick, " gold=", gold, " lv=", heroes.map(func(x): return x.level), " inv=", inventory.size(), " perks=", perks.size())
	gimmick = ""
	hud.set_gimmick("", "")
	Engine.time_scale = cam.base_scale
	if UiTheme.tt():
		hud.ribbon_banner("WAVE CLEAR!", "웨이브 %d 돌파" % cleared, UiTheme.ORANGE, 0.9)
	else:
		hud.banner("WAVE CLEAR!", Color("8fe36a"), 0.7, 100)
	Sfx.play("chime", -4.0)
	Meta.add_crystals(2)
	hud.set_crystals(Meta.crystals)
	hud.toast("시간의 결정 +2", Defs.COL_CRYSTAL)
	for h in alive_heroes():
		_victory_hop(h)
	_collect_coins()
	var loot_t := _collect_loot()
	if cleared == 40:
		hud.banner("☕ 커피 획득!", Color("ffd27a"), 2.4, 110, 140)
	_shot_later(0.4, "wave_clear")
	await get_tree().create_timer(TRANSITION_DELAY + 0.5).timeout
	for e in enemies:
		hud.unregister_unit(e)
		e.queue_free()
	enemies.clear()
	var heal := WAVE_HEAL + Stats.g(Stats.perk_fx(self), "waveHealBonus")
	var k := 0
	for h in alive_heroes():
		h.reset_status()
		h.heal(heal, true)
		var dest := World.tile_pos(h.home.x, h.home.y)
		get_tree().create_timer(0.06 * k).timeout.connect(func(): h.hop_to(dest, 0.42, 0.9))
		k += 1
	await get_tree().create_timer(maxf(0.6 + 0.06 * k, loot_t - TRANSITION_DELAY - 0.5)).timeout
	_returning = false
	wave = cleared + 1
	if cleared >= 10 and cleared % 10 == 0 and hud.open_merchant():
		await hud.overlay_closed
	if cleared >= 3 and cleared % 3 == 0 and hud.open_perks():
		await hud.overlay_closed
	if phase == P.TRANSITION:
		enter_placement()
		tutorial_event("wave_end")

func _victory_hop(u: Actor) -> void:
	var tw := u.create_tween()
	for i in 2:
		tw.tween_property(u.model, "position:y", 0.45, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(u.model, "position:y", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func(): u.model.punch_scale(1.25, 0.75, 0.3))
	tw.parallel().tween_property(u.model, "rotation:y", 0.0, 0.3)

func game_over() -> void:
	if phase == P.GAMEOVER:
		return
	Skills.cancel(self)
	Cinematic.reset(self)
	print("[Trio] GAME OVER wave=", wave)
	phase = P.GAMEOVER
	Meta.record_best(mode_id(), wave)
	_discard_loot()
	cam.base_scale = 1.0
	cam.group_focus([], false)
	_drag_stage(false)
	Engine.time_scale = 1.0
	get_tree().paused = false
	hud.set_fight(false)
	Sfx.play("sad", -4.0)
	Music.duck(-18.0, 1.2, 2.5)   # minor-key jingle clashes with the C-major loop
	hud.show_gameover(wave)
	_shot_later(0.9, "gameover")
	if autoplay:
		await get_tree().create_timer(3.0).timeout
		if autoplay and phase == P.GAMEOVER and quit_after <= 0.0:
			retry()

# ---------------------------------------------------------------- kills, rewards
func on_enemy_killed(e: Actor, killer: Actor) -> void:
	if not e.alive:
		return
	e.corpse = e.kind == "hydra"
	e.dead_at = now
	e.die()
	cam.add_trauma(0.08)
	if e.kind == "illusionist":
		hud.callout(e.global_position + Vector3(0, 1.4, 0), "환술사 처치!", Color("c9b8ff"))
	if e.kind == "splitter":
		Specials.split(self, e)
	for h in alive_heroes():
		if Stats.has_effect(h, "killMana"):
			h.mana = Defs.MAX_MANA
	var pf := Stats.perk_fx(self)
	if e.kind != "hydra":
		var amount := Defs.gold_base(e.kind) + int(floorf(wave / 5.0)) * 5
		_drop_coin(e.global_position, int(floorf(amount * (1.0 + Stats.g(pf, "goldMult")))))
		if killer and killer.cls == "ranger":
			var rg := Stats.g(Stats.talent_fx(killer), "rangerGoldBonus")
			if rg > 0.0:
				_drop_coin(e.global_position + Vector3(0.2, 0, 0.1), maxi(1, int(floorf(10 * rg))))
		if killer and killer.is_hero():
			grant_exp(killer, int(floorf(EXP_PER_KILL * (1.0 + Stats.g(pf, "expMult")))))
		if randf() < 0.05 + Stats.g(pf, "crystalDropBonus"):
			Meta.add_crystals(1)
			hud.set_crystals(Meta.crystals)
			hud.float_text(e.global_position + Vector3(0, 1.3, 0), "+1 결정", Defs.COL_CRYSTAL)
	_roll_drops(e, pf)

func _roll_drops(e: Actor, pf: Dictionary) -> void:
	var at := e.global_position
	if e.kind != "hydra":
		if wave >= 20 and randf() < 0.03:
			_give(Inventory.make_skillbook(), at)
		if wave >= 20 and randf() < 0.04:
			_give(Inventory.make("special", "inventoryExpand"), at)
		if wave >= 15:
			var r := randf()
			if r < 0.003:
				_give(Inventory.make("relic", Inventory.random_relic("legendary")), at)
			elif r < 0.013:
				_give(Inventory.make("relic", Inventory.random_relic("rare")), at)
	# Gear drop window (Gear): boss-role enemies roll one grade higher; a mid-boss (giant) always drops
	# GIANT_DROPS jackpot pieces — the region's "graduation" loot that seeds the next region's base grade.
	var role := Defs.role(e.kind)
	var jackpot := role == "boss" or role == "giant"
	var n := GIANT_DROPS if role == "giant" else (1 if randf() < Defs.DROP_RATES.get(role, 0.2) + Stats.g(pf, "dropBonus") + Gear.drop_bonus(wave) else 0)
	for i in n:
		var k := Inventory.random_item_key(wave, self, jackpot)
		_give(Inventory.make_found(k, wave), at + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)) * float(mini(i, 1)))

const GIANT_DROPS := 2

## Drops land on the field first (Diablo style) and fly into the bag when the wave ends.
var field_loot: Array = []   # [{entry, node}]
var _loot_in_flight := 0
var _loot_pending := 0      # collected items not yet in the bag: merges wait until every one has landed
var _merging := false       # the sequential merge show is playing

func _give(entry: Dictionary, at: Vector3) -> void:
	var col: Color = Defs.RARITY_COL[Inventory.rarity_of(entry)]
	var node := Vfx.loot_drop(at, col, Inventory.tier_of(entry))
	field_loot.append({"entry": entry, "node": node})
	hud.add_loot_tag(node, Inventory.name_of(entry), Inventory.rarity_of(entry))

## Fly every field item into the bag. Returns the time the flights take.
func _collect_loot() -> float:
	var list := field_loot.duplicate()
	field_loot.clear()
	_loot_pending += list.size()
	var i := 0
	for l in list:
		var n: Node3D = l["node"]
		var e: Dictionary = l["entry"]
		var d := 0.35 + 0.14 * i
		i += 1
		get_tree().create_timer(d).timeout.connect(func():
			if not is_instance_valid(n):
				Inventory.add(self, e)
				_loot_landed()
				return
			var lift := n.create_tween().set_parallel(true)
			lift.tween_property(n, "global_position:y", n.global_position.y + 0.6, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			lift.tween_property(n, "scale", Vector3.ONE * 0.2, 0.18)
			var sp := cam.unproject_position(n.global_position + Vector3(0, 0.4, 0))
			Vfx.sparks(n.global_position + Vector3(0, 0.3, 0), Hud._vivid(Defs.RARITY_COL[Inventory.rarity_of(e)]), 8, 2.0, 0.4, "star5", 0.12)
			hud.remove_loot_tag(n)
			lift.chain().tween_callback(n.queue_free)
			var slot_off := _loot_in_flight
			_loot_in_flight += 1
			hud.fly_item(sp, e, func():
				_loot_in_flight -= 1
				var res := Inventory.add(self, e)
				if res.begins_with("sold:"):
					hud.toast("가방이 가득 차서 판매 +%sG" % res.substr(5), Defs.COL_GOLD)
					hud.set_gold(gold)
				hud.refresh_inventory(e["id"])
				_loot_landed(), slot_off))
	return 0.35 + 0.14 * list.size() + 0.75 if not list.is_empty() else 0.0

func _discard_loot() -> void:
	for l in field_loot:
		if is_instance_valid(l["node"]):
			hud.remove_loot_tag(l["node"])
			l["node"].queue_free()
	field_loot.clear()

func _loot_landed() -> void:
	_loot_pending = maxi(0, _loot_pending - 1)
	if _loot_pending == 0:
		get_tree().create_timer(0.25, true, false, true).timeout.connect(queue_merges)   # a beat after the last item lands

## Called by Inventory.settle after any bag / equipment change. Merges are staged one by one in the bag
## (HudPanels.play_merge); while loot is still flying in they wait, so the bag fills first, then merges.
func queue_merges() -> void:
	if _loot_pending > 0 or _merging or not is_inside_tree():
		return
	if Inventory.find_merge(self) == "":
		return
	_play_merges()

func _play_merges() -> void:
	_merging = true
	var chain := 0
	while is_inside_tree():
		var k := Inventory.find_merge(self)
		if k == "":
			break
		if test_mode != "":
			print("[MergeShow] t=", snappedf(_clock, 0.01), " ", k, " pending=", _loot_pending)
		await hud.panels.play_merge(k, chain)
		chain += 1
	_merging = false

func on_merged(names: Array) -> void:
	for n in names:
		hud.toast("합성! %s" % n, Color("ffd27a"))
	Sfx.play("chime", -5.0, 1.3)
	hud.refresh_inventory()

func _drop_coin(pos: Vector3, amount: int) -> void:
	var node := Vfx.coin(pos)
	coins.append({"node": node, "amount": amount})

func _collect_coins() -> void:
	var list := coins.duplicate()
	coins.clear()
	var i := 0
	for c in list:
		var n: Node3D = c["node"]
		var amount: int = c["amount"]
		if not is_instance_valid(n):
			gold += amount
			continue
		var d := 0.25 + 0.03 * i
		i += 1
		get_tree().create_timer(d).timeout.connect(func():
			if not is_instance_valid(n):
				return
			var sp := cam.unproject_position(n.global_position)
			n.queue_free()
			hud.fly_coin(sp, func():
				gold += amount
				hud.set_gold(gold)))
	hud.set_gold(gold)

func grant_exp(h: Actor, amount: int) -> void:
	h.exp += amount
	var leveled := false
	while h.exp >= h.level * 40:
		h.exp -= h.level * 40
		h.level += 1
		h.max_hp += 15
		h.atk += 8
		h.hp = minf(h.hp + 30, h.max_hp)
		if h.level % 2 == 0:
			h.sp += 1
		leveled = true
	for slot in h.skillbooks:
		var b: Dictionary = h.skillbooks[slot]
		b["exp"] += amount
		while b["level"] < Defs.SKILLBOOK_MAX and b["exp"] >= Defs.skillbook_exp_need(b["level"]):
			b["exp"] -= Defs.skillbook_exp_need(b["level"])
			b["level"] += 1
	if leveled:
		Vfx.upgrade_pillar(h.global_position)
		h.model.punch_scale(1.4, 0.65, 0.5)
		h.model.flash(Color(1, 0.9, 0.4), 1.4, 0.35)
		hud.callout(h.global_position + Vector3(0, 1.5, 0), "LEVEL UP!", Defs.COL_GOLD)
		Sfx.play("chime", -6.0, 1.1)

func on_hero_down(h: Actor) -> void:
	if not h.alive:
		return
	if h.cls == "warrior" and Meta.has_flag("warFinal") and not revive_used.get("warFinal", false):
		revive_used["warFinal"] = true
		h.hp = maxf(1.0, floorf(h.max_hp * 0.5))
		_revive_fx(h, "영원의 방패!")
		return
	if Meta.has_flag("secondChance") and not revive_used.get("secondChance", false):
		revive_used["secondChance"] = true
		h.hp = maxf(1.0, floorf(h.max_hp * 0.3))
		_revive_fx(h, "두 번째 기회!")
		return
	h.die()
	dead_order.append(h)
	cam.add_trauma(0.3)
	hud.callout(h.global_position + Vector3(0, 1.4, 0), "%s 쓰러짐!" % h.def["name"], Color("ff8a9a"))
	if alive_heroes().size() == 1 and not revive_used.get("tip", false):
		revive_used["tip"] = true
		hud.toast("상인에게서 부활의 깃털을 얻어 동료를 되살리세요!", Color("ffd27a"))

func _revive_fx(h: Actor, text: String) -> void:
	Vfx.upgrade_pillar(h.global_position)
	h.model.flash(Color(1, 0.95, 0.6), 1.8, 0.5)
	hud.callout(h.global_position + Vector3(0, 1.5, 0), text, Defs.COL_GOLD)
	Sfx.play("chime", -4.0, 0.9)

## Revive the earliest fallen hero next to its death spot (revive feather).
func revive_fallen() -> bool:
	if dead_order.is_empty():
		return false
	var h: Actor = dead_order.pop_front()
	h.reset_status()
	if not in_battle():
		var t := h.home
		var occ := _hero_on_tile(t, h)
		if occ:
			for c in 6:
				for r in 4:
					if _hero_on_tile(Vector2i(c, r), h) == null:
						t = Vector2i(c, r)
		h.home = t
		h.position = World.tile_pos(t.x, t.y)
	h.revive(1.0)
	return true

# ---------------------------------------------------------------- items
func sell_item(e: Dictionary) -> void:
	if not inventory.has(e):
		return
	if not tutorial_allows("item"):
		return
	var price := Inventory.sell_price(self, e)
	inventory.erase(e)
	gold += price
	if e["kind"] == "relic":
		Inventory.save_relics(self)
	hud.set_gold(gold)
	hud.refresh_inventory()
	hud.toast("+%dG" % price, Defs.COL_GOLD)
	Sfx.play("tick", -4.0, 1.4)
	tutorial_event("item")

func discard_item(e: Dictionary) -> void:
	inventory.erase(e)
	hud.refresh_inventory()

func equip_item(h: Actor, e: Dictionary) -> bool:
	if not inventory.has(e) or not h.alive:
		return false
	if not Defs.item(e.get("key", "")).has("slot") or not (e["kind"] == "equip" or e["kind"] == "special"):
		hud.toast("장착할 수 없는 아이템이에요")
		return false
	if not can_equip():
		hud.toast("전투 중에는 장착할 수 없어요!")
		return false
	if not tutorial_allows("item"):
		return false
	Inventory.equip(self, h, e)
	h.model.punch_scale(1.3, 0.75, 0.4)
	h.model.flash(Color(1, 1, 1), 1.2, 0.25)
	Vfx.item_drop(h.global_position, Defs.RARITY_COL[Inventory.rarity_of(e)])
	hud.callout(h.global_position + Vector3(0, 1.4, 0), Inventory.name_of(e), Defs.RARITY_COL[Inventory.rarity_of(e)])
	hud.refresh_inventory()
	if selected == h or hud.hero_shown() == h:
		hud.show_hero_panel(h)
	tutorial_event("item")
	return true

func use_item(e: Dictionary) -> void:
	if not inventory.has(e):
		return
	if not tutorial_allows("item"):
		return
	if e["kind"] == "skillbook":
		e["revealed"] = true
		hud.refresh_inventory()
		hud.skillbook_choice(e)
		return
	if e["kind"] != "special":
		return
	match e["key"]:
		"revive":
			if dead_order.is_empty():
				hud.toast("쓰러진 동료가 없어요")
				return
			revive_fallen()
		"fullHeal":
			for h in alive_heroes():
				h.heal(h.max_hp, true)
			Sfx.play("chime", -5.0, 1.4)
		"skillPoint":
			for h in alive_heroes():
				h.sp += 1
				Vfx.upgrade_pillar(h.global_position)
			Sfx.play("chime", -5.0, 1.0)
		"massKill":
			if phase != P.BATTLE:
				hud.toast("전투 중에만 쓸 수 있어요")
				return
			hud.flash(0.6, 0.35)
			cam.add_trauma(0.5)
			Sfx.play("boom", -2.0, 0.6)
			for en in enemies:
				if en.alive:
					Vfx.lightning(en.global_position + Vector3(0, 6, 0), en.global_position + Vector3(0, 0.4, 0), 0.14)
					en.corpse = false
					en.die()
		"inventoryExpand":
			inv_cap += 3
			Sfx.play("chime", -5.0, 0.9)
		_:
			return
	inventory.erase(e)
	hud.refresh_inventory()
	hud.toast(Defs.SPECIAL[e["key"]]["name"] + " 사용!", Color("8fe36a"))
	if selected:
		hud.show_hero_panel(selected)
	tutorial_event("item")

func replace_skill_with_book(e: Dictionary, slot: int) -> void:
	var h := hero(e["cls"])
	if h == null:
		return
	h.skillbooks[slot] = {"id": e["skill"], "level": 1, "exp": 0}
	h.skills[slot] = 0
	inventory.erase(e)
	hud.refresh_inventory()
	Vfx.upgrade_pillar(h.global_position)
	hud.callout(h.global_position + Vector3(0, 1.5, 0), Inventory.skillbook_def(e)["name"], Color("e08aff"))
	Sfx.play("chime", -4.0, 0.8)
	if selected == h:
		hud.show_hero_panel(h)

## Merchant stock (spec §5.4). Each: {entry, price}.
func merchant_items() -> Array:
	var w := maxi(1, wave - 1)
	var out := []
	var pairs := Gear.pair_keys(self, w)
	if not pairs.is_empty():   # the merchant always carries the third copy of one pair you hold
		var pk: String = pairs[randi() % pairs.size()]
		out.append({"entry": Inventory.make("equip", pk), "price": Gear.buy_price(Gear.grade_of_key(pk))})
	while out.size() < 4:
		var r := randf()
		var e: Dictionary
		var price := 0
		if r < 0.015 and w >= 25:
			var k := Inventory.random_legendary(true)
			e = Inventory.make_found(k, w)
			price = int(Defs.LEGENDARY[k]["price"] * float(e.get("pw", 1.0)))
		elif r < 0.08:
			e = Inventory.make_found(Inventory.random_legendary(false), w)
			price = int(2000 * float(e.get("pw", 1.0)))
		elif r < 0.20:
			var keys := Defs.SPECIAL.keys()
			var sk: String = keys[randi() % keys.size()]
			e = Inventory.make("special", sk)
			if sk == "crown":
				Inventory.era_scale(e, w)
			price = int(Defs.SPECIAL[sk]["price"] * float(e.get("pw", 1.0)))
		else:
			# merchant stock rolls with the jackpot window (one grade above the field drops)
			var k2 := Inventory.random_item_key(w, null, true)
			e = Inventory.make_found(k2, w)
			if Defs.LEGENDARY.has(k2):
				price = int(Defs.LEGENDARY[k2].get("price", 2000) * float(e.get("pw", 1.0)))
			else:
				price = Gear.buy_price(Inventory.tier_of(e))
		out.append({"entry": e, "price": price})
	return out

func buy_merchant(i: int) -> bool:
	var stock: Array = hud.merchant_stock()
	if i >= stock.size() or stock[i] == null:
		return false
	var it: Dictionary = stock[i]
	if gold < it["price"]:
		hud.toast("골드가 부족해요!")
		return false
	if inventory.size() >= inv_cap:
		hud.toast("가방이 가득 찼어요!")
		return false
	gold -= it["price"]
	stock[i] = null
	Inventory.add(self, it["entry"])
	hud.set_gold(gold)
	hud.refresh_inventory(it["entry"]["id"])
	Sfx.play("chime", -5.0, 1.5)
	return true

# ---------------------------------------------------------------- treasure chests (ChestLoot rules, ChestGacha screen)
static var _chest_hinted := false   # "tap the badge" hint once per session
const CHEST_MUSIC_FADE := 1.8       # field <-> chest screen BGM crossfade (s)

## A chest joins the pile on the bag badge, flying there from screen point `from` (instant when from is INF).
func give_chest(t: int, from := Vector2.INF) -> void:
	var land := func() -> void:
		chests.append(t)
		hud.panels.refresh_chests(true)
		if not _chest_hinted:
			_chest_hinted = true
			hud.toast("보물상자 획득! 가방 왼쪽 위 상자를 눌러 열어 보세요", Color("ffd27a"))
	if from == Vector2.INF:
		land.call()
	else:
		hud.panels.fly_chest(from, t, land)

## Badge tap: the chest screen opens over a paused field; merges wait until it closes.
func open_chests() -> void:
	if chests.is_empty() or hud.has_overlay() or phase == P.GAMEOVER or Cinematic.active or Skills.aiming or drag_stage:
		return
	var was := get_tree().paused
	get_tree().paused = true
	_loot_pending += 1
	var g := ChestGacha.new()
	g.hud = hud
	g.game = self
	g.start(chest_take())
	Music.play("gacha", CHEST_MUSIC_FADE)   # the field track keeps its place and resumes there on close
	hud.overlay_closed.connect(func():
		if is_inside_tree():
			Music.play(music_track(), CHEST_MUSIC_FADE, true)
			if phase != P.GAMEOVER:
				get_tree().paused = was
			_loot_landed(), CONNECT_ONE_SHOT)
	_shot_later(0.5, "chest_open")

## Takes the next chest off the pile (its starting tier).
func chest_take() -> int:
	var t: int = chests.pop_front() if not chests.is_empty() else 0
	hud.panels.refresh_chests()
	return t

func chest_roll(t: int) -> Dictionary:
	return ChestLoot.roll(self, wave, t)

## Hands a chest's rewards over: items fly into the bag from the card positions (or drop straight in), gold too.
func chest_reward(r: Dictionary, from: Array) -> void:
	var items: Array = r.get("items", [])
	var g: int = r.get("gold", 0)
	if from.is_empty():
		for e in items:
			_chest_item_in(e)
		gold += g
		hud.set_gold(gold)
		return
	_loot_pending += items.size()
	for i in items.size():
		var e: Dictionary = items[i]
		var sp: Vector2 = from[i] if i < from.size() else hud.root.size * 0.5
		get_tree().create_timer(0.08 * i, true, false, true).timeout.connect(func():
			hud.fly_item(sp, e, func():
				_chest_item_in(e)
				_loot_landed(), i))
	var n := clampi(g / 25, 3, 8)
	var c := hud.root.size * 0.5 + Vector2(0, 280)
	for i in n:
		var share := g / n + (g % n if i == n - 1 else 0)
		get_tree().create_timer(0.05 * i, true, false, true).timeout.connect(func():
			hud.fly_coin(c + Vector2(randf_range(-60, 60), randf_range(-20, 20)), func():
				gold += share
				hud.set_gold(gold)))

func _chest_item_in(e: Dictionary) -> void:
	var res := Inventory.add(self, e)
	if res.begins_with("sold:"):
		hud.toast("가방이 가득 차서 판매 +%sG" % res.substr(5), Defs.COL_GOLD)
		hud.set_gold(gold)
	hud.refresh_inventory(e["id"])

# ---------------------------------------------------------------- skills & tutorial hooks
## Spend a skill point on passive slot i (spec §3.3). Vitality adds +20 max HP on top (original bug #2 fixed).
func upgrade_skill(h: Actor, i: int) -> bool:
	if not can_edit() or h.sp <= 0 or h.skills[i] >= Defs.SKILL_MAX or h.skillbooks.has(i):
		return false
	if not tutorial_allows("skill", h):
		return false
	h.sp -= 1
	h.skills[i] += 1
	if Defs.SKILLS[h.cls][i]["id"] == "vitality":
		h.max_hp += 20
		h.hp = minf(h.hp + 20, h.max_hp)
	h.model.punch_scale(1.3, 0.75, 0.4)
	h.model.flash(Color(1, 0.9, 0.4), 1.2, 0.3)
	Vfx.upgrade_pillar(h.global_position)
	Sfx.play("chime", -6.0, 1.2)
	tutorial_event("skill_up")
	return true

func on_ult_used(h: Actor) -> void:
	tutorial_event("ult", h)

# ---------------------------------------------------------------- tutorial (spec §8)
const TUTORIAL := {
	1: ["캐릭터 배치", "워리어, 레인저, 메이지를 각각 한 번씩 원하는 칸으로 옮겨 보세요!"],
	2: ["전투 시작", "반짝이는 [전투 시작!] 버튼을 눌러 보세요!"],
	3: ["스킬 업그레이드", "반짝이는 영웅을 눌러 상세 창을 열고, UP 버튼으로 스킬을 올려 보세요!"],
	4: ["궁극기 사용", "전투를 시작한 뒤 메이지를 길게 눌러 조준하고, 손을 떼서 궁극기를 써 보세요!"],
	5: ["아이템 장착 / 판매", "가방의 반짝이는 아이템을 영웅에게 끌어다 놓거나, 판매해 보세요!"],
}
var tut_moved := {}
var tut_pending3 := false
var tut_pending5 := false

func _tutorial_set(step: int) -> void:
	tutorial = step
	if step == 0:
		hud.set_tutorial(0, "", "")
	else:
		hud.set_tutorial(step, TUTORIAL[step][0], TUTORIAL[step][1] + (" (%d/3)" % tut_moved.size() if step == 1 else ""))

func tutorial_allows(action: String, h: Actor = null) -> bool:
	if tutorial == 0:
		return true
	var ok := false
	match action:
		"drag": ok = tutorial == 1
		"fight": ok = tutorial == 2 or tutorial == 4
		"select", "skill": ok = tutorial == 3
		"ult": ok = tutorial == 4 and h != null and h.cls == "mage"
		"item": ok = tutorial == 5
		"talent": ok = false
	if not ok:
		hud.nudge_tutorial()
	return ok

func tutorial_event(what: String, h: Actor = null) -> void:
	if tutorial == 0 and not tut_pending3 and not tut_pending5:
		return
	match what:
		"moved":
			if tutorial == 1 and h:
				tut_moved[h.cls] = true
				_tutorial_set(1)
				if tut_moved.size() >= mini(3, alive_heroes().size()):
					_tutorial_set(2)
		"fight":
			if tutorial == 2:
				tut_pending3 = true
				_tutorial_set(0)
		"skill_up":
			if tutorial == 3:
				_select(null)
				_tutorial_set(4)
		"ult":
			if tutorial == 4 and h and h.cls == "mage":
				tut_pending5 = true
				_tutorial_set(0)
				hud.toast("메이지 궁극기 사용 성공!", Color("9fe8ff"))
		"item":
			if tutorial == 5:
				_tutorial_set(0)
				Meta.tutorial_done = true
				Meta.save()
				hud.toast("튜토리얼 완료! 이제 마음껏 싸워 보세요", Color("8fe36a"))
		"wave_end":
			if tut_pending3:
				tut_pending3 = false
				for hh in alive_heroes():
					hh.sp = maxi(hh.sp, 1)
				if inventory.is_empty():
					Inventory.add(self, Inventory.make("equip", "sword1"))
					hud.refresh_inventory()
				_tutorial_set(3)
			elif tut_pending5:
				tut_pending5 = false
				if inventory.is_empty():
					Inventory.add(self, Inventory.make("equip", "sword1"))
					hud.refresh_inventory()
				_tutorial_set(5)

## Tutorial-only enemies for steps 2 and 4 (overrides gimmicks, fixing original edge case #20).
func _tutorial_wave() -> Array:
	if tutorial == 2 and wave == 1:
		return Waves.tutorial("tut_easy")
	if tutorial == 4:
		var m := hero("mage")
		if m:
			m.ult_ready_at = 0.0
		hud.toast("메이지 궁극기를 사용해 보세요!", Color("9fe8ff"))
		return Waves.tutorial("tut_tough")
	return []

## Autoplay: fire any ready ultimate at the densest spot.
func _auto_ult() -> void:
	if Skills.aiming or Cinematic.active or alive_enemies().is_empty():
		return
	for h in alive_heroes():
		if h.ult_ready_at <= now and not h.busy and randf() < 0.01:
			var e := nearest_enemy(h.global_position)
			Skills.cast_ultimate(self, h, e.global_position)
			return

# ---------------------------------------------------------------- queries
func alive_heroes() -> Array:
	return heroes.filter(func(u): return u.alive)

func alive_enemies() -> Array:
	return enemies.filter(func(u): return u.alive)

## Chatter feed: every living unit on the field with what it is doing right now.
func _chatter_list() -> Array:
	var out := []
	for u in units_root.get_children():
		if u is Actor and u.alive and u.visible:
			var h: float = u.def.get("bar_h", 1.05) * u.model.scale.y / Actor.MODEL_SCALE + u.model.position.y + 0.15
			out.append({"n": u, "key": u.kind, "ctx": chat_ctx(u), "h": h})
	return out

## What a unit would talk about (mode hook). "" keeps it quiet.
func chat_ctx(u: Actor) -> String:
	if phase == P.GAMEOVER or phase == P.TRANSITION or u.is_illusion and randf() < 0.5:
		return ""
	if in_battle() and (u.is_hero() or enemies.has(u)):
		return "low" if u.hp < u.max_hp * 0.3 else "battle"
	return "idle"

func all_alive() -> Array:
	return alive_heroes() + alive_enemies()

func hero_alive(cls: String) -> bool:
	for h in heroes:
		if h.cls == cls and h.alive:
			return true
	return false

func hero(cls: String) -> Actor:
	for h in heroes:
		if h.cls == cls:
			return h
	return null

func illusionist_alive() -> bool:
	for e in enemies:
		if e.kind == "illusionist" and e.alive:
			return true
	return false

func nearest_enemy(p: Vector3) -> Actor:
	var best: Actor = null
	var bd := INF
	for e in alive_enemies():
		var d := Actor._flat(e.global_position - p).length()
		if d < bd:
			bd = d
			best = e
	return best

func in_battle() -> bool:
	return phase == P.BATTLE

func is_placement() -> bool:
	return phase == P.PLACEMENT and not _returning

func can_edit() -> bool:
	return (phase == P.PLACEMENT or phase == P.TRANSITION) and not _returning

## Delayed call on the game clock (pauses with the battle).
func after(t: float, cb: Callable) -> void:
	get_tree().create_timer(t, false).timeout.connect(cb)

# ---------------------------------------------------------------- input
func _ray_plane(screen: Vector2, y: float) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	if absf(d.y) < 0.0001:
		return Vector3.INF
	var t := (y - o.y) / d.y
	return o + d * t

func hero_at_screen(sp: Vector2) -> Actor:
	var pb := _ray_plane(sp, 0.35)
	var best: Actor = null
	var bd := 0.6
	for h in alive_heroes():
		var d := Actor._flat(pb - h.global_position).length()
		if d < bd:
			bd = d
			best = h
	return best

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed:
		if ev.keycode == KEY_ESCAPE:
			if hud.has_overlay():
				if phase != P.GAMEOVER:
					hud.close_overlays()
			else:
				go_lobby()
		elif ev.keycode == KEY_SPACE and phase == P.PLACEMENT:
			start_battle()
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_press(ev.position)
		else:
			_release(ev.position)
	elif ev is InputEventMouseMotion:
		_motion(ev.position)

func _press(sp: Vector2) -> void:
	press_hero = hero_at_screen(sp)
	press_pos = sp
	press_t = _clock
	dragging = false
	if press_hero == null:
		if can_edit():
			_select(null)
		return
	if phase == P.BATTLE:
		Skills.begin_hold(self, press_hero)
		get_viewport().set_input_as_handled()

# ---------------------------------------------------------------- hover & drag-target focus
## Focused hero: thin neon-yellow outline + scale-up, the field dims a little and a key light
## isolates that hero. Dragging gear onto a hero uses the same look (red when equipping isn't allowed).
const NEON_YELLOW := Color(1.0, 1.0, 0.0)
const EQUIP_NO_COL := Color(1.0, 0.25, 0.25)
const FOCUS_DIM := 0.6
var hovered: Actor
var drag_target: Actor
var _focused: Actor
var _focus_light: OmniLight3D
var _focus_tw: Tween

func _clear_hl(h: Actor) -> void:
	if h and is_instance_valid(h):
		if drag_stage and h.is_hero() and h.alive:
			h.model.set_highlight(DRAG_OUTLINE, 1.06, 2.0, 1.2)   # back to the drag stage outline
		else:
			h.model.set_highlight(Color(0, 0, 0, 0))

func _update_hover(h: Actor) -> void:
	if h == hovered:
		return
	hovered = h
	_refresh_focus()

func set_drag_target(h: Actor) -> void:
	if h == drag_target:
		return
	drag_target = h
	_refresh_focus()

func _refresh_focus() -> void:
	var f: Actor = drag_target if drag_target else hovered
	if f and not is_instance_valid(f):
		f = null
	var is_drag := f != null and f == drag_target
	if f == _focused:
		if f:
			f.model.set_highlight(_focus_col(is_drag), 1.24 if is_drag else 1.16)
		return
	_clear_hl(_focused)
	# detach the key light before touching mesh layers (avoids stale light/geometry pairing)
	if _focus_light and is_instance_valid(_focus_light):
		_focus_light.get_parent().remove_child(_focus_light)
		_focus_light.queue_free()
	_focus_light = null
	_set_focus_layer(_focused, false)
	_focused = f
	if f:
		f.model.set_highlight(_focus_col(is_drag), 1.24 if is_drag else 1.16)
		f.model.punch_scale(1.12 if is_drag else 1.08, 0.92, 0.22)
		_set_focus_layer(f, true)   # layers first, then add the light
		_focus_light = OmniLight3D.new()
		_focus_light.light_cull_mask = FOCUS_LAYER   # lights only the focused hero, not the board
		_focus_light.light_color = Color(1.0, 0.97, 0.88)
		_focus_light.light_energy = 2.4
		_focus_light.omni_range = 1.9
		_focus_light.omni_attenuation = 0.8
		f.add_child(_focus_light)
		_focus_light.position = Vector3(0.2, 1.3, 0.7)
		Sfx.play("click", -10.0 if is_drag else -16.0, 1.5 if is_drag else 1.7)
	_tween_focus_dim(FOCUS_DIM if f else 0.0)

const FOCUS_LAYER := 1 << 9   # render layer 10, used only by the focused hero's meshes

## Put the hero's model meshes on/off the focus render layer so the key light touches only them.
func _set_focus_layer(h: Actor, on: bool) -> void:
	_set_layer_bit(h, FOCUS_LAYER, on)

func _set_layer_bit(h: Actor, bit: int, on: bool) -> void:
	if h == null or not is_instance_valid(h):
		return
	var stack: Array[Node] = [h.model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.layers = (mi.layers | bit) if on else (mi.layers & ~bit)
		stack.append_array(n.get_children())

func _focus_col(is_drag: bool) -> Color:
	return EQUIP_NO_COL if is_drag and not can_equip() else NEON_YELLOW

func _tween_focus_dim(to: float) -> void:
	if _focus_tw and _focus_tw.is_valid():
		_focus_tw.kill()
	_focus_tw = create_tween().set_ignore_time_scale(true)   # also snappy during the drag slow motion
	_focus_tw.tween_method(world.set_focus_dim, world.dim_focus, to, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
func _motion(sp: Vector2) -> void:
	_update_hover(press_hero if dragging else hero_at_screen(sp))
	if phase == P.BATTLE:
		Skills.aim_motion(self, sp)
		return
	if press_hero == null or not can_edit() or phase != P.PLACEMENT:
		return
	if not dragging and sp.distance_to(press_pos) > 10.0:
		if not tutorial_allows("drag"):
			press_hero = null
			return
		dragging = true
		press_hero.set_lifted(true)
		Sfx.play("click", -4.0, 1.3)
	if dragging:
		var p := _ray_plane(sp, 0.0)
		if p == Vector3.INF:
			return
		press_hero.position = Vector3(clampf(p.x, -3.2, 3.2), 0, clampf(p.z, -4.2, 4.2))
		world.clear_highlights()
		var t := World.pos_to_tile(p)
		if World.in_board(t) and t.y < 4:
			world.set_tile_highlight(t, Color(1, 1, 1, 0.55))

func _release(sp: Vector2) -> void:
	if phase == P.BATTLE:
		Skills.end_hold(self, sp)
		press_hero = null
		return
	if press_hero == null:
		return
	if dragging:
		_end_drag(false, sp)
	elif can_edit():
		_select(press_hero if selected != press_hero else null)
	press_hero = null

func _end_drag(cancel: bool, sp := Vector2.ZERO) -> void:
	if not dragging or press_hero == null:
		dragging = false
		return
	var h := press_hero
	h.set_lifted(false)
	world.clear_highlights()
	dragging = false
	var t := Vector2i(-1, -1)
	if not cancel:
		var p := _ray_plane(sp, 0.0)
		if p != Vector3.INF:
			t = World.pos_to_tile(p)
	if World.in_board(t) and t.y < 4:
		var occ := _hero_on_tile(t, h)
		if occ:
			occ.home = h.home
			occ.position = World.tile_pos(occ.home.x, occ.home.y)
			occ.drop_in(0.4)
		h.home = t
		hud.on_hero_moved(h)
	h.position = World.tile_pos(h.home.x, h.home.y)
	h.drop_in(0.35)

func _hero_on_tile(t: Vector2i, except: Actor) -> Actor:
	for h in alive_heroes():
		if h != except and h.home == t:
			return h
	return null

func _select(h: Actor) -> void:
	if selected and is_instance_valid(selected):
		selected.set_selected(false)
	if h and not tutorial_allows("select", h):
		h = null
	selected = h
	if h:
		h.set_selected(true)
		h.model.punch_scale(1.2, 0.85, 0.3)
		Sfx.play("click", -6.0, 1.1)
	hud.show_hero_panel(h)

# ---------------------------------------------------------------- screenshots
func _shot_later(delay: float, tag: String) -> void:
	if shots_dir == "":
		return
	await get_tree().create_timer(delay, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot_n += 1
	img.save_png("%s/w%02d_%02d_%s.png" % [shots_dir, wave, _shot_n, tag])
