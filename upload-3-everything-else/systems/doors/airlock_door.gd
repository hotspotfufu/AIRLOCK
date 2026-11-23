class_name AirlockDoor
extends Node3D
## A bulkhead with a door in it, in the AIRLOCK style: blue-grey steel plate,
## green side panels, hazard stripes, the AIRLOCK logo with a red light above.
##
## The door's open/closed state is the StationState key "door.<door_id>".
## Ways to operate it (set per door with `mode`):
##   manual_or_power  with main power: press E on the door.
##                    without power: break the emergency glass next to it and
##                    pull the manual release.
##   power_only       opens only with main power (magnetic lock).
##   sealed           never opens (hull breach or a later level).
##   airlock          operated by an AirlockChamber (two doors, never both open).
##
## The passage runs along this node's Z axis. Side A is +Z, side B is -Z.

@export var door_id := "door"
@export var destination := ""          ## small text under the logo
@export_enum("manual_or_power", "power_only", "sealed", "airlock") var mode := "manual_or_power"
@export var opening := Vector2(4.12, 2.56)
@export var plate := Vector2(12.5, 4.6)
@export var thickness := 0.3
@export var release_side_a := true
@export var release_side_b := true
@export var sign_side_a := true
@export var sign_side_b := true
## Door panels that already exist in a purchased model (moved up to open).
## If empty, this door builds its own two sliding leaves.
@export var external_model: NodePath
## Comma-separated node names (plain String: arrays were lost in exported builds).
@export var external_panel_names := ""
@export var external_open_offset := Vector3(0, 2.6, 0)
## Thin purchased gate meshes are see-through from behind: add a solid back.
@export var external_backing := true
@export var sealed_text := "SEALED"
@export var start_open := false
## False = use the doorway that already exists in a purchased model (no plate, no sign).
@export var build_plate := true

const DoorButtonScript := preload("res://systems/doors/door_button.gd")
const ReleaseBoxScript := preload("res://systems/doors/release_box.gd")

var station: StationState
var _panels: Array[Node3D] = []
var _panel_closed: Array[Vector3] = []
var _panel_open: Array[Vector3] = []
var _blocker: CollisionShape3D
var _lamp: StandardMaterial3D
var _open_amount := 0.0
var _target := 0.0


func key() -> String:
	return "door." + door_id


func is_open() -> bool:
	return station != null and station.get_value(key(), "closed") == "open"


func has_power() -> bool:
	return station != null and station.is_true("power")


func _ready() -> void:
	station = Level.instance.station if Level.instance != null else null
	_build()
	if station != null:
		station.changed.connect(_on_state_changed)
		if multiplayer.is_server() and station.get_value(key()) == null:
			station.set_value(key(), "open" if start_open else "closed")
	_target = 1.0 if is_open() else 0.0
	_open_amount = _target
	_apply_panels()


## Host only. Open or close (used by buttons, releases, airlock chamber).
func set_open(open: bool) -> void:
	if station != null and mode != "sealed":
		station.set_value(key(), "open" if open else "closed")


func toggle() -> void:
	set_open(not is_open())


func _on_state_changed(changed_key: String, _value: Variant) -> void:
	if changed_key == key():
		_target = 1.0 if is_open() else 0.0
		Sfx.play_at("door", global_position)
	if changed_key == key() or changed_key == "power":
		_refresh_lamp()


func _process(delta: float) -> void:
	if is_equal_approx(_open_amount, _target):
		return
	_open_amount = move_toward(_open_amount, _target, delta / 1.4)
	_apply_panels()


func _apply_panels() -> void:
	var t := smoothstep(0.0, 1.0, _open_amount)
	for i in _panels.size():
		if is_instance_valid(_panels[i]):
			_panels[i].position = _panel_closed[i].lerp(_panel_open[i], t)
	if _blocker != null:
		_blocker.disabled = _open_amount > 0.6


func _refresh_lamp() -> void:
	if _lamp == null:
		return
	if mode == "sealed":
		Kit.set_glow(_lamp, Kit.WARNING_RED, 2.5)
	elif is_open():
		Kit.set_glow(_lamp, Kit.OK_GREEN, 1.5)
	else:
		Kit.set_glow(_lamp, Kit.WARNING_RED, 2.5)


# --- Construction ------------------------------------------------------------------

func _build() -> void:
	var steel := Kit.mat(Kit.STEEL, 0.7, 0.42)
	var dark := Kit.mat(Kit.STEEL_DARK, 0.7, 0.5)
	var green := Kit.mat(Kit.GREEN_PANEL, 0.5, 0.5)
	var half_open := opening.x * 0.5
	var side_w := (plate.x - opening.x) * 0.5
	var top_h := plate.y - opening.y

	if build_plate:
		_build_plate(steel, dark, green, half_open, side_w, top_h)
	_build_door(dark, half_open)


func _build_plate(steel: Material, dark: Material, green: Material, half_open: float, side_w: float, top_h: float) -> void:
	var body := StaticBody3D.new()
	body.name = "Bulkhead"
	add_child(body)
	# Plate = left + right + top pieces around the opening.
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * (half_open + side_w * 0.5), plate.y * 0.5, 0)
		Kit.box(self, Vector3(side_w, plate.y, thickness), c, steel)
		Kit.collider(body, Vector3(side_w, plate.y, thickness), c)
		# Green side panel flanking the door, on both faces.
		Kit.box(self, Vector3(0.55, opening.y * 0.9, thickness + 0.06),
			Vector3(sx * (half_open + 0.45), opening.y * 0.47, 0), green)
	var top_c := Vector3(0, opening.y + top_h * 0.5, 0)
	Kit.box(self, Vector3(opening.x, top_h, thickness), top_c, steel)
	Kit.collider(body, Vector3(opening.x, top_h, thickness), top_c)
	# Hazard stripe along the top of the doorway and a dark threshold frame.
	Kit.box(self, Vector3(opening.x + 0.3, 0.14, thickness + 0.08), Vector3(0, opening.y + 0.07, 0), Kit.hazard_material())
	Kit.box(self, Vector3(opening.x + 0.3, 0.05, thickness + 0.1), Vector3(0, 0.0, 0), dark)

	# Signage + red light, per side.
	_lamp = Kit.glow(Kit.WARNING_RED, 2.5)
	for side: float in [1.0, -1.0]:
		if (side > 0 and not sign_side_a) or (side < 0 and not sign_side_b):
			continue
		var holder := Node3D.new()
		holder.position = Vector3(0, opening.y + 0.42, side * (thickness * 0.5 + 0.03))
		if side < 0:
			holder.rotation.y = PI
		add_child(holder)
		Kit.box(holder, Vector3(1.9, 0.62, 0.03), Vector3(0, 0.12, -0.02), dark)
		Kit.airlock_logo(holder, Vector3(0, 0.0, 0.0), 1.0)
		if destination != "":
			Kit.label(holder, destination, Vector3(0, -0.14, 0), 30, Color(0.75, 0.8, 0.85), 0.0035)
		Kit.box(holder, Vector3(0.5, 0.09, 0.07), Vector3(0, 0.52, 0.0), _lamp)
		if side > 0 or not sign_side_a:
			var light := OmniLight3D.new()
			light.light_color = Color(1.0, 0.1, 0.06)
			light.light_energy = 0.9
			light.omni_range = 3.2
			light.position = Vector3(0, 0.5, 0.45)
			holder.add_child(light)


func _build_door(dark: Material, half_open: float) -> void:
	# Door panels.
	var door_body := StaticBody3D.new()
	door_body.name = "DoorBody"
	add_child(door_body)
	_blocker = Kit.collider(door_body, Vector3(opening.x, opening.y, 0.2), Vector3(0, opening.y * 0.5, 0))
	if external_panel_names == "":
		for sx: float in [-1.0, 1.0]:
			var leaf := Node3D.new()
			leaf.position = Vector3(sx * opening.x * 0.25, opening.y * 0.5, 0)
			add_child(leaf)
			Kit.box(leaf, Vector3(opening.x * 0.5, opening.y, 0.14), Vector3.ZERO, Kit.mat(Kit.STEEL.lightened(0.08), 0.75, 0.38))
			Kit.box(leaf, Vector3(opening.x * 0.5 - 0.3, 0.16, 0.17), Vector3(0, 0.25, 0), Kit.hazard_material())
			Kit.box(leaf, Vector3(0.1, opening.y * 0.8, 0.18), Vector3(-sx * (opening.x * 0.25 - 0.1), 0, 0), dark)
			_panels.append(leaf)
			_panel_closed.append(leaf.position)
			_panel_open.append(leaf.position + Vector3(sx * (opening.x * 0.5 - 0.06), 0, 0))
	else:
		var model := get_node_or_null(external_model)
		for panel_name in external_panel_names.split(",", false):
			var n := (model.find_child(panel_name.strip_edges(), true, false) as Node3D) if model != null else null
			if n != null:
				_panels.append(n)
				_panel_closed.append(n.position)
				_panel_open.append(n.position + n.get_parent_node_3d().global_transform.basis.inverse() * external_open_offset)
		if external_backing:
			var back := Node3D.new()
			back.position = Vector3(0, opening.y * 0.5, 0.07)
			add_child(back)
			Kit.box(back, Vector3(opening.x, opening.y, 0.1), Vector3.ZERO, Kit.mat(Kit.STEEL.lightened(0.05), 0.75, 0.4))
			Kit.box(back, Vector3(opening.x - 0.5, 0.18, 0.12), Vector3(0, 0.25, 0), Kit.hazard_material())
			Kit.box(back, Vector3(0.12, opening.y * 0.85, 0.12), Vector3(0, 0, 0), dark)
			_panels.append(back)
			_panel_closed.append(back.position)
			_panel_open.append(back.position + global_transform.basis.inverse() * external_open_offset)

	if mode == "sealed":
		for side: float in [1.0, -1.0]:
			var l := Kit.label(self, sealed_text, Vector3(0, opening.y * 0.55, side * 0.11), 56, Color(1.0, 0.25, 0.2), 0.004)
			if side < 0:
				l.rotation.y = PI

	# Buttons (aim at the door itself) and manual release boxes.
	for side: float in [1.0, -1.0]:
		var button := Area3D.new()
		button.name = "ButtonA" if side > 0 else "ButtonB"
		button.set_script(DoorButtonScript)
		button.set("door", self)
		button.set("size", Vector3(opening.x, opening.y, 0.25))
		button.position = Vector3(0, opening.y * 0.5, side * 0.22)
		add_child(button)
		var wants_release := release_side_a if side > 0 else release_side_b
		if wants_release and mode == "manual_or_power" and build_plate:
			var box := Area3D.new()
			box.name = "ReleaseA" if side > 0 else "ReleaseB"
			box.set_script(ReleaseBoxScript)
			box.set("door", self)
			box.set("side_name", "a" if side > 0 else "b")
			box.position = Vector3(side * (half_open + 1.15), 1.35, side * (thickness * 0.5 + 0.02))
			if side < 0:
				box.rotation.y = PI
			add_child(box)
	_refresh_lamp()
