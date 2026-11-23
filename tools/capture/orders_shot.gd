extends Node3D
## Screenshots of the shouted-orders poses: a suspect on their knees with
## their hands on their head, a cuffed prisoner told to stay put (kneeling),
## and one walking cuffed. Run as a scene so the autoloads are there:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/orders_shot.tscn -- <out_dir>


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
	var poses := [[Suspect.S.SURRENDER, false], [Suspect.S.CUFFED, true], [Suspect.S.CUFFED, false]]
	var ss := []
	for i in poses.size():
		var s := Suspect.new()
		s.look = 3 + i
		s.net_id = 10 + i
		s.position = Vector3(-1.6 + i * 1.6, 0.05, 0)
		s.rotation.y = 0.5 - i * 0.2
		add_child(s)
		s.set_state(poses[i][0])
		s.stay = poses[i][1]
		ss.append(s)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.4, 1.5, 4.4)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.current = true
	for i in 90:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/orders_poses.png" % out)
	cam.position = Vector3(-1.6, 1.5, -2.2)
	cam.look_at(Vector3(-1.6, 1.0, 0))
	for i in 5:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/orders_hands_back.png" % out)
	get_tree().quit()
