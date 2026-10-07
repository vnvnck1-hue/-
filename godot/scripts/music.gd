extends Node
## BGM player + audio bus mix (autoload "Music"). Survives scene changes; each scene
## asks for its track with Music.play("lobby") etc. and the switch is a crossfade.
## Tracks are synthesized by tools/bgm_synth (seamless loops, EQ-carved around the
## procedural Sfx bands):
##   battle : bgm_main.wav  — synth_bgm.py --game       (120 BPM, 16 bars)
##   lobby  : bgm_lobby.wav — synth_bgm_calm.py --game  (72 BPM, 16 bars)
##   field  : bgm_field.wav — synth_bgm_field.py --game (90 BPM, 16 bars) — endless march
##
## Buses (built in code, like everything else here):
##   Music -> Master : volume + sidechain compressor keyed by SFX (ducks under hits)
##   SFX   -> Master : all Sfx players
##   Master          : hard limiter so stacked hits never clip

## name -> [path, track gain dB]. Gains level the files against each other: battle
## sits at ~-28 dBFS in game, the lobby loop ~2 dB softer.
const TRACKS := {
	"battle": ["res://audio/bgm_main.wav", 0.0],
	"lobby": ["res://audio/bgm_lobby.wav", -3.0],
	"field": ["res://audio/bgm_field.wav", 0.0],   # file is 0.7 dB under battle already
}
## Measured from an in-game Movie Maker capture (tools/bgm_synth/analyze_recording.py):
## BGM file sits at ~-16 dBFS short-term, busy combat Sfx at ~-20 dBFS. -12 dB keeps the
## music ~8 dB under the hits; Sfx gets 1.5 dB of headroom because 14 voices stack.
const MUSIC_DB := -12.0
const SFX_DB := -1.5
const FIRST_FADE := 1.5
const CROSSFADE := 1.2

var current := ""
var _players: Array[AudioStreamPlayer] = []
var _fades := {}          # player -> Tween
var _active := 0
var _duck_db := 0.0
var _duck_tw: Tween
var _quitting := false

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		add_child(p)
		_players.append(p)

func _ready() -> void:
	get_tree().auto_accept_quit = false   # window close goes through quit() below

## Switch to a track. The old one fades out while the new one fades in from its start.
func play(track: String, fade := -1.0) -> void:
	if track == current or not TRACKS.has(track) or _quitting:
		return
	var stream := _load(TRACKS[track][0])
	if stream == null:
		return
	if fade < 0.0:
		fade = FIRST_FADE if current == "" else CROSSFADE
	current = track
	var old := _players[_active]
	_active = 1 - _active
	var p := _players[_active]
	if old.stream != null:
		_fade(old, 0.0, fade, true)
	p.stream = stream
	p.volume_linear = 0.0
	p.play()
	_fade(p, db_to_linear(TRACKS[track][1]), fade, false)

func _load(path: String) -> AudioStreamWAV:
	var s := load(path) as AudioStreamWAV
	if s == null:
		push_warning("Music: missing " + path)
		return null
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = int(round(s.get_length() * s.mix_rate))
	return s

func _fade(p: AudioStreamPlayer, to: float, time: float, stop_after: bool) -> void:
	if _fades.has(p):
		_fades[p].kill()
	var tw := p.create_tween().set_ignore_time_scale()   # hit-stop slows time_scale
	tw.tween_property(p, "volume_linear", to, time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if stop_after:
		tw.tween_callback(func():
			p.stop()
			p.stream = null)
	_fades[p] = tw

func _build_buses() -> void:
	var music := _ensure_bus(&"Music")
	var sfx := _ensure_bus(&"SFX")
	AudioServer.set_bus_volume_db(music, MUSIC_DB)
	AudioServer.set_bus_volume_db(sfx, SFX_DB)

	# Light ducking: combat Sfx are near-continuous, so only real hits (thud/boom/
	# clash/chime peaks) cross the threshold and dip the music 2-4 dB for ~0.3 s.
	var duck := AudioEffectCompressor.new()
	duck.sidechain = &"SFX"
	duck.threshold = -14.0
	duck.ratio = 2.0
	duck.attack_us = 8000.0
	duck.release_ms = 320.0
	duck.gain = 0.0
	AudioServer.add_bus_effect(music, duck)

	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.0   # the limiter lets single-sample spikes ~0.5 dB through
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(0, lim)

## Quit the game. Godot frees a stopped playback only after the audio thread has
## processed the stop and a later main-thread frame runs, so quitting right away
## leaks the looping stream — stop first, give the audio thread ~0.12 s, then quit.
func quit() -> void:
	if _quitting:
		return
	_quitting = true
	for p in _players:
		p.stop()
		p.stream = null
	await get_tree().create_timer(0.12, true, false, true).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()

## AudioServer outlives the scene tree; drop our effects on exit.
func _exit_tree() -> void:
	for bus in [&"Music", &"Master"]:
		var idx := AudioServer.get_bus_index(bus)
		for e in range(AudioServer.get_bus_effect_count(idx) - 1, -1, -1):
			AudioServer.remove_bus_effect(idx, e)

func _ensure_bus(bus_name: StringName) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"Master")
	return idx

## Temporarily pull the music down (e.g. under a jingle), then ease back.
## Works on the Music bus, so it composes with crossfades.
func duck(db: float, hold: float, release := 1.5) -> void:
	if _duck_tw:
		_duck_tw.kill()
	_duck_tw = create_tween().set_ignore_time_scale()
	_duck_tw.tween_method(_set_duck, _duck_db, db, 0.25)
	_duck_tw.tween_interval(hold)
	_duck_tw.tween_method(_set_duck, db, 0.0, release) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_duck(db: float) -> void:
	_duck_db = db
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Music"), MUSIC_DB + db)
