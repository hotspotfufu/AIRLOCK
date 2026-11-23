class_name SwarmDirector
extends Node3D
## Decides when the crew catches a glimpse of the organism.
##
## This is the first, small version of the pacing "director": no attacks,
## only sightings. The host picks a moment and a route; every player then
## sees the same swarm cross the same corridor and vanish. Routes are the
## child Path markers set up in the level (each child = one route, its
## Marker3D children = the points along it).
##   - scripted: trigger zones in the level call trigger_route("name")
##   - ambient: every so often, a route some distance from the crew
## NOT IMPLEMENTED YET: any real alien behaviour (hunting, hosts, three swarms).

@export var ambient_min_seconds := 75.0
@export var ambient_max_seconds := 160.0

var _timer := 60.0
var _routes: Dictionary = {}
var _quiet_until := 0.0
var _clock := 0.0


func _ready() -> void:
	for child in get_children():
		var pts := PackedVector3Array()
		for m: Node3D in child.get_children():
			pts.append(m.global_position)
		if pts.size() >= 2:
			_routes[String(child.name)] = pts
	_timer = randf_range(ambient_min_seconds, ambient_max_seconds)
	set_physics_process(multiplayer.is_server())


## Host: play a named route for everyone (ignored during the quiet period
## that follows any sighting, so scares never stack up).
func trigger_route(route: String, flicker := true, force := false) -> void:
	if not multiplayer.is_server() or not _routes.has(route):
		return
	if _clock < _quiet_until and not force:
		return
	_quiet_until = _clock + 25.0
	_play.rpc(route, flicker)


@rpc("authority", "call_local", "reliable")
func _play(route: String, flicker: bool) -> void:
	if not _routes.has(route):
		return
	var swarm := SwarmVisual.new()
	swarm.path = _routes[route]
	add_child(swarm)
	if flicker and Level.instance != null:
		var lights := Level.instance.get_node_or_null("Lighting") as LightingController
		if lights != null:
			lights.flicker_burst(1.2)


func _physics_process(delta: float) -> void:
	_clock += delta
	_timer -= delta
	if _timer > 0.0 or Level.instance == null:
		return
	_timer = randf_range(ambient_min_seconds, ambient_max_seconds)
	var humans := Level.instance.get_humans()
	if humans.is_empty():
		return
	var who: Astronaut = humans.pick_random()
	# Prefer a route that starts a fair distance away: seen, not met.
	var best := ""
	var best_score := INF
	for route: String in _routes:
		var d: float = who.global_position.distance_to(_routes[route][0])
		var score := absf(d - 16.0) + randf() * 6.0
		if d > 9.0 and score < best_score:
			best_score = score
			best = route
	if best != "":
		trigger_route(best, randf() > 0.5)
