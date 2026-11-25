extends Node

var shot: String
var out: String


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	shot = a[0]
	out = a[1]
	await _run()
	get_tree().quit()


func _frames(n: int) -> void:
	print("frames ", n, " t=", Time.get_ticks_msec())
	for i in n:
		await get_tree().process_frame


func _save() -> void:
	# No HUD, so the looks compare on the 3D picture alone.
	for c in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(c as CanvasLayer).visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)


func _yaw_to(from: Vector3, to: Vector3) -> float:
	var d := to - from
	return atan2(d.x, d.z)


## An over-the-shoulder camera behind `who`, looking at `at`.
func _shoulder(s: Node, who: Vector3, at: Vector3, back := 3.2, side := 0.8, up := 1.75) -> Camera3D:
	var cam := Camera3D.new()
	s.add_child(cam)
	cam.far = 1500.0
	cam.fov = 65.0
	var f := (at - who) * Vector3(1, 0, 1)
	f = f.normalized()
	var r := f.cross(Vector3.UP).normalized()
	var p := who - f * back + r * side + Vector3(0, up, 0)
	cam.look_at_from_position(p, at + Vector3(0, 1.2, 0) + r * side * 0.5)
	cam.current = true
	return cam


func _run() -> void:
	City.next_seed = 4242
	Settings.values["tips"] = false
	get_tree().change_scene_to_file("res://game/city/city.tscn")
	await _frames(3)
	var s := get_tree().current_scene
	await _frames(10)
	for n in s.find_children("*", "NetOverlay", false, false):
		n.queue_free()
	(s.dispatch as Dispatcher).enabled = false
	var o: Officer = s.sync.my_pawn()
	var j := CityGenerator.junction(2, 3)
	match shot:
		"street", "night":
			s.dispatch.missions.minute = (14 * 60.0) if shot == "street" else (23 * 60.0)
			var at := j + Vector3(2, 0, 16)
			o.global_position = j + Vector3(-2, 0.1, -6)
			var aim := {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": _yaw_to(o.global_position, at)}
			s.sync.input_source = func(): return aim
			await _frames(40)
			o.rotation.y = aim.aim_yaw
			_shoulder(s, o.global_position, at)
			await _frames(60)
			await _save()
		"shootout":
			s.dispatch.missions.minute = 16 * 60.0 + 30.0
			o.global_position = j + Vector3(-2, 0.1, -6)
			var foe := j + Vector3(1.2, 0.1, 2.5)
			var a: Suspect = s.dispatch.spawn_suspect(foe, Suspect.S.SHOOT, true)
			var b: Suspect = s.dispatch.spawn_suspect(foe + Vector3(-3.5, 0, 2.5), Suspect.S.SHOOT, true)
			var yaw := _yaw_to(o.global_position, foe)
			var cmd := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": yaw, "aim_point": foe + Vector3(0, 1.3, 0)}
			s.sync.input_source = func(): return cmd
			await _frames(30)
			_shoulder(s, o.global_position, foe, 2.6, 0.75, 1.65)
			# One goes down in a spray, then the officer keeps firing.
			b.take_damage(500.0, (b.global_position - o.global_position).normalized())
			await _frames(40)
			cmd.buttons = PlayerInput.AIM | PlayerInput.FIRE
			var n := MuzzleFx.count
			for i in 90:
				await _frames(1)
				if MuzzleFx.count != n:
					break
			await _frames(1)
			await _save()
			print("a state ", Suspect.S.keys()[a.state], " b ", Suspect.S.keys()[b.state])
		"inside":
			s.dispatch.missions.minute = 14 * 60.0
			var bs: Array = s.gen.buildings.filter(func(x): return x.type == "office" and x.storeys >= 3)
			var bd: Dictionary = bs[0]
			# Stand well inside the far corner so the camera behind stays indoors
			# (not looking in through the glass).
			o.global_position = bd.origin + bd.u * ((bd.w - 2.0) * 4.0) + bd.v * ((bd.d - 2.0) * 4.0) + Vector3(0, 0.05, 0)
			s._furnish_near(false)
			var mid: Vector3 = bd.origin + bd.u * (bd.w * 2.0) + bd.v * (bd.d * 2.0)
			mid.y = o.global_position.y
			var aim := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": _yaw_to(o.global_position, mid), "aim_point": mid + Vector3(0, 1.2, 0)}
			s.sync.input_source = func(): return aim
			await _frames(40)
			_shoulder(s, o.global_position, mid, 2.4, 0.7, 1.6)
			await _frames(60)
			await _save()
