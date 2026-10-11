extends Node
## BGM player + audio bus mix (autoload "Music"). Survives scene changes; each scene
## asks for its track with Music.play("lobby") etc. and the switch is a crossfade.
## Tracks are synthesized by tools/bgm_synth (seamless loops, EQ-carved around the
## procedural Sfx bands):
##   battle : bgm_main.wav  — synth_bgm.py --game       (120 BPM, 16 bars)
##   lobby  : bgm_lobby.wav — synth_bgm_calm.py --game  (72 BPM, 16 bars)
##   field  : bgm_field.wav — synth_bgm_field.py --game (90 BPM, 16 bars) — endless march
##   gacha  : bgm_gacha.wav — synth_bgm_gacha.py --game (100 BPM, 16 bars) — treasure chest screen
##
## Switching is an equal-power crossfade (no loudness dip in the middle). A track that was
## faded out remembers where it was, so play(track, fade, true) picks it back up there —
## the field march carries on under the chest screen instead of restarting.
##
## Buses (built in code, like everything else here):
##   Music -> Master : volume + sidechain compressor keyed by SFX (ducks under hits)
##   SFX   -> Master : all Sfx players
##   Master          : hard limiter so stacked hits never clip
##
## Player volume (lobby settings panel): one 0..1 slider per channel, applied on top of
## the tuned mix above (1.0 = the mix as designed) and saved to user://audio.cfg.

## name -> [path, track gain dB]. Gains level the files against each other: battle
## sits at ~-28 dBFS in game, the lobby loop ~2 dB softer.
const TRACKS := {
	"battle": ["res://audio/bgm_main.wav", 0.0],
	"lobby": ["res://audio/bgm_lobby.wav", -3.0],
	"field": ["res://audio/bgm_field.wav", 0.0],   # file is 0.7 dB under battle already
	"gacha": ["res://audio/bgm_gacha.wav", -1.0],  # same RMS as field but brighter (celesta/glock)
}
## Measured from an in-game Movie Maker capture (tools/bgm_synth/analyze_recording.py):
## BGM file sits at ~-16 dBFS short-term, busy combat Sfx at ~-20 dBFS. -12 dB keeps the
## music ~8 dB under the hits; Sfx gets 1.5 dB of headroom because 14 voices stack.
const MUSIC_DB := -12.0
const SFX_DB := -1.5
const FIRST_FADE := 1.5
const CROSSFADE := 1.2
## Remembered positions older than this restart the track instead (a whole other scene ago).
const RESUME_MAX_AGE := 120.0
const SETTINGS_PATH := "user://audio.cfg"
## channel -> bus. Order is the settings panel order.
const CHANNELS := {"master": &"Master", "music": &"Music", "sfx": &"SFX"}
const CHANNEL_NAME := {"master": "전체 음량", "music": "배경음악", "sfx": "효과음"}
const BASE_DB := {"master": 0.0, "music": MUSIC_DB, "sfx": SFX_DB}

var current := ""
var _players: Array[AudioStreamPlayer] = []
var _fades := {}          # player -> Tween
var _track_of := {}       # player -> track name it is playing
var _resume := {}         # track -> [playback position s, time it stopped ms]
var _active := 0
var _duck_db := 0.0
var _duck_tw: Tween
var _quitting := false
var volumes := {"master": 1.0, "music": 1.0, "sfx": 1.0}

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_buses()
	_load_volumes()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = &"Music"
		add_child(p)
		_players.append(p)

func _ready() -> void:
	get_tree().auto_accept_quit = false   # window close goes through quit() below

## Switch to a track. The old one fades out while the new one fades in — from its start, or
## with `resume` from where it was last faded out (if that was recent).
func play(track: String, fade := -1.0, resume := false) -> void:
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
	if p.playing and _track_of.get(p, "") == track:
		# quick back-and-forth: this track is still fading out here — turn it around mid-fade
		_fade(p, db_to_linear(TRACKS[track][1]), fade, false)
		return
	if _fades.has(p):
		_fades[p].kill()
		_stop(p)
	var from := 0.0
	if resume and _resume.has(track) and Time.get_ticks_msec() - _resume[track][1] < RESUME_MAX_AGE * 1000.0:
		from = fmod(_resume[track][0], stream.get_length())
	p.stream = stream
	_track_of[p] = track
	p.volume_linear = 0.0
	p.play(from)
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

## Equal-power fade: amplitude follows a quarter sine/cosine, so the outgoing and incoming
## tracks' summed power stays flat through the crossfade — a smooth gradient, no hole.
func _fade(p: AudioStreamPlayer, to: float, time: float, stop_after: bool) -> void:
	if _fades.has(p):
		_fades[p].kill()
	var start := p.volume_linear
	var tw := p.create_tween().set_ignore_time_scale()   # hit-stop slows time_scale
	if to > start:
		tw.tween_method(func(k: float): p.volume_linear = lerpf(start, to, sin(k * PI * 0.5)), 0.0, 1.0, time)
	else:
		tw.tween_method(func(k: float): p.volume_linear = lerpf(to, start, cos(k * PI * 0.5)), 0.0, 1.0, time)
	if stop_after:
		tw.tween_callback(_stop.bind(p))
	_fades[p] = tw

## Stops a player, remembering where its track was for a later play(track, fade, true).
func _stop(p: AudioStreamPlayer) -> void:
	if p.playing and _track_of.has(p):
		_resume[_track_of[p]] = [p.get_playback_position(), Time.get_ticks_msec()]
	_fades.erase(p)
	_track_of.erase(p)
	p.stop()
	p.stream = null

func _build_buses() -> void:
	var music := _ensure_bus(&"Music")
	var sfx := _ensure_bus(&"SFX")
	AudioServer.set_bus_volume_db(music, MUSIC_DB)   # _load_volumes() then layers the player volume on
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
	_apply_volume("music")

# ---------------------------------------------------------------- player volume
## Set a channel's volume (0..1). Applies right away; call save_volumes() to persist.
func set_volume(ch: String, v: float) -> void:
	if not volumes.has(ch):
		return
	volumes[ch] = clampf(v, 0.0, 1.0)
	_apply_volume(ch)

func get_volume(ch: String) -> float:
	return volumes.get(ch, 1.0)

func save_volumes() -> void:
	var cf := ConfigFile.new()
	for ch in volumes:
		cf.set_value("volume", ch, volumes[ch])
	cf.save(SETTINGS_PATH)

func _load_volumes() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		for ch in volumes:
			volumes[ch] = clampf(float(cf.get_value("volume", ch, 1.0)), 0.0, 1.0)
	for ch in volumes:
		_apply_volume(ch)

## Slider -> dB on a squared curve (50% ≈ -12 dB) so the low half of the slider is
## still usable; 0 mutes the bus outright.
func _apply_volume(ch: String) -> void:
	var idx := AudioServer.get_bus_index(CHANNELS[ch])
	if idx == -1:
		return
	var v: float = volumes[ch]
	var db: float = BASE_DB[ch] + (_duck_db if ch == "music" else 0.0)
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, db + linear_to_db(maxf(v * v, 0.0001)))
