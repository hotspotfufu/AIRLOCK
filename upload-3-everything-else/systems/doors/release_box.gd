extends Interactable
## Emergency manual release beside a door. First break the glass (short hold),
## which exposes the release lever; then pull the lever (long hold) to crank
## the door open or closed without power.

var door: AirlockDoor
var side_name := "a"

var _glass: MeshInstance3D
var _lever: Node3D


func _setup() -> void:
	size = Vector3(0.6, 0.7, 0.35)
	Kit.box(self, Vector3(0.5, 0.6, 0.12), Vector3(0, 0, 0.06), Kit.mat(Kit.WARNING_RED, 0.3, 0.55))
	Kit.box(self, Vector3(0.4, 0.5, 0.02), Vector3(0, 0, 0.125), Kit.mat(Color(0.05, 0.05, 0.06), 0.2, 0.8))
	_lever = Node3D.new()
	_lever.position = Vector3(0, -0.12, 0.14)
	add_child(_lever)
	Kit.box(_lever, Vector3(0.06, 0.3, 0.05), Vector3(0, 0.15, 0), Kit.mat(Color(0.95, 0.8, 0.1), 0.3, 0.5))
	var glass_mat := StandardMaterial3D.new()
	glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass_mat.albedo_color = Color(0.6, 0.85, 1.0, 0.28)
	glass_mat.roughness = 0.05
	glass_mat.metallic = 0.3
	_glass = Kit.box(self, Vector3(0.44, 0.54, 0.015), Vector3(0, 0, 0.2), glass_mat)
	Kit.label(self, "EMERGENCY\nRELEASE", Vector3(0, 0.42, 0.13), 26, Color(1, 0.95, 0.9), 0.003)
	_refresh()


func _glass_key() -> String:
	return "door.%s.glass_%s" % [door.door_id, side_name]


func _broken() -> bool:
	return station != null and station.is_true(_glass_key())


func get_prompt(_who: Astronaut) -> String:
	if door == null:
		return ""
	if not _broken():
		return "Break emergency glass"
	return "Pull manual release (%s door)" % ("close" if door.is_open() else "open")


func interact(_who: Astronaut) -> void:
	if not _broken():
		station.set_value(_glass_key(), true)
	else:
		door.toggle()


func _physics_process(_delta: float) -> void:
	# Breaking the glass is quick; cranking the door takes effort.
	hold_time = 0.5 if not _broken() else 2.2


func _on_state_changed(changed_key: String, _value: Variant) -> void:
	if changed_key == _glass_key():
		_refresh()
		Sfx.play_at("glass", global_position)
		_spawn_shards()
	elif door != null and changed_key == door.key():
		_lever.rotation.x = 1.2 if door.is_open() else 0.0


func _refresh() -> void:
	if _glass != null:
		_glass.visible = not _broken()


func _spawn_shards() -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 24
	p.lifetime = 0.9
	p.explosiveness = 1.0
	p.direction = Vector3(0, 0, 1)
	p.spread = 50.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -7, 0)
	var shard := BoxMesh.new()
	shard.size = Vector3(0.03, 0.03, 0.004)
	p.mesh = shard
	p.position = Vector3(0, 0, 0.2)
	add_child(p)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
