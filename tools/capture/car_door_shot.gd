extends Node3D
## Screenshot of a prisoner being put in the back of a police car (door open).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/car_door_shot.tscn -- <out_dir>


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	ProtoWorld.ground(self, 60.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var pc := PoliceCar.new()
	pc.position = Vector3(0, 1.0, 0)
	add_child(pc)
	for i in 60:
		await get_tree().physics_frame
	var s := Suspect.new()
	s.look = 4
	s.net_id = 5
	add_child(s)
	s.global_position = pc.door_point(2) + Vector3(-1.5, -pc.door_point(2).y + 0.02, -0.5)
	s.set_state(Suspect.S.CUFFED)
	await get_tree().physics_frame
	s.put_in_car(pc, 2)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(-5.5, 2.6, -3.5)
	cam.look_at(pc.global_position + Vector3(0, 0.2, -0.5))
	cam.current = true
	for i in 50:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/car_door_open.png" % out)
	for i in 200:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/car_door_seated.png" % out)
	get_tree().quit()
