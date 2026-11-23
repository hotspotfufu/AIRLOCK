class_name CellSocket
extends Interactable
## A generator socket that takes one power cell. When every socket is filled
## the generator is fuelled ("generator.fueled") and the breakers will work.

@export var index := 0

var _lamp: StandardMaterial3D


func _setup() -> void:
	add_to_group("cell_sockets")
	size = Vector3(0.6, 0.8, 0.6)
	Kit.box(self, Vector3(0.5, 0.25, 0.5), Vector3(0, -0.2, 0), Kit.mat(Kit.STEEL_DARK))
	Kit.cylinder(self, 0.16, 0.12, Vector3(0, -0.05, 0), Kit.mat(Kit.STEEL, 0.9, 0.3))
	_lamp = Kit.glow(Kit.WARNING_RED, 2.0)
	Kit.box(self, Vector3(0.12, 0.05, 0.05), Vector3(0, -0.2, 0.26), _lamp)
	_refresh()


func _filled() -> bool:
	return station != null and station.is_true("socket.%d" % index)


func get_prompt(who: Astronaut) -> String:
	if _filled():
		return ""
	return "Insert power cell" if who.carrying != "" else "Empty power cell socket"


func can_use(who: Astronaut) -> bool:
	return who.carrying != ""


func get_blocked_reason(_who: Astronaut) -> String:
	return "Bring a power cell"


func interact(who: Astronaut) -> void:
	if _filled() or who.carrying == "":
		return
	station.set_value("cell." + who.carrying, {"s": "socket", "i": index})
	station.set_value("socket.%d" % index, true)
	var total := get_tree().get_nodes_in_group("cell_sockets").size()
	var filled := 0
	for s in total:
		if station.is_true("socket.%d" % s):
			filled += 1
	if filled >= total:
		station.set_value("generator.fueled", true)
		Level.instance.announce("Generator fuelled. Engage both breakers together.")
	else:
		Level.instance.announce("Power cell installed (%d/%d)." % [filled, total])


func _on_state_changed(changed_key: String, _value: Variant) -> void:
	if changed_key == "socket.%d" % index:
		_refresh()


func _refresh() -> void:
	Kit.set_glow(_lamp, Kit.OK_GREEN if _filled() else Kit.WARNING_RED, 2.0)
