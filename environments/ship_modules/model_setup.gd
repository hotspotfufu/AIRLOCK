class_name ModelSetup
extends Node3D
## Wraps an imported station model (GLB/FBX) and applies small fixes at load:
## removes parts we don't want (for example a wall that blocks a doorway) and
## can tint untextured models. Keeps the purchased files themselves untouched.

## Names of nodes inside the model to delete, separated by commas.
## (A plain String on purpose: PackedStringArray properties were lost in exported builds.)
@export var remove_nodes := ""
## If set, every surface of the model is multiplied by this colour.
@export var tint := Color.WHITE
## Extra roughness/metal tweak for untextured models (0 = leave as imported).
@export var force_roughness := 0.0
@export var force_metallic := -1.0


func _ready() -> void:
	for node_name in remove_nodes.split(",", false):
		var n := find_child(node_name.strip_edges(), true, false)
		if n != null:
			n.get_parent().remove_child(n)
			n.queue_free()
	if tint != Color.WHITE or force_roughness > 0.0 or force_metallic >= 0.0:
		_apply_material_tweaks()


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
