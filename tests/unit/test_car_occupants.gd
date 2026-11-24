extends Node
## v0.25 (beenster, 2026-11-24): people in cars can be told apart and shot
## through the glass: dispatch describes the driver, some cars carry a
## passenger, and a bullet through a window hits whoever's sat in its way.
var t


func test_dispatch_describes_people() -> void:
	var a := SuspectLook.describe(3)
	t.check(a.contains(" top, ") and (a.contains("beanie") or a.contains("no hat")), "a description: %s" % a)
	var n := {}
	for i in 40:
		n[SuspectLook.describe(i)] = true
	t.check(n.size() > 25, "descriptions differ from person to person (%d of 40)" % n.size())
	t.check(SuspectLook.describe(SuspectLook.WORKER).contains("hi-vis"), "a council worker is in hi-vis")


func test_passengers_from_the_look() -> void:
	var with := 0
	for i in 200:
		if TrafficSystem.has_passenger(i):
			with += 1
		t.check(TrafficSystem.passenger_look(i) < SuspectLook.WORKER, "a passenger is a civilian")
	t.check(with > 30 and with < 70, "about one car in four has a passenger (%d of 200)" % with)


func test_shot_through_the_window_hits_the_driver() -> void:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	for i in 40:
		await get_tree().physics_frame
	var tr := s.traffic
	var rider := 0
	for dr in tr.drivers:
		if dr.get("rider", false) and dr.get("prig") != null and (dr.prig as Node3D).visible:
			rider += 1
	t.check(rider > 0, "some cars have a passenger in them (%d)" % rider)
	# Stop a car and shoot its driver through the side window.
	var dr: Dictionary = {}
	for d in tr.drivers:
		if (d.car as CivilianVehicle).kind in ["sedan", "hatchback"]:
			dr = d
			break
	var car: CivilianVehicle = dr.car
	dr.mode = "parked"
	s.cars.ai_inputs.erase(dr.idx)
	for i in 90:
		car.linear_velocity = Vector3.ZERO
		await get_tree().physics_frame
	var head = TrafficSystem._bone_at(dr.rig, "head_2")
	t.check(head != null, "the driver has a head to aim at")
	if head == null:
		s.queue_free()
		return
	var side := car.global_transform.basis.x * signf(car.seats[0].x)
	var o: Officer = s.sync.my_pawn()
	var from: Vector3 = head + side * 5.0
	o.global_position = from - Vector3(0, 1.5, 0)
	await get_tree().physics_frame
	var end := Gunfire.resolve(s.world, s.cars, from, (head - from).normalized(), false, o)
	t.check(end.distance_to(head) < 0.4, "the bullet ends in the driver, not the door (%.2f m off)" % end.distance_to(head))
	t.check(int(dr.get("hurt", 0)) & 1 == 1, "the driver is hit and slumps")
	t.check(absf((dr.rig as Node3D).rotation.x) > 0.3, "slumped in the seat")
	# On a client the encoded traffic carries the hurt driver.
	var b := tr._encode()
	t.check(b.size() == 5 + tr.drivers.size() * 2, "two bytes a car")
	s.queue_free()
	await get_tree().process_frame
