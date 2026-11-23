extends Node
## Wave 2, Phase 2.4: every civilian vehicle settles on its wheels, drives,
## steers and stays upright; the artic pulls its trailer round a corner.
var t


func _vehicle(kind: String, at := Vector3(0, 1.4, 0)) -> CivilianVehicle:
	var v := CivilianVehicle.make(kind, 3)
	v.position = at
	add_child(v)
	return v


func test_every_vehicle_drives() -> void:
	ProtoWorld.ground(self, 600.0)
	var x := -120.0
	var all: Array = []
	for kind in CivilianVehicle.TYPES:
		all.append(_vehicle(kind, Vector3(x, 2.2, 0)))
		x += 18.0
	for i in 90:
		await get_tree().physics_frame
	for v in all:
		var cv := v as CivilianVehicle
		t.check(cv.global_transform.basis.y.dot(Vector3.UP) > 0.97, "%s level at rest" % cv.kind)
		t.check(cv.linear_velocity.length() < 0.4, "%s at rest (%.2f)" % [cv.kind, cv.linear_velocity.length()])
		cv.set_meta("z0", cv.global_position.z)
		cv.throttle = 1.0
	for i in 180:
		await get_tree().physics_frame
	for v in all:
		var cv := v as CivilianVehicle
		var moved: float = cv.global_position.z - float(cv.get_meta("z0"))
		print("    %-12s %5.0f kg  %3.0f km/h after 3 s, %.1f m" % [cv.kind, cv.mass, cv.speed_kmh(), moved])
		t.check(moved > 8.0, "%s drives forward (%.1f m)" % [cv.kind, moved])
		cv.steer = 0.6
	var yaw0 := {}
	for v in all:
		yaw0[v] = (v as Node3D).global_rotation.y
	for i in 90:
		await get_tree().physics_frame
	for v in all:
		var cv := v as CivilianVehicle
		t.check(absf(angle_difference(yaw0[v], cv.global_rotation.y)) > 0.3, "%s turns" % cv.kind)
		t.check(cv.global_transform.basis.y.dot(Vector3.UP) > 0.8, "%s stays upright" % cv.kind)
		t.check(cv.seats.size() == cv.doors.size() and cv.seats.size() >= 2, "%s has seats and doors" % cv.kind)


func test_the_artic_pulls_its_trailer() -> void:
	ProtoWorld.ground(self, 600.0)
	var cab := _vehicle("hgv_tractor", Vector3(0, 1.6, 0))
	for i in 10:
		await get_tree().physics_frame
	var tr := Trailer.make("box", 1)
	add_child(tr)
	tr.hitch(cab)
	for i in 90:
		await get_tree().physics_frame
	t.check(tr.hitched(), "hitched")
	t.check(tr.global_transform.basis.y.dot(Vector3.UP) > 0.95, "trailer level (%.2f)" % tr.global_transform.basis.y.dot(Vector3.UP))
	var gap0 := tr.global_position.distance_to(cab.global_position)
	cab.throttle = 0.8
	for i in 240:
		await get_tree().physics_frame
	cab.steer = 0.5
	cab.throttle = 0.5
	for i in 180:
		await get_tree().physics_frame
	var gap1 := tr.global_position.distance_to(cab.global_position)
	print("    tractor %.0f km/h, trailer %.1f m behind (was %.1f), yaw apart %.0f deg" % [cab.speed_kmh(), gap1, gap0,
		rad_to_deg(absf(angle_difference(cab.global_rotation.y, tr.global_rotation.y)))])
	t.check(tr.hitched(), "still hitched after the corner")
	t.check(absf(gap1 - gap0) < 1.0, "the trailer follows at the hitch")
	t.check(tr.global_transform.basis.y.dot(Vector3.UP) > 0.8, "trailer upright")
	tr.unhitch()
	for i in 60:
		await get_tree().physics_frame
	t.check(not tr.hitched(), "comes off the hitch")
