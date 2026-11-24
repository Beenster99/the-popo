extends Node3D
## v0.24: crooks busy at the crime: rummaging (standing and low), smashing,
## jimmying, dealing and keeping watch. Run as a scene:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/crime_shot.tscn -- <out_dir>


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
	var acts := [Suspect.ACT.RUMMAGE, Suspect.ACT.RUMMAGE_LOW, Suspect.ACT.SMASH, Suspect.ACT.JIMMY, Suspect.ACT.DEAL, Suspect.ACT.LOOKOUT]
	for i in acts.size():
		var s := Suspect.new()
		s.look = 2 + i
		s.net_id = 10 + i
		s.position = Vector3(-4.0 + i * 1.6, 0.05, 0)
		add_child(s)
		s.set_meta("stay", true)
		s.rotation.y = 1.2
		var p := s.position
		s.work = [{"p": p, "at": p + Vector3(sin(1.2), 0, cos(1.2)) * 2.0, "act": acts[i]}]
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, 1.4, 5.2)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.current = true
	for k in 3:
		for i in 40:
			await get_tree().physics_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/crime_work_%d.png" % [out, k])
	get_tree().quit()
