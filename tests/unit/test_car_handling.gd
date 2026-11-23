extends Node
## Handling feel: oversteer and handbrake turns (beenster's v0.1.0 notes).
var t


func _car() -> Car:
	ProtoWorld.ground(self, 400.0)
	var c := Car.new()
	c.position = Vector3(0, 1.0, -150)
	add_child(c)
	return c


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## Drives up to speed, then steers hard (with or without the handbrake) for
## one second. Returns [yaw turned (rad), worst slip angle (rad)].
func _turn(handbrake: bool) -> Array:
	var c := _car()
	await _frames(30)
	c.throttle = 1.0
	await _frames(150)
	c.throttle = 0.3
	c.steer = 1.0
	c.handbrake = handbrake
	var yaw0 := c.global_rotation.y
	var slip := 0.0
	for i in 60:
		await get_tree().physics_frame
		var v := Vector3(c.linear_velocity.x, 0, c.linear_velocity.z)
		if v.length() > 2.0:
			slip = maxf(slip, absf(v.normalized().signed_angle_to(c.global_transform.basis.z, Vector3.UP)))
	var yaw := absf(angle_difference(yaw0, c.global_rotation.y))
	c.queue_free()
	await _frames(2)
	return [yaw, slip]


func test_handbrake_swings_the_tail_out() -> void:
	var plain: Array = await _turn(false)
	var hb: Array = await _turn(true)
	print("    1 s full lock: yaw %.2f rad, slip %.0f deg; with handbrake: yaw %.2f rad, slip %.0f deg" % [plain[0], rad_to_deg(plain[1]), hb[0], rad_to_deg(hb[1])])
	t.check(plain[1] > deg_to_rad(22.0), "the tail steps out a little on full lock (oversteer)")
	t.check(hb[1] > deg_to_rad(65.0) and hb[0] < PI, "handbrake slides the tail out without spinning right round")
	t.check(hb[0] > plain[0] * 1.5, "handbrake turns much tighter")


func test_horn_sounds_while_held_and_syncs() -> void:
	var c := _car()
	await _frames(2)
	c.horn = true
	await _frames(2)
	t.check(c._horn_player.playing, "horn plays while held")
	var b := StreamPeerBuffer.new()
	c.encode_state(b)
	b.seek(0)
	t.check(Car.decode_state(b).horn == true, "horn state travels to other players")
	c.horn = false
	await _frames(2)
	t.check(not c._horn_player.playing, "horn stops when released")


## v0.8.1 (beenster: "they have a tendency to roll"): flat out, then full
## lock for two seconds, with and without the handbrake. The car leans but
## stays on its wheels.
func test_full_lock_at_speed_does_not_roll_over() -> void:
	for hb in [false, true]:
		var c := _car()
		await _frames(30)
		c.throttle = 1.0
		await _frames(240)
		var kmh := c.speed_kmh()
		c.steer = 1.0
		c.handbrake = hb
		var worst := 1.0
		for i in 120:
			await get_tree().physics_frame
			worst = minf(worst, c.global_transform.basis.y.y)
		print("    %s at %.0f km/h: most lean %.0f deg" % ["handbrake" if hb else "full lock", kmh, rad_to_deg(acos(clampf(worst, -1.0, 1.0)))])
		t.check(worst > 0.7, "stays on its wheels (%s): up.y %.2f" % ["handbrake" if hb else "full lock", worst])
		c.queue_free()
		await _frames(2)
