class_name Trailer
extends Car
## Wave 2, Phase 2.4: an articulated lorry's trailer (box, tanker or
## flatbed) on the same wheel physics as the cars, hitched to a tractor
## unit's fifth wheel by a ball joint, so it follows round corners, swings
## out when braking hard on a bend and can jackknife. A hard enough crash
## (or the tractor wrecked) knocks it off the hitch; then it sits on its
## landing legs, or slides and tips. Heavy: it ploughs through cars and
## shop fronts.

const KINDS := {
	"box": {"L": 12.0, "mass": 9000.0, "cargo": [Vector3(2.5, 2.7, 11.9), Vector3(0, 1.1, 0)]},
	"tanker": {"L": 11.0, "mass": 12000.0, "cargo": [Vector3(2.3, 2.3, 10.0), Vector3(0, 1.0, 0.2)]},
	"flatbed": {"L": 12.0, "mass": 7000.0, "cargo": [Vector3(2.2, 0.9, 11.0), Vector3(0, 0.35, 0)]},
}
## The kingpin, in trailer space (over the tractor's fifth wheel).
const KINGPIN_Z_FROM_FRONT := 1.0
const UNHITCH_IMPULSE := 160000.0

signal unhitched

var kind := "box"
var length := 12.0
var tractor: CivilianVehicle
var _joint: Generic6DOFJoint3D
var _legs: CollisionShape3D


static func make(kind_name: String, colour_seed := 0) -> Trailer:
	var t := Trailer.new()
	t.kind = kind_name
	var k: Dictionary = KINDS[kind_name]
	t.length = k.L
	t.size = Vector3(2.4, 0.4, k.L)
	t.cabin_box = k.cargo
	var L: float = k.L
	t.wheel_mounts = []
	for z in [-L / 2 + 1.0, -L / 2 + 2.3, -L / 2 + 3.6]:
		t.wheel_mounts.append(Vector3(-1.0, -0.45, z))
		t.wheel_mounts.append(Vector3(1.0, -0.45, z))
	t.wheel_radius = 0.48
	t.mass = k.mass
	t.spring = SPRING * k.mass / 1250.0 * 0.7
	t.damp = DAMP * k.mass / 1250.0 * 0.7
	t.engine = 0.0
	t.steer_max = 0.0
	t.steer_min = 0.0
	t.yaw_assist = 0.0
	t.brake_force = BRAKE * k.mass / 1250.0
	var r := RandomNumberGenerator.new()
	r.seed = colour_seed * 31 + 7
	t.color = [Color("e8e6e0"), Color("2f5f8a"), Color("c9302c"), Color("3f6b3a"), Color("d9d6cf")][r.randi_range(0, 4)]
	t.center_of_mass = Vector3(0, 0.3, 0)
	return t


func _build_body() -> void:
	var model: Node3D = (load("res://assets/models/vehicles/trailer_%s.glb" % kind) as PackedScene).instantiate()
	model.name = "Model"
	add_child(model)
	Cel.apply(model)
	var mat := Cel.material(color, true, 0.02)
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			if src and src.resource_name.begins_with("paint"):
				m.set_surface_override_material(i, mat)
	var w := model.find_child("wheel", true, false)
	if w:
		w.get_parent().remove_child(w)
		w.free()
	for n in ["cargo_box", "tank"]:
		var mi := model.find_child(n, true, false) as MeshInstance3D
		if mi:
			add_deformable(mi)
	# Landing legs at the front: only solid once it's off the hitch.
	_legs = CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.8, 0.9, 0.3)
	_legs.shape = bs
	_legs.position = Vector3(0, -0.95, length / 2 - 2.5)
	_legs.disabled = true
	add_child(_legs)


func _make_wheel() -> Node3D:
	var m: Node3D = (load("res://assets/models/vehicles/trailer_%s.glb" % kind) as PackedScene).instantiate()
	var w := m.find_child("wheel", true, false) as Node3D
	if w:
		w.get_parent().remove_child(w)
		w.position = Vector3.ZERO
		Cel.apply(w)
	m.free()
	return w if w else super._make_wheel()


## Hitches this trailer behind the tractor (placed in line behind it).
func hitch(t: CivilianVehicle) -> void:
	tractor = t
	var pin_t := Vector3(0, -0.25, -t.size.z / 2 + 1.0)                # tractor space
	var pin_r := Vector3(0, -0.62, length / 2 - KINGPIN_Z_FROM_FRONT)  # trailer space
	global_transform = Transform3D(t.global_basis, t.global_transform * pin_t - t.global_basis * pin_r + Vector3(0, 0.15, 0))
	add_collision_exception_with(t)
	_joint = Generic6DOFJoint3D.new()
	t.get_parent().add_child(_joint)
	_joint.global_position = t.global_transform * pin_t
	_joint.node_a = t.get_path()
	_joint.node_b = get_path()
	# Free to turn about the kingpin (yaw), a little pitch and roll.
	for ax in ["x", "y", "z"]:
		_joint.set("linear_limit_%s/enabled" % ax, true)
		_joint.set("linear_limit_%s/upper_distance" % ax, 0.0)
		_joint.set("linear_limit_%s/lower_distance" % ax, 0.0)
	_joint.set("angular_limit_x/enabled", true)
	_joint.set("angular_limit_x/upper_angle", deg_to_rad(12.0))
	_joint.set("angular_limit_x/lower_angle", deg_to_rad(-12.0))
	_joint.set("angular_limit_z/enabled", true)
	_joint.set("angular_limit_z/upper_angle", deg_to_rad(8.0))
	_joint.set("angular_limit_z/lower_angle", deg_to_rad(-8.0))
	_joint.set("angular_limit_y/enabled", true)
	_joint.set("angular_limit_y/upper_angle", deg_to_rad(88.0))
	_joint.set("angular_limit_y/lower_angle", deg_to_rad(-88.0))
	_legs.disabled = true


func hitched() -> bool:
	return _joint != null and is_instance_valid(_joint)


func unhitch() -> void:
	if not hitched():
		return
	_joint.queue_free()
	_joint = null
	_legs.disabled = false
	if tractor and is_instance_valid(tractor):
		remove_collision_exception_with(tractor)
	tractor = null
	unhitched.emit()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# The trailer's brakes work with the tractor's.
	if tractor and is_instance_valid(tractor):
		brake = maxf(tractor.brake, 1.0 if tractor.handbrake else 0.0)
	elif not hitched():
		brake = 1.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	super._integrate_forces(state)
	if hitched() and Net.is_host():
		for i in state.get_contact_count():
			if state.get_contact_impulse(i).length() > UNHITCH_IMPULSE:
				unhitch.call_deferred()
				break
		if tractor and is_instance_valid(tractor) and tractor.wrecked:
			unhitch.call_deferred()
