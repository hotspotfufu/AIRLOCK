extends Node
## NetworkManager (autoload)
##
## Owns the multiplayer connection. Everything else asks this node to
## host / join / leave and listens to its signals; nothing else creates peers.
##
## Transport today: ENet (direct IP) — for LAN and local 4-instance testing.
## Transport later: Steam (GodotSteam). It will plug in behind host()/join()
## so menus, levels and players don't change. See README "Steam".
##
## Model: listen server. The host is peer id 1 and is authoritative for all
## shared state (doors, power, oxygen, alien). Each player owns only their
## own astronaut's movement.

signal hosting_started
signal joined_session
signal connection_failed(reason: String)
signal session_ended(reason: String)
signal player_list_changed

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4


func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_connected.connect(_on_peer_changed)
	multiplayer.peer_disconnected.connect(_on_peer_changed)


## True when this build can host/join online sessions. False in browser
## (web) builds: browsers can't open the raw UDP connections ENet uses.
## Browser multiplayer needs a WebRTC/WebSocket transport (a later decision).
func networking_supported() -> bool:
	return not OS.has_feature("web") and ClassDB.class_exists("ENetMultiplayerPeer")


## Solo mode: play the level alone with no network. Used by browser builds and
## for quick single-player testing. The game logic still runs as "host"
## (peer id 1), so everything written for multiplayer works unchanged.
var is_solo := false


func start_solo() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_solo = true
	player_list_changed.emit()


## Start a session on this machine. Returns OK or an Error code.
func host(port: int = DEFAULT_PORT) -> Error:
	if not networking_supported():
		return ERR_UNAVAILABLE
	# Created by name so browser builds (no ENet) still load this script.
	var peer = ClassDB.instantiate("ENetMultiplayerPeer")
	var err: Error = peer.create_server(port, MAX_PLAYERS - 1)  # host + 3 clients
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_solo = false
	hosting_started.emit()
	player_list_changed.emit()
	return OK


## Start connecting to a host. Success/failure arrives later as a signal.
func join(address: String, port: int = DEFAULT_PORT) -> Error:
	if not networking_supported():
		return ERR_UNAVAILABLE
	var peer = ClassDB.instantiate("ENetMultiplayerPeer")
	var err: Error = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_solo = false
	return OK


## Leave the session (host: ends it for everyone) or stop solo play.
func leave() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_solo = false
	player_list_changed.emit()


## True while in a level: online session or solo.
func is_playing() -> bool:
	return is_solo or is_in_session()


func is_in_session() -> bool:
	var peer := multiplayer.multiplayer_peer
	return (
		peer != null
		and not (peer is OfflineMultiplayerPeer)
		and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	)


func is_host() -> bool:
	return is_in_session() and multiplayer.is_server()


func get_player_count() -> int:
	if not is_in_session():
		return 0
	return multiplayer.get_peers().size() + 1


func _on_connected_to_server() -> void:
	joined_session.emit()
	player_list_changed.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	connection_failed.emit("Could not connect. The host may be unreachable or the session is full (4/4).")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	session_ended.emit("The host ended the session.")


func _on_peer_changed(_id: int) -> void:
	player_list_changed.emit()
