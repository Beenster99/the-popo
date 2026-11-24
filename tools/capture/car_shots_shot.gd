extends Node3D
## v0.20.0 check: a parked patrol car shot along its side (bullet holes, a
## broken window, a flat front tyre), and a second one doing a burnout
## (rear wheelspin, smoke, rubber). Saves <out>_holes.png and <out>_burnout.png.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/car_shots_shot.tscn -- <out>


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/car_shots"
	ProtoWorld.ground(self, 400.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var cs := CarSync.new()
	add_child(cs)
	var c := PoliceCar.new()
	c.position = Vector3(0, 1.0, 0)
	add_child(c)
	cs.add_car(c)
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.current = true
	for i in 40:
		await get_tree().physics_frame
	# A burst along the left side, from someone standing off to the left.
	var shooter := Vector3(-9, 1.2, 1.5)
	var space := get_world_3d().direct_space_state
	for k in 14:
		var target := c.global_transform * Vector3(-0.9, randf_range(-0.25, 0.55), randf_range(-1.8, 1.8))
		var dir := (target - shooter).normalized()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(shooter, shooter + dir * 20.0, 4))
		var ty := cs.tyre_on_path(shooter, hit.position if hit else shooter + dir * 20.0)
		if not ty.is_empty():
			cs.burst_tyre(ty.car, ty.wheel)
		elif hit:
			cs.bullet_hit(c, hit.position, dir)
	# And one at the front left tyre itself.
	var tyre: Vector3 = c.global_transform * (c._wheels[0].node as Node3D).position
	var ty2 := cs.tyre_on_path(shooter, tyre + (tyre - shooter).normalized() * 3.0)
	if not ty2.is_empty():
		cs.burst_tyre(ty2.car, ty2.wheel)
	for i in c._wheels.size():
		if c.tyre_flat(i):
			print("flat: wheel ", i, " at ", c._wheels[i].pos)
	for i in 60:
		await get_tree().physics_frame
	cam.position = c.global_position + Vector3(-4.6, 0.9, 2.2)
	cam.look_at(c.global_position + Vector3(0, 0.1, 0.3))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "_holes.png")
	print("flat tyres ", c.flat_tyres(), " broken windows ", c.broken_windows(), " holes ", c._holes.size())
	# Burnout: a second car floors it from a standstill.
	var b := PoliceCar.new()
	b.position = Vector3(12, 1.0, -30)
	add_child(b)
	for i in 40:
		await get_tree().physics_frame
	b.throttle = 1.0
	b.steer = 0.0
	var peak := 0.0
	for i in 25:
		await get_tree().physics_frame
		peak = maxf(peak, b.spin_k)
	# Hold it mid-launch, as a friend's copy of the car is (frozen, the
	# wheelspin from the snapshot), so the smoke builds over rendered frames.
	var spin := b.spin_k
	b.freeze = true
	for i in 40:
		b.spin_k = spin
		await get_tree().process_frame
	cam.position = b.global_position + Vector3(-7, 2.6, -8)
	cam.look_at(b.global_position + Vector3(0, 0.3, -1.5))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out + "_burnout.png")
	print("burnout peak wheelspin ", peak, " now ", b.spin_k, " at ", b.speed_kmh(), " km/h")
	get_tree().quit()
