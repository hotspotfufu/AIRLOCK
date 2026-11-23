extends Level
## STATION, Level 1: "Restore Power".
##
## The crew wake in the medical bay after the impacts. Power is out, the air
## is slowly going bad, and something is moving in the corridors.
##   1. Get out of the medical bay (door has no power: emergency release).
##   2. Find the two power cells (their hiding places change every run) and
##      fit them to the generator in Engineering.
##   3. Two crew hold the two main breakers together -> main power.
##   4. Restart air circulation at Life Support.
##   5. Restore communications in the Control Room -> level complete.
##   Optional: go through the service tunnel airlock (zero-g, no air) and
##   inspect the sealed impact-zone bulkhead.
##
## This script only holds the rules of this level. The parts it drives
## (doors, breakers, consoles, lights, air) are separate reusable systems
## that all talk through StationState.

const CELL_COUNT := 2

var _breaker_progress := 0.0
var _assist_bot: BotBrain = null
var _elapsed := 0.0
var _fail_check := 0.0
var _failing := false
var _alarm_timer := 3.0
var _fans: Array[Node3D] = []
var _fan_axes: Array[Vector3] = []
var _fan_speed := 0.0

@onready var lighting: LightingController = $Lighting
@onready var swarm: SwarmDirector = $SwarmDirector


func _ready() -> void:
	super._ready()
	station.changed.connect(_on_state_changed)
	# Ventilation fans in the junction model spin once circulation is back.
	var junction := get_node_or_null("Geometry/Junction")
	if junction != null:
		for mi: MeshInstance3D in junction.find_children("fan_*", "MeshInstance3D", true, false):
			var s := mi.get_aabb().size
			var axis := Vector3.RIGHT
			if s.y <= s.x and s.y <= s.z:
				axis = Vector3.UP
			elif s.z <= s.x and s.z <= s.y:
				axis = Vector3.BACK
			_fans.append(mi)
			_fan_axes.append(axis)
	# Background hum removed: players heard it as static.


func _level_started() -> void:
	# Host: hide the power cells in two of the possible spots (different each run).
	var spots := get_node("CellSpots").get_children()
	spots.shuffle()
	var i := 0
	for cell: PowerCell in get_tree().get_nodes_in_group("power_cells"):
		var spot := spots[i % spots.size()] as Node3D
		station.set_value(cell.key(), {"s": "world", "p": spot.global_position})
		i += 1
	for key: String in ["power", "vents", "comms", "generator.fueled", "complete"]:
		station.set_value(key, false)
	for zone: Zone in get_node("Triggers").get_children():
		zone.entered_first_time.connect(_on_trigger.bind(String(zone.name)))
	_intro()


func _intro() -> void:
	await get_tree().create_timer(2.5).timeout
	announce("Main power is out. Emergency lighting only.")
	await get_tree().create_timer(5.0).timeout
	var bots := get_bots()
	if not bots.is_empty():
		radio(bots[0], "Door's dead. There should be an emergency release beside it.")


# --- Objectives (same on every machine: worked out from StationState) ------------

## Lines for the HUD: [{text, done, optional}]
func get_objectives() -> Array[Dictionary]:
	var s := station
	var list: Array[Dictionary] = []
	var exited := s.is_true("obj.exit")
	list.append({"text": "Leave the medical bay (emergency release beside the door)", "done": exited})
	if not exited:
		return list
	var installed := 0
	for i in CELL_COUNT:
		if s.is_true("socket.%d" % i):
			installed += 1
	var fueled := s.is_true("generator.fueled")
	list.append({"text": "Find 2 power cells and fit them to the generator in Engineering (%d/%d)" % [installed, CELL_COUNT], "done": fueled})
	if not fueled:
		return list
	var power := s.is_true("power")
	list.append({"text": "Two crew: hold both main breakers at the same time", "done": power})
	if not power:
		return list
	list.append({"text": "Restart air circulation at Life Support (Engineering)", "done": s.is_true("vents")})
	list.append({"text": "Restore communications in the Control Room (past the medical bay)", "done": s.is_true("comms")})
	list.append({"text": "Optional: inspect the impact-zone bulkhead (service tunnel airlock: zero-g, no air)",
		"done": s.is_true("tunnel.inspected"), "optional": true})
	return list


func get_breaker_progress() -> float:
	return float(station.get_value("breaker.progress", 0.0))


# --- Host rules ------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_spin_fans(delta)
	if not multiplayer.is_server():
		return
	if not station.is_true("complete"):
		_elapsed += delta
	_update_breakers(delta)
	_update_alarm(delta)
	_fail_check -= delta
	if _fail_check <= 0.0:
		_fail_check = 1.0
		_check_mission_failed()


func _update_breakers(delta: float) -> void:
	var breakers := get_tree().get_nodes_in_group("breakers")
	if station.is_true("power") or breakers.size() < 2:
		_set_assist(null, null)
		return
	var all_held := true
	var human_on: Breaker = null
	var free_one: Breaker = null
	for b: Breaker in breakers:
		if not b.is_held():
			all_held = false
			free_one = b
		if b.held_by_human():
			human_on = b
	if all_held and station.is_true("generator.fueled"):
		_breaker_progress += delta / 2.0
	else:
		_breaker_progress = maxf(0.0, _breaker_progress - delta * 0.8)
	station.set_value("breaker.progress", snappedf(_breaker_progress, 0.1))
	if _breaker_progress >= 1.0:
		_power_on()
		return
	# Solo / short-handed: an AI crew member takes the other lever.
	if human_on != null and free_one != null and _assist_bot == null:
		var best: BotBrain = null
		var best_d := INF
		for bot in get_bots():
			var brain := bot.get_node_or_null("BotBrain") as BotBrain
			if brain != null and brain.is_free():
				var d := bot.global_position.distance_to(free_one.global_position)
				if d < best_d:
					best_d = d
					best = brain
		if best != null:
			_set_assist(best, free_one)
			radio(best.me, "I'll take the other breaker.")
	elif human_on == null and _assist_bot != null:
		_set_assist(null, null)


func _set_assist(brain: BotBrain, target: Breaker) -> void:
	if _assist_bot != null and is_instance_valid(_assist_bot) and _assist_bot != brain:
		_assist_bot.assign_hold(null)
	_assist_bot = brain
	if brain != null:
		brain.assign_hold(target)


func _power_on() -> void:
	station.set_value("breaker.progress", 1.0)
	station.set_value("power", true)
	_set_assist(null, null)
	announce("MAIN POWER RESTORED. Doors and consoles are online.")
	await get_tree().create_timer(3.5).timeout
	if is_instance_valid(swarm):
		swarm.trigger_route("EngineeringVent", true, true)
	await get_tree().create_timer(4.0).timeout
	var bots := get_bots()
	if not bots.is_empty():
		radio(bots[bots.size() - 1], "Did... did anyone else see that?")


func _update_alarm(delta: float) -> void:
	if station.is_true("power"):
		return
	_alarm_timer -= delta
	if _alarm_timer <= 0.0:
		_alarm_timer = 9.0
		_alarm.rpc()


@rpc("authority", "call_local", "unreliable")
func _alarm() -> void:
	Sfx.play_ui("alarm", -18.0)


func _on_state_changed(key: String, value: Variant) -> void:
	if not multiplayer.is_server():
		return
	if key == "door.med" and value == "open" and not station.is_true("obj.exit"):
		station.set_value("obj.exit", true)
	elif key == "vents" and value == true:
		pass
	elif key == "comms" and value == true and not station.is_true("complete"):
		station.set_value("complete.time", int(_elapsed))
		station.set_value("complete", true)
	elif key == "tunnel.inspected" and value == true:
		swarm.trigger_route("TunnelEnd", false, true)


func _on_trigger(_who: Astronaut, zone_name: String) -> void:
	if not multiplayer.is_server():
		return
	match zone_name:
		"FirstJunction":
			swarm.trigger_route("HubCrossing", true, true)
		"Observation":
			swarm.trigger_route("OutsideWindow", false, true)
		"EngineeringEntry":
			var bots := get_bots()
			if not bots.is_empty():
				radio(bots[0], "Generator's through here. Sockets are empty, we need those cells.")


func drop_carried(who: Astronaut) -> void:
	if who.carrying == "":
		return
	var forward := -who.global_transform.basis.z
	var p := who.global_position + forward * 0.7
	p.y = 0.14
	station.set_value("cell." + who.carrying, {"s": "world", "p": p})


func _check_mission_failed() -> void:
	if _failing:
		return
	var humans := get_humans()
	if humans.is_empty():
		return
	for h in humans:
		if not h.downed:
			return
	for bot in get_bots():
		var brain := bot.get_node_or_null("BotBrain") as BotBrain
		if brain != null and brain.medkits > 0 and not bot.downed:
			return  # help is still coming
	_failing = true
	announce("ALL CREW DOWN. Restarting from the medical bay...")
	await get_tree().create_timer(6.0).timeout
	var main := get_tree().root.get_node_or_null("Main")
	if main != null and main.has_method("change_level"):
		main.change_level(scene_file_path)


# --- Cosmetic (every machine) -----------------------------------------------------------

func _spin_fans(delta: float) -> void:
	var target := 9.0 if station.is_true("vents") else 0.0
	_fan_speed = move_toward(_fan_speed, target, delta * 2.5)
	if _fan_speed <= 0.01:
		return
	for i in _fans.size():
		if is_instance_valid(_fans[i]):
			_fans[i].rotate_object_local(_fan_axes[i], _fan_speed * delta)


func _start_ambience() -> void:
	var stream := Sfx.get_stream("hum") as AudioStreamWAV
	if stream == null and ResourceLoader.exists("res://assets/audio/ambience/hum.wav"):
		stream = load("res://assets/audio/ambience/hum.wav")
	if stream == null:
		return
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -20.0
	add_child(p)
	p.play()
