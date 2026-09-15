class_name SfxPlayer
extends Node
## Original procedural PCM effects, region music and ambience. No external audio assets.
## Receives presentation cues only; gameplay rules stay outside this node.
## Shutdown may still emit Godot audio ObjectDB warnings; see reports/V02_STAGE3.md.

const MIX_RATE := 22050
const MAX_AMPLITUDE := 0.35

enum Cue { SWING, HIT, BLOCK, DEATH, PICKUP, LEVEL_UP, FOOTSTEP, ARROW, STAB }
static var volumes: Array[float] = [0.8, 0.35, 0.8]
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _last_play: Dictionary = {}

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams: Dictionary = {}

func _ready() -> void:
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "SFX"
	_ambient.volume_db = -18
	add_child(_ambient)
	_apply_volumes()
	## A small pool so overlapping cues do not cut each other off.
	for _i in 4:
		var player := AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_players.append(player)
	_streams[Cue.SWING] = _make_sweep(0.10, 640.0, 240.0, 0.25)
	_streams[Cue.HIT] = _make_sweep(0.12, 300.0, 90.0, 0.40)
	_streams[Cue.BLOCK] = _make_sweep(0.09, 900.0, 500.0, 0.30)
	_streams[Cue.DEATH] = _make_sweep(0.40, 420.0, 60.0, 0.45)
	_streams[Cue.PICKUP] = _make_sweep(0.10, 720.0, 1180.0, 0.30)
	_streams[Cue.LEVEL_UP] = _make_sweep(0.32, 520.0, 1240.0, 0.35)
	_streams[Cue.FOOTSTEP] = _make_noise(0.06, 0.1, 160.0)
	_streams[Cue.ARROW] = _make_noise(0.14, 0.22, 600.0)
	_streams[Cue.STAB] = _make_noise(0.09, 0.22, 420.0)
	_streams[Cue.SWING] = _make_noise(0.18, 0.28, 240.0)
	_streams[Cue.HIT] = _make_noise(0.12, 0.4, 90.0)

func play(cue: Cue) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_play.get(cue, -1000)) < 45: return
	_last_play[cue] = now
	var stream: AudioStreamWAV = _streams.get(cue)
	if stream == null or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.play()

func set_volume(index: int, value: float) -> void:
	volumes[index] = clampf(value, 0, 1)
	_apply_volumes()

func _apply_volumes() -> void:
	for i in 3:
		var index := AudioServer.get_bus_index(["Master", "Music", "SFX"][i])
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, volumes[i])))
			AudioServer.set_bus_mute(index, volumes[i] == 0)

func _wav(samples: PackedByteArray, looped := false) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.data = samples
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples.size() / 2
	return stream

func _put(samples: PackedByteArray, frame: int, sample: float) -> void:
	var value := int(clampf(sample, -1, 1) * 32767)
	samples[frame * 2] = value & 255
	samples[frame * 2 + 1] = (value >> 8) & 255

func _make_noise(seconds: float, gain: float, frequency: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 312
	var bytes := PackedByteArray()
	var count := int(seconds * MIX_RATE)
	bytes.resize(count * 2)
	var filtered := 0.0
	for frame in count:
		var t := float(frame) / MIX_RATE
		filtered = lerpf(filtered, rng.randf_range(-1, 1), 0.35)
		_put(bytes, frame, (filtered * 0.65 + sin(TAU * frequency * t) * 0.35) * gain * pow(1 - t / seconds, 2))
	return _wav(bytes)

func start_region(region: String) -> void:
	# Short original modal melody, plucked harmonics, low drone. Loop boundaries fade to silence.
	var inside := region.begins_with("outpost")
	var forest := region == "forest"
	var count := MIX_RATE * 8
	var music := PackedByteArray()
	var ambience := PackedByteArray()
	music.resize(count * 2)
	ambience.resize(count * 2)
	var notes := [0, 7, 3, 10, 7, 5, 3, 2, 0, 3, 7, 12, 10, 7, 5, 2]
	var base := 110.0 if inside else (146.83 if forest else 196.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 801
	var noise := 0.0
	for frame in count:
		var t := float(frame) / MIX_RATE
		var beat := int(t * 2)
		var age := fmod(t, 0.5)
		var freq := base * pow(2, float(notes[beat % 16]) / 12)
		var env := (1 - exp(-age * 90)) * exp(-age * 7)
		var fade := minf(1, minf(t * 20, (8 - t) * 20))
		var pluck := sin(TAU * freq * t) + 0.25 * sin(TAU * freq * 2 * t)
		var drone := sin(TAU * base * 0.5 * t) * 0.06
		_put(music, frame, (pluck * env * 0.12 + drone) * fade)
		noise = lerpf(noise, rng.randf_range(-1, 1), 0.03)
		var wind := noise * (0.3 + 0.1 * sin(t * TAU / 8))
		if forest and fmod(t, 2) < 0.13:
			wind += sin(TAU * (1600 * t + 800 * t * t)) * 0.06
		_put(ambience, frame, wind * fade)
	_music.stream = _wav(music, true)
	_ambient.stream = _wav(ambience, true)
	_music.play()
	_ambient.play()

func _exit_tree() -> void:
	for player in _players:
		player.stop()
		player.stream = null
	if _music != null:
		_music.stop()
		_music.stream = null
	if _ambient != null:
		_ambient.stop()
		_ambient.stream = null

## A short tone whose frequency slides from `from_hz` to `to_hz`, with a linear fade so the cue
## does not click at either end.
func _make_sweep(duration: float, from_hz: float, to_hz: float, amplitude: float) -> AudioStreamWAV:
	var frames := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var phase := 0.0
	for index in frames:
		var t := float(index) / float(frames)
		var frequency := lerpf(from_hz, to_hz, t)
		phase += TAU * frequency / float(MIX_RATE)
		var envelope := (1.0 - t) * amplitude
		var sample := sin(phase) * envelope
		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data[index * 2] = value & 0xFF
		data[index * 2 + 1] = (value >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = data
	return stream
