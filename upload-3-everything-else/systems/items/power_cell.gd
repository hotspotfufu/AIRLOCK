class_name PowerCell
extends Interactable
## A portable power cell. Crew pick it up (one item at a time), carry it to
## the generator and plug it into a socket.
##
## Its whole life is one StationState entry "cell.<id>":
##   {"s":"world","p":Vector3}   lying somewhere
##   {"s":"held","by":"<astronaut node name>"}
##   {"s":"socket","i":<socket index>}

@export var cell_id := "a"

var _state := "world"
var _holder: Astronaut = null
var _band: StandardMaterial3D


func _setup() -> void:
	add_to_group("power_cells")
	prompt = "Pick up power cell"
	size = Vector3(0.5, 0.6, 0.5)
	Kit.cylinder(self, 0.11, 0.36, Vector3.ZERO, Kit.mat(Kit.STEEL_DARK, 0.8, 0.35))
	_band = Kit.glow(Kit.CYAN, 2.5)
	Kit.cylinder(self, 0.118, 0.08, Vector3(0, 0.07, 0), _band)
	Kit.cylinder(self, 0.05, 0.42, Vector3.ZERO, Kit.mat(Kit.STEEL, 0.9, 0.3))
	if station != null:
		_apply(station.get_value(key(), {"s": "world", "p": global_position}))


func key() -> String:
	return "cell." + cell_id


func is_loose() -> bool:
	return _state == "world"


func get_prompt(_who: Astronaut) -> String:
	return prompt if _state == "world" else ""


func can_use(who: Astronaut) -> bool:
	return who.carrying == ""


func get_blocked_reason(_who: Astronaut) -> String:
	return "Hands full"


func interact(who: Astronaut) -> void:
	if _state != "world" or who.carrying != "":
		return
	station.set_value(key(), {"s": "held", "by": String(who.name)})
	station.set_value(key() + ".found", true)


func _on_state_changed(changed_key: String, value: Variant) -> void:
	if changed_key == key():
		_apply(value)


func _apply(value: Dictionary) -> void:
	var was := _state
	_state = value.get("s", "world")
	if _holder != null and is_instance_valid(_holder) and _holder.carrying == cell_id:
		_holder.carrying = ""
	_holder = null
	match _state:
		"world":
			global_position = value.get("p", global_position)
			rotation = Vector3(0, 0, PI * 0.5)  # lying on its side
			if was == "held":
				Sfx.play_at("pickup", global_position, -6.0, 0.7)
		"held":
			if was != "held":
				Sfx.play_at("pickup", global_position)
		"socket":
			rotation = Vector3.ZERO
			var socket := _find_socket(int(value.get("i", 0)))
			if socket != null:
				global_position = socket.global_position + Vector3(0, 0.05, 0)
			Sfx.play_at("lever", global_position)
	var shape := get_node_or_null("Shape") as CollisionShape3D
	if shape != null:
		shape.set_deferred("disabled", _state != "world")


func _process(_delta: float) -> void:
	if _state != "held" or Level.instance == null:
		return
	if _holder == null or not is_instance_valid(_holder):
		var value: Dictionary = station.get_value(key(), {})
		_holder = Level.instance.players_root.get_node_or_null(String(value.get("by", ""))) as Astronaut
		if _holder == null:
			# Carrier left the game: put the cell down where it was.
			if multiplayer.is_server():
				station.set_value(key(), {"s": "world", "p": Vector3(global_position.x, 0.2, global_position.z)})
			return
	_holder.carrying = cell_id
	var xf := _holder.global_transform
	global_position = xf.origin + xf.basis * Vector3(0.0, 1.0, -0.48)
	rotation = Vector3(0, _holder.rotation.y, 0)


func _find_socket(index: int) -> Node3D:
	for s: Node3D in get_tree().get_nodes_in_group("cell_sockets"):
		if s.get("index") == index:
			return s
	return null
