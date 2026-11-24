extends Node
## v0.20.0 (beenster: shoot out tyres and windows, bullet holes, police cars
## rear-wheel drive with wheelspin and tyre smoke).
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _police(at := Vector3(0, 1.0, -150)) -> PoliceCar:
	ProtoWorld.ground(self, 400.0)
	var c := PoliceCar.new()
	c.position = at
	add_child(c)
	return c


func test_officer_bullets_hit_cars() -> void:
	var c := _police(Vector3(0, 1.0, 0))
	await _frames(20)
	var o := Officer.new()
	add_child(o)
	o.global_position = Vector3(0, 0, -8)
	await _frames(2)
	var hit := Melee.bullet_ray(get_viewport().get_world_3d().direct_space_state, Vector3(0, 1.0, -8), Vector3(0, 0, 1), o)
	t.check(not hit.is_empty() and hit.collider == c, "an officer's bullet stops on a car (it used to fly through)")
	o.queue_free()
	c.queue_free()
	await _frames(2)


func test_shot_at_the_glass_breaks_the_window() -> void:
	var c := _police(Vector3(0, 1.0, 0))
	await _frames(30)
	# Straight at the windscreen from in front, level with it.
	var g: AABB = c.glass["win_front"].box
	var aim := c.global_transform * g.get_center()
	var from := aim + c.global_transform.basis.z * 8.0
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, aim + (aim - from).normalized() * 3.0, 4))
	t.check(not hit.is_empty(), "the shot reaches the car")
	if hit.is_empty():
		return
	var lp := c.global_transform.affine_inverse() * (hit.position as Vector3)
	var ld := c.global_transform.basis.inverse() * (aim - from).normalized()
	t.check(c.window_at(lp, ld) == "win_front", "the windscreen is the window that shot meets (got %s)" % c.window_at(lp, ld))
	# A side shot through the driver's window.
	var gs: AABB = c.glass["win_fl"].box
	var aim2 := c.global_transform * gs.get_center()
	var from2 := aim2 - c.global_transform.basis.x * 8.0
	var hit2 := get_viewport().get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from2, aim2 + (aim2 - from2).normalized() * 3.0, 4))
	var lp2 := c.global_transform.affine_inverse() * (hit2.position as Vector3)
	var ld2 := c.global_transform.basis.inverse() * (aim2 - from2).normalized()
	t.check(c.window_at(lp2, ld2) == "win_fl", "a side shot breaks the side window (got %s)" % c.window_at(lp2, ld2))
	c.queue_free()
	await _frames(2)


func test_shot_tyre_goes_flat_and_pulls() -> void:
	var c := _police()
	await _frames(30)
	# Aim at the front left wheel's middle from the side: that passes under
	# the body box, so it is found along the shot's path.
	var w: Node3D = c._wheels[0].node
	var aim := c.global_transform * w.position
	var from := aim + c.global_transform.basis.x * 8.0 * signf(w.position.x)
	var cs := CarSync.new()
	add_child(cs)
	cs.add_car(c)
	var ty := cs.tyre_on_path(from, aim + (aim - from).normalized() * 6.0)
	t.check(not ty.is_empty() and ty.car == c and ty.wheel == 0, "a shot at the tyre's middle finds that tyre")
	# A shot at the top of the tyre meets the body box first.
	var top := aim + c.global_transform.basis.y * 0.25
	var fromt := top + (from - aim)
	var hit := get_viewport().get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(fromt, top + (top - fromt).normalized() * 3.0, 4))
	if not hit.is_empty():
		var lp := c.global_transform.affine_inverse() * (hit.position as Vector3)
		var ld := c.global_transform.basis.inverse() * (top - fromt).normalized()
		t.check(c.tyre_at(lp, ld) == 0, "a shot on the wheel arch finds the tyre (got %d)" % c.tyre_at(lp, ld))
	cs.queue_free()
	# A shot at the door doesn't count as the tyre.
	var door := c.global_transform * Vector3(-0.9, 0.3, 0.0)
	var lpd := c.global_transform.affine_inverse() * door
	t.check(c.tyre_at(lpd, Vector3(1, 0, 0)) == -1, "a door shot leaves the tyres alone")
	var y0 := c.global_position.y
	c.flatten_tyre(0)
	await _frames(40)
	t.check(c.tyre_flat(0) and c.flat_tyres() == 1, "the tyre is flat")
	var tilt := (c.global_transform.basis.x).y
	print("    flat front left: body tilt %.3f, height change %.3f" % [tilt, c.global_position.y - y0])
	t.check(tilt > 0.01, "the car sags on the flat corner")
	# Drive straight: the flat corner drags it off line.
	c.throttle = 0.8
	await _frames(240)
	var yaw := c.global_rotation.y
	print("    after 4 s at part throttle with a flat: yaw %.1f deg" % rad_to_deg(yaw))
	t.check(absf(yaw) > deg_to_rad(3.0), "a flat pulls the car off a straight line")
	c.queue_free()
	await _frames(2)


func test_police_car_spins_its_rear_wheels_off_the_line() -> void:
	var c := _police()
	await _frames(30)
	c.throttle = 1.0
	var spin := 0.0
	var smoking := 0
	for i in 40:
		await get_tree().physics_frame
		spin = maxf(spin, c.spin_k)
		if c.spin_k > 0.2:
			smoking += 1
	print("    flat-out launch: rear wheelspin %.2f, front wheels spin %s" % [spin, str(c._wheels.filter(func(w): return w.front and w.wspin > 0.0).size())])
	t.check(spin > 0.3 and smoking > 30, "flooring it from a standstill spins and smokes the rear tyres (%d ticks)" % smoking)
	t.check(c._wheels.filter(func(w): return w.front and w.wspin > 0.0).is_empty(), "the fronts never spin (rear-wheel drive)")
	await _frames(240)
	print("    at %.0f km/h: wheelspin %.2f" % [c.speed_kmh(), c.spin_k])
	t.check(c.spin_k < 0.05, "it hooks up once it's moving")
	# Wheelspin reaches friends' copies in the snapshot.
	c.spin_k = 0.6
	var b := StreamPeerBuffer.new()
	c.encode_state(b)
	b.seek(0)
	t.check(absf(Car.decode_state(b).spin - 0.6) < 0.01, "wheelspin travels to other players")
	c.queue_free()
	await _frames(2)


func test_plain_car_launch_does_not_spin() -> void:
	ProtoWorld.ground(self, 400.0)
	var c := CivilianVehicle.make("sedan")
	c.position = Vector3(0, 1.0, -150)
	add_child(c)
	await _frames(30)
	c.throttle = 1.0
	var smoking := 0
	for i in 120:
		await get_tree().physics_frame
		if c.spin_k > 0.2:
			smoking += 1
	t.check(smoking < 15, "a family saloon pulls away without smoking its tyres (%d ticks of wheelspin)" % smoking)
	c.queue_free()
	await _frames(2)


func test_tyres_and_holes_travel_in_the_catch_up() -> void:
	var cs := CarSync.new()
	add_child(cs)
	var c := _police(Vector3(5, 1.0, 5))
	cs.add_car(c)
	await _frames(5)
	c.flatten_tyre(2, true)
	c.apply_dent(Vector3(0.9, 0.1, 0.2), Vector3(-1, 0, 0), Car.BULLET_DENT)
	var b := StreamPeerBuffer.new()
	cs.write_state(b)
	var c2 := _police(Vector3(15, 1.0, 5))
	var cs2 := CarSync.new()
	add_child(cs2)
	cs2.add_car(c2)
	await _frames(2)
	b.seek(0)
	cs2.read_state(b)
	t.check(c2.tyre_flat(2) and c2.flat_tyres() == 1, "a friend joining late sees the flat tyre")
	t.check(c2.dent_log.size() == 1 and is_equal_approx(c2.dent_log[0][2], Car.BULLET_DENT), "and the bullet dent (which makes the hole)")
	for n in [c, c2, cs, cs2]:
		n.queue_free()
	await _frames(2)
