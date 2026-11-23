class_name AstronautVisual
extends Node3D
## The astronaut's visible body and its animation.
##
## The purchased astronaut is a single solid statue (no skeleton), so the
## build pipeline cuts it into seven rigid pieces with joints at the hips,
## knees and shoulders (tools: make_astronaut.py). This script swings those
## pieces from code: walk/run cycle, crouch, carrying, floating, lying down.
## PLACEHOLDER: when a properly rigged model (e.g. via Mixamo) is available,
## replace this script with an AnimationTree; nothing else needs to change.

signal footstep

const THIGH_LEN := 0.378
const SHIN_LEN := 0.432
const HIP_HEIGHT := 0.81

var torso: Node3D
var arm_l: Node3D
var arm_r: Node3D
var thigh_l: Node3D
var thigh_r: Node3D
var shin_l: Node3D
var shin_r: Node3D

var _phase := 0.0
var _amp := 0.0
var _crouch := 0.0
var _down := 0.0
var _float := 0.0
var _arm_r_raise := 0.0
var _carry := 0.0
var _last_step_sign := 1.0


func _ready() -> void:
	torso = find_child("Torso", true, false)
	arm_l = find_child("ArmL", true, false)
	arm_r = find_child("ArmR", true, false)
	thigh_l = find_child("ThighL", true, false)
	thigh_r = find_child("ThighR", true, false)
	shin_l = find_child("ShinL", true, false)
	shin_r = find_child("ShinR", true, false)


## Suit colour + number so the four astronauts can be told apart.
func setup(suit_color: Color, number: int) -> void:
	var shared: StandardMaterial3D = null
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		if shared == null:
			var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
			shared = src.duplicate() if src != null else StandardMaterial3D.new()
			shared.albedo_color = suit_color
			shared.roughness = 0.65
			shared.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.set_surface_override_material(0, shared)
	if torso != null and torso.get_node_or_null("BackNumber") == null:
		var label := Label3D.new()
		label.name = "BackNumber"
		label.text = "%02d" % number
		label.font_size = 96
		label.pixel_size = 0.0016
		label.modulate = Color(0.08, 0.09, 0.1)
		label.outline_size = 0
		label.position = Vector3(0, 0.62, 0.295)
		torso.add_child(label)


## Hide/show for the local first-person player (own body is not drawn).
func set_layers(layer_bits: int) -> void:
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		mi.layers = layer_bits
		# Otherwise the player's own (invisible) arm shadows their flashlight.
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var label := find_child("BackNumber", true, false) as Label3D
	if label != null:
		label.layers = layer_bits


func animate(delta: float, speed: float, crouching: bool, floating: bool, downed: bool,
		flashlight_on: bool, carrying: bool, sprinting: bool) -> void:
	if torso == null:
		return
	var k := clampf(delta * 8.0, 0.0, 1.0)
	_amp = lerpf(_amp, clampf(speed / 3.0, 0.0, 1.0) * (0.0 if floating or downed else 1.0), k)
	_crouch = lerpf(_crouch, 1.0 if crouching and not floating else 0.0, k)
	_down = lerpf(_down, 1.0 if downed else 0.0, clampf(delta * 3.0, 0.0, 1.0))
	_float = lerpf(_float, 1.0 if floating and not downed else 0.0, clampf(delta * 3.0, 0.0, 1.0))
	_arm_r_raise = lerpf(_arm_r_raise, 1.0 if flashlight_on and not downed else 0.0, k)
	_carry = lerpf(_carry, 1.0 if carrying and not downed else 0.0, k)

	_phase += speed * 2.7 * delta
	var s := sin(_phase)
	if _amp > 0.25 and signf(s) != _last_step_sign:
		_last_step_sign = signf(s)
		footstep.emit()

	var swing := s * 0.55 * _amp
	var lean := (0.10 if sprinting else 0.03) * _amp + 0.35 * _crouch
	var crouch_thigh := 1.05 * _crouch + 0.35 * _float
	var crouch_shin := 1.9 * _crouch + 0.7 * _float

	var tl := swing + crouch_thigh
	var tr := -swing + crouch_thigh
	var sl := -maxf(0.0, sin(_phase - 0.9)) * 0.9 * _amp - crouch_shin
	var sr := -maxf(0.0, sin(_phase - 0.9 + PI)) * 0.9 * _amp - crouch_shin

	torso.rotation.x = -lean
	thigh_l.rotation.x = tl + lean
	thigh_r.rotation.x = tr + lean
	shin_l.rotation.x = sl
	shin_r.rotation.x = sr

	# Keep the lower foot on the floor: hip height follows the leg pose.
	var reach_l := THIGH_LEN * cos(tl) + SHIN_LEN * cos(tl + sl)
	var reach_r := THIGH_LEN * cos(tr) + SHIN_LEN * cos(tr + sr)
	var hip := maxf(reach_l, reach_r) - absf(s) * 0.02 * _amp
	hip = lerpf(hip, HIP_HEIGHT, _float)
	torso.position.y = hip + sin(Time.get_ticks_msec() * 0.0012) * 0.03 * _float

	var arm_swing := swing * 0.7
	arm_l.rotation.x = lerpf(-arm_swing, 0.9, _carry) + 0.25 * _float
	arm_r.rotation.x = lerpf(lerpf(arm_swing, 1.15, _arm_r_raise), 0.9, _carry) + 0.25 * _float
	arm_l.rotation.z = -0.25 * _float
	arm_r.rotation.z = 0.25 * _float

	# Incapacitated: fall onto the back.
	rotation.x = lerpf(0.0, PI * 0.5, _down)
	position.y = lerpf(0.0, 0.3, _down)
	position.z = lerpf(0.0, -0.8, _down)
