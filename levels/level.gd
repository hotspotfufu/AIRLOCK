class_name Level
extends Node3D
## Base script for every playable level.
##
## Host: spawns one astronaut per connected player at this level's
## SpawnPoints and removes astronauts whose player leaves.
## Clients: do nothing here — PlayerSpawner recreates the host's astronauts
## locally by calling _spawn_player with the same data.
##
## Required children: SpawnPoints (Marker3Ds), Players (Node3D),
## PlayerSpawner (MultiplayerSpawner with spawn_path = ../Players).

const PLAYER_SCENE := preload("res://characters/astronaut/player.tscn")
const MAX_SLOTS := 4

@onready var players_root: Node3D = $Players
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var spawn_points: Array[Node] = $SpawnPoints.get_children()

var _slot_by_peer: Dictionary = {}  # peer id -> spawn slot 0..3


func _ready() -> void:
	player_spawner.spawn_function = _spawn_player
	if not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	_add_player(1)  # the host's own astronaut
	for id in multiplayer.get_peers():
		_add_player(id)


func _add_player(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var slot := _first_free_slot()
	_slot_by_peer[id] = slot
	player_spawner.spawn({"id": id, "slot": slot})


func _remove_player(id: int) -> void:
	_slot_by_peer.erase(id)
	if players_root.has_node(str(id)):
		players_root.get_node(str(id)).queue_free()


## Called on host and every client with identical data, so every machine
## builds the same astronaut with the same name, owner and spawn position.
func _spawn_player(data: Dictionary) -> Node:
	var astronaut := PLAYER_SCENE.instantiate() as Astronaut
	var id: int = data["id"]
	var slot: int = data["slot"]
	astronaut.name = str(id)
	astronaut.peer_id = id
	astronaut.slot = slot
	var marker := spawn_points[slot % spawn_points.size()] as Node3D
	astronaut.transform = marker.transform
	return astronaut


func _first_free_slot() -> int:
	var used := _slot_by_peer.values()
	for i in MAX_SLOTS:
		if not used.has(i):
			return i
	return 0
