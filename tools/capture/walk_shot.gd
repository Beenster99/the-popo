extends Node3D
## Frames of the mocap walks for a check reel: each walk travels past a side
## camera at its own pace over a striped floor (so foot slide shows), the
## relaxed walk holstered, the tactical ones with the gun at low ready or
## aimed. Run as a scene so the autoloads are there:
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/walk_shot.tscn -- <out_dir>
## Frames land in <out_dir>/<clip>/f####.png at 30 fps.

const SHOTS := [
	# [clip label, lower, upper, travel direction in the rig's space, speed m/s, view]
	["walk", "walk", "none", Vector3(0, 0, 1), 1.0, "side"],
	["walk_ready", "walk_ready", "ready_hold", Vector3(0, 0, 1), 1.3, "side"],
	["walk_ready_front", "walk_ready", "ready_hold", Vector3(0, 0, 1), 1.3, "front"],
	["walk_back_aim", "walk_ready", "aim_hold", Vector3(0, 0, -1), 0.9, "side"],
	["walk_left_aim", "walk_ready", "aim_hold", Vector3(1, 0, 0), 1.0, "front"],
	["walk_right_aim", "walk_ready", "aim_hold", Vector3(-1, 0, 0), 1.0, "front"],
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	ProtoWorld.ground(self, 80.0)
	for i in range(-40, 41):
		ProtoWorld.block(self, Vector3(0.05, 0.004, 8.0), Vector3(i * 0.5, 0.002, 0), Color("4a4e52"), "Stripe", false)
		ProtoWorld.block(self, Vector3(8.0, 0.004, 0.05), Vector3(0, 0.002, i * 0.5), Color("4a4e52"), "Stripe", false)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.62, 0.7)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.current = true
	for shot in SHOTS:
		var label: String = shot[0]
		DirAccess.make_dir_recursive_absolute("%s/%s" % [out, label])
		var holder := Node3D.new()
		add_child(holder)
		var rig := OfficerRig.new()
		holder.add_child(rig)
		await get_tree().process_frame
		rig.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		if shot[2] == "none":
			# Holstered: no pistol in the hand (the game does this in Officer).
			var slide := rig.model.find_child("gun_slide", true, false) as Node3D
			if slide:
				for g in slide.get_parent().get_children():
					if g is Node3D and String(g.name).begins_with("gun_"):
						(g as Node3D).visible = false
		var dir: Vector3 = shot[3]
		var speed: float = shot[4]
		var lower: String = shot[1]
		var upper: String = shot[2]
		var d := Vector2(-dir.x, dir.z)
		var clip_speed := OfficerRig.tac_clip_speed(d) if lower == "walk_ready" else rig.WALK_CLIP_SPEED
		holder.position = -dir * speed * 1.2
		var dt := 1.0 / 30.0
		for f in 75:
			rig.update_pose(lower, upper, speed, dt, holder.position + Vector3(0, 1.35, 6.0) if upper == "aim_hold" else Vector3.ZERO)
			if lower == "walk_ready":
				rig.tree.set("parameters/a_walk_ready/blend_position", d)
				rig.tree.set("parameters/ts_walk_ready/scale", speed / clip_speed)
			holder.position += dir * speed * dt
			var c := holder.position + Vector3(0, 0.9, 0)
			if shot[5] == "side":
				cam.position = c + Vector3(-3.6, 0.5, 0)
			else:
				cam.position = c + Vector3(0.6, 0.6, 3.6)
			cam.look_at(c)
			rig.tree.advance(dt)
			await get_tree().process_frame
			await get_tree().process_frame
			if f >= 15:
				get_viewport().get_texture().get_image().save_png("%s/%s/f%04d.png" % [out, label, f - 15])
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()
