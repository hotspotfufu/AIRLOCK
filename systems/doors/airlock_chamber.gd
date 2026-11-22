class_name AirlockChamber
extends Node3D
## A working airlock: an inner door, an outer door and the space between.
## The two doors are never open together. Pressing E on either door (or on
## the console inside) runs a cycle: close whatever is open, wait while the
## chamber pumps down or refills, then open the other side.
## Runs on its own emergency battery, so it works without main power.

@export var chamber_id := "tunnel"
@export var inner: NodePath
@export var outer: NodePath
@export var cycle_seconds := 3.5

var station: StationState
var _inner: AirlockDoor
var _outer: AirlockDoor
var _light: OmniLight3D
var _spin := 0.0


func _ready() -> void:
	add_to_group("airlock_chambers")
	_inner = get_node_or_null(inner) as AirlockDoor
	_outer = get_node_or_null(outer) as AirlockDoor
	station = Level.instance.station if Level.instance != null else null
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.25, 0.05)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 2.6, 0)
	add_child(_light)


func owns(door: AirlockDoor) -> bool:
	return door == _inner or door == _outer


func is_busy() -> bool:
	return station != null and station.is_true("airlock.%s.busy" % chamber_id)


func get_door_prompt(door: AirlockDoor) -> String:
	if door.is_open():
		return "Close airlock door"
	var other := _outer if door == _inner else _inner
	return "Cycle airlock" if other.is_open() else "Open airlock door"


## Host: a crew member pressed E on one of the two doors.
func door_pressed(door: AirlockDoor) -> void:
	if is_busy() or not multiplayer.is_server():
		return
	var other := _outer if door == _inner else _inner
	if door.is_open():
		door.set_open(false)
	elif other.is_open():
		_cycle(door, other)
	else:
		door.set_open(true)


func _cycle(to_open: AirlockDoor, to_close: AirlockDoor) -> void:
	station.set_value("airlock.%s.busy" % chamber_id, true)
	to_close.set_open(false)
	Sfx.play_at("hiss", global_position)
	await get_tree().create_timer(cycle_seconds).timeout
	if not is_instance_valid(self):
		return
	to_open.set_open(true)
	station.set_value("airlock.%s.busy" % chamber_id, false)


func _process(delta: float) -> void:
	# Warning beacon pulses while the chamber is cycling.
	if is_busy():
		_spin += delta * 7.0
		_light.light_energy = 1.2 + sin(_spin) * 1.0
	else:
		_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 3.0)
