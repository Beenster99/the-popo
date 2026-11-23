class_name Gore
extends RefCounted
## Phase 1.5 catch-up (beenster, v0.2.11): blood and wounds, on a slider in
## Settings > Gameplay > Gore (Off, Some, Lots, Extreme).
##   hit       a bullet in a person: a spray out of the exit side, a splat on
##             the wall or floor behind, drips under them, and a wound that
##             stays on the body (a hole in the head for a head shot; on
##             Extreme, bits come off too).
##   downed    a pool spreads out under the body, and on Extreme a broken
##             bone pokes out of an arm or leg.
##   ragdolls  bodies take the bullet's push at the bone it hit, so they
##             fall the way they were shot, and a body on the floor still
##             jerks when it is shot.
## All of it is cosmetic and made on every machine from the same bullet
## event (SfxSync), so nothing extra goes over the network.

const RAGDOLL_LAYER := 64
## Render layer for people's meshes (see OfficerRig): world decals leave it
## alone and wound decals touch nothing else.
const BODY_LAYER := 2
const MAX_DECALS := [0, 120, 220, 360]
const SPRAY := [0, 10, 22, 40]
const SPLAT_SIZE := [0.0, 0.45, 0.8, 1.25]
const POOL_SIZE := [0.0, 0.8, 1.4, 2.2]
const BLOOD := Color(0.42, 0.02, 0.03)
const BLOOD_DARK := Color(0.22, 0.0, 0.01)

static var _decals: Array = []
static var _tex := {}
static var _drop_mat: StandardMaterial3D
static var _gib_mat: Material
static var _bone_mat: Material


static func level() -> int:
	return clampi(int(Settings.values.get("gore", 3)), 0, 3)


## A bullet from a hit at at (everyone, from the bullet event).
static func hit(parent: Node, from: Vector3, at: Vector3) -> void:
	var lv := level()
	var dir := (at - from).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var who := _person_near(parent.get_tree(), at)
	# A body on the floor jerks where it was hit (it may lie well away from
	# where its character stood).
	var body := _ragdoll_near(parent.get_tree(), at)
	if body:
		who = body
	_push_ragdoll(who, at, dir * 14.0)
	if lv == 0 or not parent.is_inside_tree():
		return
	var head := who != null and at.y - (who as Node3D).global_position.y > 1.45
	# The wet sound of it, louder the higher the setting; bone on a head shot.
	Sfx.play(parent, "gore_hit", at, -6.0 + lv * 2.0, 35.0, 0.08)
	if head and lv >= 2:
		Sfx.play(parent, "bone_snap", at, -2.0, 30.0, 0.1)
	_spray(parent, at, dir, SPRAY[lv] * (2 if head else 1))
	var space := (parent as Node).get_viewport().world_3d.direct_space_state
	var ex: Array[RID] = []
	if who is CollisionObject3D:
		ex.append((who as CollisionObject3D).get_rid())
	# Out the back and onto whatever is behind.
	var q := PhysicsRayQueryParameters3D.create(at + dir * 0.2, at + dir * (2.0 + lv * 1.2), 1 | 4 | 16, ex)
	var h := space.intersect_ray(q)
	if h:
		splat(parent, h.position, h.normal, SPLAT_SIZE[lv] * (1.6 if head else 1.0) * randf_range(0.7, 1.3))
	# Drips on the floor under them.
	var dq := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 3.0, 1 | 16, ex)
	var dh := space.intersect_ray(dq)
	if dh:
		splat(parent, dh.position + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)) + dir * 0.4, dh.normal, SPLAT_SIZE[lv] * 0.5)
	if who:
		_wound(who, at, dir, head, lv)
		if head and lv >= 3:
			_gibs(parent, at, dir, 5)


## A blood splat on a surface (decal), size in metres.
static func splat(parent: Node, at: Vector3, normal: Vector3, size: float, dark := false) -> Decal:
	var lv := level()
	if lv == 0 or size <= 0.0:
		return null
	var d := Decal.new()
	d.texture_albedo = _splat_tex(randi() % 4)
	d.modulate = BLOOD_DARK if dark else BLOOD
	d.size = Vector3(size, 0.35, size)
	d.albedo_mix = 1.0
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.cull_mask = 1   # the world, not people walking through it
	parent.add_child(d)
	var up := normal.normalized()
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	d.global_transform = Transform3D(Basis(side, up, side.cross(up)).rotated(up, randf() * TAU), at + up * 0.02)
	_decals.append(d)
	while _decals.size() > MAX_DECALS[lv]:
		var old = _decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	return d


## A body is down: a pool spreads under it; on Extreme a bone comes out.
static func downed(rig: OfficerRig) -> void:
	var lv := level()
	if lv == 0 or rig == null or not rig.is_inside_tree():
		return
	var body := rig.get_parent() as Node3D
	# By id, not by capture: the body may be gone when the timer fires.
	rig.get_tree().create_timer(1.6).timeout.connect(_pool.bind(rig.get_instance_id(), lv))
	if lv >= 3:
		var limbs := ["forearm.L", "forearm.R", "shin.L", "shin.R"]
		var pick: String = limbs[absi(hash(body.name)) % limbs.size()]
		_bone_out(rig, pick)
		Sfx.play(rig, "bone_snap", body.global_position, 0.0, 30.0, 0.1)


static func _pool(rig_id: int, lv: int) -> void:
	var rig := instance_from_id(rig_id) as OfficerRig
	if rig == null or not rig.is_inside_tree() or not rig.downed:
		return
	var body := rig.get_parent() as Node3D
	var hips := rig.bone_body("hips")
	var at: Vector3 = hips.global_position if hips else body.global_position
	var space := rig.get_viewport().world_3d.direct_space_state
	var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 2.0, 1 | 16))
	if not h:
		return
	var pool := splat(body.get_parent(), h.position, h.normal, 0.3, true)
	if pool:
		var full: float = POOL_SIZE[lv] * randf_range(0.8, 1.2)
		pool.create_tween().tween_property(pool, "size", Vector3(full, 0.35, full), 9.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


# --- pieces --------------------------------------------------------------------------

static func _person_near(tree: SceneTree, at: Vector3) -> Node3D:
	var best: Node3D = null
	var bd := 0.9
	for g in ["suspects", "officers"]:
		for n in tree.get_nodes_in_group(g):
			var c := n as Node3D
			var p := c.global_position + Vector3(0, 0.9, 0)
			var d := Vector2(p.x - at.x, p.z - at.z).length()
			if d < bd and at.y > c.global_position.y - 0.3 and at.y < c.global_position.y + 2.1:
				bd = d
				best = c
	return best


static func _ragdoll_near(tree: SceneTree, at: Vector3) -> Node3D:
	# The body with a bone nearest the hit (bodies can lie on each other).
	var best: Node3D = null
	var bd := 0.45
	for g in ["suspects", "officers"]:
		for n in tree.get_nodes_in_group(g):
			var rig := _rig_of(n)
			if rig == null or not rig.downed or n.is_queued_for_deletion():
				continue
			for c in rig.physics.get_children():
				if c is PhysicalBone3D and (c as Node3D).global_position.distance_to(at) < bd:
					bd = (c as Node3D).global_position.distance_to(at)
					best = n as Node3D
	return best


static func _rig_of(who: Node) -> OfficerRig:
	if who == null:
		return null
	var r = who.get("rig")
	return r as OfficerRig


static func _push_ragdoll(who: Node, at: Vector3, impulse: Vector3) -> void:
	var rig := _rig_of(who)
	if rig == null or not rig.downed or rig.physics == null:
		return
	var best: PhysicalBone3D = null
	var bd := INF
	for c in rig.physics.get_children():
		var pb := c as PhysicalBone3D
		if pb and pb.global_position.distance_to(at) < bd:
			bd = pb.global_position.distance_to(at)
			best = pb
	if best:
		PhysicsServer3D.body_set_state(best.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)
		best.apply_impulse(impulse, at - best.global_position)


static func _spray(parent: Node, at: Vector3, dir: Vector3, n: int) -> void:
	if n <= 0 or DisplayServer.get_name() == "headless":
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = n
	p.explosiveness = 0.95
	p.lifetime = 0.9
	p.direction = dir
	p.spread = 28.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6
	var m := SphereMesh.new()
	m.radius = 0.022
	m.height = 0.044
	m.radial_segments = 6
	m.rings = 3
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_drop_mat.albedo_color = BLOOD
	m.material = _drop_mat
	p.mesh = m
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	# A finer mist back towards the shooter.
	var mist := p.duplicate() as CPUParticles3D
	mist.amount = maxi(4, n / 3)
	mist.direction = -dir
	mist.spread = 50.0
	mist.initial_velocity_max = 2.5
	parent.add_child(mist)
	mist.global_position = at
	mist.emitting = true
	p.get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	p.get_tree().create_timer(2.0).timeout.connect(mist.queue_free)


## A wound on the body: a dark patch that moves with the bone it is on.
## The bullet's hit point is on the collision capsule, which stands well off
## the body, so the wound is put on the bone itself, on the side the bullet
## came from (2026-11-23: a dark ball floating by shot suspects' heads was
## the old head hole sitting out on the capsule).
static func _wound(who: Node3D, at: Vector3, dir: Vector3, head: bool, lv: int) -> void:
	var rig := _rig_of(who)
	if rig == null or rig.skeleton == null:
		return
	var sk := rig.skeleton
	var best := -1
	var bd := INF
	var bone_at := Vector3.ZERO
	for i in sk.get_bone_count():
		var bp := (sk.global_transform * sk.get_bone_global_pose(i)).origin
		# Measured across the shot, so the nearest bone along the line wins.
		var off := bp - at
		var d := (off - dir * off.dot(dir)).length()
		if d < bd:
			bd = d
			best = i
			bone_at = bp
	if best < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = best
	sk.add_child(att)
	var surface := bone_at - dir * (0.1 if head else 0.13)
	var d := Decal.new()
	d.texture_albedo = _splat_tex(4)
	d.modulate = BLOOD
	var s := (0.12 if head else 0.1) * (1.0 + lv * 0.2)
	d.size = Vector3(s, 0.3, s)
	d.albedo_mix = 1.0
	d.cull_mask = BODY_LAYER
	att.add_child(d)
	var up := -dir
	var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	d.global_transform = Transform3D(Basis(side, up, side.cross(up)), surface)
	if head and lv >= 2:
		# The hole itself: a small dark socket, set into the head.
		var hole := Decal.new()
		hole.texture_albedo = _splat_tex(4)
		hole.modulate = BLOOD_DARK
		hole.size = Vector3(0.045, 0.3, 0.045)
		hole.albedo_mix = 1.0
		hole.cull_mask = BODY_LAYER
		att.add_child(hole)
		hole.global_transform = d.global_transform


## Extreme: a broken bone through the skin of a limb.
static func _bone_out(rig: OfficerRig, bone: String) -> void:
	var sk := rig.skeleton
	var idx := sk.find_bone(bone)
	if idx < 0:
		return
	var att := BoneAttachment3D.new()
	att.bone_idx = idx
	sk.add_child(att)
	var shard := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.004
	cm.bottom_radius = 0.018
	cm.height = 0.13
	cm.radial_segments = 6
	shard.mesh = cm
	if _bone_mat == null:
		_bone_mat = Cel.material(Color(0.93, 0.9, 0.8), true, 0.01)
	shard.material_override = _bone_mat
	att.add_child(shard)
	shard.position = Vector3(0.05, 0.12, 0.02)
	shard.rotation = Vector3(0.0, 0.0, -1.1)
	var gash := MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 0.04
	gm.height = 0.05
	gash.mesh = gm
	gash.material_override = Cel.material(BLOOD, false)
	att.add_child(gash)
	gash.position = Vector3(0.02, 0.12, 0.01)


## Extreme head shots: bits fly.
static func _gibs(parent: Node, at: Vector3, dir: Vector3, n: int) -> void:
	if _gib_mat == null:
		_gib_mat = Cel.material(Color(0.55, 0.08, 0.08), true, 0.01)
	for i in n:
		var rb := RigidBody3D.new()
		rb.mass = 0.08
		rb.collision_layer = 0
		rb.collision_mask = 1 | 16
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.025
		cs.shape = sh
		rb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.03, 0.06), randf_range(0.02, 0.04), randf_range(0.03, 0.06))
		mi.mesh = bm
		mi.material_override = _gib_mat
		rb.add_child(mi)
		parent.add_child(rb)
		rb.global_position = at + Vector3(randf_range(-0.05, 0.05), randf_range(-0.05, 0.05), randf_range(-0.05, 0.05))
		rb.linear_velocity = (dir + Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.8), randf_range(-0.5, 0.5))).normalized() * randf_range(3.0, 7.0)
		rb.angular_velocity = Vector3(randf_range(-10, 10), randf_range(-10, 10), randf_range(-10, 10))
		rb.get_tree().create_timer(25.0).timeout.connect(rb.queue_free)


## Splat textures, made once: a blob with drips and specks round it.
## Variant 4 is a tight wound patch.
static func _splat_tex(v: int) -> Texture2D:
	if _tex.has(v):
		return _tex[v]
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + v
	var blobs := []
	var c := Vector2(size, size) * 0.5
	var main_r := size * (0.18 if v == 4 else 0.24)
	blobs.append([c, main_r])
	for i in (4 if v == 4 else 14):
		var a := rng.randf() * TAU
		var dist := rng.randf_range(0.4, 1.6) * main_r
		blobs.append([c + Vector2.from_angle(a) * dist, rng.randf_range(0.08, 0.45) * main_r])
	if v != 4:
		for i in 26:
			var a := rng.randf() * TAU
			blobs.append([c + Vector2.from_angle(a) * rng.randf_range(1.4, 2.5) * main_r, rng.randf_range(0.02, 0.09) * main_r])
	for y in size:
		for x in size:
			var p := Vector2(x, y)
			var a := 0.0
			for b in blobs:
				var d: float = p.distance_to(b[0]) / float(b[1])
				a = maxf(a, clampf((1.0 - d) * 4.0, 0.0, 1.0))
			if a > 0.0:
				var shade := 0.75 + 0.25 * sin(x * 0.31 + y * 0.17)
				img.set_pixel(x, y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[v] = t
	return t
