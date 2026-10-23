extends SceneTree
## Headless check of the toy-camp lobby's wiring on a throwaway save: every view signal opens the right existing
## screen, nothing else opens on top of it, closing reloads the lobby quietly with fresh values, chapter arrows stop
## at both ends, the start / endless buttons leave exactly once with the right flags, and settings / screens block
## the start button.
##   Godot --headless --path . -s res://tools/lobby_probe.gd

const PROBE := "user://trio_save_lobby_probe.json"
var ok := true

func _initialize() -> void:
	Meta.path = PROBE
	for p in [Meta.path, Meta.path + Meta.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	Meta.load_save()
	Meta.gold = 4321
	Meta.stones = 55
	Meta.crystals = 7
	Meta.cleared = 2
	Meta.chapter = 1
	Meta.camp_since = Meta._now() - 3 * 3600
	Meta.save()
	_run.call_deferred()

func _check(what: String, cond: bool) -> void:
	print("[Lobby] ", "ok   " if cond else "FAIL ", what)
	ok = ok and cond

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _wait(sec: float) -> void:
	await create_timer(sec).timeout

func _lobby() -> Node:
	return current_scene

func _run() -> void:
	change_scene_to_file("res://scenes/Lobby.tscn")
	await _wait(1.2)
	var lb := _lobby()
	_check("lobby built: stage + view", lb.stage != null and lb.view != null)
	_check("the day's attendance opens by itself", lb._daily is AttendScreen)
	lb._daily.close()
	await _wait(0.6)
	lb = _lobby()
	_check("closing reloads quietly (fresh lobby, no screen)", lb._daily == null and lb.view != null)
	var v: LobbyView = lb.view
	_check("currencies come from Meta", v._vals["gold"].text == "4,321" and v._vals["stones"].text == "55" and v._vals["crystals"].text == "7")
	_check("chapter row shows Meta's chapter", v._chapter.text == Meta.chapter_name(1) and v._objective.text == "클리어 완료")
	_check("reward pill: 3h pile is ready, dot on", v._reward_label.text == "보상 받기" and v._reward_dot.visible)
	_check("number format", LobbyView.fmt(0) == "0" and LobbyView.fmt(47769) == "47,769" and LobbyView.fmt(999999) == "999,999" and LobbyView.fmt(1234567) == "1.23M" and LobbyView.fmt(123456789) == "123.5M")

	# chapter arrows: 0..cleared, ends disabled
	v.chapter_step_requested.emit(1)
	_check("next chapter -> 2 (last open)", Meta.chapter == 2 and v._next.disabled and not v._prev.disabled and v._objective.text == "%d무리 돌파" % Regions.PER_REGION)
	v.chapter_step_requested.emit(1)
	_check("can't pass the last open chapter", Meta.chapter == 2)
	v.chapter_step_requested.emit(-1)
	v.chapter_step_requested.emit(-1)
	v.chapter_step_requested.emit(-1)
	_check("first chapter: left arrow off", Meta.chapter == 0 and v._prev.disabled and not v._next.disabled)
	v._next.pressed.emit()
	_check("arrow button press steps the chapter", Meta.chapter == 1)
	v._prev.disabled = true
	v._prev.pressed.emit()
	_check("a disabled arrow does nothing", Meta.chapter == 1)
	v.refresh(lb._snapshot())

	# every screen: opens, blocks the rest, closes back to a quiet lobby
	var cases := [["equipment_requested", "_gear", GearScreen], ["relics_requested", "_relic", RelicScreen],
		["reward_requested", "_daily", CampScreen], ["challenge_requested", "_daily", RaidScreen],
		["growth_requested", "_daily", TalentScreen], ["mission_requested", "_daily", MissionScreen],
		["attendance_requested", "_daily", AttendScreen]]
	for c in cases:
		lb = _lobby()
		v = lb.view
		v.emit_signal(c[0])
		await _frames(2)
		var scr: Control = lb.get(c[1])
		_check("%s opens %s" % [c[0], c[2].get_global_name()], scr != null and is_instance_of(scr, c[2]))
		_check("  view is blocked while it is open", v.blocked)
		v.emit_signal("settings_requested")
		v.emit_signal("expedition_requested")
		await _frames(2)
		_check("  nothing else opens / no departure behind it", lb._settings == null and not lb._leaving)
		if scr:
			scr.close()
		await _wait(0.6)
		_check("  closed -> quiet reload", _lobby() != lb and _lobby()._gear == null and _lobby()._relic == null and _lobby()._daily == null)

	# 캠프 tab = home: no screen
	lb = _lobby()
	lb.view.camp_requested.emit()
	await _frames(3)
	_check("캠프 tab opens nothing", lb._gear == null and lb._relic == null and lb._daily == null and lb._settings == null)

	# settings blocks the start button, closes cleanly
	lb.view.settings_requested.emit()
	await _frames(2)
	_check("settings opens", lb._settings != null)
	lb._go("march", true)
	_check("settings open: _go refuses", not lb._leaving)
	lb._close_settings()
	await _wait(0.4)
	_check("settings closed", lb._settings == null and not lb.view.blocked)

	# start: exactly one departure with the expedition flag, even when tapped twice
	var runs := Meta.mission_progress("run")
	Meta.expedition = false
	lb.view.expedition_requested.emit()
	lb.view.expedition_requested.emit()
	_check("start: leaving once, expedition on", lb._leaving and Meta.expedition and Meta.mission_progress("run") == mini(runs + 1, _goal("run")))
	await _wait(0.8)
	_check("start: March scene", current_scene != null and current_scene.scene_file_path == "res://scenes/March.tscn")

	# endless: back to the lobby, then the endless link leaves without the expedition flag
	change_scene_to_file("res://scenes/Lobby.tscn")
	await _wait(1.0)
	lb = _lobby()
	lb.view.endless_requested.emit()
	_check("endless: leaving, expedition off", lb._leaving and not Meta.expedition and Meta.raid == "")
	await _wait(0.6)

	print("[Lobby] ", "ALL OK" if ok else "FAILED")
	for p in [PROBE, PROBE + Meta.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	quit(0 if ok else 1)

func _goal(id: String) -> int:
	for m in Meta.DAILY:
		if m["id"] == id:
			return int(m["goal"])
	return 999
