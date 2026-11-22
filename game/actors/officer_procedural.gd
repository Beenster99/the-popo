class_name OfficerProcedural
extends SkeletonModifier3D
## Procedural layers applied after the animation each frame:
##  - aim tracking: spine and chest turn toward the aim so the gun points at
##    the mouse while the legs run another way; the head follows.
##  - foot placement: each foot finds the ground under it (steps, kerbs,
##    rubble) with two-bone IK, and the hips drop to reach the lower foot.
##  - gun hand lock: the left hand stays on the grip under recoil and twist.

var aim_yaw_offset := 0.0     # radians, aim direction minus body facing
var feet_enabled := true
var hand_lock := false
var ground_y := 0.0           # the character's floor height (world)
## Point the barrel at this world point while aiming (the reticle).
var aim_active := false
var aim_target := Vector3.ZERO
## The gun slide's transform relative to the right hand bone (set by the rig).
var slide_rel := Transform3D()
var have_slide := false
const MAX_AIM_FIX := 1.0      # radians the chest may turn to line up the barrel

var _legs := [["thigh.L", "shin.L", "foot.L"], ["thigh.R", "shin.R", "foot.R"]]
var _idx := {}
var _lock_offset := Transform3D()
var _lock_was := false
var _hips_drop := 0.0


func _ready() -> void:
	var sk := get_skeleton()
	for n in ["hips", "spine", "chest_2", "neck_2", "head_2", "thigh.L", "shin.L", "foot.L", "thigh.R", "shin.R", "foot.R",
			"upper_arm.L", "forearm.L", "hand.L", "hand.R"]:
		_idx[n] = sk.find_bone(n)
	_idx["hand.R"] = sk.find_bone("hand.R")


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _idx.is_empty():
		return
	_aim(sk)
	_line_up_barrel(sk)
	if feet_enabled:
		_feet(sk)
	else:
		_hips_drop = lerpf(_hips_drop, 0.0, 0.2)
	_hand_lock(sk)


func _rotate_global(sk: Skeleton3D, bone: int, q: Quaternion) -> void:
	var g := sk.get_bone_global_pose(bone)
	g.basis = Basis(q) * g.basis
	sk.set_bone_global_pose(bone, g)


func _aim(sk: Skeleton3D) -> void:
	var yaw := clampf(wrapf(aim_yaw_offset, -PI, PI), -1.4, 1.4)
	if absf(yaw) < 0.001:
		return
	# Skeleton space up is the model's up (the glTF rig has no tilt).
	var up := sk.global_basis.inverse() * Vector3.UP
	_rotate_global(sk, _idx["spine"], Quaternion(up.normalized(), yaw * 0.35))
	_rotate_global(sk, _idx["chest_2"], Quaternion(up.normalized(), yaw * 0.45))
	_rotate_global(sk, _idx["head_2"], Quaternion(up.normalized(), yaw * 0.2))


## The barrel in world space: [muzzle, direction], from the posed right hand.
func barrel(sk: Skeleton3D) -> Array:
	var hand := sk.global_transform * sk.get_bone_global_pose(_idx["hand.R"])
	var sl := hand * slide_rel
	var d := -sl.basis.y.normalized()
	return [sl.origin + d * 0.095, d]


## Turns the chest (arms and gun with it) so the barrel lines up with the
## aim point, up and down as well as sideways. Two passes, because the gun
## sits off to the side of the chest.
func _line_up_barrel(sk: Skeleton3D) -> void:
	if not (aim_active and have_slide):
		return
	for i in 2:
		var b := barrel(sk)
		var want: Vector3 = aim_target - b[0]
		if want.length() < 0.5:
			return
		var axis: Vector3 = (b[1] as Vector3).cross(want.normalized())
		var ang := (b[1] as Vector3).angle_to(want.normalized())
		if axis.length() < 0.0001 or ang < 0.002:
			return
		ang = minf(ang, MAX_AIM_FIX)
		var axis_sk := (sk.global_basis.inverse() * axis).normalized()
		_rotate_global(sk, _idx["chest_2"], Quaternion(axis_sk, ang))


func _feet(sk: Skeleton3D) -> void:
	var space := sk.get_world_3d().direct_space_state
	var xf := sk.global_transform
	var deltas := []
	for leg in _legs:
		var foot: Vector3 = xf * sk.get_bone_global_pose(_idx[leg[2]]).origin
		var lift: float = foot.y - ground_y  # how high the animation lifts this foot
		var q := PhysicsRayQueryParameters3D.create(Vector3(foot.x, ground_y + 0.6, foot.z), Vector3(foot.x, ground_y - 0.6, foot.z), 1 | 16)
		var hit := space.intersect_ray(q)
		var d := 0.0
		if hit:
			d = clampf((hit.position.y + lift) - foot.y, -0.4, 0.4)
		deltas.append(d)
	var drop: float = min(0.0, min(deltas[0], deltas[1]))
	_hips_drop = lerpf(_hips_drop, drop, 0.35)
	if absf(_hips_drop) > 0.002:
		var h := sk.get_bone_global_pose(_idx["hips"])
		h.origin += xf.basis.inverse() * Vector3(0, _hips_drop, 0)
		sk.set_bone_global_pose(_idx["hips"], h)
	for i in 2:
		var leg: Array = _legs[i]
		var foot_g := xf * sk.get_bone_global_pose(_idx[leg[2]]).origin
		var target: Vector3 = foot_g + Vector3(0, deltas[i] - _hips_drop, 0)
		if absf(deltas[i] - _hips_drop) > 0.005:
			_two_bone(sk, _idx[leg[0]], _idx[leg[1]], _idx[leg[2]], xf.affine_inverse() * target)


func _hand_lock(sk: Skeleton3D) -> void:
	var r := sk.get_bone_global_pose(_idx["hand.R"])
	var l := sk.get_bone_global_pose(_idx["hand.L"])
	if hand_lock and not _lock_was:
		_lock_offset = r.affine_inverse() * l
	_lock_was = hand_lock
	if not hand_lock:
		return
	var want := r * _lock_offset
	_two_bone(sk, _idx["upper_arm.L"], _idx["forearm.L"], _idx["hand.L"], want.origin)
	var lg := sk.get_bone_global_pose(_idx["hand.L"])
	lg.basis = want.basis
	sk.set_bone_global_pose(_idx["hand.L"], lg)


## Analytic two-bone IK in skeleton space. Keeps the joint bending the way
## the animation already bends it, and keeps the end bone's orientation.
func _two_bone(sk: Skeleton3D, a: int, b: int, c: int, target: Vector3) -> void:
	var ga := sk.get_bone_global_pose(a)
	var gb := sk.get_bone_global_pose(b)
	var gc := sk.get_bone_global_pose(c)
	var A := ga.origin
	var B := gb.origin
	var C := gc.origin
	var la := A.distance_to(B)
	var lb := B.distance_to(C)
	var to_t := target - A
	var d := clampf(to_t.length(), 0.01, la + lb - 0.001)
	var dir := to_t.normalized()
	var bend := (B - A) - dir * (B - A).dot(dir)
	if bend.length() < 0.0001:
		bend = ga.basis.z
	bend = bend.normalized()
	var cos_a := clampf((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var B2 := A + dir * cos_a * la + bend * sqrt(1.0 - cos_a * cos_a) * la
	var q1 := Quaternion((B - A).normalized(), (B2 - A).normalized())
	ga.basis = Basis(q1) * ga.basis
	sk.set_bone_global_pose(a, ga)
	gb = sk.get_bone_global_pose(b)
	var C1 := sk.get_bone_global_pose(c).origin
	var q2 := Quaternion((C1 - gb.origin).normalized(), (A + dir * d - gb.origin).normalized())
	gb.basis = Basis(q2) * gb.basis
	sk.set_bone_global_pose(b, gb)
	var gc2 := sk.get_bone_global_pose(c)
	gc2.basis = gc.basis
	sk.set_bone_global_pose(c, gc2)
