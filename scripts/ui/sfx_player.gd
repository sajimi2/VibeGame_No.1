class_name SfxPlayer
extends Node
## Placeholder sound effects, generated as raw PCM at runtime. No external asset is used, so there
## is nothing to license and nothing to ship alongside the project (T06 asks for "necessary
## sound"; the art/audio pass proper is T06's later half, and this keeps it procedural until real
## assets exist).
##
## It only plays sounds it is told to play: game rules never live here.
##
## Known engine-side warning: once any cue has been played, quitting the process makes Godot report
## "2 ObjectDB instances were leaked at exit" (an AudioStreamWAV plus its AudioStreamPlaybackWAV,
## both at reference count 1). It was reproduced with nothing but this class playing a single cue,
## and it survives stopping the player, clearing its stream and freeing the node before shutdown, so
## it is the audio layer retaining the playback rather than a dangling reference here. It is a
## shutdown-only message with no effect on a session; level startup deliberately plays no cue so the
## headless startup check stays clean.

const MIX_RATE := 22050
const MAX_AMPLITUDE := 0.35

enum Cue { SWING, HIT, BLOCK, DEATH, PICKUP, LEVEL_UP }

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams: Dictionary = {}

func _ready() -> void:
	## A small pool so overlapping cues do not cut each other off.
	for _i in 4:
		var player := AudioStreamPlayer.new()
		player.bus = &"Master"
		add_child(player)
		_players.append(player)
	_streams[Cue.SWING] = _make_sweep(0.10, 640.0, 240.0, 0.25)
	_streams[Cue.HIT] = _make_sweep(0.12, 300.0, 90.0, 0.40)
	_streams[Cue.BLOCK] = _make_sweep(0.09, 900.0, 500.0, 0.30)
	_streams[Cue.DEATH] = _make_sweep(0.40, 420.0, 60.0, 0.45)
	_streams[Cue.PICKUP] = _make_sweep(0.10, 720.0, 1180.0, 0.30)
	_streams[Cue.LEVEL_UP] = _make_sweep(0.32, 520.0, 1240.0, 0.35)

func play(cue: Cue) -> void:
	var stream: AudioStreamWAV = _streams.get(cue)
	if stream == null or _players.is_empty():
		return
	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.play()

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
