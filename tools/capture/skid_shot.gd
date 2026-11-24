extends Node3D
## Skid marks check: a car drives up, stamps on the brakes, then does a
## handbrake turn on a plain road; a camera above saves a frame.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/skid_shot.tscn -- <out.png>


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/skids.png"
	ProtoWorld.ground(self, 400.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var c := Car.new()
	c.position = Vector3(0, 1.0, -60)
	add_child(c)
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.current = true
	cam.position = Vector3(-22, 26, -48)
	cam.look_at(Vector3(4, 0, -28))
	for i in 30:
		await get_tree().physics_frame
	c.throttle = 1.0
	for i in 110:
		await get_tree().physics_frame
	c.throttle = 0.0
	c.brake = 1.0
	for i in 25:
		await get_tree().physics_frame
	c.brake = 0.0
	c.throttle = 1.0
	for i in 40:
		await get_tree().physics_frame
	c.throttle = 0.3
	c.steer = 1.0
	c.handbrake = true
	for i in 70:
		await get_tree().physics_frame
	c.handbrake = false
	c.steer = 0.0
	c.throttle = 0.0
	c.brake = 1.0
	for i in 30:
		await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	print("strips ", SkidMarks.for_tree(get_tree()).strip_count(), " car at ", c.global_position)
	get_tree().quit()
