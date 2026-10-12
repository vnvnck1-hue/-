extends SceneTree
## Leak probe: runs a scene (default March, autoplay) and prints object/node/resource counts
## every few seconds, so growth over a long session shows up as a rising column.
##   Godot --headless --path . -s res://tools/leak_probe.gd --fixed-fps 60 -- --autoplay [--probe-scene=res://scenes/Main.tscn] [--probe-secs=600]
## Uses the test save (main.gd switches to user://trio_save_test.json under --autoplay).

var _t := 0.0
var _next := 0.0
var _secs := 600.0
var _every := 30.0

func _initialize() -> void:
	var scene := "res://scenes/March.tscn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probe-scene="):
			scene = a.substr(14)
		elif a.begins_with("--probe-secs="):
			_secs = float(a.substr(13))
		elif a.begins_with("--probe-every="):
			_every = float(a.substr(14))
	change_scene_to_file.call_deferred(scene)
	print("[probe] t,objects,nodes,orphans,resources,scene")

func _process(delta: float) -> bool:
	_t += delta
	if _t >= _next:
		_next += _every
		var cs := current_scene
		print("[probe] %d,%d,%d,%d,%d,%s" % [_t,
			Performance.get_monitor(Performance.OBJECT_COUNT),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
			Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
			cs.name if cs else "-"])
	return _t >= _secs
