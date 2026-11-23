class_name Breaker
extends Interactable
## One of the two main breaker levers. Both must be held at the same moment
## (two crew members) to restore power. The station level script watches
## "breaker.<n>.held" and counts up "breaker.progress".

@export var index := 0

var _holders: Dictionary = {}
var _lever: Node3D
var _lamp: StandardMaterial3D


func _setup() -> void:
	add_to_group("breakers")
	continuous = true
	size = Vector3(0.7, 1.0, 0.5)
	Kit.box(self, Vector3(0.6, 0.9, 0.16), Vector3(0, 0, -0.08), Kit.mat(Kit.STEEL_DARK))
	Kit.box(self, Vector3(0.62, 0.1, 0.17), Vector3(0, 0.46, -0.08), Kit.hazard_material())
	_lever = Node3D.new()
	_lever.position = Vector3(0, -0.2, 0.02)
	add_child(_lever)
	Kit.box(_lever, Vector3(0.07, 0.5, 0.07), Vector3(0, 0.25, 0), Kit.mat(Kit.WARNING_RED, 0.3, 0.5))
	Kit.box(_lever, Vector3(0.22, 0.08, 0.1), Vector3(0, 0.5, 0), Kit.mat(Color(0.05, 0.05, 0.05), 0.1, 0.8))
	_lamp = Kit.glow(Kit.WARNING_RED, 2.0)
	Kit.box(self, Vector3(0.1, 0.1, 0.04), Vector3(0.2, 0.3, 0.01), _lamp)
	Kit.label(self, "MAIN BREAKER %s" % ("A" if index == 0 else "B"), Vector3(0, 0.62, 0.0), 40, Color(0.9, 0.9, 0.85), 0.003)
	_refresh()


func is_held() -> bool:
	return station != null and station.is_true("breaker.%d.held" % index)


func held_by_human() -> bool:
	for holder: String in _holders:
		if not holder.begins_with("bot"):
			return true
	return false


func get_prompt(_who: Astronaut) -> String:
	if station.is_true("power"):
		return ""
	return "Hold breaker lever (needs 2 crew at once)"


func can_use(_who: Astronaut) -> bool:
	return station.is_true("generator.fueled")


func get_blocked_reason(_who: Astronaut) -> String:
	return "Generator needs 2 power cells"


func set_held(who: Astronaut, held: bool) -> void:
	if held:
		_holders[String(who.name)] = true
	else:
		_holders.erase(String(who.name))
	station.set_value("breaker.%d.held" % index, not _holders.is_empty())


func _on_state_changed(changed_key: String, _value: Variant) -> void:
	if changed_key == "breaker.%d.held" % index or changed_key == "power":
		_refresh()
		if changed_key != "power":
			Sfx.play_at("lever", global_position)


func _refresh() -> void:
	var powered := station != null and station.is_true("power")
	var down := is_held() or powered
	_lever.rotation.x = 1.9 if down else 0.5
	Kit.set_glow(_lamp, Kit.OK_GREEN if powered else (Kit.AMBER if is_held() else Kit.WARNING_RED), 2.0)
