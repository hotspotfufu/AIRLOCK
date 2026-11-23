class_name LightingController
extends Node3D
## Station lighting. Two sets of lights live under this node:
##   Main       normal white lighting, only on when main power is on
##   Emergency  red emergency lighting, on while power is out (some flicker)
## It also darkens the glowing lamp fittings inside the purchased models
## while power is out, and can make every light stutter for a moment
## (used for scripted scares and when power comes back).

## Model nodes to search for lamp fittings (comma-separated paths).
@export var model_roots := ""
const LAMP_PREFIXES: Array[String] = ["lights", "SM_Lamp", "SM_SphereLamp"]

var station: StationState
var _main: Array[Light3D] = []
var _emergency: Array[Light3D] = []
var _base: Dictionary = {}
var _lamp_meshes: Array[MeshInstance3D] = []
var _dark := StandardMaterial3D.new()
var _powered := false
var _burst := 0.0
var _startup := 0.0
var _time := 0.0


func _ready() -> void:
	station = Level.instance.station if Level.instance != null else null
	for l: Light3D in get_node("Main").find_children("*", "Light3D", true, false):
		_main.append(l)
		_base[l] = l.light_energy
	for l: Light3D in get_node("Emergency").find_children("*", "Light3D", true, false):
		_emergency.append(l)
		_base[l] = l.light_energy
	_dark.albedo_color = Color(0.03, 0.03, 0.035)
	_dark.roughness = 0.6
	for path in model_roots.split(",", false):
		var root := get_node_or_null(NodePath(path.strip_edges()))
		if root == null:
			continue
		for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
			for prefix in LAMP_PREFIXES:
				if String(mi.name).begins_with(prefix):
					_lamp_meshes.append(mi)
					break
	if station != null:
		station.changed.connect(_on_state_changed)
		_powered = station.is_true("power")
	_apply_lamps()


func _on_state_changed(key: String, value: Variant) -> void:
	if key == "power":
		_powered = value == true
		if _powered:
			_startup = 1.6  # lights stutter on
			Sfx.play_ui("power_up", -2.0)
		_apply_lamps()


## Every light stutters for `seconds` (all players; called via the level).
func flicker_burst(seconds: float) -> void:
	_burst = maxf(_burst, seconds)


func _apply_lamps() -> void:
	for mi in _lamp_meshes:
		if is_instance_valid(mi):
			mi.material_override = null if _powered else _dark


func _process(delta: float) -> void:
	_time += delta
	_burst = maxf(0.0, _burst - delta)
	_startup = maxf(0.0, _startup - delta)
	var stutter := 1.0
	if _burst > 0.0 or _startup > 0.0:
		stutter = 1.0 if randf() > 0.45 else 0.08
	for l in _main:
		l.visible = _powered
		if _powered:
			l.light_energy = _base[l] * stutter
	for l in _emergency:
		l.visible = not _powered
		if not _powered:
			var e: float = _base[l] * (0.8 + 0.2 * sin(_time * 1.7 + l.position.x))
			if l.has_meta("flicker"):
				e *= 1.0 if randf() > 0.12 else 0.1
			l.light_energy = e * stutter
