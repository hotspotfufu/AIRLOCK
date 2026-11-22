class_name Interactable
extends Area3D
## Anything a crew member can look at and use with E: panels, levers, doors,
## pickups. The astronaut finds these with a short ray from the camera.
##
## Flow: the player presses (or holds) E -> their game asks the host ->
## the host checks they are close enough and calls interact() here ->
## the script changes StationState -> every player sees the result.
## AI crew call interact() directly on the host.

const LAYER_BIT := 8  # physics layer 4 "interactables"

## Short verb phrase shown as "[E] <prompt>".
@export var prompt := "Use"
## Seconds E must be held. 0 = single press.
@export var hold_time := 0.0
## If true the action only lasts while E stays held (e.g. a breaker lever).
@export var continuous := false
## Size of the box the player can aim at.
@export var size := Vector3(0.6, 0.6, 0.6)
## How far away (m) the host still accepts the interaction.
@export var max_distance := 3.2

var station: StationState


func _ready() -> void:
	collision_layer = LAYER_BIT
	collision_mask = 0
	monitoring = false
	monitorable = true
	var level := Level.instance
	if level != null:
		station = level.station
		if station != null:
			station.changed.connect(_on_state_changed)
	_setup()
	if get_node_or_null("Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		add_child(shape)


## Override: one-time setup after `station` is known.
func _setup() -> void:
	pass


## Override: react to station state (runs on every player).
func _on_state_changed(_key: String, _value: Variant) -> void:
	pass


## Override: text for the HUD. Return "" to hide the prompt entirely.
func get_prompt(_who: Astronaut) -> String:
	return prompt


## Override: false shows the prompt greyed out (get_blocked_reason explains).
func can_use(_who: Astronaut) -> bool:
	return true


## Override: why it can't be used right now ("No power").
func get_blocked_reason(_who: Astronaut) -> String:
	return ""


## Override (host only): do the thing.
func interact(_who: Astronaut) -> void:
	pass


## Override (host only): continuous interactables get hold start/stop.
func set_held(_who: Astronaut, _held: bool) -> void:
	pass


## Where an AI crew member should stand to use this.
func get_stand_point() -> Vector3:
	var p := global_position + global_transform.basis.z * 0.9
	p.y = 0.05
	return p
