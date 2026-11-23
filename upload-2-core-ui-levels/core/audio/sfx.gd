extends Node
## Sfx (autoload): plays short sounds by name, in 3D or flat (UI).
## Sounds live in assets/audio/sfx/<name>.wav. A missing file is simply
## silent, so game code never has to check. The current sounds are
## synthesised placeholders (tools/make_audio.py) until real recordings exist.

const DIR := "res://assets/audio/sfx/"
const NAMES := ["step", "click", "door", "alarm", "confirm", "deny", "glass", "lever",
	"power_up", "hiss", "skitter", "pickup", "hurt", "breath"]

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _ui: AudioStreamPlayer


func _ready() -> void:
	for n: String in NAMES:
		var path := DIR + n + ".wav"
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in 12:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 4.0
		p.max_distance = 45.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool.append(p)
	_ui = AudioStreamPlayer.new()
	add_child(_ui)


func has_sound(sound: String) -> bool:
	return _streams.has(sound)


func get_stream(sound: String) -> AudioStream:
	return _streams.get(sound)


func play_at(sound: String, where: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sound]
	p.global_position = where
	p.volume_db = volume_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


func play_ui(sound: String, volume_db := -6.0) -> void:
	if not _streams.has(sound):
		return
	_ui.stream = _streams[sound]
	_ui.volume_db = volume_db
	_ui.play()
