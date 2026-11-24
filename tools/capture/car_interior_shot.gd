extends Node
## Car interiors with people in them, seen from outside through the glass.
##   xvfb-run -a godot --path . res://tools/capture/car_interior_shot.tscn -- <out_dir> [kind]

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var out: String = a[0] if a.size() > 0 else "/tmp"
	var kind: String = a[1] if a.size() > 1 else "sedan"
	get_tree().root.size = Vector2i(1000, 620)
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 40.0)
	var v: Car
	if kind == "police":
		v = PoliceCar.new()
	else:
		var cv := CivilianVehicle.new()
		cv.setup(kind, 2)
		v = cv
	v.position = Vector3(0, 1.0, 0)
	add_child(v)
	v.freeze = true
	await get_tree().process_frame
	var seats: Array = v.seats
	for i in mini(seats.size(), 3):
		var r := OfficerRig.new()
		v.add_child(r)
		r.position = seats[i]
		await get_tree().process_frame
		SuspectLook.apply(r.model, 3 + i * 5)
		EnemyGuns.show_in_hand(r.model, EnemyGuns.PISTOL if i == 1 else EnemyGuns.NONE)
		for f in 3:
			r.update_pose("sit", "drive" if i == 0 else ("ready_hold" if i == 1 else "civ_texting"), 0.0, 0.016)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.current = true
	var views := {"front": Vector3(2.6, 2.0, 5.2), "side": Vector3(-4.2, 1.9, 0.6), "close": Vector3(-2.3, 1.75, 0.9)}
	for k in views:
		cam.position = views[k]
		cam.look_at(Vector3(0, 1.1, 0.0))
		for f in 8:
			await get_tree().process_frame
		get_tree().root.get_texture().get_image().save_png("%s/%s_%s.png" % [out, kind, k])
	get_tree().quit()
