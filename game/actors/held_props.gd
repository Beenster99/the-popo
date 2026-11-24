class_name HeldProps
extends RefCounted
## Small things people carry in the right hand for everyday clips
## (OfficerRig.DAILY_HELD): a phone, a shovel, a hammer. Built from a few
## boxes, laid out in the hand bone's space (+Y runs along the fingers).

## Offset of each kind from the hand bone, tuned against the clips.
const PLACE := {
	"phone": [Vector3(0.0, 0.07, 0.02), Vector3(0, 0, 0)],
	"shovel": [Vector3(0.0, -0.33, 0.0), Vector3(0, 0, 0)],
	"hammer": [Vector3(0.0, 0.05, 0.0), Vector3(90, 0, 0)],
}


static func make(kind: String) -> Node3D:
	var root := Node3D.new()
	root.name = "held_" + kind
	var metal := Cel.material(Color("8a8d92"), true, 0.006)
	var dark := Cel.material(Color("1b1c20"), true, 0.006)
	var wood := Cel.material(Color("9a6a3a"), true, 0.006)
	match kind:
		"phone":
			_box(root, Vector3(0.072, 0.15, 0.009), Vector3.ZERO, dark)
			_box(root, Vector3(0.064, 0.13, 0.002), Vector3(0, 0, 0.0055), Cel.material(Color("3a5a78"), false))
		"shovel":
			# Shaft along +Y (the hand grips it a third of the way down).
			_box(root, Vector3(0.035, 1.05, 0.035), Vector3(0, -0.15, 0), wood)
			_box(root, Vector3(0.14, 0.035, 0.035), Vector3(0, 0.38, 0), dark)
			_box(root, Vector3(0.24, 0.30, 0.012), Vector3(0, -0.82, 0.02), metal)
		"hammer":
			_box(root, Vector3(0.03, 0.32, 0.03), Vector3(0, 0.08, 0), wood)
			_box(root, Vector3(0.05, 0.05, 0.14), Vector3(0, 0.24, 0.02), metal)
	var p: Array = PLACE.get(kind, [Vector3.ZERO, Vector3.ZERO])
	root.position = p[0]
	root.rotation_degrees = p[1]
	return root


static func _box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = at
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
