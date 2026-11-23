extends Node
## InputSetup (autoload)
##
## Registers every input action the game uses, in one place.
## Doing this in code (instead of Project Settings > Input Map) keeps the
## bindings readable and diff-friendly. A rebinding menu can later overwrite
## these at runtime.

## action name -> list of physical keys
const KEY_BINDINGS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"sprint": [KEY_SHIFT],
	"crouch": [KEY_CTRL, KEY_C],
	"flashlight": [KEY_F],
	"interact": [KEY_E],
	"jump": [KEY_SPACE],
	"drop": [KEY_G],
	"pause": [KEY_ESCAPE],
}


func _enter_tree() -> void:
	for action: String in KEY_BINDINGS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEY_BINDINGS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
