class_name InspectPoint
extends Interactable
## Something to look at closely. Sets a StationState key (so objectives and
## scripted moments can react) and shows a line of text to the whole crew.

@export var action := "Inspect"
@export var sets_key := ""
@export var message := ""


func _setup() -> void:
	hold_time = 1.2


func get_prompt(_who: Astronaut) -> String:
	return "" if station.is_true(sets_key) else action


func interact(_who: Astronaut) -> void:
	if station.is_true(sets_key):
		return
	station.set_value(sets_key, true)
	if message != "":
		Level.instance.announce(message)
