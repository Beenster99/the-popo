class_name Reticle
extends Node3D
## The aiming reticle: a ring lying on whatever surface the player points at
## (a wall, a car, the floor), shown while aiming. It turns red when the
## shot from the barrel would be blocked before it gets there.

var pawn_getter: Callable   # () -> Node3D (the local pawn), or empty
var _ring: MeshInstance3D
var _dot: MeshInstance3D
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.95, 0.6)
	_mat.no_depth_test = true
	_mat.render_priority = 10
	var torus := TorusMesh.new()
	torus.inner_radius = 0.13
	torus.outer_radius = 0.17
	torus.rings = 24
	torus.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = _mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	var dot := SphereMesh.new()
	dot.radius = 0.03
	dot.height = 0.06
	_dot = MeshInstance3D.new()
	_dot.mesh = dot
	_dot.material_override = _mat
	_dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_dot)
	visible = false


func _process(_delta: float) -> void:
	var pawn: Node3D = pawn_getter.call() if pawn_getter.is_valid() else null
	var aiming: bool = pawn != null and pawn.has_method("is_aiming") and pawn.is_aiming()
	visible = aiming
	if not aiming:
		return
	var n := PlayerInput.aim_normal.normalized()
	global_position = PlayerInput.aim_point + n * 0.02
	var up := Vector3.FORWARD if absf(n.dot(Vector3.UP)) > 0.95 else Vector3.UP
	# TorusMesh lies in its local XZ plane, so point its Y along the normal.
	var x := up.cross(n).normalized()
	global_transform.basis = Basis(x, n, x.cross(n).normalized())
	_mat.albedo_color = Color(1.0, 0.35, 0.3) if _blocked(pawn) else Color(1.0, 0.95, 0.6)


func _blocked(pawn: Node3D) -> bool:
	if not pawn.has_method("muzzle_position"):
		return false
	var m: Vector3 = pawn.muzzle_position()
	var q := PhysicsRayQueryParameters3D.create(m, PlayerInput.aim_point, 1 | 4 | 16)
	if pawn is CollisionObject3D:
		q.exclude = [(pawn as CollisionObject3D).get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit.position.distance_to(PlayerInput.aim_point) > 0.3
