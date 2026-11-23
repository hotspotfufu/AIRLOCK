class_name MainMenu
extends Control
## Title screen: host, join by IP, quit.
## Placeholder visuals — the real AIRLOCK logo screen comes in Milestone 8.

signal host_requested
signal join_requested(address: String)
signal solo_requested
signal quit_requested

@onready var _host_button: Button = $Center/Panel/HostButton
@onready var _join_button: Button = $Center/Panel/JoinRow/JoinButton
@onready var _address_edit: LineEdit = $Center/Panel/JoinRow/AddressEdit
@onready var _solo_button: Button = $Center/Panel/SoloButton
@onready var _quit_button: Button = $Center/Panel/QuitButton
@onready var _message: Label = $Center/Panel/Message


func _ready() -> void:
	_host_button.pressed.connect(host_requested.emit)
	_join_button.pressed.connect(_on_join_pressed)
	_address_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_solo_button.pressed.connect(solo_requested.emit)
	_quit_button.pressed.connect(quit_requested.emit)
	if OS.has_feature("web"):
		_quit_button.hide()  # a browser tab can't quit itself


func set_message(text: String) -> void:
	_message.text = text


func set_busy(busy: bool) -> void:
	var online := NetworkManager.networking_supported()
	_host_button.disabled = busy or not online
	_join_button.disabled = busy or not online
	_address_edit.editable = online and not busy
	_solo_button.disabled = busy


## Browser builds: online play isn't available yet, only solo.
func set_network_available(available: bool) -> void:
	_host_button.disabled = not available
	_join_button.disabled = not available
	_address_edit.editable = available
	if not available:
		_host_button.text = "Host Game (desktop build only)"


func _on_join_pressed() -> void:
	join_requested.emit(_address_edit.text)
