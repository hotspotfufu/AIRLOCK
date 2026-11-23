class_name Sparks
extends Node3D
## A damaged live cable: bursts of sparks and a blue-white flash. Purely the
## visible part; the damage comes from a "hazard" Zone placed on top of it.
## Stops when the StationState key `stops_when` becomes true.

@export var stops_when := ""

var _particles: CPUParticles3D
var _light: OmniLight3D
var _timer := 0.5


func _ready() -> void:
	_particles = CPUParticles3D.new()
	_particles.one_shot = true
	_particles.emitting = false
	_particles.amount = 26
	_particles.lifetime = 0.55
	_particles.explosiveness = 0.95
	_particles.direction = Vector3.UP
	_particles.spread = 65.0
	_particles.initial_velocity_min = 1.5
	_particles.initial_velocity_max = 4.2
	_particles.gravity = Vector3(0, -9, 0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.015, 0.015, 0.06)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.5)
	mesh.material = m
	_particles.mesh = mesh
	add_child(_particles)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.7, 0.85, 1.0)
	_light.omni_range = 6.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.3, 0)
	add_child(_light)


func _process(delta: float) -> void:
	_light.light_energy = move_toward(_light.light_energy, 0.0, delta * 14.0)
	if stops_when != "" and Level.instance != null and Level.instance.station.is_true(stops_when):
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = randf_range(0.25, 2.2)
		_particles.restart()
		_light.light_energy = randf_range(1.5, 3.5)
		Sfx.play_at("click", global_position, -2.0, 1.6)
