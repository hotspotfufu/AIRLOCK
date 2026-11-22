class_name Kit
extends RefCounted
## Small helpers for building simple station props from code (panels, levers,
## door plates). Everything made here is a stand-in shape in the AIRLOCK
## colour scheme: blue-grey steel, green side panels, red warning lights.

const STEEL := Color(0.34, 0.39, 0.46)
const STEEL_DARK := Color(0.16, 0.18, 0.22)
const GREEN_PANEL := Color(0.16, 0.36, 0.26)
const WARNING_RED := Color(0.85, 0.08, 0.05)
const SCREEN_OFF := Color(0.02, 0.03, 0.04)
const OK_GREEN := Color(0.15, 1.0, 0.35)
const AMBER := Color(1.0, 0.6, 0.1)
const CYAN := Color(0.2, 0.9, 1.0)

static var _cache: Dictionary = {}
static var _hazard_tex: ImageTexture


static func mat(color: Color, metallic := 0.6, roughness := 0.45) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f" % [color.to_html(), metallic, roughness]
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.metallic = metallic
		m.roughness = roughness
		_cache[key] = m
	return _cache[key]


## A glowing material. NOT shared, so each lamp can change colour on its own.
static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.6)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func set_glow(m: StandardMaterial3D, color: Color, energy := 2.0) -> void:
	m.albedo_color = color.darkened(0.6)
	m.emission = color
	m.emission_energy_multiplier = energy


static func box(parent: Node, size: Vector3, pos: Vector3, material: Material, node_name := "") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material
	if node_name != "":
		mi.name = node_name
	parent.add_child(mi)
	return mi


static func cylinder(parent: Node, radius: float, height: float, pos: Vector3, material: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = material
	parent.add_child(mi)
	return mi


static func label(parent: Node, text: String, pos: Vector3, font_size := 48, color := Color.WHITE, pixel := 0.004) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = font_size
	l.pixel_size = pixel
	l.modulate = color
	l.outline_size = 0
	l.position = pos
	l.shaded = false
	parent.add_child(l)
	return l


static func collider(body: PhysicsBody3D, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)
	return cs


## Red-and-white diagonal hazard stripes (generated, no image file needed).
static func hazard_material() -> StandardMaterial3D:
	if _hazard_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
		for y in 64:
			for x in 64:
				var stripe := ((x + y) / 16) % 2 == 0
				img.set_pixel(x, y, Color(0.8, 0.08, 0.05) if stripe else Color(0.9, 0.9, 0.88))
		_hazard_tex = ImageTexture.create_from_image(img)
	var m := StandardMaterial3D.new()
	m.albedo_texture = _hazard_tex
	m.roughness = 0.7
	m.uv1_scale = Vector3(6, 1, 1)
	return m


## The AIRLOCK mark: small white ringed planet above the word.
static func airlock_logo(parent: Node, pos: Vector3, scale := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "AirlockLogo"
	root.position = pos
	root.scale = Vector3.ONE * scale
	parent.add_child(root)
	var white := StandardMaterial3D.new()
	white.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	white.albedo_color = Color(0.92, 0.92, 0.9)
	var planet := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.085
	sphere.height = 0.17
	planet.mesh = sphere
	planet.material_override = white
	planet.position = Vector3(0, 0.23, 0)
	root.add_child(planet)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.125
	torus.outer_radius = 0.15
	ring.mesh = torus
	ring.material_override = white
	ring.position = planet.position
	ring.rotation_degrees = Vector3(72, 0, 18)
	root.add_child(ring)
	var word := label(root, "AIRLOCK", Vector3.ZERO, 64, Color(0.92, 0.92, 0.9), 0.0042)
	word.name = "Word"
	return root
