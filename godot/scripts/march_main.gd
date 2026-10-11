extends "res://scripts/main.gd"
## Endless March mode: the trio marches up one endless, procedurally generated, winding battle field and
## runs into enemy camps along it — seamlessly, in real time. No board, no tiles, no start/end staging:
## the camp notices the trio, shouts and charges while the march glides to a halt; once the last enemy
## falls the drops fly into the bag and the trio is already walking again.
##   - group k uses the same composition / scaling / rewards as classic wave k (balance parity);
##     `wave` is the group number.
##   - drops stay on the field and fly into the bag once the whole group is wiped out.
##   - waiting groups live around a campfire (wander, sit, sleep, dance, spar, keep watch).
##   - every 10th group is a mid-boss with escorts; the field widens and the camera pulls back.
##   - camps are drawn from the region's creature line (Regions "roster" -> Defs.ROSTERS): beasts or monsters
##     stand in for the classic roles with identical numbers; each line has its own mid-boss (BossSkills).
##   - while marching the formation can be dragged freely (no snapping) and gear equipped.
##   - every MERCHANT_EVERY-th group the wandering merchant sets up his stall at the roadside; the shop only
##     opens when he is tapped (his stock stays the same for that visit).
##   - now and then a treasure chest lies on the road between camps (ChestLoot.FIELD_CHANCE); the trio grabs it on the
##     way past and it flies onto the bag's chest badge; every mid-boss drops one that starts at 희귀 (ChestGacha).
##   - two ways to play it (lobby): an expedition chapter (Meta.expedition) is one region — groups c*10+1 ..
##     c*10+10 — started at a fitting hero level (CHAPTER_LEVEL) and won by beating its mid-boss; the endless
##     march starts at group 1 and goes on until the team is wiped out.
##   - either way the run ends in a settlement (Main.end_run): gear is permanent, gold and 강화석 are banked,
##     learned skills and perks are gone. [다시 도전] / [다음 챕터] reloads the scene.

const MARCH_SPEED := 4.3
const ACCEL := 5.0
const BRAKE := 6.5             # glide to a halt over ~1.4 m once a camp is engaged
const ENGAGE_LEAD := 1.45      # engage this far before the camp's anchor (≈ braking distance)
const SPAWN_AHEAD := 24.0
const BOSS_ZOOM := 0.3
const MARCH_CAM := Vector3(0, 14.6, 11.2)   # flatter than classic: more of the road ahead (and its camps) reads
const REFORM_SPEED := 4.6
const MERCHANT_EVERY := 13      # was every mid-boss (10 groups); now 30% rarer and no longer forced open
const MERCHANT_AHEAD := 1.6     # stall sits this far before the camp: right beside the trio when they stop
const CHEST_AHEAD := 5.6        # field chests lie this far before a camp (about halfway from the previous one)

var mw: MarchWorld
var dist := 0.0
var speed := 0.0
var pending := {}          # group k -> {"enemies": Array[Actor], "gimmick": String, "fire": Vector3}
var formation := {}        # hero cls -> Vector3 offset (x relative to the field centre, local z)
var _fires: Array = []     # [{node, s}] campfires living on the track
var _drift: Array = []     # field objects (coins, loot) that ride along with the scrolling ground
var _boss_cam := 0.0
var _hud_dist := -1
var _idle_t := 0.0
var _last_auto_ult := -99.0
var mobile: HudMobile
var atlas: MapHud
var _merchant := {}        # {"node", "figure", "s", "k", "bubble", "seen"} — the roadside stall, if any
var _press_merchant := false
var _field_chests: Array = []   # [{"node", "model", "s", "t", "fx"}] treasure chests lying on the road
var _lost_perks := 0

func mode_id() -> String:
	return "march"

## Endless march keeps its best-group record; expedition chapters don't.
func record_id() -> String:
	return "" if expedition else "march"

var expedition := false
var chapter := 0
var _cleared := false
## Hero level an expedition chapter starts at (index = chapter; later laps keep climbing).
const CHAPTER_LEVEL := [1, 5, 7, 9, 11, 13]   # ≈ the levels the old endless march reached by then

func start_level() -> int:
	if not expedition:
		return 1
	if chapter < CHAPTER_LEVEL.size():
		return CHAPTER_LEVEL[chapter]
	return CHAPTER_LEVEL[-1] + 2 * (chapter - CHAPTER_LEVEL.size() + 1)

func last_group() -> int:
	return Meta.chapter_first_group(chapter) + Regions.PER_REGION - 1

func music_track() -> String:
	return "field"

func _make_world() -> World:
	mw = MarchWorld.new()
	mw.seed_v = randi()
	return mw

func _ready() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var dev_wave := args.any(func(a): return a.begins_with("--wave="))
	var dev := args.any(func(a): return a == "--autoplay" or a.begins_with("--test="))
	var forced := args.filter(func(a): return a.begins_with("--chapter="))   # dev: play expedition chapter N (1-based)
	expedition = not forced.is_empty() or (Meta.expedition and not dev_wave and not dev)
	if expedition:
		if not forced.is_empty() or dev:
			Meta.path = "user://trio_save_test.json"
		Meta.load_save()
		chapter = clampi(Meta.chapter, 0, Meta.cleared)
		if not forced.is_empty():
			chapter = maxi(0, int(forced[0].substr(10)) - 1)
		wave = Meta.chapter_first_group(chapter)
	super._ready()
	hud.wave_title.text = "무리"
	hud.talent_btn.visible = false
	hud.fight_btn.visible = false
	mobile = HudMobile.new()
	mobile.hud = hud
	mobile.game = self
	hud.add_child(mobile)
	mobile.build()
	atlas = MapHud.new()   # region chip + world map
	atlas.hud = hud
	atlas.game = self
	hud.add_child(atlas)
	atlas.build()
	Actor.clamp_fn = func(p: Vector3, m: float) -> Vector3: return mw.clamp_local(p, m)
	if wave > 1:   # expedition chapter (or dev --wave=N): start on the approach to group N
		var r := Regions.of_group(wave)
		dist = mw.region_start(r) + 0.1 if expedition and r > 0 else mw.arena_s(wave - 1)
		mw.set_dist(dist)
		_set_bounds()
	if expedition:
		var info: Dictionary = Regions.info(chapter)
		if UiTheme.tt():
			hud.ribbon_banner(Meta.chapter_name(chapter), "중간 보스를 쓰러뜨리면 원정 성공!", MapHud.ACCENT[info["theme"]], 1.2, -300)
		else:
			hud.banner(Meta.chapter_name(chapter), Color.WHITE, 1.0, 64, -200)

func gameover_text() -> String:
	if expedition:
		var n := clampi(wave - Meta.chapter_first_group(chapter) + (1 if _cleared else 0), 0, Regions.PER_REGION)
		return "%s · 무리 %d/%d" % [Meta.chapter_name(chapter), n, Regions.PER_REGION]
	return "%d번째 무리 · %dm 행군" % [wave, int(dist)]

# The march replaces the classic tutorial and the fight button.
func _tutorial_set(_step: int) -> void:
	super._tutorial_set(0)

func start_battle() -> void:
	pass

## Gear can be put on at any time (dragging it slows the game down instead of pausing it).
func can_equip() -> bool:
	return phase != P.GAMEOVER

# Ultimates are cast automatically, so a tap on a hero simply opens (or closes) its info.
func _press(sp: Vector2) -> void:
	press_hero = hero_at_screen(sp)
	press_pos = sp
	press_t = _clock
	dragging = false
	_press_merchant = press_hero == null and _merchant_hit(sp)
	if press_hero == null and can_edit() and not _press_merchant:
		_select(null)

func _release(sp: Vector2) -> void:
	if _press_merchant:
		_press_merchant = false
		if sp.distance_to(press_pos) < 24.0:
			open_shop()
		return
	if press_hero == null:
		return
	if dragging:
		_end_drag(false, sp)
	else:
		_select(press_hero if selected != press_hero else null)
	press_hero = null

## Auto ultimates: a ready hero fires at the densest cluster; casts are spaced so the
## (softened) cinematics never chain back to back.
func _auto_cast_ults() -> void:
	if Skills.aiming or Cinematic.active or drag_stage or now - _last_auto_ult < 1.4:   # no ult over the gear drag stage
		return
	var foes := alive_enemies()
	if foes.is_empty():
		return
	for h in alive_heroes():
		if h.ult_ready_at <= now and not h.busy:
			_last_auto_ult = now
			Skills.cast_ultimate(self, h, _densest(foes))
			_shot_later(0.3, "ult_intro")
			_shot_later(1.0, "ult_after")
			return

func _densest(foes: Array) -> Vector3:
	var best: Vector3 = foes[0].global_position
	var bn := -1
	for e in foes:
		var n := 0
		for o in foes:
			if Actor._flat(o.global_position - e.global_position).length() < 1.6:
				n += 1
		if n > bn:
			bn = n
			best = e.global_position
	return best

# ---------------------------------------------------------------- run
func start_run(first := false) -> void:
	_clear_pending()
	for f in _fires:
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	_fires.clear()
	_drift.clear()
	_remove_merchant()
	_clear_field_chests()
	dist = 0.0
	speed = 0.0
	_boss_cam = 0.0
	formation.clear()
	for cls in Defs.HERO_ORDER:
		var t: Vector2i = Defs.HERO_START[cls]
		formation[cls] = World.tile_pos(t.x, t.y)
	if mw and mw.track:
		mw.reset(randi())
	super.start_run(first)

func _clear_pending() -> void:
	for k in pending:
		for e in pending[k]["enemies"]:
			if is_instance_valid(e):
				hud.unregister_unit(e)
				e.queue_free()
	pending.clear()

## Marching (reuses the PLACEMENT phase so dragging heroes and equipping keep working).
func enter_placement() -> void:
	phase = P.PLACEMENT
	_phase_t = 0.0
	gimmick = ""
	world.deploy_glow = 0.0
	_set_bounds()
	hud.set_wave(wave, 0, 1)
	hud.set_enemy_count(0)
	hud.set_gimmick("", "")
	hud.fight_btn.visible = false
	hud.talent_btn.visible = false   # the talent tree lives in the bottom navigation bar
	_hud_dist = -1
	_update_march_hud()
	if wave == 1 and dist < 1.0:
		hud.banner("행군 시작!", Color.WHITE, 0.4, 96, -160)
	_shot_later(0.8, "march")

## Rectangle bounds still used by a few skills / loot landings; the real limit is the field clamp.
func _set_bounds() -> void:
	Actor.BOARD_X = mw.half_w(dist) - 0.35
	Actor.BOARD_Z = 4.6

func _update_march_hud() -> void:
	var to_boss := MarchWorld.BOSS_EVERY - ((wave - 1) % MarchWorld.BOSS_EVERY) - 1
	hud.sub_label.text = "중간 보스!" if MarchWorld.is_boss(wave) else "보스까지 %d무리" % to_boss
	var left := int(ceilf(maxf(0.0, mw.arena_s(wave) - dist)))
	if left != _hud_dist and phase == P.PLACEMENT:
		_hud_dist = left
		hud.set_phase("다음 무리까지 %dm" % left)

# ---------------------------------------------------------------- per frame
func _process(delta: float) -> void:
	_clock += delta / maxf(Engine.time_scale, 0.001)
	_phase_t += delta
	if quit_after > 0.0 and _clock > quit_after:
		Music.quit()
	_info_pause_tick()
	match phase:
		P.PLACEMENT:
			if not _info_paused:
				_march_tick(delta)
		P.BATTLE, P.SPAWNING:
			if speed > 0.0 and not get_tree().paused:
				speed = move_toward(speed, 0.0, delta * BRAKE)
				_scroll(speed * delta)
			if phase == P.BATTLE:
				Skills.update_hold(self)
				if not get_tree().paused:
					now += delta
					_battle_tick(delta)
					if phase == P.BATTLE:
						_auto_cast_ults()
		P.TRANSITION:
			if speed > 0.0:
				speed = move_toward(speed, 0.0, delta * BRAKE)
				_scroll(speed * delta)
	if not get_tree().paused:
		_idle_t += delta
		_camp_tick(delta)
	if autoplay and int(_clock * 2.0) % 2 == 0:
		auto_books()
	_update_camera(delta)
	_merchant_tick()
	_chest_tick(delta)

## The march itself is live too: an open card stops the party mid-stride.
func _info_pause_phase() -> bool:
	return phase == P.PLACEMENT or phase == P.SPAWNING or phase == P.BATTLE

func _march_tick(delta: float) -> void:
	_ensure_pending()
	var hold := hud.has_overlay() or dragging
	speed = move_toward(speed, 0.0 if hold else MARCH_SPEED, delta * (BRAKE if hold else ACCEL))
	_scroll(speed * delta)
	_march_heroes(delta)
	_update_march_hud()
	if dist >= mw.arena_s(wave) - ENGAGE_LEAD:
		_engage()

## Advance the treadmill: the track moves, and everything lying on the ground moves with it.
func _scroll(dd: float) -> void:
	if dd <= 0.0:
		return
	var ox := mw.center_x(dist)
	dist += dd
	mw.set_dist(dist)
	var shift := Vector3(ox - mw.center_x(dist), 0, dd)
	for e in enemies:
		if is_instance_valid(e):
			e.position += shift
	for c in coins:
		if is_instance_valid(c["node"]):
			c["node"].position += shift
	for l in field_loot:
		if is_instance_valid(l["node"]):
			l["node"].position += shift
	var keep: Array = []
	for n in _drift:
		if is_instance_valid(n):
			n.position += shift
			keep.append(n)
	_drift = keep
	_place_pending()
	if not _merchant.is_empty() and _merchant["s"] < dist - MarchWorld.BEHIND:
		_remove_merchant()
	for c in _field_chests.duplicate():
		if c["s"] < dist - MarchWorld.BEHIND:
			_field_chests.erase(c)
			if is_instance_valid(c["node"]):
				c["node"].queue_free()
	for f in _fires.duplicate():
		if f["s"] < dist - MarchWorld.BEHIND:
			if is_instance_valid(f["node"]):
				f["node"].queue_free()
			_fires.erase(f)

## Coins and loot keep riding the ground while they fly into the HUD.
func _collect_coins() -> void:
	for c in coins:
		_drift.append(c["node"])
	super._collect_coins()

func _collect_loot() -> float:
	for l in field_loot:
		_drift.append(l["node"])
	return super._collect_loot()

## Heroes keep their formation along the winding field (walking back into it after a fight).
func _march_heroes(delta: float) -> void:
	var scroll := clampf(speed / 1.4, 0.0, 1.0)
	for h in alive_heroes():
		if dragging and h == press_hero:
			continue
		var f: Vector3 = formation.get(h.cls, Vector3.ZERO)
		var goal := Vector3(f.x + mw.local_center(f.z), 0, f.z)
		var to := Actor._flat(goal - h.position)
		var step := REFORM_SPEED * delta
		var walking := scroll
		if to.length() > step:
			h.position += to.normalized() * step
			walking = 1.0
		else:
			h.position = goal
		h.model.walk = lerpf(h.model.walk, walking, 1.0 - exp(-delta * 8.0))
		if to.length() > 0.3:
			h._face(to, delta, 10.0)
		elif scroll > 0.05:
			var sh: float = dist - h.position.z
			var slope := (mw.center_x(sh + 0.4) - mw.center_x(sh - 0.4)) / 0.8
			h._face(Vector3(slope, 0, -1), delta, 8.0)
		else:
			h._face(Vector3(0, 0, -1), delta, 6.0)

## Free formation drag (no tiles): drop anywhere in the rear half of the field.
func _end_drag(cancel: bool, sp := Vector2.ZERO) -> void:
	if not dragging or press_hero == null:
		dragging = false
		return
	var h := press_hero
	h.set_lifted(false)
	dragging = false
	if not cancel:
		var p := _ray_plane(sp, 0.0)
		if p != Vector3.INF:
			var z := clampf(p.z, 0.3, 3.9)
			var w := mw.half_w(dist - z) - 0.5
			var x := clampf(p.x - mw.local_center(z), -w, w)
			formation[h.cls] = Vector3(x, 0, z)
			hud.on_hero_moved(h)
	var f: Vector3 = formation.get(h.cls, Vector3.ZERO)
	h.position = Vector3(f.x + mw.local_center(f.z), 0, f.z)
	h.drop_in(0.35)

## Pull the camera back while a mid-boss field is near.
func _update_camera(delta: float) -> void:
	var goal := mw.boss_k(dist)
	if phase == P.BATTLE and MarchWorld.is_boss(wave):
		goal = 1.0
	_boss_cam = lerpf(_boss_cam, goal, 1.0 - exp(-delta * 3.0))
	var look := Vector3(0, 0, -1.0 - 0.6 * _boss_cam)
	cam.set_base(look + MARCH_CAM * (1.0 + BOSS_ZOOM * _boss_cam), look)

## Chatter context: heroes talk on the road, waiting camps chat around the fire (or mumble in their sleep).
func chat_ctx(u: Actor) -> String:
	var c := super.chat_ctx(u)
	if c != "idle":
		return c
	if u.is_hero():
		return "march"
	if u.has_meta("idle"):
		return "sleep" if (u.get_meta("idle") as Dictionary)["mode"] == "sleep" else "camp"
	return "idle"

# ---------------------------------------------------------------- enemy camps
func _ensure_pending() -> void:
	for k in [wave, wave + 1]:
		if not pending.has(k) and mw.arena_s(k) - dist < SPAWN_AHEAD:
			_make_group(k)

## Same rules as classic wave k; every 10th group is a mid-boss. The group camps around a fire.
func _make_group(k: int) -> void:
	var g := ""
	var list := []   # [{kind, pos}] — pos is in camp coordinates (field-centre relative, local z at engagement)
	var roster: String = Regions.info(Regions.of_group(k)).get("roster", "")
	if MarchWorld.is_boss(k):
		g = "giantBoss"
		list = _boss_list(k, roster)
	else:
		g = force_gimmick if force_gimmick != "" else Waves.pick_gimmick(k)
		if g == "giantBoss":
			g = ""   # mid-bosses keep their own rhythm
		for s in (Waves.gimmick(g) if g != "" else Waves.normal(k)):
			var p := World.tile_pos(s["tile"].x, s["tile"].y) + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.6, 0.3))
			if Defs.ENEMIES[s["kind"]].get("size", 1) > 1:
				p += Vector3(0.5, 0, -0.5)
			list.append({"kind": Defs.skin(s["kind"], roster), "pos": p})
	var fire := Vector3(0, 0, -3.4)
	if not list.is_empty():
		var c := Vector3.ZERO
		for s in list:
			c += s["pos"]
		fire = c / list.size()
		fire.x = clampf(fire.x, -1.5, 1.5)
	var mult := Defs.scaling(k)
	var arr: Array = []
	for s in list:
		var u := Actor.new()
		units_root.add_child(u)
		u.setup(s["kind"], Defs.TEAM_ENEMY, self, mult)
		u.is_illusion = s["kind"] == "illusion"
		u.set_meta("fp", s["pos"])
		u.set_meta("idle", _new_idle(u, fire, k))
		arr.append(u)
	_pair_sparrers(arr)
	pending[k] = {"enemies": arr, "gimmick": g, "fire": fire}
	# the campfire lives on the track itself
	var ak := mw.arena_s(k)
	var fs := ak - fire.z
	var node := MarchProps.campfire(mw.track, Vector3(mw.center_x(fs) + fire.x, 0.0, -fs), mw.camp_stone(fs))
	_fires.append({"node": node, "s": fs})
	if _merchant_at(k):
		_spawn_merchant(k)
	elif not MarchWorld.is_boss(k) and k > 1 and randf() < ChestLoot.FIELD_CHANCE:
		_spawn_field_chest(mw.arena_s(k) - CHEST_AHEAD)
	_place_pending()

## Mid-boss: the region line's boss (war mammoth / abyss lord; golem without a roster) dozing at the back of
## the wide field plus escorts drawn from the classic mix.
func _boss_list(k: int, roster := "") -> Array:
	var out := [{"kind": Defs.skin("giant", roster), "pos": Vector3(0, 0, -4.4)}]
	var escorts: Array = Waves.normal(k)
	var n := mini(2 + int(k / 10.0), 6)
	var xs := [-3.4, 3.4, -2.2, 2.2, -3.9, 3.9]
	for i in mini(n, escorts.size()):
		out.append({"kind": Defs.skin(escorts[i]["kind"], roster), "pos": Vector3(xs[i], 0, -2.8 - (i % 2) * 1.3)})
	return out

const IDLE_MODES := [["wander", 0.26], ["sit", 0.24], ["sleep", 0.12], ["dance", 0.1], ["spar", 0.16], ["lookout", 0.12]]

func _new_idle(u: Actor, fire: Vector3, k: int) -> Dictionary:
	var mode := "wander"
	if Defs.is_huge(u.kind):
		mode = "sleep"
	elif u.kind in ["splitter", "splitling", "hydra", "eyebat", "mimic", "horror"]:
		mode = "dance" if randf() < 0.5 else "wander"   # blobs, floaters and chests just bounce around
	elif not u.model.quad_legs.is_empty() or u.kind == "hornbunny":
		mode = ["wander", "wander", "sleep", "lookout", "dance"][randi() % 5]   # beasts prowl, nap and sniff the air
	else:
		var total := 0.0
		for m in IDLE_MODES:
			total += m[1]
		var r := randf() * total
		for m in IDLE_MODES:
			r -= m[1]
			if r <= 0.0:
				mode = m[0]
				break
	var d := {"mode": mode, "fire": fire, "t": randf() * 2.0, "goal": u.get_meta("fp"), "partner": null, "seen": false, "k": k}
	if mode == "sit" or mode == "sleep":
		var a := randf() * TAU
		var r2 := 0.95 if mode == "sit" else 1.5
		if Defs.is_huge(u.kind):
			r2 = 0.0
		var spot: Vector3 = fire + Vector3(cos(a), 0, sin(a)) * r2
		if Defs.is_huge(u.kind):
			spot = u.get_meta("fp")
		d["goal"] = spot
		u.set_meta("fp", spot)
	elif mode == "lookout":
		var fp: Vector3 = u.get_meta("fp")
		u.set_meta("fp", Vector3(fp.x, 0, fire.z + 1.4))
	return d

func _pair_sparrers(arr: Array) -> void:
	var lone: Actor = null
	for u in arr:
		var d: Dictionary = u.get_meta("idle")
		if d["mode"] != "spar":
			continue
		if lone == null:
			lone = u
		else:
			d["partner"] = lone
			(lone.get_meta("idle") as Dictionary)["partner"] = u
			var mid: Vector3 = (u.get_meta("fp") + lone.get_meta("fp")) * 0.5
			u.set_meta("fp", mid + Vector3(0.45, 0, 0))
			lone.set_meta("fp", mid - Vector3(0.45, 0, 0))
			lone = null
	if lone:
		(lone.get_meta("idle") as Dictionary)["mode"] = "wander"

## Waiting camps ride along with the field until the trio reaches them.
func _place_pending() -> void:
	for k in pending:
		var ak := mw.arena_s(k)
		for e in pending[k]["enemies"]:
			if is_instance_valid(e) and e.alive:
				var fp: Vector3 = e.get_meta("fp")
				var s := ak - fp.z
				e.position = Vector3(mw.center_x(s) - mw.center_x(dist) + fp.x, 0, dist - s)

## Camp life: each waiting monster does its own thing around the fire.
func _camp_tick(delta: float) -> void:
	for k in pending:
		var near := mw.arena_s(k) - dist < 9.0
		for e in pending[k]["enemies"]:
			if not is_instance_valid(e) or not e.alive:
				continue
			var d: Dictionary = e.get_meta("idle")
			d["t"] += delta
			var fp: Vector3 = e.get_meta("fp")
			var fire: Vector3 = d["fire"]
			var m: UnitModel = e.model
			var on_screen: bool = e.position.z > -11.0
			match d["mode"]:
				"wander":
					var to := Actor._flat((d["goal"] as Vector3) - fp)
					if to.length() > 0.08:
						fp += to.normalized() * minf(0.75 * delta, to.length())
						m.walk = lerpf(m.walk, 1.0, 1.0 - exp(-delta * 8.0))
						e._face(to, delta, 8.0)
						d["t"] = 0.0
					else:
						m.walk = lerpf(m.walk, 0.0, 1.0 - exp(-delta * 8.0))
						if d["t"] > randf_range(0.9, 2.6):
							var a := randf() * TAU
							d["goal"] = fire + Vector3(cos(a) * randf_range(0.9, 2.0), 0, sin(a) * randf_range(0.6, 1.3))
				"sit":
					m.position.y = -0.1
					m.rotation.x = -0.12
					e._face(fire - fp, delta, 6.0)
					if d["t"] > 2.2:
						d["t"] = randf() * 0.8
						m.punch_scale(1.15, 0.85, 0.3)   # chuckle / warm hands
				"sleep":
					var huge := Defs.is_huge(e.kind)
					m.rotation.z = lerpf(m.rotation.z, 1.3 if not huge else 0.0, 1.0 - exp(-delta * 6.0))
					m.position.y = 0.04 if not huge else -0.06
					if huge:
						m.rotation.x = -0.25 + sin(_idle_t * 1.6) * 0.05   # head nodding
					if d["t"] > 1.6 and on_screen:
						d["t"] = 0.0
						hud.float_text(e.global_position + Vector3(0.2, 0.9 * m.scale.x / Actor.MODEL_SCALE + 0.4, 0), "z", Color("bfe4ff"))
				"dance":
					m.position.y = absf(sin(d["t"] * 7.0)) * 0.18
					m.rotation.y += delta * 2.4
					if absf(sin(d["t"] * 7.0)) < 0.08:
						m.punch_scale(1.15, 0.85, 0.2)
				"spar":
					var p: Actor = d["partner"]
					if p and is_instance_valid(p) and p.alive:
						e._face((p.get_meta("fp") as Vector3) - fp, delta, 10.0)
						if d["t"] > 1.2:
							d["t"] = randf() * 0.3
							m.play_attack("melee")
							p.model.punch_scale(1.2, 0.8, 0.3)
							if on_screen and randf() < 0.3:
								Sfx.play("tick", -18.0, 1.6)
				"lookout":
					m.rotation.y = PI + sin(d["t"] * 1.3) * 0.7
					if near and not d["seen"]:
						d["seen"] = true
						m.rotation.y = PI
						hud.float_text(e.global_position + Vector3(0, 1.3, 0), "?", Color("ffd27a"))
						m.punch_scale(0.85, 1.2, 0.3)
			e.set_meta("fp", fp)

## The camp notices the trio: "!" pop, a startled hop, then they charge — the battle simply begins.
func _engage() -> void:
	_ensure_pending()
	var grp: Dictionary = pending[wave]
	pending.erase(wave)
	_end_drag(true)
	_select(null)
	relic_tempo = 0
	enemies.clear()
	var i := 0
	for e in grp["enemies"]:
		enemies.append(e)
		hud.register_unit(e)   # bars appear once the camp turns hostile (camps stay uncluttered)
		_alert(e, i)
		i += 1
	var boss := MarchWorld.is_boss(wave)
	_set_bounds()
	gimmick = grp["gimmick"]
	sub_waves = 1 if boss else Defs.sub_wave_count(wave)
	sub_wave = 0
	_sub_pending = false
	if boss:
		var bk := "giant"
		for e in enemies:
			if Defs.is_huge(e.kind):
				bk = e.kind
		var bi: Dictionary = Defs.BOSS_INFO.get(bk, Defs.BOSS_INFO["giant"])
		hud.set_gimmick(bi["title"], bi["hint"])
	elif gimmick != "":
		var info: Dictionary = Waves.GIMMICK_INFO[gimmick]
		hud.set_gimmick(info["title"], info["hint"])
	hud.set_phase("")
	phase = P.BATTLE
	_phase_t = 0.0
	hud.set_wave(wave, sub_wave, sub_waves)
	_update_march_hud()
	hud.set_enemy_count(alive_enemies().size())
	_shot_later(0.4, "engage")
	_shot_later(2.0, "battle")

func _alert(e: Actor, i: int) -> void:
	var was_sleeping: bool = (e.get_meta("idle") as Dictionary)["mode"] == "sleep"
	e.reset_status()
	e.busy = true
	var delay := 0.05 * i + (0.25 if was_sleeping else 0.0)
	var tw := e.create_tween()
	tw.tween_interval(delay)
	tw.tween_callback(func():
		if not e.alive:
			return
		hud.float_text(e.global_position + Vector3(0, 1.2 * e.model.scale.y / Actor.MODEL_SCALE + 0.3, 0), "!", Color("ff6b6b"))
		e.model.punch_scale(0.75, 1.35, 0.3)
		if Defs.is_huge(e.kind):
			cam.add_trauma(0.35)
			Sfx.play("boom", -6.0, 0.7)
			if e.kind != "giant":   # the region boss roars its name
				hud.callout(e.global_position + Vector3(0, e.def.get("bar_h", 1.05) * e.model.scale.y / Actor.MODEL_SCALE + 0.9, 0), "크아앙!", Color("ff9a6a")))
	tw.tween_property(e.model, "position:y", 0.45, 0.13).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(e.model, "position:y", 0.0, 0.11).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		e.busy = false
		e.model.punch_scale(1.25, 0.75, 0.25))

# ---------------------------------------------------------------- group cleared
## No end-of-fight staging: drops fly into the bag while the trio is already marching on.
func finish_wave() -> void:
	if phase == P.TRANSITION or phase == P.GAMEOVER:
		return
	Skills.cancel(self)
	Cinematic.reset(self)
	var cleared := wave
	var boss := MarchWorld.is_boss(cleared)
	print("[March] clear group=", cleared, " dist=", int(dist), " gimmick=", gimmick, " gold=", gold, " lv=", heroes.map(func(x): return x.level), " inv=", inventory.size())
	gimmick = ""
	hud.set_gimmick("", "")
	Engine.time_scale = cam.base_scale
	if boss:
		_boss_chest()
	var crystals := 6 if boss else 2
	Meta.add_crystals(crystals)
	hud.set_crystals(Meta.crystals)
	if boss:
		hud.toast("중간 보스 처치! 시간의 결정 +%d" % crystals, Defs.COL_CRYSTAL)
	Sfx.play("chime", -10.0, 1.2)
	for h in alive_heroes():
		h.reset_status()
		h.heal(WAVE_HEAL + Stats.g(Stats.perk_fx(self), "waveHealBonus"), true)
	_collect_coins()
	_collect_loot()   # this group's drops fly into the bag now
	# free the (already vanished) bodies a little later: in-flight projectiles / attacks still hold them
	var bodies := enemies.duplicate()
	enemies.clear()
	for e in bodies:
		hud.unregister_unit(e)
	get_tree().create_timer(1.5).timeout.connect(func():
		for e in bodies:
			if is_instance_valid(e):
				e.queue_free())
	wave = cleared + 1
	_shot_later(0.3, "group_clear")
	if boss and expedition and cleared >= last_group():
		_chapter_clear()
		return
	if boss:
		phase = P.TRANSITION
		_returning = true
		await get_tree().create_timer(0.5).timeout
		_returning = false
		if hud.open_perks():   # perk roulette after a mid-boss (the merchant waits at the roadside instead)
			await hud.overlay_closed
		if phase != P.TRANSITION:
			return
	enter_placement()

## The chapter's mid-boss is down: victory hop, the boss chest lands, first-clear bonus, settlement.
func _chapter_clear() -> void:
	_cleared = true
	phase = P.TRANSITION
	_returning = true
	for h in alive_heroes():
		_victory_hop(h)
	if UiTheme.tt():
		hud.ribbon_banner("원정 성공!", Meta.chapter_name(chapter), UiTheme.ORANGE, 1.1)
	else:
		hud.banner("원정 성공!", Defs.COL_GOLD, 1.0, 100)
	Sfx.play("chime", -2.0, 1.0)
	await get_tree().create_timer(1.6).timeout   # the boss chest flies onto the badge first
	if phase != P.TRANSITION:
		return
	if Meta.on_chapter_cleared(chapter):
		var bonus_g := 150 * (chapter + 1)
		var bonus_s := 8 * (chapter + 1)
		gold += bonus_g
		stones += bonus_s
		hud.toast("첫 클리어 보상! 골드 +%d · 강화석 +%d" % [bonus_g, bonus_s], Defs.COL_GOLD)
	phase = P.GAMEOVER
	_returning = false
	Music.duck(-8.0, 0.6, 2.0)
	hud.show_settlement(end_run(true))
	_shot_later(0.9, "chapter_clear")

# ---------------------------------------------------------------- wandering merchant
static func is_merchant(k: int) -> bool:
	return k > 0 and k % MERCHANT_EVERY == 0

## Expedition chapters are only 10 groups long: the merchant waits once per chapter, at its 6th group.
func _merchant_at(k: int) -> bool:
	return (k - 1) % Regions.PER_REGION == 5 if expedition else is_merchant(k)

## The stall lives on the track next to group k's camp, on the grass just off the field edge (on the side that
## keeps it on screen), so it is there all through that group's approach and fight, then scrolls away behind.
func _spawn_merchant(k: int) -> void:
	_remove_merchant()
	var s := mw.arena_s(k) - MERCHANT_AHEAD
	var lc := mw.center_x(s) - mw.center_x(mw.arena_s(k) - ENGAGE_LEAD)
	var side := -1.0 if lc > 0.0 else 1.0
	var x := mw.center_x(s) + side * (mw.half_w(s) + 0.15)   # on the curb, so it stays on screen
	var m := MarchProps.merchant(mw.track, Vector3(x, 0.0, -s), side)
	hud.panels.merchant_stock = []   # fresh stock for this visit, kept while he stays
	var bubble := _merchant_bubble()
	_merchant = {"node": m["root"], "figure": m["figure"], "s": s, "k": k, "bubble": bubble, "seen": false}
	print("[March] merchant at group ", k, " s=", snappedf(s, 0.1))

func _remove_merchant() -> void:
	if _merchant.is_empty():
		return
	if is_instance_valid(_merchant["node"]):
		_merchant["node"].queue_free()
	if is_instance_valid(_merchant["bubble"]):
		_merchant["bubble"].queue_free()
	_merchant = {}

## Speech bubble above the stall: coin + "상점", bobbing; tapping it opens the shop too.
func _merchant_bubble() -> Control:
	var b := Panel.new()
	b.size = Vector2(124, 52)
	b.pivot_offset = Vector2(62, 52)
	b.add_theme_stylebox_override("panel", hud.box(Color("fff4e0"), 22, 4, UiTheme.ink()))
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.visible = false
	hud.root.add_child(b)
	hud.root.move_child(b, 0)   # under the panels / popups
	var ic := Hud.CoinIcon.new()
	ic.position = Vector2(6, 6)
	ic.size = Vector2(40, 40)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	var l := hud.label("상점", 26, Color("5a3a00"), 0)
	l.position = Vector2(46, 0)
	l.size = Vector2(72, 52)
	b.add_child(l)
	var tail := Panel.new()
	tail.size = Vector2(18, 18)
	tail.position = Vector2(53, 42)
	tail.rotation = PI * 0.25
	tail.pivot_offset = Vector2(9, 9)
	tail.add_theme_stylebox_override("panel", hud.box(Color("fff4e0"), 3, 4, UiTheme.ink()))
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tail.show_behind_parent = true
	b.add_child(tail)
	b.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			open_shop())
	return b

## World point of the stall's head in local (game) space.
func _merchant_pos() -> Vector3:
	var n: Node3D = _merchant["figure"]
	return n.global_position + Vector3(0, 1.2, 0)

func _merchant_hit(sp: Vector2) -> bool:
	if _merchant.is_empty() or not is_instance_valid(_merchant["figure"]):
		return false
	var p := _merchant_pos()
	if cam.is_position_behind(p):
		return false
	var c := cam.unproject_position(p - Vector3(0, 0.6, 0))
	return sp.distance_to(c) < 90.0

func _merchant_tick() -> void:
	if _merchant.is_empty():
		return
	var b: Control = _merchant["bubble"]
	if not is_instance_valid(b) or not is_instance_valid(_merchant["figure"]):
		return
	var p := _merchant_pos()
	var z := p.z
	var on := z > -11.0 and z < 6.0 and not cam.is_position_behind(p) and phase != P.GAMEOVER
	var sp := cam.unproject_position(p + Vector3(0, 0.35, 0))
	on = on and Rect2(Vector2(-60, -60), hud.root.size + Vector2(120, 120)).has_point(sp) and not hud.has_overlay()
	b.visible = on
	if on:
		b.position = sp - Vector2(62, 52) + Vector2(0, -6.0 * absf(sin(_clock * 3.2)))
	if on and not _merchant["seen"] and z > -8.5:
		_merchant["seen"] = true
		hud.bump(b, 1.5)
		hud.toast("떠돌이 상인이 길가에 자리를 잡았어요! 터치해서 거래하세요", Color("ffd27a"))
		hud.callout(p + Vector3(0, 0.3, 0), "어서 오게!", Color("ffd27a"))
		Sfx.play("chime", -8.0, 1.4)
		_shot_later(0.4, "merchant")

## Tap on the merchant: the shop opens over a paused field and closes back into the march / battle.
func open_shop() -> void:
	if _merchant.is_empty() or hud.has_overlay() or phase == P.GAMEOVER or Cinematic.active or Skills.aiming or drag_stage:
		return
	var fig: Node3D = _merchant["figure"]
	if is_instance_valid(fig):
		var tw := fig.create_tween()
		tw.tween_property(fig, "scale", Vector3(1.2, 0.85, 1.2), 0.08)
		tw.tween_property(fig, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	Sfx.play("click", -4.0, 1.1)
	var was := get_tree().paused
	get_tree().paused = true
	if not hud.open_merchant(true):
		get_tree().paused = was
		return
	hud.overlay_closed.connect(func():
		if is_inside_tree() and phase != P.GAMEOVER:
			get_tree().paused = was, CONNECT_ONE_SHOT)
	_shot_later(0.5, "shop")

# ---------------------------------------------------------------- treasure chests on the road
## A toy chest lying on the road at track distance s (x jittered around the centre so the trio walks over it).
func _spawn_field_chest(s: float, t := 0) -> void:
	var x := mw.center_x(s) + randf_range(-0.8, 0.8)
	var root := Node3D.new()
	root.position = Vector3(x, 0.0, -s)
	mw.track.add_child(root)
	var halo := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.55
	disc.bottom_radius = 0.55
	disc.height = 0.01
	halo.mesh = disc
	halo.material_override = MarchProps.glow_mat(Color(1.0, 0.85, 0.3, 0.22), 1.0)
	halo.position.y = 0.02
	root.add_child(halo)
	var m := ChestModel.new(t)
	m.scale = Vector3.ONE * 0.72
	m.rotation.y = randf_range(-0.45, 0.45)
	root.add_child(m)
	var l := OmniLight3D.new()
	l.light_color = Color("ffd27a")
	l.light_energy = 0.9
	l.omni_range = 1.8
	l.position = Vector3(0, 1.1, 0.5)
	root.add_child(l)
	# breathing + the lid peeking open now and then (a glint from inside)
	var bt := m.create_tween().set_loops()
	bt.tween_property(m, "scale", Vector3(0.76, 0.68, 0.76), 0.5).set_trans(Tween.TRANS_SINE)
	bt.tween_property(m, "scale", Vector3(0.7, 0.76, 0.7), 0.5).set_trans(Tween.TRANS_SINE)
	var lt := m.lid.create_tween().set_loops()
	lt.tween_interval(1.3)
	lt.tween_property(m.lid, "rotation:x", -0.35, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lt.tween_property(m.lid, "rotation:x", 0.0, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	var ht := halo.create_tween().set_loops()
	ht.tween_property(halo, "scale", Vector3(1.25, 1, 1.25), 0.5).set_trans(Tween.TRANS_SINE)
	ht.tween_property(halo, "scale", Vector3(0.9, 1, 0.9), 0.5).set_trans(Tween.TRANS_SINE)
	_field_chests.append({"node": root, "model": m, "s": s, "t": t, "fx": 0.0, "tws": [bt, lt, ht]})

func _clear_field_chests() -> void:
	for c in _field_chests:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	_field_chests.clear()

## Glints while waiting; grabbed when a hero walks over it or the trio's line passes it.
func _chest_tick(delta: float) -> void:
	if _field_chests.is_empty() or get_tree().paused or phase == P.GAMEOVER:
		return
	var heroes_alive := alive_heroes()
	var back := -INF
	for h in heroes_alive:
		back = maxf(back, h.global_position.z)
	for c in _field_chests.duplicate():
		var root: Node3D = c["node"]
		if not is_instance_valid(root):
			_field_chests.erase(c)
			continue
		var p := root.global_position
		c["fx"] -= delta
		if c["fx"] <= 0.0 and p.z > -11.0:
			c["fx"] = 0.45
			Vfx.sparks(p + Vector3(randf_range(-0.3, 0.3), 0.55, 0), Color("fff2a0"), 3, 1.2, 0.5, "star5", 0.1, -1.0)
		var grab := not heroes_alive.is_empty() and p.z > back - 0.4
		for h in heroes_alive:
			if Actor._flat(h.global_position - p).length() < 0.9:
				grab = true
		if grab:
			_pickup_chest(c)

func _pickup_chest(c: Dictionary) -> void:
	_field_chests.erase(c)
	var root: Node3D = c["node"]
	var m: ChestModel = c["model"]
	for t in c["tws"]:
		(t as Tween).kill()
	Sfx.play("pop", -3.0, 1.1)
	Sfx.play("chime", -7.0, 1.6)
	Vfx.sparks(root.global_position + Vector3(0, 0.4, 0), Color("ffd23f"), 14, 3.2, 0.5, "star5", 0.16)
	hud.callout(root.global_position + Vector3(0, 1.3, 0), "보물상자!", Color("ffd27a"))
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "position:y", 1.2, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "rotation:y", m.rotation.y + TAU, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "scale", Vector3.ONE * 1.0, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(m.lid, "rotation:x", -0.5, 0.15)
	tw.chain().tween_callback(func():
		var sp := cam.unproject_position(m.global_position + Vector3(0, 0.3, 0))
		give_chest(int(c["t"]), sp)
		root.queue_free())

## Mid-boss loot: a chest that already starts at 희귀 bursts out of the fallen boss.
func _boss_chest() -> void:
	var at := Vector3.ZERO
	for e in enemies:
		if is_instance_valid(e) and Defs.is_huge(e.kind):
			at = e.global_position
	var top := at + Vector3(0, 1.4, 0)
	hud.callout(top + Vector3(0, 0.6, 0), "희귀 보물상자!", Color("8fd0ff"))
	get_tree().create_timer(0.55).timeout.connect(func():
		if is_inside_tree():
			give_chest(ChestLoot.BOSS_TIER, cam.unproject_position(top)))

# ---------------------------------------------------------------- team wiped out
## A wipe-out costs every run perk; the game-over card then offers to resume from the region's first group.
func game_over() -> void:
	if phase == P.GAMEOVER:
		return
	_lost_perks = clear_perks()
	super.game_over()

func gameover_note() -> String:
	return "특성 %d개가 모두 사라졌어요" % _lost_perks if _lost_perks > 0 else "특성은 전멸하면 모두 사라져요"

func retry_label() -> String:
	if expedition:
		return "다음 챕터 ▶" if _cleared else "다시 도전"
	return "다시 행군"

## A new run: the scene starts over (an expedition picks up Meta.chapter — the next one after a clear).
func retry() -> void:
	if expedition and _cleared:
		Meta.chapter = mini(chapter + 1, Meta.cleared)
		Meta.save()
	Engine.time_scale = 1.0
	get_tree().paused = false
	Skills.cancel(self)
	Cinematic.reset(self)
	get_tree().reload_current_scene()

## Dev only (--test=shop): resume from the first group of the region that was reached.
func resume_region() -> void:
	var r := Regions.of_group(wave)
	var first := r * Regions.PER_REGION + 1
	print("[March] retry region=", r, " from group ", first, " (died at ", wave, ")")
	get_tree().paused = false
	Skills.cancel(self)
	Cinematic.reset(self)
	cam.base_scale = 1.0
	cam.group_focus([], false)
	_drag_stage(false)
	Engine.time_scale = 1.0
	hud.close_overlays()
	_end_drag(true)
	_select(null)
	_clear_pending()
	for e in enemies:
		if is_instance_valid(e):
			hud.unregister_unit(e)
			e.queue_free()
	enemies.clear()
	for c in coins:
		if is_instance_valid(c["node"]):
			c["node"].queue_free()
	coins.clear()
	_discard_loot()
	for f in _fires:
		if is_instance_valid(f["node"]):
			f["node"].queue_free()
	_fires.clear()
	_drift.clear()
	_remove_merchant()
	_clear_field_chests()
	dead_order.clear()
	revive_used = {}
	relic_tempo = 0
	gimmick = ""
	sub_wave = 0
	_sub_pending = false
	_returning = false
	wave = first
	dist = mw.region_start(r) + 0.1 if r > 0 else 0.0
	speed = 0.0
	mw.set_dist(dist)
	_set_bounds()
	var i := 0
	for h in heroes:
		h.reset_status()
		if not h.alive:
			h.revive(1.0)
		h.hp = h.max_hp
		var f: Vector3 = formation.get(h.cls, Vector3.ZERO)
		h.position = Vector3(f.x + mw.local_center(f.z), 0, f.z)
		h.drop_in(1.6, 0.12 * i)
		i += 1
	enter_placement()
	var name_r: String = Regions.info(r)["name"]
	if UiTheme.tt():
		hud.ribbon_banner(name_r, "처음부터 다시 행군!", MapHud.ACCENT[Regions.info(r)["theme"]], 1.1, -300)
	else:
		hud.banner("%s 처음부터!" % name_r, Color.WHITE, 0.9, 72, -200)
	_shot_later(1.0, "retry")

# ---------------------------------------------------------------- dev checks
## --test=camp: stop short of the first camps and capture their idle life (and a mid-boss camp).
func _run_test() -> void:
	if test_mode == "panel" or test_mode == "books":
		await _test_books()
		return
	if test_mode == "ui":
		await _test_ui()
		return
	if test_mode == "pause":
		await _test_pause()
		return
	if test_mode == "notice":
		await _test_notice()
		return
	if test_mode == "bestiary":
		await _test_bestiary()
		return
	if test_mode == "shop":
		await _test_shop()
		return
	if test_mode == "chest":
		await _test_chest()
		return
	if test_mode == "debug":   # DBG menu -> random item drop flying into the bag
		await get_tree().create_timer(0.8).timeout
		hud.debug_hud.toggle()
		_shot_later(0.3, "debug_menu")
		await get_tree().create_timer(0.5).timeout
		hud.debug_hud._run("loot_fly")
		_shot_later(0.9, "debug_drop")
		_shot_later(1.75, "debug_fly")
		await get_tree().create_timer(3.0).timeout
		print("[Debug] inventory=", inventory.size())
		Music.quit()
		return
	if test_mode != "camp":
		return
	for k in [1, 10]:
		dist = mw.arena_s(k) - 4.5
		wave = k
		mw.set_dist(dist)
		_clear_pending()
		_ensure_pending()
		set_process(false)
		for i in 40:
			await get_tree().process_frame
			_camp_tick(1.0 / 40.0 * 3.0)
			_idle_t += 0.075
			_update_camera(0.5)
		_shot_later(0.0, "camp_a")
		for i in 30:
			await get_tree().process_frame
			_camp_tick(0.05)
		_shot_later(0.0, "camp_b")
		await get_tree().create_timer(0.3).timeout
	Music.quit()

## --test=books: skill books of every grade in the bag -> learn / level up / full slots choice -> hero card,
## a slot-levelled loadout, the chest screen with book + 강화석 cards, then the settlement.
func _test_books() -> void:
	var rt := func(t: float) -> Signal: return get_tree().create_timer(t, true, false, true).timeout
	await rt.call(0.6)
	var w := hero("warrior")
	for id in ["ironWall", "vitality", "slamMastery", "earthFury", "ironWall", "ironWall"]:
		var b := Inventory.make_skillbook(1, "warrior")
		b["skill"] = id
		inventory.append(b)
		use_book(b)
	for g in [1, 2, 3, 4]:
		inventory.append(Inventory.make_skillbook(g))
	inventory.append(Inventory.make_skillbook(2, "warrior"))
	hud.refresh_inventory()
	print("[Books] warrior learned=", w.learned, " max_hp=", w.max_hp, " badge=", books_for("warrior"))
	_select(w)
	await rt.call(0.5)
	print("[Books] hero card=", hud.panels.hero_card != null and is_instance_valid(hud.panels.hero_card), " selected=", selected)
	_shot_later(0.0, "books_hero_panel")
	await rt.call(0.5)
	_select(null)
	var extra: Dictionary = inventory.filter(func(x): return x["kind"] == "skillbook" and Inventory.skillbook_def(x)["cls"] == "warrior" and learned_index(w, x["skill"]) < 0)[0]
	use_book(extra)
	_shot_later(0.4, "books_full_choice")
	await rt.call(0.9)
	hud.close_overlays()
	hud.show_tip(inventory.filter(func(x): return x["kind"] == "skillbook")[0])
	_shot_later(0.3, "books_tip")
	await rt.call(0.7)
	hud.close_tip()
	add_stones(7)
	give_chest(3, hud.root.size * 0.5)
	await rt.call(1.0)
	open_chests()
	var g: ChestGacha = hud.overlay
	await rt.call(1.0)
	for i in 4:
		g.tap()
		while g.state != "tap" and g.state != "open":
			await get_tree().process_frame
	g.tap()
	_shot_later(3.2, "books_chest_cards")
	await rt.call(4.0)
	hud.close_overlays()
	await rt.call(0.5)
	give_chest(1)
	phase = P.GAMEOVER
	hud.show_settlement(end_run(false))
	_shot_later(0.9, "books_settlement")
	await rt.call(1.4)
	print("[Books] meta gold=", Meta.gold, " stones=", Meta.stones, " storage=", Meta.storage.size())
	Music.quit()

## --test=shop (use --wave=13): roadside merchant appears, tap opens the shop (same stock on a second tap),
## perk roulette, then a team wipe -> perks gone -> resume from the region's first group.
func _test_shop() -> void:
	var rt := func(t: float) -> Signal: return get_tree().create_timer(t, true, false, true).timeout
	gold = 5000
	hud.set_gold(gold)
	while _merchant.is_empty() or not _merchant["seen"]:
		await get_tree().process_frame
	await rt.call(0.6)
	print("[Shop] merchant k=", _merchant["k"], " wave=", wave, " bubble=", (_merchant["bubble"] as Control).visible)
	_shot_later(0.0, "shop_merchant")
	await rt.call(0.2)
	var tap := cam.unproject_position(_merchant_pos() - Vector3(0, 0.6, 0))
	print("[Shop] hit=", _merchant_hit(tap))
	_press(tap)
	_release(tap)
	await rt.call(0.6)
	var first: Array = hud.merchant_stock().map(func(x): return x["entry"]["key"] if x else "")
	print("[Shop] open=", hud.has_overlay(), " paused=", get_tree().paused, " stock=", first)
	_shot_later(0.0, "shop_open")
	await rt.call(0.2)
	hud.close_overlays()
	await rt.call(0.3)
	open_shop()
	await rt.call(0.3)
	print("[Shop] reopen same stock=", hud.merchant_stock().map(func(x): return x["entry"]["key"] if x else "") == first, " paused=", get_tree().paused)
	hud.close_overlays()
	await rt.call(0.3)
	print("[Shop] closed paused=", get_tree().paused)
	# perk roulette x2
	for i in 2:
		var t0 := Time.get_ticks_msec()
		hud.open_perks()
		_shot_later(0.7, "roulette_spin_%d" % i)
		_shot_later(1.9, "roulette_result_%d" % i)
		while hud.has_overlay():
			await get_tree().process_frame
		print("[Perk] roulette total=", (Time.get_ticks_msec() - t0) / 1000.0, "s")
	print("[Perk] perks=", perks, " max_hp=", heroes.map(func(x): return x.max_hp))
	hud.perk_hud.toggle()
	await rt.call(0.4)
	_shot_later(0.0, "perk_list")
	await rt.call(0.2)
	hud.perk_hud.toggle()
	# wipe out
	while phase != P.BATTLE:
		await get_tree().process_frame
	await rt.call(0.5)
	for h in alive_heroes():
		h.hp = 1.0
		on_hero_down(h)
	revive_used = {"warFinal": true, "secondChance": true}
	for h in alive_heroes():
		h.die()
	await rt.call(1.5)
	print("[Wipe] phase=", phase, " perks=", perks.size(), " lost=", _lost_perks, " max_hp=", heroes.map(func(x): return x.max_hp))
	_shot_later(0.0, "wipe_gameover")
	await rt.call(0.3)
	run_over = false
	resume_region()
	await rt.call(1.4)
	print("[Retry] wave=", wave, " dist=", int(dist), " region=", mw.region_at(dist), " alive=", alive_heroes().size(), " hp=", heroes.map(func(x): return x.hp), " phase=", phase)
	_shot_later(0.0, "retry")
	await rt.call(0.3)
	Music.quit()

## --test=chest: a chest on the road ahead -> the trio grabs it -> badge; then the chest screen with forced taps
## (tier ups, a plain tap, open, card reveal), [다음 상자] into a boss chest, [받기] -> items fly into the bag.
func _test_chest() -> void:
	var rt := func(t: float) -> Signal: return get_tree().create_timer(t, true, false, true).timeout
	print("[Chest] final tier odds=", ChestLoot.odds().map(func(x): return snappedf(x, 0.001)))
	var hist := [0, 0, 0, 0]
	for i in 2000:
		var t := 0
		for j in ChestLoot.TAPS:
			if ChestLoot.roll_up(t):
				t += 1
		hist[t] += 1
	print("[Chest] sim 2000 opens=", hist)
	await rt.call(0.5)
	_spawn_field_chest(dist + 4.2)
	_shot_later(0.25, "chest_field")
	var t0 := _clock
	var grabbed := -1.0
	while chests.is_empty() and _clock - t0 < 8.0:
		await get_tree().process_frame
		if _field_chests.is_empty() and grabbed < 0.0:
			grabbed = _clock
			_shot_later(0.12, "chest_grab")
			_shot_later(0.4, "chest_fly")
			_shot_later(0.7, "chest_fly_b")
	print("[Chest] picked up=", chests, " after ", snappedf(_clock - t0, 0.01), "s")
	await rt.call(0.3)
	give_chest(ChestLoot.BOSS_TIER, hud.root.size * 0.5)
	await rt.call(1.0)
	_shot_later(0.0, "chest_badge")
	await rt.call(0.2)
	open_chests()
	var g: ChestGacha = hud.overlay
	g.force = [true, false, true, true]   # 일반 -> 희귀, miss, -> 영웅, -> 전설
	_shot_later(0.2, "gacha_drop")
	_shot_later(0.85, "gacha_intro")
	await rt.call(1.0)
	for i in 4:
		g.tap()
		if i == 0:
			_shot_later(0.4, "gacha_charge")
			_shot_later(0.62, "gacha_comet")
			_shot_later(0.76, "gacha_flash")
			_shot_later(1.0, "gacha_rare")
		if i == 3:
			_shot_later(1.1, "gacha_legend")
		while g.state != "tap" and g.state != "open":
			await get_tree().process_frame
		print("[Chest] tap ", i, " tier=", g.tier, " state=", g.state)
		await rt.call(0.25)
	_shot_later(0.1, "gacha_ready_open")
	await rt.call(0.3)
	g.tap()
	_shot_later(0.3, "gacha_open_jump")
	_shot_later(0.62, "gacha_open_burst")
	_shot_later(1.15, "gacha_cards_fly")
	while g.state != "result":
		await get_tree().process_frame
	print("[Chest] reward=", g.reward["items"].map(func(x): return x["key"]), " lucky=", g.reward["lucky"], " gold=", g.reward["gold"])
	_shot_later(0.7, "gacha_result")
	await rt.call(1.0)
	var inv0 := inventory.size()
	g._collect(true)   # [다음 상자] -> the boss chest (starts at 희귀)
	_shot_later(0.25, "gacha_next_drop")
	while g.state != "tap":
		await get_tree().process_frame
	print("[Chest] next chest tier=", g.tier, " bag ", inv0, "->", inventory.size(), " left=", chests.size())
	_shot_later(0.1, "gacha_next_intro")
	await rt.call(0.3)
	g.force = [false, false, false, false]
	for i in 4:
		g.tap()
		while g.state != "tap" and g.state != "open":
			await get_tree().process_frame
		await rt.call(0.1)
	g.tap()
	while g.state != "result":
		await get_tree().process_frame
	await rt.call(0.8)
	_shot_later(0.0, "gacha_result_2")
	await rt.call(0.2)
	var gold0 := gold
	var inv1 := inventory.size()
	g._collect(false)   # [받기]
	_shot_later(0.35, "gacha_collect_fly")
	await rt.call(2.0)
	print("[Chest] closed overlay=", hud.has_overlay(), " paused=", get_tree().paused, " bag ", inv1, "->", inventory.size(), " gold ", gold0, "->", gold, " badge=", hud.panels.chest_badge.visible)
	_shot_later(0.0, "gacha_after")
	await rt.call(0.3)
	Music.quit()

## --test=bestiary: line up both creature rosters and both mid-bosses close to the camera (idle, then walking).
func _test_bestiary() -> void:
	set_process(false)
	for h in heroes:
		h.visible = false
	hud.visible = false
	var rows := [["wolf", "hornbunny", "boar", "bear"], ["imp", "eyebat", "mimic", "horror"]]
	var made: Array = []
	for ri in rows.size():
		for i in rows[ri].size():
			var u := Actor.new()
			units_root.add_child(u)
			u.setup(rows[ri][i], Defs.TEAM_ENEMY, self, 1.0)
			u.position = Vector3(-2.25 + i * 1.5, 0, 1.4 - ri * 2.4)
			u.model.rotation.y = PI + 0.3
			made.append(u)
	var look := Vector3(0, 0.4, 0.5)
	cam.set_base(look + Vector3(0, 7.6, 9.8), look)
	await get_tree().create_timer(1.0).timeout
	_shot_later(0.0, "bestiary_idle")
	for u in made:
		u.model.walk = 1.0
	await get_tree().create_timer(0.37).timeout
	_shot_later(0.0, "bestiary_walk")
	await get_tree().create_timer(0.4).timeout
	for u in made:
		u.queue_free()
	for k in ["mammoth", "abyss"]:
		var b := Actor.new()
		units_root.add_child(b)
		b.setup(k, Defs.TEAM_ENEMY, self, 1.0)
		b.position = Vector3(0, 0, 0)
		b.model.rotation.y = PI + 0.5
		var bl := Vector3(0, 1.4, 0)
		cam.set_base(bl + Vector3(0, 4.6, 8.4), bl)
		await get_tree().create_timer(1.0).timeout
		_shot_later(0.0, "boss_" + k)
		b.model.rotation.y = PI - 1.2
		b.model.walk = 1.0
		await get_tree().create_timer(0.5).timeout
		_shot_later(0.0, "boss_" + k + "_side")
		await get_tree().create_timer(0.3).timeout
		b.queue_free()
	await get_tree().create_timer(0.3).timeout
	Music.quit()

## --test=notice: centred gimmick text + toast band (max 2, newest pushes the oldest out).
func _test_notice() -> void:
	await get_tree().create_timer(0.5).timeout
	# fly-to-bag icons: rarity under-glow + one additive flash (direct calls, calm field)
	var fly_keys := ["sword1", "sword2", "ring3", "bow4", "thunderHeart"]
	for i in fly_keys.size():
		print("[Fly] ", fly_keys[i], " rarity=", Inventory.rarity_of(Inventory.make("equip", fly_keys[i])))
		hud.fly_item(Vector2(110 + i * 125, 520), Inventory.make("equip", fly_keys[i]), func(): pass, i)
	_shot_later(0.04, "fly_glow_0")
	_shot_later(0.1, "fly_glow_1")
	_shot_later(0.17, "fly_glow_a")
	_shot_later(0.24, "fly_glow_b")
	_shot_later(0.32, "fly_glow_c")
	_shot_later(0.45, "fly_glow_d")
	await get_tree().create_timer(1.0, true, false, true).timeout
	# gear drag: near-freeze slow motion + camera eases in on the three heroes
	Inventory.add(self, Inventory.make("equip", "sword2"))
	hud.refresh_inventory()
	var rt := func(t: float) -> Signal: return get_tree().create_timer(t, true, false, true).timeout
	_shot_later(0.0, "drag_before")
	await rt.call(0.1)
	hud.panels._begin_drag(inventory.size() - 1)
	await rt.call(0.9)
	print("[Drag] time_scale=", Engine.time_scale, " group_k=", snappedf(cam.group_k, 0.01), " ratio=", snappedf(cam._group_ratio, 0.01))
	print("[Drag] stage=", drag_stage, " dim_drag=", snappedf(world.dim_drag, 0.01), " sun=", snappedf(mw.sun.light_energy, 0.01), " lights=", _drag_lights.size())
	_shot_later(0.0, "drag_zoom")
	await rt.call(0.2)
	hud.panels._drop(Vector2(-500, -500))
	await rt.call(0.9)
	print("[Drag] after drop time_scale=", Engine.time_scale, " group_k=", snappedf(cam.group_k, 0.01))
	# clustered field loot: name plates must not overlap (stack flush, edge to edge)
	var c := Vector3(hero("ranger").global_position.x, 0, -Actor.BOARD_Z + 1.2)
	var keys := ["sword2", "royalDecree", "ring3", "thunderHeart", "helmet2", "bow4"]
	for i in keys.size():
		_give(Inventory.make("equip", keys[i]), c + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.4, 0.4)))
	await get_tree().create_timer(1.6).timeout
	_shot_later(0.0, "loot_tags")
	await get_tree().create_timer(0.2).timeout
	_collect_loot()   # items fly into the bag as bare icons
	_shot_later(0.2, "loot_fly_flash")
	_shot_later(0.35, "loot_fly")
	_shot_later(0.5, "loot_fly_b")
	await get_tree().create_timer(1.2).timeout
	var info: Dictionary = Waves.GIMMICK_INFO["hydra"]
	hud.set_gimmick(info["title"], info["hint"])
	hud.toast("가방이 가득 차서 판매 +120G", Defs.COL_GOLD)
	_shot_later(0.5, "notice_1")
	await get_tree().create_timer(0.7).timeout
	hud.toast("합성! 강철 검", Color("ffd27a"))
	_shot_later(0.5, "notice_2")
	await get_tree().create_timer(0.7).timeout
	hud.toast("시간의 결정 +2", Defs.COL_CRYSTAL)
	print("[Notice] toasts on screen=", hud._toasts.size())
	_shot_later(0.1, "notice_3_push")
	_shot_later(0.5, "notice_3")
	await get_tree().create_timer(3.0).timeout
	print("[Notice] toasts after expiry=", hud._toasts.size())
	_shot_later(0.0, "notice_clear")
	await get_tree().create_timer(0.3).timeout
	Music.quit()

## --test=ui: drag slow motion, equipping mid-battle, face tap -> hero info, auto ultimate staging.
## Item card / hero card open -> march and battle freeze in place; closed -> they pick up again.
func _test_pause() -> void:
	Inventory.add(self, Inventory.make("equip", "sword2"))
	hud.refresh_inventory()
	await get_tree().create_timer(1.0).timeout
	var d0 := dist
	hud.show_tip(inventory[0])
	await get_tree().create_timer(0.6).timeout
	var d1 := dist
	await get_tree().create_timer(0.6).timeout
	print("[Pause] march tip: paused=", get_tree().paused, " moved=", snappedf(dist - d1, 0.001), " (before ", snappedf(d1 - d0, 0.001), ")")
	_shot_later(0.0, "pause_tip")
	await get_tree().create_timer(0.2).timeout
	hud.close_tip()
	await get_tree().create_timer(0.6).timeout
	print("[Pause] tip closed: paused=", get_tree().paused, " moved=", snappedf(dist - d1, 0.001))
	while phase != P.BATTLE:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	hud._on_status_tap("mage")
	await get_tree().process_frame
	var t0 := now
	var hp0 := enemies.map(func(e): return e.hp)
	await get_tree().create_timer(1.0).timeout
	print("[Pause] battle hero card: paused=", get_tree().paused, " now+", snappedf(now - t0, 0.001), " enemy hp same=", hp0 == enemies.map(func(e): return e.hp))
	_shot_later(0.0, "pause_hero")
	await get_tree().create_timer(0.2).timeout
	hud._on_status_tap("mage")
	await get_tree().create_timer(1.0).timeout
	print("[Pause] hero card closed: paused=", get_tree().paused, " now+", snappedf(now - t0, 0.001), " phase=", phase, " cine=", Cinematic.active, " ts=", Engine.time_scale)
	Music.quit()

func _test_ui() -> void:
	Inventory.add(self, Inventory.make("equip", "sword2"))
	hud.refresh_inventory()
	while phase != P.BATTLE:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var e: Dictionary = inventory[inventory.size() - 1]
	hud.panels._begin_drag(inventory.size() - 1)
	print("[UI] dragging: time_scale=", Engine.time_scale)
	set_drag_target(hero("warrior"))
	_shot_later(0.0, "ui_drag_slowmo")
	_shot_later(0.55, "ui_drag_zoom")
	await get_tree().create_timer(0.6, true, false, true).timeout
	hud.panels._drop(cam.unproject_position(hero("warrior").global_position + Vector3(0, 0.4, 0)))
	print("[UI] dropped: time_scale=", Engine.time_scale, " equipped_in_battle=", hero("warrior").equipment["weapon"] == e)
	await get_tree().create_timer(0.4).timeout
	hud._on_status_tap("mage")
	print("[UI] face tap -> panel shows ", hud.hero_shown().cls if hud.hero_shown() else "none")
	_shot_later(0.1, "ui_face_tap")
	await get_tree().create_timer(0.5).timeout
	hud._on_status_tap("mage")
	for h in alive_heroes():
		h.ult_ready_at = 0.0
	_last_auto_ult = -99.0
	await get_tree().create_timer(0.25, true, false, true).timeout
	_shot_later(0.0, "ui_ult_intro")
	await get_tree().create_timer(1.2, true, false, true).timeout
	_shot_later(0.0, "ui_after_ult")
	await get_tree().create_timer(0.5, true, false, true).timeout
	Music.quit()
