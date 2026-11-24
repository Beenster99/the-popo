extends Node
## v0.14.0 check shots: the mini map (small and large), the job markers on
## and off screen, the custody bay in front of the station, and both sides
## of a patrol car (POLICE must read left to right). Run as a scene:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . res://tools/capture/minimap_shot.tscn -- <out_dir>

var out := "/tmp"


func _ready() -> void:
	_run.call_deferred()


func _shot(name: String, frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	Settings.values["tips"] = false
	var c: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(c)
	c.dispatch.missions.enabled = false
	c.dispatch.stories.enabled = false
	for i in 60:
		await get_tree().physics_frame
	c.dispatch.missions.minute = 12 * 60.0
	var o: Officer = c.sync.my_pawn()
	var id := c.dispatch.start_call(Dispatcher.Kind.BURGLARY)
	print("call ", id, " at ", c.dispatch.calls[id].marker if id >= 0 else Vector3.ZERO, " me ", o.global_position)
	for i in 30:
		await get_tree().physics_frame
	# Job behind the camera: the edge arrow and the map.
	Settings.set_value("minimap", 1, false)
	await _shot("minimap_small", 20)
	# Face the job: the pin on screen.
	var to: Vector3 = c.dispatch.calls[id].marker - o.global_position
	c.cam.set("_yaw", rad_to_deg(atan2(-to.x, -to.z)))
	c.cam.set("_yaw_target", rad_to_deg(atan2(-to.x, -to.z)))
	await _shot("minimap_facing_job", 30)
	Settings.set_value("minimap", 2, false)
	await _shot("minimap_large", 10)
	Settings.set_value("minimap", 1, false)
	# The station front and the custody bay, from a free camera.
	var cam := Camera3D.new()
	c.add_child(cam)
	var bay := c.dispatch.bay_position()
	var st := c.gen.station()
	var v: Vector3 = st.v
	cam.position = bay - v * 14.0 + Vector3(0, 7, 0)
	cam.look_at(bay + v * 2.0 + Vector3(0, 1.5, 0))
	cam.current = true
	await _shot("station_bay", 10)
	# Both sides of a patrol car.
	var car: Node3D = c.police_cars[0]
	var r: Vector3 = car.global_transform.basis.x
	for side in [1.0, -1.0]:
		cam.position = car.global_position + r * side * 4.5 + Vector3(0, 1.4, 0)
		cam.look_at(car.global_position + Vector3(0, 0.6, 0))
		await _shot("car_side_%s" % ("right" if side < 0.0 else "left"), 6)
	cam.position = car.global_position + car.global_transform.basis.z * 5.0 + Vector3(0, 3.0, 0)
	cam.look_at(car.global_position)
	await _shot("car_front", 6)
	get_tree().quit()
