class_name MainMenu
extends Control
## Title screen: host, join by IP, quit.
## Placeholder visuals — the real AIRLOCK logo screen comes in Milestone 8.

signal host_requested
signal join_requested(address: String)
signal quit_requested

@onready var _host_button: Button = $Center/Panel/HostButton
@onready var _join_button: Button = $Center/Panel/JoinRow/JoinButton
@onready var _address_edit: LineEdit = $Center/Panel/JoinRow/AddressEdit
@onready var _quit_button: Button = $Center/Panel/QuitButton
@onready var _message: Label = $Center/Panel/Message


func _ready() -> void:
	_host_button.pressed.connect(host_requested.emit)
	_join_button.pressed.connect(_on_join_pressed)
	_address_edit.text_submitted.connect(func(_t: String) -> void: _on_join_pressed())
	_quit_button.pressed.connect(quit_requested.emit)


func set_message(text: String) -> void:
	_message.text = text


func set_busy(busy: bool) -> void:
	_host_button.disabled = busy
	_join_button.disabled = busy
	_address_edit.editable = not busy


func _on_join_pressed() -> void:
	join_requested.emit(_address_edit.text)
