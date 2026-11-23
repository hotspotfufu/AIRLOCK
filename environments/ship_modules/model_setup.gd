class_name ModelSetup
extends Node3D
## Wraps an imported station model (GLB/FBX) and applies fixes at load time,
## without changing the purchased files themselves:
##   - removes parts we don't want (a wall blocking a doorway, for example)
##   - "skins" models that arrived WITHOUT textures (Moon Base, Engineering):
##     each material gets a proper colour and a panel / floor texture taken
##     from the textured station models, so every room looks finished.
##     When the real texture files arrive this can be switched off (skin = "").

## Names of nodes inside the model to delete, separated by commas.
## (A plain String on purpose: PackedStringArray properties were lost in exported builds.)
@export var remove_nodes := ""
## Which material set to apply: "", "moon_base" or "engineering".
@export var skin := ""
## Old option, kept so existing scenes still load. Ignored when `skin` is set.
@export var tint := Color.WHITE
@export var force_roughness := 0.0
@export var force_metallic := -1.0

const TEX := "res://assets/textures/station/"

static var _skin_cache: Dictionary = {}


func _ready() -> void:
	for node_name in remove_nodes.split(",", false):
		var n := find_child(node_name.strip_edges(), true, false)
		if n != null:
			n.get_parent().remove_child(n)
			n.queue_free()
	if skin != "":
		_apply_skin()
	elif tint != Color.WHITE or force_roughness > 0.0 or force_metallic >= 0.0:
		_apply_material_tweaks()


# --- skins ------------------------------------------------------------------------

static func _tex(file: String) -> Texture2D:
	return load(TEX + file) if ResourceLoader.exists(TEX + file) else null


## Panel texture projected from all sides, so it needs no UV maps.
static func _panel(color: Color, file: String, scale: float, metallic := 0.55, roughness := 0.4,
		normal_file := "") -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _tex(file)
	m.metallic = metallic
	m.roughness = roughness
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	if normal_file != "":
		m.normal_enabled = true
		m.normal_texture = _tex(normal_file)
		m.normal_scale = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _plain(color: Color, metallic := 0.3, roughness := 0.5) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := _plain(color.darkened(0.5), 0.0, 0.4)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


static func _glass() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.7, 0.8, 0.22)
	m.metallic = 0.4
	m.roughness = 0.05
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Material name -> material, per skin. Names come from the purchased files.
static func _skin_table(skin_name: String) -> Dictionary:
	if _skin_cache.has(skin_name):
		return _skin_cache[skin_name]
	var t := {}
	match skin_name:
		"moon_base":
			# Matches the Fab preview: white glossy panels, orange accents, dark floor.
			t["Painted_White"] = _panel(Color(0.9, 0.91, 0.93), "trim.jpg", 0.35, 0.25, 0.32)
			t["Painted_Black"] = _panel(Color(0.2, 0.21, 0.24), "trim.jpg", 0.35, 0.5, 0.4)
			t["Painted_Orange"] = _plain(Color(0.95, 0.38, 0.1), 0.2, 0.45)
			t["Painted_Black_Floor"] = _panel(Color(0.3, 0.31, 0.34), "floor_tread.jpg", 0.5, 0.7, 0.35, "floor_tread_normal.png")
			t["Steel"] = _plain(Color(0.65, 0.67, 0.7), 0.9, 0.25)
			t["Sofa"] = _plain(Color(0.16, 0.17, 0.2), 0.0, 0.8)
			t["Glass"] = _glass()
			t["Glass Clear"] = _glass()
			t["Emissive_blue"] = _glow(Color(0.3, 0.7, 1.0), 2.0)
			t["ui"] = _glow(Color(0.3, 0.85, 1.0), 1.4)
			t["ui_off"] = _glow(Color(0.1, 0.3, 0.45), 0.6)
		"engineering":
			t["wall_01"] = _panel(Color(0.62, 0.66, 0.7), "wall_panel.jpg", 0.4, 0.55, 0.4)
			t["wall_02"] = _panel(Color(0.42, 0.46, 0.5), "trim.jpg", 0.45, 0.6, 0.38)
			t["Ceiling_01"] = _panel(Color(0.55, 0.58, 0.62), "trim.jpg", 0.4, 0.5, 0.45)
			t["Ceiling_02"] = _plain(Color(0.3, 0.32, 0.36), 0.6, 0.45)
			t["MI_Floor_01"] = _panel(Color(0.36, 0.37, 0.4), "floor_tread.jpg", 0.5, 0.7, 0.35, "floor_tread_normal.png")
			t["Prop_01"] = _panel(Color(0.32, 0.4, 0.36), "wall_panel.jpg", 0.8, 0.5, 0.45)
			t["MI_Chair_01"] = _plain(Color(0.14, 0.15, 0.18), 0.1, 0.7)
	_skin_cache[skin_name] = t
	return t


func _apply_skin() -> void:
	var table := _skin_table(skin)
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var key := src.resource_name if src != null else ""
			if table.has(key):
				mi.set_surface_override_material(s, table[key])
			elif src is BaseMaterial3D:
				# Anything not listed: keep it, but visible from both sides.
				var m := (src as BaseMaterial3D).duplicate() as BaseMaterial3D
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.set_surface_override_material(s, m)


func _apply_material_tweaks() -> void:
	var cache := {}
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if src == null:
				continue
			if not cache.has(src):
				var m := src.duplicate() as BaseMaterial3D
				m.albedo_color = src.albedo_color * tint
				if force_roughness > 0.0:
					m.roughness = force_roughness
				if force_metallic >= 0.0:
					m.metallic = force_metallic
				cache[src] = m
			mi.set_surface_override_material(s, cache[src])
