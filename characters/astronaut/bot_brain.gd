class_name BotBrain
extends Node
## AI crew member (runs on the host only). Used in solo play so the player
## still has a crew of four.
##
## What it does today:
##   - follows the nearest human through the station (navmesh pathfinding)
##   - sweeps its flashlight around when standing still
##   - walks to a lever/console and holds it when the level asks (two-person tasks)
##   - revives a downed human (each AI carries one medkit)
##   - calls out power cells it can see
## What it does NOT do yet: carry items, open doors on its own, use oxygen,
## enter zero-g sections, fight or flee. It is a helper, not a full player.

enum Task { FOLLOW, HOLD, REVIVE }

const REPATH_INTERVAL := 0.35

var me: Astronaut
var agent: NavigationAgent3D
var task := Task.FOLLOW
var hold_target: Interactable = null
var medkits := 1

var _repath := 0.0
var _goal := Vector3.ZERO
var _idle_yaw := 0.0
var _idle_timer := 0.0
var _stuck_time := 0.0
var _holding := false
var _revive_time := 0.0
var _revive_target: Astronaut = null
var _callout_cooldown := 8.0
var _called_out: Dictionary = {}


func _ready() -> void:
	me = get_parent() as Astronaut
	agent = me.get_node("NavigationAgent3D")
	_idle_yaw = me.rotation.y
	set_physics_process(multiplayer.is_server())


## Level asks this crew member to go and hold a lever (null = stop).
func assign_hold(target: Interactable) -> void:
	if hold_target == target:
		return
	_release_hold()
	hold_target = target


func is_free() -> bool:
	return hold_target == null and task != Task.REVIVE and not me.downed


func _physics_process(delta: float) -> void:
	me.ai_wish_dir = Vector3.ZERO
	me.ai_sprint = false
	me.ai_has_yaw_target = false
	var level := Level.instance
	if level == null or me.downed:
		_release_hold()
		return
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return  # navigation not ready on the very first frames

	var leader := _pick_leader(level)
	_revive_target = _pick_revive_target(level)
	if _revive_target != null:
		task = Task.REVIVE
	elif hold_target != null and is_instance_valid(hold_target):
		task = Task.HOLD
	else:
		task = Task.FOLLOW

	match task:
		Task.REVIVE:
			_release_hold()
			_do_revive(delta, level)
		Task.HOLD:
			_do_hold(delta)
		Task.FOLLOW:
			_do_follow(delta, leader)
	_callouts(delta, level)


func _pick_leader(level: Level) -> Astronaut:
	var best: Astronaut = null
	var best_d := INF
	for h in level.get_humans():
		var d := me.global_position.distance_squared_to(h.global_position) + (10000.0 if h.downed else 0.0)
		if d < best_d:
			best_d = d
			best = h
	return best


func _pick_revive_target(level: Level) -> Astronaut:
	if medkits <= 0:
		return null
	for h in level.get_humans():
		if not h.downed:
			continue
		# Only the closest AI with a medkit goes.
		var mine := me.global_position.distance_to(h.global_position)
		var closest := true
		for other in level.get_bots():
			if other == me or other.downed:
				continue
			var brain := other.get_node_or_null("BotBrain") as BotBrain
			if brain != null and brain.medkits > 0 and other.global_position.distance_to(h.global_position) < mine - 0.01:
				closest = false
		if closest:
			return h
	return null


func _do_follow(delta: float, leader: Astronaut) -> void:
	if leader == null:
		return
	if leader.is_floating:
		_idle_look(delta)  # AI crew wait outside zero-g sections
		return
	# Each AI keeps its own spot behind the leader so they don't pile up.
	var back := leader.global_transform.basis.z
	var side := leader.global_transform.basis.x
	var lane := float(me.slot) - 1.5
	var goal := leader.global_position + back * (1.8 + 0.5 * absf(lane)) + side * lane * 1.1
	var dist := me.global_position.distance_to(leader.global_position)
	if dist < 2.6:
		_idle_look(delta)
		return
	_move_to(delta, goal, dist > 8.0)
	# Hopelessly stuck or left far behind (closed door, etc.): catch up.
	if _stuck_time > 4.0 and dist > 9.0:
		me.global_position = leader.global_position + back * 1.2
		me.velocity = Vector3.ZERO
		_stuck_time = 0.0


func _do_hold(delta: float) -> void:
	var stand := hold_target.get_stand_point()
	var flat := me.global_position
	flat.y = stand.y
	if flat.distance_to(stand) > 0.55:
		if _holding:
			_release_hold_only()
		_move_to(delta, stand, false)
		return
	_face(hold_target.global_position)
	if not _holding and hold_target.can_use(me):
		_holding = true
		hold_target.set_held(me, true)


func _do_revive(delta: float, level: Level) -> void:
	var target := _revive_target
	if me.global_position.distance_to(target.global_position) > 1.6:
		_revive_time = 0.0
		_move_to(delta, target.global_position, true)
		return
	_face(target.global_position)
	_revive_time += delta
	if _revive_time >= 3.0:
		_revive_time = 0.0
		medkits -= 1
		target.apply_revive.rpc_id(target.get_multiplayer_authority())
		level.radio(me, "Got you. That was my only medkit, stay close.")


func _move_to(delta: float, goal: Vector3, sprint: bool) -> void:
	_repath -= delta
	if _repath <= 0.0 or _goal.distance_to(goal) > 1.5:
		_repath = REPATH_INTERVAL
		_goal = goal
		agent.target_position = goal
	if agent.is_navigation_finished():
		return
	var next := agent.get_next_path_position()
	var dir := next - me.global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return
	dir = dir.normalized()
	me.ai_wish_dir = dir
	me.ai_sprint = sprint
	me.ai_yaw_target = atan2(-dir.x, -dir.z)
	me.ai_has_yaw_target = true
	var speed := Vector2(me.velocity.x, me.velocity.z).length()
	_stuck_time = _stuck_time + delta if speed < 0.25 else 0.0


func _face(point: Vector3) -> void:
	var dir := point - me.global_position
	if Vector2(dir.x, dir.z).length() > 0.05:
		me.ai_yaw_target = atan2(-dir.x, -dir.z)
		me.ai_has_yaw_target = true


func _idle_look(delta: float) -> void:
	_stuck_time = 0.0
	_idle_timer -= delta
	if _idle_timer <= 0.0:
		_idle_timer = randf_range(2.5, 6.0)
		_idle_yaw = me.rotation.y + randf_range(-1.4, 1.4)
	me.ai_yaw_target = _idle_yaw
	me.ai_has_yaw_target = true


func _release_hold() -> void:
	_release_hold_only()
	hold_target = null


func _release_hold_only() -> void:
	if _holding and hold_target != null and is_instance_valid(hold_target):
		hold_target.set_held(me, false)
	_holding = false


func _callouts(delta: float, level: Level) -> void:
	_callout_cooldown -= delta
	if _callout_cooldown > 0.0:
		return
	for cell: Node3D in get_tree().get_nodes_in_group("power_cells"):
		if _called_out.has(cell.name) or not cell.has_method("is_loose") or not cell.is_loose():
			continue
		if me.global_position.distance_to(cell.global_position) < 7.0 and _can_see(cell.global_position):
			_called_out[cell.name] = true
			_callout_cooldown = 10.0
			level.radio(me, "Power cell over here.")
			return


func _can_see(point: Vector3) -> bool:
	var from := me.global_position + Vector3.UP * 1.5
	var query := PhysicsRayQueryParameters3D.create(from, point + Vector3.UP * 0.2, 1)
	return me.get_world_3d().direct_space_state.intersect_ray(query).is_empty()
