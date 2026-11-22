class_name PauseMenu
extends Control
## In-session menu (Esc). The game keeps running underneath — it's multiplayer,
## so there is no real pause.

signal resume_requested
signal leave_requested

@onready var _resume_button: Button = $Center/Panel/ResumeButton
@onready var _leave_button: Button = $Center/Panel/LeaveButton


func _ready() -> void:
	_resume_button.pressed.connect(resume_requested.emit)
	_leave_button.pressed.connect(leave_requested.emit)
