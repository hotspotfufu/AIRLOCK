class_name StationState
extends Node
## Shared "blackboard" for everything about the station that all players must
## agree on: which doors are open, whether power is on, oxygen level, where
## each power cell is, objective progress.
##
## Only the host writes (set_value). Every change is sent to all players, and
## anyone who joins late asks the host for the full table. Objects in the
## level never talk to the network themselves: they read keys from here and
## react to the `changed` signal. In solo play the same code runs locally.

signal changed(key: String, value: Variant)

var _data: Dictionary = {}


func _ready() -> void:
	if not multiplayer.is_server():
		_request_full.rpc_id(1)


func get_value(key: String, default: Variant = null) -> Variant:
	return _data.get(key, default)


func is_true(key: String) -> bool:
	return _data.get(key, false) == true


## Host only. Ignored on clients.
func set_value(key: String, value: Variant) -> void:
	if not multiplayer.is_server():
		return
	if _data.has(key) and typeof(_data[key]) == typeof(value) and _data[key] == value:
		return
	_apply.rpc(key, value)


@rpc("authority", "call_local", "reliable")
func _apply(key: String, value: Variant) -> void:
	_data[key] = value
	changed.emit(key, value)


@rpc("any_peer", "call_remote", "reliable")
func _request_full() -> void:
	if multiplayer.is_server():
		_full.rpc_id(multiplayer.get_remote_sender_id(), _data)


@rpc("authority", "call_remote", "reliable")
func _full(data: Dictionary) -> void:
	for key: String in data:
		_data[key] = data[key]
		changed.emit(key, data[key])
