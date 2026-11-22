class_name StateConsole
extends Interactable
## A console that performs one station action when a crew member holds E:
## for example "Restart air circulation" or "Restore communications".
## It can require something first (usually main power) and shows its status
## with a coloured screen: dark = no power, amber = ready, green = done.

@export var title := "CONSOLE"
@export var action := "Activate"
## StationState key that must be true before this works ("" = none).
@export var requires_key := "power"
@export var blocked_reason := "No power"
## StationState key this console sets to true.
@export var sets_key := ""
@export var done_message := ""
## Build a simple console model here. Turn off when placing this on top of
## a console that already exists in a purchased model.
@export var build_model := true

var _screen: StandardMaterial3D


func _setup() -> void:
	hold_time = 2.5
	size = Vector3(1.0, 1.3, 0.7)
	_screen = Kit.glow(Kit.SCREEN_OFF, 0.0)
	if build_model:
		Kit.box(self, Vector3(0.9, 0.9, 0.5), Vector3(0, -0.25, -0.1), Kit.mat(Kit.STEEL_DARK))
		Kit.box(self, Vector3(0.9, 0.06, 0.55), Vector3(0, 0.22, -0.08), Kit.mat(Kit.GREEN_PANEL))
		var screen := Kit.box(self, Vector3(0.74, 0.42, 0.04), Vector3(0, 0.5, -0.22), _screen)
		screen.rotation.x = -0.3
		Kit.label(self, title, Vector3(0, 0.84, -0.26), 40, Color(0.85, 0.9, 0.95), 0.003)
	else:
		Kit.box(self, Vector3(0.3, 0.12, 0.03), Vector3(0, 0.0, 0.0), _screen)
		Kit.label(self, title, Vector3(0, 0.16, 0.0), 36, Color(0.85, 0.9, 0.95), 0.003)
	_refresh()


func _ready_to_use() -> bool:
	return requires_key == "" or station.is_true(requires_key)


func _done() -> bool:
	return sets_key != "" and station.is_true(sets_key)


func get_prompt(_who: Astronaut) -> String:
	return "" if _done() else action


func can_use(_who: Astronaut) -> bool:
	return _ready_to_use()


func get_blocked_reason(_who: Astronaut) -> String:
	return blocked_reason


func interact(_who: Astronaut) -> void:
	if _done() or not _ready_to_use():
		return
	station.set_value(sets_key, true)
	if done_message != "":
		Level.instance.announce(done_message)


func _on_state_changed(changed_key: String, _value: Variant) -> void:
	if changed_key == requires_key or changed_key == sets_key:
		_refresh()
		if changed_key == sets_key and _done():
			Sfx.play_at("confirm", global_position)


func _refresh() -> void:
	if station == null:
		return
	if _done():
		Kit.set_glow(_screen, Kit.OK_GREEN, 1.6)
	elif _ready_to_use():
		Kit.set_glow(_screen, Kit.AMBER, 1.6)
	else:
		Kit.set_glow(_screen, Kit.SCREEN_OFF, 0.0)
