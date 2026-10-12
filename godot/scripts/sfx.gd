class_name Sfx
extends Node
## Tiny procedural sound synth — no audio assets needed.

static var inst: Sfx
static var _synth := {}   # name -> AudioStreamWAV, synthesized once per session (every scene makes an Sfx)
const RATE := 22050
var streams := {}
var players: Array[AudioStreamPlayer] = []
var _next := 0

func _ready() -> void:
	inst = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"   # bus built by the Music autoload
		add_child(p)
		players.append(p)
	if _synth.is_empty():
		_synthesize()
	streams = _synth

func _exit_tree() -> void:
	if inst == self:
		inst = null   # the next scene's Sfx takes over; play() is a no-op in between

func _synthesize() -> void:
	_synth["pop"] = _make(0.14, func(t: float, _i: int) -> float:
		var f := 520.0 + 900.0 * exp(-t * 30.0)
		return sin(TAU * f * t) * exp(-t * 28.0))
	_synth["thud"] = _make(0.16, func(t: float, _i: int) -> float:
		var f := 150.0 * exp(-t * 8.0) + 60.0
		return (sin(TAU * f * t) * 0.9 + (randf() * 2.0 - 1.0) * 0.4 * exp(-t * 60.0)) * exp(-t * 20.0))
	_synth["whoosh"] = _make(0.2, func(t: float, _i: int) -> float:
		var env := sin(PI * t / 0.2)
		return (randf() * 2.0 - 1.0) * env * 0.35)
	_synth["boom"] = _make(0.5, func(t: float, _i: int) -> float:
		var f := 90.0 * exp(-t * 4.0) + 35.0
		return (sin(TAU * f * t) * 0.8 + (randf() * 2.0 - 1.0) * 0.5 * exp(-t * 9.0)) * exp(-t * 6.0))
	_synth["poof"] = _make(0.3, func(t: float, _i: int) -> float:
		return (randf() * 2.0 - 1.0) * 0.45 * exp(-t * 12.0) + sin(TAU * (300.0 + 400.0 * t) * t) * 0.2 * exp(-t * 14.0))
	_synth["chime"] = _make(0.6, func(t: float, _i: int) -> float:
		var n := 880.0 if t < 0.1 else (1108.7 if t < 0.2 else 1318.5)
		return (sin(TAU * n * t) * 0.5 + sin(TAU * n * 2.0 * t) * 0.15) * exp(-fmod(t, 0.1) * 6.0) * exp(-t * 2.5))
	_synth["tick"] = _make(0.05, func(t: float, _i: int) -> float:
		return sin(TAU * 1500.0 * t) * exp(-t * 90.0) * 0.6)
	_synth["clash"] = _make(0.7, func(t: float, _i: int) -> float:
		var f := 220.0 + 40.0 * sin(t * 30.0)
		return (sin(TAU * f * t) * 0.4 + sin(TAU * f * 1.5 * t) * 0.3 + (randf() * 2.0 - 1.0) * 0.3 * exp(-t * 10.0)) * exp(-t * 3.5))
	_synth["fanfare"] = _make(1.3, func(t: float, _i: int) -> float:
		var notes := [523.25, 659.25, 783.99, 1046.5]
		var idx := mini(int(t / 0.16), 3)
		var n: float = notes[idx]
		var lt := t - idx * 0.16
		var env := exp(-lt * (3.0 if idx < 3 else 1.4))
		return (sin(TAU * n * t) * 0.45 + sin(TAU * n * 2.0 * t) * 0.12 + sin(TAU * n * 0.5 * t) * 0.15) * env)
	_synth["sad"] = _make(1.0, func(t: float, _i: int) -> float:
		var n := 392.0 if t < 0.3 else (349.2 if t < 0.6 else 311.1)
		return sin(TAU * n * t) * 0.4 * exp(-fmod(t, 0.3) * 3.0))
	_synth["click"] = _make(0.06, func(t: float, _i: int) -> float:
		return sin(TAU * 900.0 * t) * exp(-t * 60.0) * 0.5)
	# chest gacha: rising charge-up sweep, and a cluster of glassy twinkles
	_synth["rise"] = _make(0.65, func(t: float, _i: int) -> float:
		var f := 260.0 + 900.0 * t * t
		var env := minf(1.0, t * 5.0) * (1.0 - smoothstep(0.55, 0.65, t))
		return (sin(TAU * f * t) * 0.32 + sin(TAU * f * 2.01 * t) * 0.12 + (randf() * 2.0 - 1.0) * 0.12 * t) * env)
	_synth["sparkle"] = _make(0.6, func(t: float, _i: int) -> float:
		var v := 0.0
		for k in 5:
			var lt := t - k * 0.07
			if lt >= 0.0:
				v += sin(TAU * (2100.0 + k * 380.0) * lt) * exp(-lt * 16.0) * 0.26
		return v)

func _make(dur: float, fn: Callable) -> AudioStreamWAV:
	var n := int(dur * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var v: float = clampf(fn.call(t, i), -1.0, 1.0)
		# tiny fade in/out to avoid clicks
		v *= minf(1.0, i / 40.0) * minf(1.0, (n - i) / 80.0)
		data.encode_s16(i * 2, int(v * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

static func play(name: String, vol_db := -6.0, pitch := 1.0) -> void:
	if not is_instance_valid(inst) or not inst.streams.has(name):
		return
	var p := inst.players[inst._next]
	inst._next = (inst._next + 1) % inst.players.size()
	p.stream = inst.streams[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()
