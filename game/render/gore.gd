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
## Blood marks stay until a council crew cleans them (RepairCrews); these
## caps only stop a long fight costing frames (the oldest go first).
const MAX_DECALS := [0, 150, 300, 500]
const SPRAY := [0, 10, 22, 40]
const SPLAT_SIZE := [0.0, 0.45, 0.8, 1.25]
const POOL_SIZE := [0.0, 1.0, 1.8, 2.8]
## Fine spatter thrown out of the exit wound: how many marks it leaves
## round about, and how far it carries.
const SPATTER_RAYS := [0, 1, 3, 6]
const SPATTER_REACH := [0.0, 2.5, 3.5, 4.5]
const MIST := [0, 6, 10, 16]
## Texture kinds (see _splat_tex).
const TEX_WOUND := 4
const TEX_FAN := 5        # fine spray thrown one way (towards +Z of the decal)
const TEX_SPECKLE := 6    # fine drips all round
const TEX_POOL := 7
const FADE_FROM := 45.0   # decals fade out beyond this, to keep frames up
const BLOOD := Color(0.42, 0.02, 0.03)
const BLOOD_DARK := Color(0.22, 0.0, 0.01)

static var _decals: Array = []
static var _tex := {}
static var _drop_mat: StandardMaterial3D
static var _mist_mat: StandardMaterial3D
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
	_spray(parent, at, dir, SPRAY[lv] * (2 if head else 1), MIST[lv] * (2 if head else 1))
	var space := (parent as Node).get_viewport().world_3d.direct_space_state
	var ex: Array[RID] = []
	if who is CollisionObject3D:
		ex.append((who as CollisionObject3D).get_rid())
	# beenster (2026-11-24): a fine mist bursts out of the exit wound and
	# leaves a fine spatter on whatever is round about (walls, floor,
	# furniture), which stays until it is cleaned. One ray straight on, the
	# rest in a cone; the further it carries, the wider and fainter it gets.
	var reach: float = SPATTER_REACH[lv] * (1.3 if head else 1.0)
	for k in SPATTER_RAYS[lv] + (2 if head else 0):
		var d := dir
		if k > 0:
			# Somewhere in a cone of about 35 degrees round the shot.
			d = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.6).normalized()
		var q := PhysicsRayQueryParameters3D.create(at + d * 0.2, at + d * reach, 1 | 4 | 16, ex)
		var h := space.intersect_ray(q)
		if h:
			var far := at.distance_to(h.position)
			var size: float = SPLAT_SIZE[lv] * (0.35 + far * 0.22) * (1.3 if head else 1.0) * randf_range(0.8, 1.2)
			# Hitting a surface square on, it lands all round; at a slant
			# it fans out the way it was flying.
			var n: Vector3 = h.normal
			var slant := (d - n * d.dot(n)).length()
			splat(parent, h.position, h.normal, size, false, TEX_FAN if slant > 0.35 else TEX_SPECKLE, d)
	# Drips on the floor under them.
	var dq := PhysicsRayQueryParameters3D.create(at, at + Vector3.DOWN * 3.0, 1 | 16, ex)
	var dh := space.intersect_ray(dq)
	if dh:
		splat(parent, dh.position + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3)) + dir * 0.4, dh.normal, SPLAT_SIZE[lv] * 0.6, false, TEX_SPECKLE)
	if who:
		_wound(who, at, dir, head, lv)
		if head and lv >= 3:
			_gibs(parent, at, dir, 5)


## A blood splat on a surface (decal), size in metres.
## kind picks the look (-1: a mixed splat); along, if given, is the way the
## blood was travelling, so a fan of spray points the way it flew.
## Every blood mark is in the group "blood", so crews can clean it.
static func splat(parent: Node, at: Vector3, normal: Vector3, size: float, dark := false, kind := -1, along := Vector3.ZERO) -> Decal:
	var lv := level()
	if lv == 0 or size <= 0.0 or parent == null:
		return null
	var d := Decal.new()
	d.texture_albedo = _splat_tex(kind if kind >= 0 else randi() % 4)
	d.modulate = BLOOD_DARK if dark else BLOOD
	d.size = Vector3(size, 0.16, size)
	d.albedo_mix = 1.0
	d.upper_fade = 0.3
	d.lower_fade = 0.3
	# Not smeared down the sides of whatever it's on (the floor's blood ran
	# up the foot of the wall in long streaks).
	d.normal_fade = 0.5
	d.cull_mask = 1   # the world, not people walking through it
	d.distance_fade_enabled = true
	d.distance_fade_begin = FADE_FROM
	d.distance_fade_length = 15.0
	d.add_to_group("blood")
	parent.add_child(d)
	var up := normal.normalized()
	var fwd := along - up * along.dot(up)
	var basis: Basis
	if fwd.length() > 0.05:
		fwd = fwd.normalized()
		basis = Basis(up.cross(fwd), up, fwd).orthonormalized()
	else:
		var side := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
		basis = Basis(side, up, side.cross(up)).rotated(up, randf() * TAU)
	# A fan starts where the blood hit and spreads on from there.
	var centre := at + (fwd * size * 0.3 if kind == TEX_FAN and fwd.length() > 0.05 else Vector3.ZERO)
	d.global_transform = Transform3D(basis, centre + up * 0.02)
	d.set_meta("t", Time.get_ticks_msec())
	_decals.append(d)
	if _decals.size() > MAX_DECALS[lv]:
		_decals = _decals.filter(func(x): return is_instance_valid(x))   # cleaned up already
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
	var body := _character_of(rig)
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
	# The character, not the rig's parent: an officer's rig sits on a visual
	# node inside them, and a pool hung off that followed them round after
	# they were revived (beenster, 2026-11-24). The pool goes in the world.
	var body := _character_of(rig)
	var hips := rig.bone_body("hips")
	var at: Vector3 = hips.global_position if hips else body.global_position
	var space := rig.get_viewport().world_3d.direct_space_state
	var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, at + Vector3.DOWN * 2.0, 1 | 16))
	if not h:
		return
	var pool := splat(body.get_parent(), h.position, h.normal, 0.3, true, TEX_POOL)
	if pool:
		var full: float = POOL_SIZE[lv] * randf_range(0.8, 1.2)
		pool.create_tween().tween_property(pool, "size", Vector3(full, 0.16, full), 9.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


# --- pieces --------------------------------------------------------------------------

static func _character_of(rig: Node) -> Node3D:
	var n := rig
	while n and not n is CharacterBody3D:
		n = n.get_parent()
	return (n if n else rig.get_parent()) as Node3D


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


## The burst out of the exit wound: a spray of fine droplets that fall
## fast, and a red mist that hangs and spreads for a moment.
static func _spray(parent: Node, at: Vector3, dir: Vector3, n: int, mist_n: int) -> void:
	if n <= 0 or DisplayServer.get_name() == "headless":
		return
	if _drop_mat == null:
		_drop_mat = StandardMaterial3D.new()
		_drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_drop_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_drop_mat.albedo_color = BLOOD
		_mist_mat = StandardMaterial3D.new()
		_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mist_mat.vertex_color_use_as_albedo = true
		_mist_mat.albedo_texture = _puff_tex()
		_mist_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# Droplets: many and tiny, most of them thrown on out of the exit.
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = n * 4
	p.explosiveness = 1.0
	p.lifetime = 0.6
	p.direction = dir
	p.spread = 22.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 11.0
	p.damping_min = 1.0
	p.damping_max = 4.0
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.014, 0.014)
	q.material = _drop_mat
	p.mesh = q
	# Placed before it goes in, or the first burst comes out at the
	# parent's origin.
	p.top_level = true
	p.position = at
	parent.add_child(p)
	p.emitting = true
	# The mist: soft puffs that billow out, grow and fade.
	var m := CPUParticles3D.new()
	m.one_shot = true
	m.amount = maxi(2, mist_n)
	m.explosiveness = 1.0
	m.lifetime = 0.9
	m.direction = dir
	m.spread = 30.0
	m.initial_velocity_min = 0.8
	m.initial_velocity_max = 3.5
	m.damping_min = 3.0
	m.damping_max = 6.0
	m.gravity = Vector3(0, -0.6, 0)
	m.scale_amount_min = 0.7
	m.scale_amount_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.6))
	m.scale_amount_curve = grow
	var fade := Gradient.new()
	fade.set_color(0, Color(0.36, 0.0, 0.02, 0.7))
	fade.set_color(1, Color(0.28, 0.0, 0.02, 0.0))
	m.color_ramp = fade
	var mq := QuadMesh.new()
	mq.size = Vector2(0.28, 0.28)
	mq.material = _mist_mat
	m.mesh = mq
	m.top_level = true
	m.position = at + dir * 0.1
	parent.add_child(m)
	m.emitting = true
	p.get_tree().create_timer(1.5).timeout.connect(p.queue_free)
	p.get_tree().create_timer(1.5).timeout.connect(m.queue_free)


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


## Splat textures, made once each.
##   0-3      a blob with drips and specks round it (smears, blasts)
##   4        a tight wound patch
##   5 fan    fine spray from the exit wound: dense where it hit, fanning
##            out and thinning towards +Z, specks stretched the way they flew
##   6        fine drips and specks all round
##   7 pool   one big irregular pool
static func _splat_tex(v: int) -> Texture2D:
	if _tex.has(v):
		return _tex[v]
	var size := 512 if v in [TEX_FAN, TEX_SPECKLE] else 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + v
	var c := Vector2(size, size) * 0.5
	match v:
		TEX_FAN:
			# Hit point towards -Z (top of the texture), spreading to +Z.
			var o := Vector2(size * 0.5, size * 0.2)
			_dot(img, o, size * 0.012, Vector2.DOWN, 1.3)
			for i in 1100:
				var t := pow(rng.randf(), 1.7)          # most of it near the hit
				var ang := rng.randf_range(-0.75, 0.75) * (0.35 + t)
				var dist := t * size * 0.75
				var way := Vector2.DOWN.rotated(ang)
				var r := lerpf(3.2, 0.7, t) * rng.randf_range(0.4, 1.2) * size / 512.0
				_dot(img, o + way * dist + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)), r, way, 1.0 + t * 3.0)
		TEX_SPECKLE:
			for i in 500:
				var t := pow(rng.randf(), 1.4)
				var way := Vector2.from_angle(rng.randf() * TAU)
				var r := lerpf(6.0, 0.7, t) * rng.randf_range(0.5, 1.2) * size / 512.0
				_dot(img, c + way * t * size * 0.47, r, way, 1.0 + t * 2.0)
		TEX_POOL:
			_dot(img, c, size * 0.26, Vector2.RIGHT, 1.0)
			for i in 14:
				var way := Vector2.from_angle(rng.randf() * TAU)
				_dot(img, c + way * rng.randf_range(0.1, 0.3) * size, rng.randf_range(0.08, 0.17) * size, way, rng.randf_range(1.0, 1.6))
			for i in 30:
				var way := Vector2.from_angle(rng.randf() * TAU)
				_dot(img, c + way * rng.randf_range(0.3, 0.45) * size, rng.randf_range(0.004, 0.02) * size, way, 1.0)
		_:
			var main_r := size * (0.18 if v == TEX_WOUND else 0.24)
			_dot(img, c, main_r, Vector2.RIGHT, 1.0)
			for i in (4 if v == TEX_WOUND else 14):
				var way := Vector2.from_angle(rng.randf() * TAU)
				_dot(img, c + way * rng.randf_range(0.4, 1.6) * main_r, rng.randf_range(0.08, 0.45) * main_r, way, 1.0)
			if v != TEX_WOUND:
				for i in 60:
					var way := Vector2.from_angle(rng.randf() * TAU)
					_dot(img, c + way * rng.randf_range(1.4, 2.5) * main_r, rng.randf_range(0.02, 0.09) * main_r, way, 1.0 + rng.randf() * 2.0)
	img.generate_mipmaps()
	var tx := ImageTexture.create_from_image(img)
	_tex[v] = tx
	return tx


## One drop on a texture: an ellipse of radius r, stretched by stretch along
## way, solid with a crisp edge (the old shading made stripes).
static func _dot(img: Image, at: Vector2, r: float, way: Vector2, stretch: float) -> void:
	r = maxf(r, 0.6)
	var long := r * stretch
	var w := img.get_width()
	var h := img.get_height()
	var n := way.normalized()
	var x0 := maxi(0, int(at.x - long - 2))
	var x1 := mini(w - 1, int(at.x + long + 2))
	var y0 := maxi(0, int(at.y - long - 2))
	var y1 := mini(h - 1, int(at.y + long + 2))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var off := Vector2(x + 0.5, y + 0.5) - at
			var a_ := off.dot(n) / long
			var b_ := off.dot(Vector2(-n.y, n.x)) / r
			var d := sqrt(a_ * a_ + b_ * b_)
			# About a pixel of soft edge, whatever the size.
			var alpha := clampf((1.0 - d) * r + 0.5, 0.0, 1.0)
			if alpha > 0.0:
				var old := img.get_pixel(x, y).a
				if alpha > old:
					img.set_pixel(x, y, Color(1, 1, 1, alpha))


## A soft round puff for the mist.
static func _puff_tex() -> Texture2D:
	if _tex.has("puff"):
		return _tex["puff"]
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - size * 0.5, y + 0.5 - size * 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	img.generate_mipmaps()
	var tx := ImageTexture.create_from_image(img)
	_tex["puff"] = tx
	return tx
