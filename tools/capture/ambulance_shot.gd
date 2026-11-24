extends Node
## Ambulance check: someone dies in the street, the ambulance comes, the
## paramedics load them and wheel them back; saves a frame at each stage.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/ambulance_shot.tscn -- <out dir>

var out := "/tmp"
var cam: Camera3D


func _ready() -> void:
	_run.call_deferred()


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	cam.global_position = from
	cam.look_at(at)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out.path_join(name))
	print("saved ", name)


func _run() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		out = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	for i in 20:
		await get_tree().physics_frame
	s.dispatch.enabled = false
	s.dispatch.missions.enabled = false
	s.dispatch.stories.enabled = false
	cam = Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	var amb := s.ambulances
	var at: Vector3 = s.gen.pavement_near(CityGenerator.junction(3, 2) + Vector3(14, 0, 4))
	if s.nav and s.nav.ready_to_use:
		at = s.nav.closest(at)
	var body := s.dispatch.spawn_suspect(at, Suspect.S.WANDER, false)
	body.civilian = true
	for i in 10:
		await get_tree().physics_frame
	body.take_damage(999.0, Vector3(1, 0, 0))
	if Gore.level() > 0:
		Gore.hit(s, at + Vector3(-1, 1, 0), at + Vector3(0, 1, 0))
	for i in 30:
		await get_tree().physics_frame
	amb._down[body] = AmbulanceService.WAIT
	await get_tree().physics_frame
	var a: Dictionary = amb.ambos.filter(func(x): return x.state != "idle")[0]
	var car: CivilianVehicle = a.car
	var got := {}
	for i in 60 * 200:
		cam.current = true
		var cp := car.global_position
		var fwd := car.global_transform.basis.z
		if a.state == "go" and not got.has("go") and cp.distance_to(at) < 70.0:
			got.go = true
			await _shot("ambulance_1_coming.png", cp + fwd * 14.0 + car.global_transform.basis.x * 4.0 + Vector3(0, 3.5, 0), cp + Vector3(0, 1.2, 0))
		if a.state == "work" and a.stage == "load" and not got.has("load") and a.load_t > 2.0:
			got.load = true
			var bp := AmbulanceService.body_pos(a.body)
			await _shot("ambulance_2_loading.png", bp + Vector3(5.5, 4.0, 5.5), bp)
		if a.state == "work" and a.stage == "return" and a.st_loaded and not got.has("back"):
			got.back = true
			for k in 40:
				await get_tree().physics_frame
			var sp: Vector3 = a.st_pos
			await _shot("ambulance_3_stretcher.png", sp + Vector3(-4.0, 3.0, 4.5), sp + Vector3(0, 0.8, 0))
			await _shot("ambulance_4_parked.png", cp - fwd * 12.0 + car.global_transform.basis.x * 6.0 + Vector3(0, 4.0, 0), cp + Vector3(0, 1.0, 0))
		if a.state == "leave":
			break
		await get_tree().physics_frame
	print("done: ", got.keys(), " collected ", amb.collected)
	get_tree().quit()
