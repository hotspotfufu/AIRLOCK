class_name Zone
extends Area3D
## A box-shaped region with a special rule. Astronauts count which zones they
## are standing in (see Astronaut.in_zone).
##   vacuum  - no air: helmets seal and suit oxygen drains
##   zero_g  - no gravity: astronauts float
##   hazard  - hurts (`damage_per_second`) while `active`
##   trigger - emits `entered_first_time` once (used for scripted moments)

signal entered_first_time(who: Astronaut)

@export_enum("vacuum", "zero_g", "hazard", "trigger") var kind := "trigger"
@export var size := Vector3(4, 3, 4)
@export var damage_per_second := 0.0
## Hazards only: StationState key that switches the hazard OFF when true.
@export var disabled_by_key := ""

var _fired := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # players
	monitoring = true
	monitorable = false
	if get_node_or_null("Shape") == null:
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		add_child(shape)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func is_active() -> bool:
	if disabled_by_key != "" and Level.instance != null and Level.instance.station != null:
		return not Level.instance.station.is_true(disabled_by_key)
	return true


func _on_body_entered(body: Node3D) -> void:
	var who := body as Astronaut
	if who == null:
		return
	who.zones_entered(self)
	if kind == "trigger" and not _fired and not who.is_bot:
		_fired = true
		entered_first_time.emit(who)


func _on_body_exited(body: Node3D) -> void:
	var who := body as Astronaut
	if who != null:
		who.zones_exited(self)
