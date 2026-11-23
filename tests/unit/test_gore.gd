extends Node
## Gore (Phase 1.5 catch-up, v0.2.11): a shot leaves blood behind the body,
## a wound on it, a pool under the fallen, bodies thrown by the shot, and
## the slider turns it all off.
var t


func _scene() -> Suspect:
	ProtoWorld.ground(self, 60.0)
	ProtoWorld.block(self, Vector3(6, 3, 0.4), Vector3(0, 1.5, -3), Color.GRAY, "Wall")
	var s := Suspect.new()
	s.position = Vector3(0, 0.05, -1.5)
	add_child(s)
	for i in 10:
		await get_tree().physics_frame
	return s


func _decals() -> Array:
	return find_children("*", "Decal", true, false)


func test_a_shot_bleeds_onto_the_wall_and_the_body() -> void:
	Settings.values["gore"] = 3
	var s: Suspect = await _scene()
	Gore.hit(self, Vector3(0, 1.2, 4), Vector3(0, 1.2, -1.4))
	var on_wall := _decals().filter(func(d): return absf((d as Decal).global_position.z - -2.8) < 0.2)
	t.check(on_wall.size() >= 1, "a splat on the wall behind: %d decals" % _decals().size())
	var on_body := s.find_children("*", "Decal", true, false)
	t.check(on_body.size() == 1, "and a wound on them")
	# A head shot leaves a hole, and on Extreme bits fly.
	var before := find_children("*", "RigidBody3D", true, false).size()
	Gore.hit(self, Vector3(0, 1.65, 4), Vector3(0, 1.65, -1.45))
	var wounds := s.find_children("*", "Decal", true, false)
	t.check(wounds.size() == 3, "a wound and a hole in the head: %d" % wounds.size())
	# Painted on the body, not floating out on the collision capsule.
	var head_at: Vector3 = (wounds[2] as Decal).global_position
	t.check(Vector2(head_at.x - s.global_position.x, head_at.z - s.global_position.z).length() < 0.2, "the hole is on the head: %s" % head_at)
	t.check(wounds.all(func(d): return (d as Decal).cull_mask == Gore.BODY_LAYER), "wounds paint only bodies")
	t.check(not s.find_children("*", "MeshInstance3D", true, false).any(func(m): return m.mesh is SphereMesh), "no ball stuck on the head")
	t.check(find_children("*", "RigidBody3D", true, false).size() >= before + 4, "and bits come off")


func test_the_fallen_bleed_and_are_thrown() -> void:
	Settings.values["gore"] = 3
	var s: Suspect = await _scene()
	var hips := s.rig.bone_body("hips")
	var p0 := hips.global_position
	s.take_damage(500.0, Vector3(0, 0, 1))
	for i in 150:
		await get_tree().physics_frame
	t.check(s.state == Suspect.S.DOWN and s.rig.downed, "down")
	t.check(hips.global_position.distance_to(p0) > 0.8, "thrown by it: %.2f m" % hips.global_position.distance_to(p0))
	var pools := _decals().filter(func(d): return (d as Decal).get_parent() == self and (d as Decal).size.x > 0.5)
	t.check(pools.size() >= 1, "a pool spreads under them")
	var bone := s.find_children("*", "MeshInstance3D", true, false).filter(func(m): return m.mesh is CylinderMesh)
	t.check(bone.size() == 1, "and on Extreme a bone is out")
	# Shooting the body moves it.
	var at := hips.global_position
	Gore.hit(self, at + Vector3(0, 0.3, 3), at)
	# Joined to the rest of the body, the hip moves with all of it: give it
	# a few frames.
	for i in 6:
		await get_tree().physics_frame
	t.check(hips.global_position.distance_to(at) > 0.01, "a body on the floor jerks when shot (moved %.3f m)" % hips.global_position.distance_to(at))


func test_gore_off_is_clean() -> void:
	Settings.values["gore"] = 0
	var s: Suspect = await _scene()
	Gore.hit(self, Vector3(0, 1.2, 4), Vector3(0, 1.2, -1.4))
	s.take_damage(500.0, Vector3(0, 0, 1))
	for i in 130:
		await get_tree().physics_frame
	t.check(_decals().is_empty(), "no blood at all with gore off")
	Settings.values["gore"] = 3
