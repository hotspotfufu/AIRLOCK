class_name Atmosphere
extends Node
## Station air (host simulates, everyone reads the result from StationState).
##
## Why the air goes bad: the second asteroid wrecked the ventilation, so air
## is no longer circulated through the scrubbers. Oxygen slowly falls and
## carbon dioxide builds up until someone restarts circulation ("vents").
## Below 16 % oxygen or above 3 % CO2 the air is not breathable: helmets seal
## and astronauts live on suit oxygen (see Astronaut._simulate_vitals).
##
## Keys written: atm.o2 (%), atm.co2 (%), atm.pressure (kPa).

@export var start_o2 := 19.6
@export var start_co2 := 0.5
@export var o2_loss_per_min := 0.33
@export var co2_gain_per_min := 0.24
@export var recovery_per_min := 2.1

var station: StationState
var _o2 := 19.6
var _co2 := 0.5
var _tick := 0.0
var _warned_thin := false
var _warned_bad := false


func _ready() -> void:
	station = Level.instance.station if Level.instance != null else null
	_o2 = start_o2
	_co2 = start_co2
	set_physics_process(multiplayer.is_server() and station != null)
	if multiplayer.is_server() and station != null:
		_publish()


func _physics_process(delta: float) -> void:
	_tick += delta
	if _tick < 1.0:
		return
	_tick -= 1.0
	if station.is_true("vents"):
		_o2 = move_toward(_o2, 20.9, recovery_per_min / 60.0)
		_co2 = move_toward(_co2, 0.04, recovery_per_min * 0.5 / 60.0)
	else:
		_o2 = maxf(8.0, _o2 - o2_loss_per_min / 60.0)
		_co2 = minf(8.0, _co2 + co2_gain_per_min / 60.0)
	_publish()
	var level := Level.instance
	if not _warned_thin and _o2 < 17.5:
		_warned_thin = true
		level.announce("Warning: oxygen is getting thin. Restart air circulation.")
	if not _warned_bad and (_o2 < 16.0 or _co2 >= 3.0):
		_warned_bad = true
		level.announce("Air is no longer breathable. Helmets sealed: you are on suit oxygen.")
	if _warned_bad and _o2 >= 16.5 and _co2 < 2.5:
		_warned_bad = false
		_warned_thin = false
		level.announce("Air is breathable again.")


func _publish() -> void:
	station.set_value("atm.o2", snappedf(_o2, 0.01))
	station.set_value("atm.co2", snappedf(_co2, 0.01))
	station.set_value("atm.pressure", 101.0)
