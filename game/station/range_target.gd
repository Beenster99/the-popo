class_name RangeTarget
extends StaticBody3D
## Phase 3.6: one swing-up target on the range: a figure on a board that
## swings up from flat, red for a crook, blue for a civilian.

var owner_range: FiringRange
var index := 0
var up := false
var civilian := false
var up_t := 0.0
var _pivot: Node3D
var _mat: StandardMaterial3D
var _shape: CollisionShape3D
var _angle := -PI / 2


func _ready() -> void:
	collision_layer = 1
	_pivot = Node3D.new()
	add_child(_pivot)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.6, 1.7, 0.05)
	board.mesh = bm
	board.position = Vector3(0, 0.85, 0)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color("b83a2e")
	board.material_override = _mat
	_pivot.add_child(board)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.16
	hm.height = 0.32
	head.mesh = hm
	head.position = Vector3(0, 1.85, 0)
	head.material_override = _mat
	_pivot.add_child(head)
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.9, 0.15, 0.3)
	post.mesh = pm
	post.position = Vector3(0, 0.07, 0)
	add_child(post)
	_shape = CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 2.0, 0.12)
	_shape.shape = sh
	_shape.position = Vector3(0, 1.0, 0)
	_shape.disabled = true
	add_child(_shape)
	_pivot.rotation.x = _angle


func set_up(on: bool, civ: bool) -> void:
	up = on
	if on:
		civilian = civ
		_mat.albedo_color = Color("2e5fb8") if civ else Color("b83a2e")
	if _shape:
		_shape.disabled = not on


func _process(delta: float) -> void:
	var want := 0.0 if up else -PI / 2
	_angle = move_toward(_angle, want, delta * 9.0)
	_pivot.rotation.x = _angle


## Host: shot (Gunfire calls this).
func on_bullet(_at: Vector3, _shooter: Node) -> void:
	if Net.is_host() and owner_range:
		owner_range.hit(self)
