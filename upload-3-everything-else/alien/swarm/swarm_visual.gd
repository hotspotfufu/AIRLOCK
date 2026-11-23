class_name SwarmVisual
extends MultiMeshInstance3D
## The nanite organism as the crew glimpses it: a ribbon of a few hundred
## silver and black metal slivers that flows along a path and is gone.
## Each sliver follows the head of the swarm with its own small delay and
## spirals around the line of travel, which gives the twisting tendril look.
##
## PLACEHOLDER for the purchased "Swarm Morph" asset: this is drawn entirely
## from code. It is visual only (no AI, cannot hurt anyone yet).

const COUNT := 340

var path := PackedVector3Array()
var speed := 6.0

var _delay := PackedFloat32Array()
var _radius := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _phase := PackedFloat32Array()
var _history: Array[Vector3] = []
var _time := 0.0
var _travel := 0.0
var _length := 0.0
var _fade := 1.0
const HISTORY_STEP := 0.02


func _ready() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.045, 0.045, 0.2)
	var m := StandardMaterial3D.new()
	m.metallic = 1.0
	m.roughness = 0.22
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = Color(0.55, 0.6, 0.7)
	m.emission_energy_multiplier = 0.35
	mesh.material = m
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = COUNT
	for i in COUNT:
		_delay.append(pow(randf(), 1.6) * 0.7)
		_radius.append(randf_range(0.02, 0.26) * (0.35 + _delay[i] * 1.6))
		_spin.append(randf_range(3.0, 9.0) * (1.0 if randf() > 0.5 else -1.0))
		_phase.append(randf() * TAU)
		var silver := randf() > 0.45
		multimesh.set_instance_color(i, Color(0.8, 0.83, 0.88) if silver else Color(0.03, 0.03, 0.04))
	for i in range(1, path.size()):
		_length += path[i - 1].distance_to(path[i])
	top_level = true
	global_transform = Transform3D.IDENTITY
	custom_aabb = AABB(Vector3(-200, -50, -200), Vector3(400, 100, 400))
	Sfx.play_at("skitter", path[0] if path.size() > 0 else Vector3.ZERO, 2.0)


func _head(distance: float) -> Vector3:
	var d := clampf(distance, 0.0, _length)
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if d <= seg or i == path.size() - 1:
			var p := path[i - 1].lerp(path[i], clampf(d / maxf(seg, 0.001), 0.0, 1.0))
			# Restless wobble so it never moves in a dead straight line.
			return p + Vector3(sin(distance * 1.9) * 0.18, sin(distance * 2.7 + 1.0) * 0.14, cos(distance * 1.3) * 0.18)
		d -= seg
	return path[path.size() - 1]


func _process(delta: float) -> void:
	if path.size() < 2:
		queue_free()
		return
	_time += delta
	_travel += speed * delta
	while _history.size() * HISTORY_STEP < _time + HISTORY_STEP:
		_history.append(_head(_history.size() * HISTORY_STEP * speed))
	if _travel > _length:
		_fade = maxf(0.0, _fade - delta * 1.6)  # pours into the vent and thins out
		if _fade <= 0.0:
			queue_free()
			return
	for i in COUNT:
		var t := maxf(0.0, _time - _delay[i])
		var idx := mini(int(t / HISTORY_STEP), _history.size() - 1)
		var centre := _history[idx]
		var ahead := _history[mini(idx + 3, _history.size() - 1)]
		var forward := (ahead - centre)
		forward = forward.normalized() if forward.length() > 0.001 else Vector3.FORWARD
		var side := forward.cross(Vector3.UP)
		side = side.normalized() if side.length() > 0.01 else Vector3.RIGHT
		var up := side.cross(forward)
		var a := _phase[i] + _time * _spin[i]
		var offset := (side * cos(a) + up * sin(a)) * _radius[i] * (1.0 + 0.4 * sin(_time * 5.0 + _phase[i]))
		var basis := Basis.looking_at(forward + offset * 0.8, Vector3.UP if absf(forward.y) < 0.95 else Vector3.RIGHT)
		var shrink := _fade if _delay[i] < _fade else _fade * 0.5
		multimesh.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE * maxf(shrink, 0.001)), centre + offset))
