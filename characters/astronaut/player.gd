class_name Astronaut
extends CharacterBody3D
## One astronaut: a human player's, a remote player's, or an AI crew member's.
##
## Who simulates it ("authority"):
##   - a human's astronaut  -> that player's own machine (instant controls)
##   - an AI crew member    -> the host
## The simulating machine moves the body and tracks health, suit oxygen and
## flashlight battery. The MultiplayerSynchronizer (player.tscn) copies the
## result to everyone else, who only smooth and animate it.
##
## Origin of this body = the feet.

const SUIT_COLORS: Array[Color] = [
	Color(0.96, 0.96, 0.98), Color(1.0, 0.62, 0.26), Color(0.42, 0.66, 1.0), Color(0.5, 0.92, 0.55),
]
## PLACEHOLDER names until the creative director names the crew.
const CREW_NAMES: Array[String] = ["CREW 1", "CREW 2", "CREW 3", "CREW 4"]

@export_group("Movement (suit feels heavy: slow to start, slow to stop)")
@export var walk_speed := 2.9
@export var sprint_speed := 5.0
@export var crouch_speed := 1.4
@export var ground_accel := 6.5
@export var ground_decel := 8.5
@export var air_control := 1.5
@export var jump_velocity := 3.3
@export_group("Zero gravity")
@export var thruster_accel := 1.7
@export var float_max_speed := 3.2
@export var push_off_speed := 2.6
@export_group("Body")
@export var stand_height := 1.8
@export var crouch_height := 1.1
@export var eye_below_top := 0.14
@export_group("Look")
@export var mouse_sensitivity := 0.0022
@export var max_pitch_deg := 85.0
@export_group("Survival")
@export var suit_o2_seconds := 240.0     ## suit reserve when the air is bad
@export var battery_seconds := 420.0     ## flashlight runtime
@export var battery_recharge_seconds := 200.0

## Set by the level's spawn function BEFORE the node enters the tree.
var peer_id := 1
var slot := 0
var is_bot := false

# --- Replicated state (see MultiplayerSynchronizer in player.tscn) ----------
var sync_pos := Vector3.ZERO
var sync_yaw := 0.0
var look_pitch := 0.0
var is_crouching := false
var is_sprinting := false
var is_floating := false
var flashlight_on := true
var health := 100.0
var suit_o2 := 100.0
var battery := 100.0
var downed := false
var helmet_sealed := false

# --- Local / derived --------------------------------------------------------
## Id of the power cell this astronaut carries ("" = none). Set by PowerCell.
var carrying := ""
## What the local player is aiming at (HUD reads these).
var focused: Interactable = null
var hold_progress := 0.0
## AI input (written by BotBrain on the host).
var ai_wish_dir := Vector3.ZERO
var ai_sprint := false
var ai_yaw_target := 0.0
var ai_has_yaw_target := false

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var flashlight: SpotLight3D = $Head/Flashlight
@onready var flashlight_model: MeshInstance3D = $Head/Camera3D/FlashlightModel
@onready var collision: CollisionShape3D = $CollisionShape3D
@onready var name_label: Label3D = $NameLabel
@onready var visual: AstronautVisual = $Visual

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _capsule: CapsuleShape3D
var _current_height := 1.8
var _zones: Array[Zone] = []
var _spawn_transform := Transform3D.IDENTITY
var _bob_phase := 0.0
var _bob_amount := 0.0
var _land_dip := 0.0
var _was_on_floor := true
var _display_speed := 0.0
var _last_pos := Vector3.ZERO
var _interact_was_pressed := false
var _hold_time := 0.0
var _hold_consumed := false
var _held_target: Interactable = null
var _flicker := 1.0
var _hurt_flash := 0.0


func _enter_tree() -> void:
	# Must happen before _ready so the synchronizer knows who sends updates.
	set_multiplayer_authority(peer_id)


func _ready() -> void:
	_capsule = collision.shape as CapsuleShape3D
	_current_height = stand_height
	_spawn_transform = transform
	sync_pos = position
	sync_yaw = rotation.y
	_last_pos = position
	add_to_group("astronauts")
	name_label.text = crew_name()
	name_label.modulate = SUIT_COLORS[slot % 4].lerp(Color.WHITE, 0.3)
	# Mostly white suits with a colour wash, so the crew reads as one team.
	visual.setup(Color.WHITE.lerp(SUIT_COLORS[slot % 4], 0.55), slot + 1)
	visual.footstep.connect(_on_footstep)

	var local_human := is_local_human()
	camera.current = local_human
	flashlight_model.visible = local_human
	if local_human:
		visual.set_layers(2)  # render layer "own_body_hidden"
		camera.cull_mask &= ~2
		name_label.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		flashlight.shadow_enabled = false


func crew_name() -> String:
	return CREW_NAMES[slot % 4]


func is_local_human() -> bool:
	return not is_bot and is_multiplayer_authority()


func in_zone(kind: String) -> bool:
	for z in _zones:
		if is_instance_valid(z) and z.kind == kind and z.is_active():
			return true
	return false


func zones_entered(z: Zone) -> void:
	if not _zones.has(z):
		_zones.append(z)


func zones_exited(z: Zone) -> void:
	_zones.erase(z)


# --- Input (local human only) ------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_local_human() or not _accepting_input():
		return
	if event is InputEventMouseMotion and not downed:
		var motion := event as InputEventMouseMotion
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var limit := deg_to_rad(max_pitch_deg)
		look_pitch = clampf(look_pitch - motion.relative.y * mouse_sensitivity, -limit, limit)
	elif event.is_action_pressed("flashlight") and not downed:
		if battery > 1.0 or flashlight_on:
			flashlight_on = not flashlight_on
			Sfx.play_at("click", global_position)
	elif event.is_action_pressed("drop") and carrying != "" and Level.instance != null:
		Level.instance.request_drop.rpc_id(1)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_simulate(delta)
		sync_pos = position
		sync_yaw = rotation.y
	else:
		# Remote astronaut: glide toward the last received position.
		var k := clampf(delta * 14.0, 0.0, 1.0)
		if position.distance_to(sync_pos) > 4.0:
			position = sync_pos
		else:
			position = position.lerp(sync_pos, k)
		rotation.y = lerp_angle(rotation.y, sync_yaw, k)
	_apply_shared_visuals(delta)
	if is_local_human():
		_update_interaction(delta)
		_update_camera_feel(delta)


# --- Simulation (authority only) ---------------------------------------------

func _simulate(delta: float) -> void:
	var wish := Vector3.ZERO      # desired direction, world space, length 0..1
	var want_sprint := false
	var want_crouch := false
	var want_jump := false
	var jump_just := false

	if downed:
		pass
	elif is_bot:
		wish = ai_wish_dir
		want_sprint = ai_sprint
		if ai_has_yaw_target:
			rotation.y = rotate_toward(rotation.y, ai_yaw_target, delta * 4.0)
		look_pitch = lerpf(look_pitch, 0.0, delta * 3.0)
	elif _accepting_input():
		var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		wish = transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
		want_sprint = Input.is_action_pressed("sprint") and input_dir.y < 0.0
		want_crouch = Input.is_action_pressed("crouch")
		want_jump = Input.is_action_pressed("jump")
		jump_just = Input.is_action_just_pressed("jump")

	is_floating = in_zone("zero_g")
	if is_floating:
		_simulate_floating(delta, wish, want_jump, want_crouch, jump_just)
	else:
		_simulate_walking(delta, wish, want_sprint, want_crouch, jump_just)

	_simulate_vitals(delta)

	if position.y < -20.0:  # fell out of the station (should never happen)
		transform = _spawn_transform
		velocity = Vector3.ZERO


func _simulate_walking(delta: float, wish: Vector3, want_sprint: bool, want_crouch: bool, jump_just: bool) -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	var on_floor := is_on_floor()
	if not on_floor:
		velocity.y -= _gravity * delta

	if want_crouch:
		is_crouching = true
	elif is_crouching and _has_headroom():
		is_crouching = false

	var burdened := carrying != ""
	is_sprinting = want_sprint and not is_crouching and not burdened and on_floor and wish.length() > 0.1
	var speed := walk_speed
	if is_crouching:
		speed = crouch_speed
	elif is_sprinting:
		speed = sprint_speed
	if burdened:
		speed *= 0.85
	if helmet_sealed and suit_o2 <= 0.0:
		speed *= 0.6  # suffocating

	var target := wish.limit_length(1.0) * speed
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var rate := ground_accel if target.length() > horizontal.length() else ground_decel
	if not on_floor:
		rate = air_control
	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if jump_just and on_floor and not is_crouching and not burdened:
		velocity.y = jump_velocity

	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_land_dip = 0.09
	_was_on_floor = is_on_floor()


func _simulate_floating(delta: float, wish: Vector3, want_up: bool, want_down: bool, jump_just: bool) -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	is_crouching = false
	is_sprinting = false
	# Suit thrusters: weak push along where you look, plus up/down.
	var thrust := Vector3.ZERO
	if wish.length() > 0.05:
		var look_basis := head.global_transform.basis
		var local := transform.basis.inverse() * wish
		thrust = look_basis * Vector3(local.x, 0.0, local.z)
	if want_up:
		thrust += Vector3.UP
	if want_down:
		thrust += Vector3.DOWN
	velocity += thrust.limit_length(1.0) * thruster_accel * delta
	# Push off a surface you are touching for a quick start.
	if jump_just and get_slide_collision_count() > 0:
		var n := get_slide_collision(0).get_normal()
		velocity += (n + -head.global_transform.basis.z).normalized() * push_off_speed
	velocity = velocity.limit_length(float_max_speed)
	velocity *= 1.0 - 0.12 * delta  # almost no drag
	move_and_slide()
	_was_on_floor = false


func _simulate_vitals(delta: float) -> void:
	# Flashlight battery.
	if flashlight_on and not is_bot:
		battery = maxf(0.0, battery - 100.0 / battery_seconds * delta)
		if battery <= 0.0:
			flashlight_on = false
	else:
		battery = minf(100.0, battery + 100.0 / battery_recharge_seconds * delta)

	if downed:
		return

	# Breathing. AI crew are simplified: they don't use oxygen (documented).
	var level := Level.instance
	var breathable := true
	if level != null and level.station != null:
		var o2: float = level.station.get_value("atm.o2", 20.9)
		var co2: float = level.station.get_value("atm.co2", 0.04)
		breathable = o2 >= 16.0 and co2 < 3.0
	if in_zone("vacuum"):
		breathable = false
	helmet_sealed = not breathable
	if not is_bot:
		if helmet_sealed:
			suit_o2 = maxf(0.0, suit_o2 - 100.0 / suit_o2_seconds * delta)
			if suit_o2 <= 0.0:
				_hurt(5.0 * delta)
		else:
			suit_o2 = minf(100.0, suit_o2 + 1.2 * delta)
			if health < 60.0:
				health = minf(60.0, health + 1.0 * delta)  # catch your breath

		for z in _zones:
			if is_instance_valid(z) and z.kind == "hazard" and z.is_active():
				_hurt(z.damage_per_second * delta)

	if health <= 0.0 and not downed:
		downed = true
		velocity = Vector3.ZERO
		flashlight_on = false
		if level != null:
			if carrying != "":
				level.request_drop.rpc_id(1)
			level.report_downed.rpc_id(1)


func _hurt(amount: float) -> void:
	if amount <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_hurt_flash = 1.0


## Latest damage flash strength 0..1 (HUD draws a red vignette).
func get_hurt_flash() -> float:
	return _hurt_flash


## Sent by the host when a teammate finishes reviving this astronaut.
@rpc("any_peer", "call_local", "reliable")
func apply_revive() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not is_multiplayer_authority():
		return
	health = 45.0
	suit_o2 = maxf(suit_o2, 35.0)
	downed = false


## Host -> owner: refill suit oxygen / heal (O2 stations, medical beds).
@rpc("any_peer", "call_local", "reliable")
func apply_supply(o2_amount: float, health_amount: float) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not is_multiplayer_authority():
		return
	suit_o2 = minf(100.0, suit_o2 + o2_amount)
	health = minf(100.0, health + health_amount)


# --- Visuals (every machine) --------------------------------------------------

func _apply_shared_visuals(delta: float) -> void:
	# Smoothed horizontal speed from actual movement (works for remotes too).
	var moved := position - _last_pos
	_last_pos = position
	moved.y = 0.0
	var inst_speed := moved.length() / maxf(delta, 0.0001)
	_display_speed = lerpf(_display_speed, minf(inst_speed, 8.0), clampf(delta * 10.0, 0.0, 1.0))

	var target_height := crouch_height if is_crouching else stand_height
	if downed:
		target_height = 0.6
	_current_height = move_toward(_current_height, target_height, 4.0 * delta)
	_capsule.height = maxf(_current_height, _capsule.radius * 2.0)
	collision.position.y = _capsule.height * 0.5

	visual.animate(delta, _display_speed, is_crouching, is_floating, downed,
		flashlight_on, carrying != "", is_sprinting)
	name_label.position.y = _current_height + 0.3

	# Flashlight (flickers when the battery is nearly flat).
	if battery < 12.0 and flashlight_on:
		_flicker = 0.35 + 0.65 * float(randf() > 0.25)
	else:
		_flicker = 1.0
	flashlight.visible = flashlight_on
	flashlight.light_energy = 3.2 * _flicker * clampf(0.45 + battery / 60.0, 0.45, 1.0)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 1.5)

	if not is_local_human():
		head.position.y = _current_height - eye_below_top
		head.rotation.x = look_pitch


func _update_camera_feel(delta: float) -> void:
	# Weighty head-bob, landing dip, slight widen of view when sprinting.
	var moving := _display_speed > 0.4 and is_on_floor() and not is_floating
	_bob_amount = lerpf(_bob_amount, 1.0 if moving else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	_bob_phase += _display_speed * 2.7 * delta
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.35)
	var bob_y := -absf(sin(_bob_phase)) * 0.035 * _bob_amount
	var bob_x := cos(_bob_phase) * 0.012 * _bob_amount
	var eye := _current_height - eye_below_top
	head.position = Vector3(bob_x, eye + bob_y - _land_dip, 0.0)
	head.rotation.x = look_pitch
	head.rotation.z = lerpf(head.rotation.z, -bob_x * 0.6, clampf(delta * 8.0, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, 77.0 if is_sprinting else 72.0, clampf(delta * 5.0, 0.0, 1.0))
	# Held flashlight sways a little behind the view.
	flashlight_model.position = Vector3(0.3 + bob_x * 1.5, -0.25 + bob_y * 1.2, -0.5)


func _on_footstep() -> void:
	# Footstep sounds are switched off (players found them loud and distracting).
	# Drop a recorded step sound into assets/audio/sfx/step.wav and re-enable here.
	pass


# --- Interaction (local human) --------------------------------------------------

func _update_interaction(delta: float) -> void:
	var level := Level.instance
	if level == null:
		return
	var pressed := Input.is_action_pressed("interact") and _accepting_input() and not downed
	var just := pressed and not _interact_was_pressed
	_interact_was_pressed = pressed

	focused = null if downed else _raycast_interactable()
	if focused != null and focused.get_prompt(self) == "":
		focused = null

	# Release a held lever if we let go or look away.
	if _held_target != null and (not pressed or focused != _held_target):
		if is_instance_valid(_held_target):
			level.request_hold.rpc_id(1, level.get_path_to(_held_target), false)
		_held_target = null

	if focused == null or not pressed or not focused.can_use(self):
		_hold_time = 0.0
		hold_progress = 0.0
		if not pressed:
			_hold_consumed = false
		return

	if focused.continuous:
		if _held_target == null:
			_held_target = focused
			level.request_hold.rpc_id(1, level.get_path_to(focused), true)
	elif focused.hold_time <= 0.0:
		if just:
			level.request_interact.rpc_id(1, level.get_path_to(focused))
	elif not _hold_consumed:
		_hold_time += delta
		hold_progress = clampf(_hold_time / focused.hold_time, 0.0, 1.0)
		if hold_progress >= 1.0:
			level.request_interact.rpc_id(1, level.get_path_to(focused))
			_hold_consumed = true
			_hold_time = 0.0
			hold_progress = 0.0


func _raycast_interactable() -> Interactable:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * 3.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | Interactable.LAYER_BIT, [get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_from_inside = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	return hit["collider"] as Interactable


# --- Helpers --------------------------------------------------------------------

func _has_headroom() -> bool:
	var probe := CapsuleShape3D.new()
	probe.radius = _capsule.radius * 0.95
	probe.height = stand_height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.transform = global_transform.translated(Vector3.UP * (stand_height * 0.5 + 0.05))
	query.collision_mask = 1
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


## Input is ignored while the mouse is released (menus open).
func _accepting_input() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or has_meta("test_input")
