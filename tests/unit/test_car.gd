extends Node
var t


func _car() -> Car:
	ProtoWorld.ground(self, 400.0)
	var c := Car.new()
	c.position = Vector3(0, 1.0, 0)
	add_child(c)
	return c


func test_car_settles_on_its_suspension() -> void:
	var c := _car()
	for i in 90:
		await get_tree().physics_frame
	print("    ride height %.2f" % c.global_position.y)
	t.check(c.global_position.y > 0.4 and c.global_position.y < 1.0, "ride height %f" % c.global_position.y)
	t.check(c.linear_velocity.length() < 0.2, "at rest")
	t.check(c.global_transform.basis.y.dot(Vector3.UP) > 0.99, "level")


func test_car_accelerates_and_steers() -> void:
	var c := _car()
	for i in 30:
		await get_tree().physics_frame
	c.throttle = 1.0
	for i in 180:
		await get_tree().physics_frame
	var kmh := c.speed_kmh()
	print("    speed after 3 s: %.0f km/h" % kmh)
	t.check(kmh > 50.0 and kmh < 140.0, "speed after 3 s full throttle: %f km/h" % kmh)
	c.steer = 1.0
	var yaw0 := c.global_rotation.y
	for i in 60:
		await get_tree().physics_frame
	t.check(absf(angle_difference(yaw0, c.global_rotation.y)) > 0.5, "turned")
	t.check(c.global_transform.basis.y.dot(Vector3.UP) > 0.8, "did not roll over")


func test_wall_hit_dents_and_drops_bumper() -> void:
	var c := _car()
	ProtoWorld.block(self, Vector3(8, 2, 1), Vector3(0, 1, 30), Color.GRAY)
	c.dented.connect(func(p, d, a): c.apply_dent(p, d, a))
	for i in 30:
		await get_tree().physics_frame
	c.throttle = 1.0
	for i in 240:
		await get_tree().physics_frame
	t.check(c.dent_amount() > 0.05, "dented %f" % c.dent_amount())
	print("    deepest dent %.2f m" % c.dent_amount())
	t.check(not c.bumper_attached, "bumper came off")


func test_coasting_car_comes_to_rest() -> void:
	var c := _car()
	for i in 30:
		await get_tree().physics_frame
	c.throttle = 1.0
	for i in 90:
		await get_tree().physics_frame
	c.throttle = 0.0
	var from := c.speed_kmh()
	var frames := 0
	while c.linear_velocity.length() > 0.05 and frames < 900:
		await get_tree().physics_frame
		frames += 1
	print("    coasted from %.0f km/h to rest in %.1f s" % [from, frames / 60.0])
	t.check(frames < 900, "still rolling at %.2f m/s after 15 s" % c.linear_velocity.length())
	t.check(frames > 120, "stops too abruptly (%d frames)" % frames)
