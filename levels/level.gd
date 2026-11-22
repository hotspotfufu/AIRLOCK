class_name Level
extends Node3D
## Base script for every playable level.
##
## Host: spawns one astronaut per connected player at this level's
## SpawnPoints, removes astronauts whose player leaves, and (in solo play)
## fills the other three slots with AI crew.
## Clients: PlayerSpawner recreates the host's astronauts locally.
## Also the single doorway for player requests ("I pressed E on that panel"):
## clients ask, the host checks and acts.
##
## Required children: StationState, SpawnPoints (Marker3Ds), Players (Node3D),
## PlayerSpawner (MultiplayerSpawner with spawn_path = ../Players).

signal announcement(text: String)
signal radio_message(speaker: String, color: Color, text: String)

const PLAYER_SCENE := preload("res://characters/astronaut/player.tscn")
const BOT_BRAIN := preload("res://characters/astronaut/bot_brain.gd")
const MAX_SLOTS := 4

## The level currently loaded (there is only ever one).
static var instance: Level

var station: StationState
var players_root: Node3D
var player_spawner: MultiplayerSpawner
var spawn_points: Array[Node] = []

var _slot_by_peer: Dictionary = {}  # peer id -> spawn slot 0..3


func _enter_tree() -> void:
	instance = self
	station = get_node_or_null("StationState")
	players_root = get_node("Players")
	player_spawner = get_node("PlayerSpawner")
	spawn_points = get_node("SpawnPoints").get_children()
	player_spawner.spawn_function = _spawn_player


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	add_to_group("level")
	if not multiplayer.is_server():
		return
	multiplayer.peer_connected.connect(_add_player)
	multiplayer.peer_disconnected.connect(_remove_player)
	_add_player(1)  # the host's own astronaut
	for id in multiplayer.get_peers():
		_add_player(id)
	if NetworkManager.is_solo:
		for i in MAX_SLOTS - 1:
			_add_bot()
	_level_started()


## Override (host): called once players and AI crew exist.
func _level_started() -> void:
	pass


# --- Spawning -------------------------------------------------------------------

func _add_player(id: int) -> void:
	if players_root.has_node(str(id)):
		return
	var slot := _first_free_slot()
	_slot_by_peer[id] = slot
	player_spawner.spawn({"id": id, "slot": slot, "bot": false})


func _add_bot() -> void:
	var slot := _first_free_slot()
	_slot_by_peer[-(slot + 1)] = slot
	player_spawner.spawn({"id": 1, "slot": slot, "bot": true})


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
	var bot: bool = data.get("bot", false)
	astronaut.name = ("bot%d" % slot) if bot else str(id)
	astronaut.peer_id = id
	astronaut.slot = slot
	astronaut.is_bot = bot
	var marker := spawn_points[slot % spawn_points.size()] as Node3D
	astronaut.transform = marker.transform
	if bot and multiplayer.is_server():
		var agent := NavigationAgent3D.new()
		agent.name = "NavigationAgent3D"
		agent.path_desired_distance = 0.6
		agent.target_desired_distance = 0.6
		agent.radius = 0.4
		astronaut.add_child(agent)
		var brain := Node.new()
		brain.name = "BotBrain"
		brain.set_script(BOT_BRAIN)
		astronaut.add_child(brain)
	return astronaut


func _first_free_slot() -> int:
	var used := _slot_by_peer.values()
	for i in MAX_SLOTS:
		if not used.has(i):
			return i
	return 0


# --- Crew lookups ---------------------------------------------------------------

func get_astronauts() -> Array[Astronaut]:
	var out: Array[Astronaut] = []
	for n in players_root.get_children():
		if n is Astronaut and not n.is_queued_for_deletion():
			out.append(n)
	return out


func get_humans() -> Array[Astronaut]:
	return get_astronauts().filter(func(a: Astronaut) -> bool: return not a.is_bot)


func get_bots() -> Array[Astronaut]:
	return get_astronauts().filter(func(a: Astronaut) -> bool: return a.is_bot)


## The astronaut this machine controls (null on a dedicated viewer).
func get_local_astronaut() -> Astronaut:
	return players_root.get_node_or_null(str(multiplayer.get_unique_id())) as Astronaut


func _sender_astronaut() -> Astronaut:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	return players_root.get_node_or_null(str(id)) as Astronaut


# --- Player requests (client -> host) ------------------------------------------------

@rpc("any_peer", "call_local", "reliable")
func request_interact(path: NodePath) -> void:
	if not multiplayer.is_server():
		return
	var who := _sender_astronaut()
	var target := get_node_or_null(path) as Interactable
	if who == null or target == null or who.downed:
		return
	if who.global_position.distance_to(target.global_position) > target.max_distance + 2.0:
		return
	if target.get_prompt(who) == "" or not target.can_use(who):
		return
	target.interact(who)


@rpc("any_peer", "call_local", "reliable")
func request_hold(path: NodePath, held: bool) -> void:
	if not multiplayer.is_server():
		return
	var who := _sender_astronaut()
	var target := get_node_or_null(path) as Interactable
	if who == null or target == null:
		return
	if held and (who.downed or not target.can_use(who)
			or who.global_position.distance_to(target.global_position) > target.max_distance + 2.0):
		return
	target.set_held(who, held)


@rpc("any_peer", "call_local", "reliable")
func request_drop() -> void:
	if not multiplayer.is_server():
		return
	var who := _sender_astronaut()
	if who != null:
		drop_carried(who)


@rpc("any_peer", "call_local", "reliable")
func report_downed() -> void:
	if not multiplayer.is_server():
		return
	var who := _sender_astronaut()
	if who != null:
		announce("%s is down! Hold E on them to revive." % who.crew_name())
		_on_astronaut_downed(who)


## Override (host): put down whatever `who` is carrying.
func drop_carried(_who: Astronaut) -> void:
	pass


## Override (host).
func _on_astronaut_downed(_who: Astronaut) -> void:
	pass


# --- Messages (host -> everyone) --------------------------------------------------

## Short system line shown on every HUD ("Main power restored").
func announce(text: String) -> void:
	if multiplayer.is_server():
		_announce.rpc(text)


@rpc("authority", "call_local", "reliable")
func _announce(text: String) -> void:
	announcement.emit(text)


## A crew member speaking over the radio (subtitle on every HUD).
func radio(who: Astronaut, text: String) -> void:
	if multiplayer.is_server() and who != null:
		_radio.rpc(who.crew_name(), Astronaut.SUIT_COLORS[who.slot % 4], text)


@rpc("authority", "call_local", "reliable")
func _radio(speaker: String, color: Color, text: String) -> void:
	radio_message.emit(speaker, color, text)
