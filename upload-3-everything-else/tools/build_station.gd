extends SceneTree
## DEV TOOL (not part of the game, not exported).
## Rebuilds the whole station level from the purchased models and the layout
## written below, then saves:
##   levels/station/station.tscn          the playable level
##   levels/station/station_navmesh.res   walkable area for the AI crew
## Collision walls come from levels/station/collision_boxes.json, which is
## generated from the models' geometry (see docs/ASSET_PIPELINE.md).
##
## Run:  godot --headless --path . -s tools/build_station.gd
##       add "-- dump" to also write wall triangles for the collision generator.
##
## NOTE: station.tscn is generated. Change the layout here and re-run rather
## than hand-editing the scene, or your edits will be overwritten.

const OUT := "res://levels/station/station.tscn"
const NAV_OUT := "res://levels/station/station_navmesh.res"
const MODELS := "res://assets/models/station/"
const WALL_HEIGHT := 4.6

var ModelSetupS: Script
var StationS: Script
var StateS: Script
var DoorS: Script
var ChamberS: Script
var LightingS: Script
var AtmosphereS: Script
var ZoneS: Script
var SparksS: Script
var CellS: Script
var SocketS: Script
var BreakerS: Script
var ConsoleS: Script
var SupplyS: Script
var InspectS: Script
var SwarmDirectorS: Script

var root_node: Node3D


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	# Loaded here (not preloaded) so the game's autoloads exist first.
	ModelSetupS = load("res://environments/ship_modules/model_setup.gd")
	StationS = load("res://levels/station/station.gd")
	StateS = load("res://systems/state/station_state.gd")
	DoorS = load("res://systems/doors/airlock_door.gd")
	ChamberS = load("res://systems/doors/airlock_chamber.gd")
	LightingS = load("res://systems/lighting/lighting_controller.gd")
	AtmosphereS = load("res://systems/atmosphere/atmosphere.gd")
	ZoneS = load("res://systems/zones/zone.gd")
	SparksS = load("res://systems/zones/sparks.gd")
	CellS = load("res://systems/items/power_cell.gd")
	SocketS = load("res://systems/power/cell_socket.gd")
	BreakerS = load("res://systems/power/breaker.gd")
	ConsoleS = load("res://systems/interaction/state_console.gd")
	SupplyS = load("res://systems/interaction/supply_station.gd")
	InspectS = load("res://systems/interaction/inspect_point.gd")
	SwarmDirectorS = load("res://alien/swarm/swarm_director.gd")
	root_node = Node3D.new()
	root_node.name = "Station"
	root_node.set_script(StationS)

	var state := Node.new()
	state.name = "StationState"
	state.set_script(StateS)
	root_node.add_child(state)

	_environment()
	var geo := _geometry()
	_collision()
	_lighting()
	_doors()
	_devices()
	_zones_and_triggers()
	_swarm_routes()
	_spawns()

	if args.has("dump"):
		# Needs the models inside the tree to read world positions.
		var copy := geo.duplicate()
		root.add_child(copy)
		await process_frame
		await process_frame
		_dump_triangles(copy, "/tmp/station_tris.bin")
		copy.queue_free()

	await _bake_navigation()

	_own(root_node, root_node)
	var ps := PackedScene.new()
	print("pack: ", ps.pack(root_node))
	print("save station: ", ResourceSaver.save(ps, OUT))
	quit()


# --- helpers -----------------------------------------------------------------------

func _own(n: Node, scene_owner: Node) -> void:
	for c in n.get_children():
		c.owner = scene_owner
		if c.scene_file_path == "":
			_own(c, scene_owner)


func _xf(pos: Vector3, yaw_deg := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), pos)


func _group(node_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = node_name
	root_node.add_child(n)
	return n


func _scripted(parent: Node, node_name: String, script: Script, base: Node, xf: Transform3D, props := {}) -> Node:
	base.name = node_name
	base.set_script(script)
	if base is Node3D:
		(base as Node3D).transform = xf
	for k: String in props:
		base.set(k, props[k])
	parent.add_child(base)
	return base


# --- environment -------------------------------------------------------------------

func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://environments/sky_stars.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.4, 0.6)
	env.ambient_light_energy = 0.09
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.03, 0.05)
	env.fog_density = 0.018
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	root_node.add_child(we)


# --- purchased models ---------------------------------------------------------------

func _model(parent: Node3D, node_name: String, file: String, xf: Transform3D, remove := "", tint := Color.WHITE) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.set_script(ModelSetupS)
	holder.remove_nodes = remove
	holder.tint = tint
	holder.transform = xf
	parent.add_child(holder)
	var inst: Node3D = load(MODELS + file).instantiate()
	inst.name = "Model"
	holder.add_child(inst)
	return holder


func _geometry() -> Node3D:
	var geo := _group("Geometry")
	# Central junction: "Sci-Fi Horror Corridor" (plus-shaped, 4 gates).
	_model(geo, "Junction", "junction.glb", Transform3D.IDENTITY)
	# East: medical bay + control room ("Moon Base").
	_model(geo, "Medbay", "moon_base.fbx", _xf(Vector3(24.74, 0, -5.03)),
		"DM_Gate_01_001", Color(0.62, 0.66, 0.7))
	# West: engineering ("Sci-Fi Space Station Corridor" interior).
	_model(geo, "Engineering", "room_interior.glb", _xf(Vector3(-31.38, 0, 8.18), 90.0), "", Color(0.55, 0.57, 0.6))
	# South: service tunnel (airlock chamber, then zero-g and vacuum).
	_model(geo, "Tunnel", "tunnel.glb",
		Transform3D(Basis.from_scale(Vector3(-1.3, 1, -0.3)), Vector3(0, 0, 17.74)))
	# North: observation corridor, three window modules.
	for i in 3:
		_model(geo, "Observation%d" % (i + 1), "window_corridor.glb",
			Transform3D(Basis.from_scale(Vector3.ONE * 1.5), Vector3(0, 1.44, -20.74 - 6.0 * i)))
	return geo


# --- collision -----------------------------------------------------------------------

func _box_shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func _slab(body: StaticBody3D, x0: float, z0: float, x1: float, z1: float, top := 0.0, thick := 0.6) -> void:
	_box_shape(body, Vector3(x1 - x0, thick, z1 - z0), Vector3((x0 + x1) * 0.5, top - thick * 0.5, (z0 + z1) * 0.5))


func _collision() -> void:
	var walls := StaticBody3D.new()
	walls.name = "Walls"
	root_node.add_child(walls)
	var boxes: Array = JSON.parse_string(FileAccess.get_file_as_string("res://levels/station/collision_boxes.json"))
	for b: Array in boxes:
		_box_shape(walls, Vector3(b[2] - b[0], WALL_HEIGHT, b[3] - b[1]),
			Vector3((b[0] + b[2]) * 0.5, WALL_HEIGHT * 0.5, (b[1] + b[3]) * 0.5))
	# Generator housing (see _devices).
	_box_shape(walls, Vector3(2.0, 0.95, 1.0), Vector3(-31.5, 0.475, 8.5))

	var floors := StaticBody3D.new()
	floors.name = "Floors"
	root_node.add_child(floors)
	_slab(floors, -17.6, -3.6, 17.6, 3.6)        # junction east-west arms
	_slab(floors, -3.6, -17.6, 3.6, 17.6)        # junction north-south arms
	_slab(floors, -6.3, -6.3, 6.3, 6.3)          # junction hub
	_slab(floors, 17.4, -6.4, 61.0, 6.4)         # medical bay + control room
	_slab(floors, 36.0, 6.0, 47.0, 14.4)         # medical bay lounge
	_slab(floors, -44.2, -2.6, -17.4, 15.0)      # engineering
	_slab(floors, -2.3, -36.0, 2.3, -17.4)       # observation corridor
	# Ceilings where the models are open or the player can float.
	_slab(floors, -2.3, -36.0, 2.3, -17.4, 3.5)  # observation
	_slab(floors, -3.2, 17.4, 3.2, 51.0, 4.6)    # tunnel roof

	# Tunnel floor is separate so the AI navmesh does not include it.
	var tunnel := StaticBody3D.new()
	tunnel.name = "TunnelFloor"
	root_node.add_child(tunnel)
	_slab(tunnel, -3.2, 17.4, 3.2, 51.0)


# --- lighting ------------------------------------------------------------------------

func _omni(parent: Node3D, pos: Vector3, color: Color, energy: float, light_range: float, flicker := false, shadows := false) -> void:
	var l := OmniLight3D.new()
	l.name = "L%d" % parent.get_child_count()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadows
	if flicker:
		l.set_meta("flicker", true)
	parent.add_child(l)


func _lighting() -> void:
	var lighting := _group("Lighting")
	lighting.set_script(LightingS)
	lighting.model_roots = "../Geometry/Junction,../Geometry/Medbay"
	var main := Node3D.new()
	main.name = "Main"
	lighting.add_child(main)
	var emergency := Node3D.new()
	emergency.name = "Emergency"
	lighting.add_child(emergency)

	var white := Color(0.92, 0.96, 1.0)
	var warm := Color(1.0, 0.93, 0.82)
	var red := Color(1.0, 0.1, 0.06)
	# Junction.
	_omni(main, Vector3(0, 3.0, 0), white, 1.5, 9.0)
	for p: Vector3 in [Vector3(0, 3.0, -12), Vector3(0, 3.0, 12), Vector3(12, 3.0, 0), Vector3(-12, 3.0, 0)]:
		_omni(main, p, white, 1.3, 6.5)
	_omni(emergency, Vector3(0, 2.9, 0), red, 1.1, 8.5)
	_omni(emergency, Vector3(0, 2.8, -12), red, 1.0, 6.0, true)
	_omni(emergency, Vector3(0, 2.8, 12), red, 1.0, 6.0)
	_omni(emergency, Vector3(12, 2.8, 0), red, 1.0, 6.0)
	_omni(emergency, Vector3(-12, 2.8, 0), red, 1.0, 6.0, true)
	# Medical bay, lounge, control room.
	_omni(main, Vector3(24, 3.5, 0), white, 1.5, 9.5)
	_omni(main, Vector3(37, 3.5, 0), white, 1.7, 9.5)
	_omni(main, Vector3(46, 3.5, 0), white, 1.7, 9.5)
	_omni(main, Vector3(41.5, 3.3, 10), warm, 1.2, 7.0)
	_omni(main, Vector3(56, 3.5, 0), white, 1.4, 7.5)
	_omni(emergency, Vector3(24, 3.4, 0), red, 1.0, 9.0)
	_omni(emergency, Vector3(41, 3.4, 0), red, 1.3, 11.0, true)
	_omni(emergency, Vector3(56, 3.4, 0), red, 0.9, 7.0)
	# Engineering.
	_omni(main, Vector3(-22, 3.2, 0), warm, 1.2, 7.0)
	_omni(main, Vector3(-32.5, 3.6, 3), warm, 1.6, 9.0)
	_omni(main, Vector3(-32.5, 3.6, 10), warm, 1.6, 9.0)
	_omni(main, Vector3(-41, 3.3, 12.5), warm, 1.1, 6.0)
	_omni(emergency, Vector3(-22, 3.0, 0), red, 0.9, 7.0, true)
	_omni(emergency, Vector3(-32.5, 3.5, 6.5), red, 1.3, 11.0)
	_omni(emergency, Vector3(-41, 3.2, 12.5), red, 0.8, 6.0)
	# Observation corridor: main lights only; starlight when power is out.
	_omni(main, Vector3(0, 2.5, -23), white, 0.9, 6.0)
	_omni(main, Vector3(0, 2.5, -31), white, 0.9, 6.0)

	# Lights that never change: starlight in the observation corridor and the
	# battery-backed beacons in the airlock tunnel.
	var always := _group("AlwaysLights")
	_omni(always, Vector3(0, 2.2, -27), Color(0.45, 0.6, 1.0), 0.35, 11.0)
	_omni(always, Vector3(0, 3.5, 20.4), Color(1.0, 0.45, 0.1), 0.7, 5.0)
	_omni(always, Vector3(0, 3.6, 31), red, 0.8, 9.0)
	_omni(always, Vector3(0, 3.6, 43), red, 0.8, 9.0)


# --- doors ----------------------------------------------------------------------------

func _door(parent: Node3D, node_name: String, xf: Transform3D, props: Dictionary) -> Node3D:
	return _scripted(parent, node_name, DoorS, Node3D.new(), xf, props) as Node3D


func _doors() -> void:
	var doors := _group("Doors")
	var junction := NodePath("../../Geometry/Junction")
	var gate_up := Vector3(0, 2.62, 0)
	_door(doors, "Medbay", _xf(Vector3(17.59, 0, 0), 90), {
		"door_id": "med", "destination": "MEDICAL  |  JUNCTION", "plate": Vector2(12.6, 4.6),
		"external_model": junction, "external_panel_names": "gate_002",
		"external_open_offset": gate_up})
	_door(doors, "Engineering", _xf(Vector3(-17.59, 0, 0), -90), {
		"door_id": "eng", "destination": "ENGINEERING  |  JUNCTION", "plate": Vector2(7.6, 4.6),
		"external_model": junction, "external_panel_names": "gate_003",
		"external_open_offset": gate_up})
	_door(doors, "Observation", _xf(Vector3(0, 0, -17.59), 180), {
		"door_id": "obs", "destination": "OBSERVATION  |  JUNCTION", "plate": Vector2(7.6, 4.6),
		"external_model": junction, "external_panel_names": "gate_001",
		"external_open_offset": gate_up})
	_door(doors, "TunnelInner", _xf(Vector3(0, 0, 17.59), 0), {
		"door_id": "tun_in", "destination": "SERVICE TUNNEL AIRLOCK", "plate": Vector2(7.6, 4.6),
		"mode": "airlock",
		"external_model": junction, "external_panel_names": "gate",
		"external_open_offset": gate_up})
	_door(doors, "TunnelOuter", _xf(Vector3(0, 0, 23.0), 180), {
		"door_id": "tun_out", "destination": "VACUUM BEYOND  |  ZERO-G", "plate": Vector2(6.4, 4.6),
		"opening": Vector2(1.7, 2.3), "mode": "airlock", "sign_side_b": false})
	_door(doors, "ControlRoom", _xf(Vector3(52.24, 0, 0), 90), {
		"door_id": "control", "mode": "power_only", "build_plate": false, "external_backing": false,
		"opening": Vector2(9.7, 3.8),
		"external_model": NodePath("../../Geometry/Medbay"),
		"external_panel_names": "DM_Gate_01",
		"external_open_offset": Vector3(0, 3.63, 0)})
	_door(doors, "CargoSealed", _xf(Vector3(0, 0, -35.9), 0), {
		"door_id": "cargo", "destination": "CARGO BAY", "mode": "sealed", "plate": Vector2(6.4, 4.0),
		"opening": Vector2(2.2, 2.4), "sign_side_b": false, "sealed_text": "SEALED\nHULL BREACH"})
	_door(doors, "ImpactSealed", _xf(Vector3(0, 0, 49.6), 180), {
		"door_id": "impact", "destination": "IMPACT ZONE", "mode": "sealed", "plate": Vector2(6.4, 4.6),
		"opening": Vector2(1.7, 2.3), "sign_side_b": false, "sealed_text": "SEALED\nIMPACT ZONE"})

	_scripted(root_node, "TunnelAirlock", ChamberS, Node3D.new(), _xf(Vector3(0, 0, 20.3)), {
		"chamber_id": "tunnel", "inner": NodePath("../Doors/TunnelInner"), "outer": NodePath("../Doors/TunnelOuter")})

	var sign := Label3D.new()
	sign.name = "ControlRoomSign"
	sign.text = "CONTROL ROOM"
	sign.font_size = 72
	sign.pixel_size = 0.005
	sign.modulate = Color(0.8, 0.88, 0.95)
	sign.transform = _xf(Vector3(51.6, 3.3, -3.4), -90)
	doors.add_child(sign)


# --- devices and items ------------------------------------------------------------------

func _static_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, metallic := 0.6) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = 0.45
	mesh.material = m
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)


func _devices() -> void:
	var dev := _group("Devices")
	# Generator in Engineering: housing built here, sockets on top.
	var gen := Node3D.new()
	gen.name = "Generator"
	gen.position = Vector3(-31.5, 0, 8.5)
	dev.add_child(gen)
	_static_box(gen, Vector3(2.0, 0.85, 1.0), Vector3(0, 0.425, 0), Color(0.16, 0.36, 0.26))
	_static_box(gen, Vector3(2.06, 0.1, 1.06), Vector3(0, 0.9, 0), Color(0.16, 0.18, 0.22))
	_static_box(gen, Vector3(0.5, 0.5, 1.04), Vector3(0, 0.45, 0), Color(0.34, 0.39, 0.46))
	var gen_label := Label3D.new()
	gen_label.text = "EMERGENCY GENERATOR\n2 POWER CELLS"
	gen_label.font_size = 40
	gen_label.pixel_size = 0.003
	gen_label.position = Vector3(0, 0.5, 0.53)
	gen.add_child(gen_label)
	_scripted(dev, "Socket0", SocketS, Area3D.new(), _xf(Vector3(-32.0, 1.2, 8.5)), {"index": 0})
	_scripted(dev, "Socket1", SocketS, Area3D.new(), _xf(Vector3(-31.0, 1.2, 8.5)), {"index": 1})
	# Main breakers on the east wall of Engineering, too far apart for one person.
	_scripted(dev, "BreakerA", BreakerS, Area3D.new(), _xf(Vector3(-27.15, 1.4, 5.2), -90), {"index": 0})
	_scripted(dev, "BreakerB", BreakerS, Area3D.new(), _xf(Vector3(-27.15, 1.4, 10.6), -90), {"index": 1})
	# Life support console in the Engineering side room.
	_scripted(dev, "LifeSupport", ConsoleS, Area3D.new(), _xf(Vector3(-42.4, 0.95, 12.5), 90), {
		"title": "LIFE SUPPORT", "action": "Restart air circulation", "sets_key": "vents",
		"done_message": "Air circulation restarted. Oxygen is recovering."})
	# Communications: one of the consoles that is part of the Moon Base model.
	_scripted(dev, "Comms", ConsoleS, Area3D.new(), _xf(Vector3(57.2, 1.35, 0.0), -90), {
		"title": "COMMS", "action": "Restore communications", "sets_key": "comms", "build_model": false,
		"done_message": "Communications restored. Transmitting distress call..."})
	# Emergency resources.
	_scripted(dev, "OxygenA", SupplyS, Area3D.new(), _xf(Vector3(24.0, 1.3, 4.85), 180), {"kind": "o2", "station_id": "o2_a"})
	_scripted(dev, "OxygenB", SupplyS, Area3D.new(), _xf(Vector3(-22.0, 1.3, 1.55), 180), {"kind": "o2", "station_id": "o2_b"})
	_scripted(dev, "MedScanner", SupplyS, Area3D.new(), _xf(Vector3(39.65, 1.45, -2.05), 0), {
		"kind": "med", "station_id": "med_a", "charges": 2})
	_scripted(dev, "ImpactInspect", InspectS, Area3D.new(), _xf(Vector3(0, 1.3, 49.2)), {
		"action": "Inspect the impact-zone bulkhead", "sets_key": "tunnel.inspected", "size": Vector3(1.8, 2.0, 0.5),
		"message": "The bulkhead is ice cold. Something on the other side is scratching at the metal."})

	# The two power cells (the level script moves them to random spots).
	var items := _group("Items")
	_scripted(items, "CellA", CellS, Area3D.new(), _xf(Vector3(2.5, 0.14, 8.5)), {"cell_id": "a"})
	_scripted(items, "CellB", CellS, Area3D.new(), _xf(Vector3(-2.4, 0.14, -12)), {"cell_id": "b"})
	var spots := _group("CellSpots")
	var i := 0
	for p: Vector3 in [Vector3(-1.2, 0.14, -14.6), Vector3(1.4, 0.14, 15.6), Vector3(-13.0, 0.14, 1.6),
			Vector3(4.6, 0.14, 4.3), Vector3(1.2, 0.14, -33.6), Vector3(20.5, 0.14, -4.2),
			Vector3(-1.0, 0.14, -24.5), Vector3(8.6, 0.14, 2.2)]:
		var m := Marker3D.new()
		m.name = "Spot%d" % i
		m.position = p
		spots.add_child(m)
		i += 1

	var atmo := Node.new()
	atmo.name = "Atmosphere"
	atmo.set_script(AtmosphereS)
	root_node.add_child(atmo)


# --- zones ------------------------------------------------------------------------------

func _zone(parent: Node3D, node_name: String, kind: String, centre: Vector3, size: Vector3, props := {}) -> void:
	var z := Area3D.new()
	z.name = node_name
	z.set_script(ZoneS)
	z.set("kind", kind)
	z.set("size", size)
	z.position = centre
	for k: String in props:
		z.set(k, props[k])
	parent.add_child(z)


func _zones_and_triggers() -> void:
	var zones := _group("Zones")
	# Service tunnel beyond the airlock: no gravity, no air.
	_zone(zones, "TunnelZeroG", "zero_g", Vector3(0, 2.3, 36.4), Vector3(6.4, 5.0, 26.4))
	_zone(zones, "TunnelVacuum", "vacuum", Vector3(0, 2.3, 36.4), Vector3(6.4, 5.0, 26.4))
	# Live cable arcing in the junction's east arm until main power re-routes it.
	_zone(zones, "LiveCable", "hazard", Vector3(10.7, 1.0, -2.5), Vector3(3.2, 2.0, 1.7),
		{"damage_per_second": 16.0, "disabled_by_key": "power"})
	_scripted(zones, "LiveCableSparks", SparksS, Node3D.new(), _xf(Vector3(10.7, 0.15, -2.7)), {"stops_when": "power"})

	var triggers := _group("Triggers")
	_zone(triggers, "FirstJunction", "trigger", Vector3(14.6, 1.5, 0), Vector3(2.5, 3, 6.6))
	_zone(triggers, "Observation", "trigger", Vector3(0, 1.5, -19.6), Vector3(4, 3, 2.5))
	_zone(triggers, "EngineeringEntry", "trigger", Vector3(-20.0, 1.5, 0), Vector3(3, 3, 3.4))


# --- swarm glimpse routes -----------------------------------------------------------------

func _route(parent: Node3D, node_name: String, points: Array) -> void:
	var r := Node3D.new()
	r.name = node_name
	parent.add_child(r)
	var i := 0
	for p: Vector3 in points:
		var m := Marker3D.new()
		m.name = "P%d" % i
		m.position = p
		r.add_child(m)
		i += 1


func _swarm_routes() -> void:
	var director := _group("SwarmDirector")
	director.set_script(SwarmDirectorS)
	_route(director, "HubCrossing", [Vector3(0.6, 3.0, -10), Vector3(-0.4, 2.5, -3.5), Vector3(-1.2, 1.7, 0.5),
		Vector3(0.6, 2.6, 5), Vector3(3.3, 1.7, 10.7)])
	_route(director, "OutsideWindow", [Vector3(5.2, 1.4, -37), Vector3(3.6, 2.3, -30), Vector3(4.6, 1.2, -24),
		Vector3(8.5, 3.2, -15)])
	_route(director, "EngineeringVent", [Vector3(-37.4, 3.7, 0.5), Vector3(-33.5, 3.0, 5), Vector3(-30.5, 3.4, 10),
		Vector3(-27.6, 3.9, 13.6)])
	_route(director, "TunnelEnd", [Vector3(1.2, 3.3, 48), Vector3(-0.9, 2.0, 44), Vector3(0.6, 3.0, 38),
		Vector3(0, 3.6, 30)])
	_route(director, "ArmNorth", [Vector3(3.3, 1.7, -12.7), Vector3(0, 2.9, -10.5), Vector3(-3.3, 1.7, -11.4)])
	_route(director, "MedbayCeiling", [Vector3(33, 3.7, -5), Vector3(40, 3.4, 0), Vector3(47, 3.7, 4.6)])
	_route(director, "ArmWest", [Vector3(-9.8, 3.1, 2.8), Vector3(-12, 2.2, 0), Vector3(-15.5, 3.1, -2.6)])


# --- spawn points ---------------------------------------------------------------------------

func _spawns() -> void:
	var sp := _group("SpawnPoints")
	var i := 1
	for p: Vector3 in [Vector3(34.0, 0.05, -1.5), Vector3(34.0, 0.05, 1.0), Vector3(36.5, 0.05, -1.5), Vector3(36.5, 0.05, 1.0)]:
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.transform = _xf(p, 90)  # facing the door to the junction (-X)
		sp.add_child(m)
		i += 1
	_group("Players")
	var spawner := MultiplayerSpawner.new()
	spawner.name = "PlayerSpawner"
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_limit = 4
	root_node.add_child(spawner)


# --- navigation (AI crew) -----------------------------------------------------------------------

func _bake_navigation() -> void:
	# Bake from a temporary copy of the walls and floors, plus stand-ins for
	# the door bulkheads (the real ones build themselves when the game runs).
	var temp := Node3D.new()
	temp.name = "NavSource"
	root.add_child(temp)
	for body_name: String in ["Walls", "Floors"]:
		temp.add_child(root_node.get_node(body_name).duplicate())
	var plates := StaticBody3D.new()
	temp.add_child(plates)
	for door: Node3D in root_node.get_node("Doors").get_children():
		if not door.get_script() == DoorS or not door.get("build_plate"):
			continue
		var opening: Vector2 = door.get("opening")
		var plate: Vector2 = door.get("plate")
		var side_w := (plate.x - opening.x) * 0.5
		for sx: float in [-1.0, 1.0]:
			var cs := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(side_w, plate.y, 0.3)
			cs.shape = shape
			cs.transform = door.transform * Transform3D(Basis.IDENTITY, Vector3(sx * (opening.x * 0.5 + side_w * 0.5), plate.y * 0.5, 0))
			plates.add_child(cs)
	await process_frame
	await physics_frame

	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 0.5
	navmesh.agent_height = 1.75
	navmesh.agent_max_climb = 0.25
	navmesh.cell_size = 0.25
	navmesh.cell_height = 0.25
	navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	navmesh.geometry_collision_mask = 1
	navmesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(navmesh, source, temp)
	NavigationServer3D.bake_from_source_geometry_data(navmesh, source)
	print("navmesh polygons: ", navmesh.get_polygon_count())
	print("save navmesh: ", ResourceSaver.save(navmesh, NAV_OUT))
	temp.queue_free()

	var region := NavigationRegion3D.new()
	region.name = "Navigation"
	region.navigation_mesh = load(NAV_OUT)
	root_node.add_child(region)


# --- collision source dump ----------------------------------------------------------------------

func _dump_triangles(geo: Node3D, path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var n := 0
	for mi: MeshInstance3D in geo.find_children("*", "MeshInstance3D", true, false):
		var nm := String(mi.name).to_lower()
		if nm.begins_with("gate") and not nm.begins_with("gate_frame"):
			continue
		if nm.begins_with("dm_gate") or mi.mesh == null:
			continue
		var xf := mi.global_transform
		var faces := mi.mesh.get_faces()
		var out := PackedFloat32Array()
		var i := 0
		while i < faces.size():
			var a := xf * faces[i]
			var b := xf * faces[i + 1]
			var c := xf * faces[i + 2]
			i += 3
			var lo := minf(a.y, minf(b.y, c.y))
			var hi := maxf(a.y, maxf(b.y, c.y))
			if hi < 0.3 or lo > 1.7:
				continue
			out.append_array([a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z])
			n += 1
		f.store_buffer(out.to_byte_array())
	f.close()
	print("dumped triangles: ", n)
