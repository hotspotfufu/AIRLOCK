extends Interactable
## Appears on an incapacitated astronaut so a teammate can revive them
## (hold E). Reviving restores some health and tops up suit oxygen.


func _setup() -> void:
	hold_time = 3.0
	size = Vector3(1.4, 0.9, 2.0)


func _physics_process(_delta: float) -> void:
	# Only aimable while the astronaut is actually down (otherwise this box
	# would block aiming at things near a teammate's legs).
	var owner_astronaut := get_parent() as Astronaut
	var shape := get_node_or_null("Shape") as CollisionShape3D
	if shape != null and owner_astronaut != null:
		shape.disabled = not owner_astronaut.downed


func get_prompt(who: Astronaut) -> String:
	var owner_astronaut := get_parent() as Astronaut
	if owner_astronaut == null or not owner_astronaut.downed or who == owner_astronaut:
		return ""
	return "Revive %s" % owner_astronaut.crew_name()


func can_use(who: Astronaut) -> bool:
	return not who.downed


func interact(who: Astronaut) -> void:
	var target := get_parent() as Astronaut
	if target != null and target.downed and not who.downed:
		target.apply_revive.rpc_id(target.get_multiplayer_authority())
		if Level.instance != null:
			Level.instance.announce("%s revived %s." % [who.crew_name(), target.crew_name()])
