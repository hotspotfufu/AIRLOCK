extends Node
## Main (persistent root scene)
##
## Holds the UI and a "Level" slot. Only the host decides which level is
## loaded; LevelSpawner copies that level to every client automatically,
## including players who join late. Campaign level changes (M7) go through
## change_level() here.
##
## Testing shortcut — launch arguments after "--":
##   --host               host immediately
##   --join[=ADDRESS]     join immediately (default 127.0.0.1), retries 5x
## In the editor: Debug > Customize Run Instances, 4 instances, give the first
## "--host" and the others "--join".

const FIRST_LEVEL := "res://levels/test_ship/test_ship.tscn"
const AUTO_JOIN_RETRIES := 5

@onready var level_root: Node = $Level
@onready var level_spawner: MultiplayerSpawner = $LevelSpawner
@onready var main_menu: MainMenu = $UI/MainMenu
@onready var pause_menu: PauseMenu = $UI/PauseMenu
@onready var status_label: Label = $UI/StatusLabel

var _auto_join_address := ""
var _auto_join_retries_left := 0


func _ready() -> void:
	level_spawner.spawn_function = _spawn_level

	main_menu.host_requested.connect(_on_host_requested)
	main_menu.join_requested.connect(_on_join_requested)
	main_menu.quit_requested.connect(get_tree().quit)
	pause_menu.resume_requested.connect(_close_pause_menu)
	pause_menu.leave_requested.connect(_on_leave_requested)

	NetworkManager.joined_session.connect(_on_joined_session)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.session_ended.connect(_on_session_ended)
	NetworkManager.player_list_changed.connect(_refresh_status)

	_show_main_menu("")
	_handle_command_line.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and NetworkManager.is_in_session():
		if pause_menu.visible:
			_close_pause_menu()
		else:
			_open_pause_menu()
		get_viewport().set_input_as_handled()


# --- Levels -----------------------------------------------------------------

## Host only: replace the current level for everyone.
func change_level(scene_path: String) -> void:
	assert(multiplayer.is_server(), "Only the host changes levels.")
	_clear_level()
	level_spawner.spawn(scene_path)


## Runs on host AND clients when the spawner creates a level.
func _spawn_level(scene_path: String) -> Node:
	var scene: PackedScene = load(scene_path)
	return scene.instantiate()


func _clear_level() -> void:
	for child in level_root.get_children():
		level_root.remove_child(child)
		child.queue_free()


# --- Menu actions -----------------------------------------------------------

func _on_host_requested() -> void:
	var err := NetworkManager.host()
	if err != OK:
		main_menu.set_message("Could not host on port %d (error %d). Is another copy already hosting?" % [NetworkManager.DEFAULT_PORT, err])
		return
	main_menu.hide()
	change_level(FIRST_LEVEL)
	_refresh_status()


func _on_join_requested(address: String) -> void:
	if address.strip_edges().is_empty():
		address = "127.0.0.1"
	var err := NetworkManager.join(address)
	if err != OK:
		main_menu.set_message("Could not start connecting (error %d)." % err)
		return
	main_menu.set_busy(true)
	main_menu.set_message("Connecting to %s ..." % address)


func _on_joined_session() -> void:
	_auto_join_retries_left = 0
	main_menu.hide()
	_refresh_status()
	# The level arrives on its own through LevelSpawner.


func _on_connection_failed(reason: String) -> void:
	if _auto_join_retries_left > 0:
		_auto_join_retries_left -= 1
		main_menu.set_message("Host not ready, retrying ...")
		await get_tree().create_timer(1.0).timeout
		_on_join_requested(_auto_join_address)
		return
	_show_main_menu(reason)


func _on_session_ended(reason: String) -> void:
	_clear_level()
	_show_main_menu(reason)


func _on_leave_requested() -> void:
	NetworkManager.leave()
	_clear_level()
	_show_main_menu("")


# --- UI state ---------------------------------------------------------------

func _show_main_menu(message: String) -> void:
	pause_menu.hide()
	main_menu.show()
	main_menu.set_busy(false)
	main_menu.set_message(message)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_status()


func _open_pause_menu() -> void:
	pause_menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_pause_menu() -> void:
	pause_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _refresh_status() -> void:
	if not NetworkManager.is_in_session():
		status_label.text = ""
		return
	var role := "HOST" if multiplayer.is_server() else "CLIENT"
	status_label.text = "%s  |  peer %d  |  crew %d/%d" % [
		role,
		multiplayer.get_unique_id(),
		NetworkManager.get_player_count(),
		NetworkManager.MAX_PLAYERS,
	]


func _handle_command_line() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--host":
			_on_host_requested()
			return
		if arg.begins_with("--join"):
			_auto_join_address = arg.get_slice("=", 1) if arg.contains("=") else "127.0.0.1"
			_auto_join_retries_left = AUTO_JOIN_RETRIES
			_on_join_requested(_auto_join_address)
			return
