class_name Astronaut
extends CharacterBody3D
## Playable astronaut — first-person controller.
##
## Network ownership: the player who controls this astronaut is its
## "multiplayer authority". Only that machine reads input and moves the body.
## The MultiplayerSynchronizer child (see player.tscn) then copies position,
## facing, look pitch, crouch and flashlight state to the other three players.
## This is client-authoritative movement: instant-feeling controls, fine for
## friends-only co-op. Shared world state (doors, power, alien) stays
## host-authoritative in later milestones.
##
## Origin of this body = the astronaut's feet.

@export_group("Movement")
@export var walk_speed := 3.2         ## m/s
@export var sprint_speed := 5.4       ## m/s, forward only
@export var crouch_speed := 1.6       ## m/s
@export var acceleration := 10.0      ## higher = snappier starts/stops
@export_group("Body")
@export var stand_height := 1.8       ## m
@export var crouch_height := 1.1      ## m, fits 1.2 m maintenance crawlspaces
@export var crouch_transition_speed := 5.0
@export var eye_below_top := 0.15     ## m from top of head to eyes
@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var max_pitch_deg := 85.0

## Set by the level's spawn function BEFORE the node enters the tree.
var peer_id := 1
var slot := 0

# --- Replicated state (listed in player.tscn's MultiplayerSynchronizer) ---
var look_pitch := 0.0
var is_crouching := false
var flashlight_on := true

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Flashlight
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var name_label: Label3D = $NameLabel

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _current_height := 1.8
var _capsule: CapsuleShape3D

const OWN_BODY_RENDER_LAYER := 2  # render layer 2 = "own_body_hidden" (bit value 2)


func _enter_tree() -> void:
	# Must happen before _ready so the synchronizer knows who sends updates.
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	_capsule = collision.shape as CapsuleShape3D
	_current_height = stand_height
	name_label.text = "ASTRONAUT %d" % (slot + 1)

	var is_local := is_multiplayer_authority()
	camera.current = is_local
	if is_local:
		# Don't render our own body/visor from inside our own head.
		camera.cull_mask &= ~OWN_BODY_RENDER_LAYER
		name_label.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or not _accepting_input():
		return
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var limit := deg_to_rad(max_pitch_deg)
		look_pitch = clampf(look_pitch - motion.relative.y * mouse_sensitivity, -limit, limit)
	elif event.is_action_pressed("flashlight"):
		flashlight_on = not flashlight_on


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_simulate_movement(delta)
	_apply_shared_visuals(delta)


func _simulate_movement(delta: float) -> void:
	var accepting := _accepting_input()

	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Crouch: hold to crouch; only stand up if there is headroom.
	if accepting and Input.is_action_pressed("crouch"):
		is_crouching = true
	elif is_crouching and _has_headroom():
		is_crouching = false

	var input_dir := Vector2.ZERO
	if accepting:
		input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif accepting and Input.is_action_pressed("sprint") and input_dir.y < 0.0:
		speed = sprint_speed

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.lerp(wish_dir * speed, clampf(acceleration * delta, 0.0, 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()


## Runs on every machine so remote astronauts look right too.
func _apply_shared_visuals(delta: float) -> void:
	head.rotation.x = look_pitch
	flashlight.visible = flashlight_on

	var target_height := crouch_height if is_crouching else stand_height
	_current_height = move_toward(_current_height, target_height, crouch_transition_speed * delta)
	_capsule.height = _current_height
	collision.position.y = _current_height * 0.5
	head.position.y = _current_height - eye_below_top
	$BodyMesh.scale.y = _current_height / stand_height
	$BodyMesh.position.y = _current_height * 0.5
	name_label.position.y = _current_height + 0.35


func _has_headroom() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = _capsule.radius * 0.95
	probe.height = stand_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = global_transform.translated(Vector3.UP * (stand_height * 0.5 + 0.05))
	query.collision_mask = 1  # world only
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Input is ignored while the mouse is released (menus open).
func _accepting_input() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
