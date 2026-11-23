extends Interactable
## Aiming at a door and pressing E. What happens depends on the door's mode
## and on whether main power is on.

var door: AirlockDoor


func get_prompt(_who: Astronaut) -> String:
	if door == null:
		return ""
	match door.mode:
		"sealed":
			return "Door sealed"
		"airlock":
			var chamber := _chamber()
			return chamber.get_door_prompt(door) if chamber != null else ""
	return "Close door" if door.is_open() else "Open door"


func can_use(_who: Astronaut) -> bool:
	if door == null or door.mode == "sealed":
		return false
	if door.mode == "airlock":
		var chamber := _chamber()
		return chamber != null and not chamber.is_busy()
	return door.has_power()


func get_blocked_reason(_who: Astronaut) -> String:
	if door.mode == "sealed":
		return door.sealed_text.capitalize()
	if door.mode == "airlock":
		return "Airlock is cycling"
	if door.mode == "power_only":
		return "Magnetic lock: no power"
	return "No power: use the manual release beside the door"


func interact(_who: Astronaut) -> void:
	if not can_use(_who):
		Sfx.play_at("deny", global_position)
		return
	if door.mode == "airlock":
		_chamber().door_pressed(door)
	else:
		door.toggle()


func _chamber() -> AirlockChamber:
	for c: AirlockChamber in get_tree().get_nodes_in_group("airlock_chambers"):
		if c.owns(door):
			return c
	return null
