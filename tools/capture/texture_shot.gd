extends Node
## v0.25 check shots: the building materials' textures. A little street of
## kit pieces (brick, stone and concrete fronts, shop and garage, pavement,
## road, a low wall), the inside (plaster, floor tiles, a door), and the
## chunks of a wall after it breaks (the bricks stay where they were).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/texture_shot.tscn -- <out_dir>

var out := "/tmp"


func _ready() -> void:
	_run.call_deferred()


func _shot(name: String, frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _piece(kind: String, xf: Transform3D, tint := Color(0, 0, 0, 0)) -> MeshInstance3D:
	var p := KitLibrary.get_piece(kind)
	var mi := MeshInstance3D.new()
	mi.mesh = p.mesh
	mi.transform = xf
	add_child(mi)
	KitLibrary.tint(mi, p.surfaces, tint)
	return mi


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	get_tree().root.size = Vector2i(1280, 720)
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	var r90 := Basis(Vector3.UP, PI / 2)
	# Ground: road in front, pavement under the buildings.
	for x in range(-3, 4):
		_piece("road_line" if x % 2 == 0 else "road", Transform3D(Basis(), Vector3(x * 4.0, 0, 6.0)))
		_piece("pavement", Transform3D(Basis(), Vector3(x * 4.0, 0, 2.0)))
		_piece("pavement", Transform3D(Basis(), Vector3(x * 4.0, 0, -2.0)))
	# Fronts: brick, stone, concrete, a shop, a garage.
	var fronts := [["wall_window", Color("8a3b2a")], ["wall_door", Color("a04a33")], ["wall_window", Color("d8cba8")],
		["wall_shopfront", Color("e2dccf")], ["wall_window", Color("7d8790")], ["wall_garage", Color("5e6f7f")], ["wall", Color("b98a4e")]]
	for i in fronts.size():
		var x := (i - 3) * 4.0
		_piece(fronts[i][0], Transform3D(Basis(), Vector3(x, 0.15, 0)), fronts[i][1])
		_piece(fronts[i][0], Transform3D(Basis(), Vector3(x, 3.15, 0)), fronts[i][1])
		if fronts[i][0] == "wall_window":
			_piece("glass_window", Transform3D(Basis(), Vector3(x, 0.15, 0)))
		if fronts[i][0] == "wall_garage":
			_piece("garage_door", Transform3D(Basis(), Vector3(x, 0.15, 0)))
		if fronts[i][0] == "wall_door":
			_piece("door_closed", Transform3D(Basis(), Vector3(x, 0.15, 0)))
	_piece("low_wall", Transform3D(Basis(), Vector3(-4, 0.15, 3.6)))
	_piece("column", Transform3D(Basis(), Vector3(14, 0.15, 0)))
	_piece("bollard", Transform3D(Basis(), Vector3(2, 0.15, 3.8)))
	_piece("lamp_post", Transform3D(Basis(), Vector3(6, 0.15, 3.8)))
	# A room behind: floor, plaster walls, a door.
	for x in range(-3, 4):
		_piece("slab", Transform3D(Basis(), Vector3(x * 4.0, 0.15, -2.0)))
		_piece("roof", Transform3D(Basis(), Vector3(x * 4.0, 6.15, -2.0)))
	_piece("int_wall_door", Transform3D(Basis(), Vector3(0, 0.15, -4.0)))
	_piece("int_wall", Transform3D(Basis(), Vector3(-4, 0.15, -4.0)))
	_piece("int_wall", Transform3D(r90, Vector3(-6, 0.15, -2.0)))
	# A broken brick wall: its chunks pulled apart a little.
	var wp := KitLibrary.get_piece("wall")
	for ch in wp.chunks:
		var mi := MeshInstance3D.new()
		mi.mesh = ch.mesh
		mi.position = Vector3(-20, 0.15, 0) + (ch.offset as Vector3) * 1.12
		add_child(mi)
		KitLibrary.tint(mi, ch.surfaces, Color("8a3b2a"))
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 60
	cam.position = Vector3(0, 2.0, 13)
	cam.look_at(Vector3(0, 2.6, 0))
	await _shot("street", 20)
	cam.position = Vector3(-10, 1.7, 4.5)
	cam.look_at(Vector3(-7, 1.6, 0))
	await _shot("brick_stone_close")
	cam.position = Vector3(6, 1.7, 4.5)
	cam.look_at(Vector3(8, 1.4, 0))
	await _shot("concrete_garage_close")
	cam.position = Vector3(2, 2.4, -1.0)
	cam.look_at(Vector3(-2, 1.0, -4.0))
	await _shot("inside")
	cam.position = Vector3(-20, 1.8, 5)
	cam.look_at(Vector3(-20, 1.5, 0))
	await _shot("broken_wall")
	get_tree().quit()
