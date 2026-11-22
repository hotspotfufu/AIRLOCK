class_name SupplyStation
extends Interactable
## Emergency resources with a limited number of uses, shared by the crew:
##   o2  - wall cabinet that refills suit oxygen
##   med - medical scanner bed that restores health (needs main power)

@export_enum("o2", "med") var kind := "o2"
@export var station_id := "o2_a"
@export var charges := 3
@export var build_model := true

var _lamp: StandardMaterial3D


func _setup() -> void:
	hold_time = 2.0
	_lamp = Kit.glow(Kit.CYAN, 1.5)
	if kind == "o2":
		size = Vector3(0.8, 1.2, 0.5)
		if build_model:
			Kit.box(self, Vector3(0.7, 1.1, 0.25), Vector3(0, 0, -0.12), Kit.mat(Kit.GREEN_PANEL))
			Kit.cylinder(self, 0.1, 0.7, Vector3(-0.17, 0, 0.03), Kit.mat(Color(0.85, 0.87, 0.9), 0.7, 0.3))
			Kit.cylinder(self, 0.1, 0.7, Vector3(0.17, 0, 0.03), Kit.mat(Color(0.85, 0.87, 0.9), 0.7, 0.3))
		Kit.box(self, Vector3(0.5, 0.06, 0.03), Vector3(0, 0.48, 0.02), _lamp)
		Kit.label(self, "O2", Vector3(0, 0.66, 0.0), 56, Color(0.85, 0.95, 1.0), 0.004)
	else:
		size = Vector3(1.6, 1.2, 1.2)
		Kit.box(self, Vector3(0.4, 0.06, 0.03), Vector3(0, 0.3, 0.0), _lamp)
		Kit.label(self, "MED SCAN", Vector3(0, 0.45, 0.0), 40, Color(0.85, 0.95, 1.0), 0.003)
	_refresh()


func _left() -> int:
	return int(station.get_value("supply." + station_id, charges)) if station != null else charges


func get_prompt(_who: Astronaut) -> String:
	if kind == "o2":
		return "Refill suit oxygen (%d left)" % _left()
	return "Use medical scanner (%d left)" % _left()


func can_use(who: Astronaut) -> bool:
	if _left() <= 0:
		return false
	if kind == "med":
		return station.is_true("power") and who.health < 99.0
	return who.suit_o2 < 99.0


func get_blocked_reason(who: Astronaut) -> String:
	if _left() <= 0:
		return "Empty"
	if kind == "med":
		return "No power" if not station.is_true("power") else "Health is full"
	return "Suit oxygen is full" if who.suit_o2 >= 99.0 else ""


func interact(who: Astronaut) -> void:
	if not can_use(who):
		return
	station.set_value("supply." + station_id, _left() - 1)
	if kind == "o2":
		who.apply_supply.rpc_id(who.get_multiplayer_authority(), 100.0, 0.0)
	else:
		who.apply_supply.rpc_id(who.get_multiplayer_authority(), 0.0, 100.0)
	Sfx.play_at("hiss", global_position)


func _on_state_changed(changed_key: String, _value: Variant) -> void:
	if changed_key == "supply." + station_id or changed_key == "power":
		_refresh()


func _refresh() -> void:
	if station == null:
		return
	var ok := _left() > 0 and (kind == "o2" or station.is_true("power"))
	Kit.set_glow(_lamp, Kit.CYAN if ok else Kit.WARNING_RED, 1.5 if ok else 0.6)
