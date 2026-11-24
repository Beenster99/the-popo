extends Node

var shot: String
var out: String
var args_extra := ""


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	shot = a[0]
	out = a[1]
	args_extra = a[2] if a.size() > 2 else ""
	await _run()
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _save() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)


func _scene(path: String) -> Node:
	get_tree().change_scene_to_file(path)
	await _frames(3)
	return get_tree().current_scene


## An empty lit floor with a camera, for close looks at characters.
func _save_as(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)


func _plain_stage(cam_at: Vector3, look: Vector3) -> Node3D:
	var root := Node3D.new()
	get_tree().root.add_child(root)
	ProtoWorld.ground(root, 60.0)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.68)
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(env)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.look_at_from_position(cam_at, look)
	cam.current = true
	return root


func _run() -> void:
	match shot:
		"city_night", "city_rain":
			# Wave 4: the street at night under the lamps, and in the rain.
			City.next_seed = 4242
			var s := await _scene("res://game/city/city.tscn")
			await _frames(10)
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			(s.dispatch as Dispatcher).enabled = false
			var w: CityWeather = s.weather
			s.dispatch.missions.minute = 23 * 60.0 if shot == "city_night" else 17 * 60.0
			if shot == "city_rain":
				w.set_weather(CityWeather.W.STORM)
				w.rain = 1.0
				w.wet = 1.0
			var cam := Camera3D.new()
			s.add_child(cam)
			cam.far = 1000.0
			var j := CityGenerator.junction(2, 4)
			cam.look_at_from_position(j + Vector3(-14, 4.0, -10), j + Vector3(4, 0.5, 6))
			cam.current = true
			await _frames(80)
			await _save()
		"nade_smoke", "nade_gas", "nade_flash", "nade_frag":
			# Grenades: a cloud of smoke or CS gas in the street, a flashbang
			# going off, a frag blast.
			City.next_seed = 4242
			var s := await _scene("res://game/city/city.tscn")
			await _frames(10)
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			(s.dispatch as Dispatcher).enabled = false
			s.dispatch.missions.minute = 14 * 60.0 if shot != "nade_flash" else 22 * 60.0
			var j := CityGenerator.junction(2, 4)
			var o: Officer = s.sync.my_pawn()
			o.global_position = j + Vector3(-6, 0.1, -4)
			var cam := Camera3D.new()
			s.add_child(cam)
			cam.far = 1000.0
			cam.look_at_from_position(j + Vector3(-14, 3.5, -10), j + Vector3(3, 1.0, 4))
			cam.current = true
			var kind: int = ["nade_smoke", "nade_gas", "nade_flash", "nade_frag"].find(shot)
			var at := j + Vector3(2, 0.4, 3)
			Grenades.throw(o, kind, at, Vector3.ZERO)
			var wait := int(60 * Grenades.FUSE[kind]) + (300 if kind < 2 else 3)
			await _frames(wait)
			await _save()
		"repair_site":
			# beenster (2026-11-24): the lorry and crane drive in and park, the
			# crane lifts a piece off the lorry and sets it in, the crew guide
			# it and fix it. Saves several frames: <out> is a folder.
			City.next_seed = 4242
			var s := await _scene("res://game/city/city.tscn")
			await _frames(10)
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			(s.dispatch as Dispatcher).enabled = false
			s.dispatch.missions.minute = 14 * 60.0
			RepairCrews.watch_all = true
			var b0: Dictionary = s.gen.buildings[3]
			var at: Vector3 = (b0.origin as Vector3) + Vector3(1.0, 1.0, 0.0)
			s.world.explode(at, 3.5, 400.0, 6.0)
			s.world.explode(at + Vector3(0, 3.2, 0), 3.0, 400.0, 6.0)
			RenderingServer.render_loop_enabled = false
			await _frames(240)
			var r: RepairCrews = s.repairs
			for id in r._broken:
				r._broken[id] = RepairCrews.WAIT
			r._tick = 0.0
			await _frames(5)
			var site: Dictionary = r.sites.values()[0]
			var ws: WorksSite = r._cones[site.id]
			var lorry: Transform3D = site.lorry
			var dir := lorry.basis.z
			var c: Vector3 = (lorry.origin + (site.crane as Transform3D).origin) * 0.5
			var side: Vector3 = site.at - lorry.origin
			side = Vector3(side.x, 0, side.z).normalized()
			var cam := Camera3D.new()
			s.add_child(cam)
			cam.far = 1000.0
			cam.current = true
			# Driving in.
			site.age = 5.5
			ws.age = 5.5
			cam.look_at_from_position(c - side * 16.0 - dir * 10.0 + Vector3(0, 5.0, 0), c + Vector3(0, 1.5, 0))
			RenderingServer.render_loop_enabled = true
			await _frames(3)
			await _save_as(out + "/1_arrive.png")
			RenderingServer.render_loop_enabled = false
			site.age = WorksSite.ARRIVE + WorksSite.SET_UP
			ws.age = site.age
			await _frames(30)
			# Knock out an outside wall upstairs, facing the lorry, so the
			# crane has a big panel to put back.
			var best := -1
			var bd := INF
			for pid in s.world.pieces_near(lorry.origin, 20.0):
				var pp: Dictionary = s.world.pieces[pid]
				var bx: AABB = pp.aabb
				if pp.kind == "wall" and pp.state == "intact" and bx.position.y > 2.5 and bx.position.y < 7.0:
					var dd := bx.get_center().distance_to(lorry.origin)
					if dd < bd:
						bd = dd
						best = pid
			if best >= 0:
				s.world.explode((s.world.pieces[best].aabb as AABB).get_center(), 1.2, 400.0, 3.0)
				await _frames(200)
				for id in r._broken:
					r._broken[id] = RepairCrews.WAIT
				r._tick = 0.0
				await _frames(3)
				print("wall ", best, " ", s.world.pieces[best].state, " in site ", (site.pieces as Array).has(best))
			# Clear the rubble quickly, keep the crew calm, then lift.
			for i in 2400:
				site.t = minf(site.t, 0.0) if site.stage == "clean" else site.t
				for w in site.crew:
					if is_instance_valid(w) and (w as Suspect).state in [Suspect.S.PANIC, Suspect.S.COWER]:
						(w as Suspect)._back_to_route()
				if site.stage == "build" and not (site.lift as Dictionary).is_empty() and site.last >= 0:
					break
				await get_tree().physics_frame
			# Let one lift go round so there's a piece just set for the fitter.
			var shots := {0.13: "2_slinging", 0.45: "3_swinging", 0.69: "4_landing", 0.95: "5_fitting"}
			var done := {}
			for i in 60 * 40:
				for w in site.crew:
					if is_instance_valid(w) and (w as Suspect).state in [Suspect.S.PANIC, Suspect.S.COWER]:
						(w as Suspect)._back_to_route()
				await get_tree().physics_frame
				if ws._lift_piece < 0 or not String(s.world.pieces[ws._lift_piece].kind).begins_with("wall"):
					continue
				var u := ws._lift_t / ws._lift_len
				for k in shots:
					if u >= k and not done.has(k) and done.size() == shots.keys().find(k):
						done[k] = true
						var tgt: Vector3 = ws._target
						var mid := (c + tgt) * 0.5
						if k < 0.3:
							cam.look_at_from_position(lorry.origin - side * 9.0 + dir * 7.0 + Vector3(0, 4.0, 0), ws.pick_point() + Vector3(0, 0.5, 0))
						elif k < 0.6:
							cam.look_at_from_position(mid - side * 26.0 - dir * 14.0 + Vector3(0, 10.0, 0), mid + Vector3(0, 5.0, 0))
						elif k < 0.8:
							cam.look_at_from_position(tgt - side * 12.0 + dir * 6.0 + Vector3(0, -1.0, 0), tgt + Vector3(0, -3.5, 0))
						else:
							var fit := Vector3.INF
							for nid in ws._crew:
								if int(ws._crew[nid].job) in [WorksSite.Job.DRILL, WorksSite.Job.WELD, WorksSite.Job.GRIND]:
									fit = (ws._crew[nid].w as Node3D).global_position
							if fit == Vector3.INF:
								fit = site.at
							cam.look_at_from_position(fit - side * 6.0 + dir * 3.0 + Vector3(0, 2.2, 0), fit + Vector3(0, 0.9, 0))
						RenderingServer.render_loop_enabled = true
						await get_tree().process_frame
						await _save_as(out + "/" + shots[k] + ".png")
						RenderingServer.render_loop_enabled = false
				if done.size() == shots.size():
					break
			print("jobs ", site.jobs)
		"station_armoury", "station_yard":
			# Wave 3: the armoury screen, and the station grown (garage, range).
			City.next_seed = 4242
			var s := await _scene("res://game/city/city.tscn")
			await _frames(10)
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			(s.dispatch as Dispatcher).enabled = false
			s.dispatch.pay = 9000
			for i in [2, Armoury.EXT_MAG, Armoury.HOLLOW, Armoury.GARAGE, Armoury.INTERCEPTOR, Armoury.RANGE, Armoury.PLAIN]:
				s.armoury._buy(i)
			var o: Officer = s.sync.my_pawn()
			if shot == "station_armoury":
				o.global_position = s.armoury.counter
				await _frames(30)
				ArmouryScreen.open(get_tree(), s.armoury, func(): return o)
			else:
				var st: Dictionary = s.gen.station()
				var cam := Camera3D.new()
				s.add_child(cam)
				cam.far = 1000.0
				var c: Vector3 = (st.origin as Vector3) + Vector3(18, 0, 22)
				cam.look_at_from_position(c + Vector3(0, 80, 0.1), c) if OS.has_environment("TOPDOWN") else cam.look_at_from_position(c + Vector3(30, 16, -30), c + Vector3(0, 0, 4))
				cam.current = true
				var r := s.get_node("Range") as FiringRange
				for tg in r.targets_list():
					tg.set_up(true, tg.index % 3 == 1)
			await _frames(60)
			await _save()
		"city_aerial", "city_street", "city_inside", "city_docks", "city_downtown", "city_traffic", "city_skyline":
			# Wave 2: the whole city.
			City.next_seed = 4242
			var s := await _scene("res://game/city/city.tscn")
			await _frames(10)
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			(s.dispatch as Dispatcher).enabled = false
			var o: Officer = s.sync.my_pawn()
			var e := CityGenerator.city_extent()
			match shot:
				"city_aerial":
					var cam := Camera3D.new()
					s.add_child(cam)
					cam.far = 2000.0
					cam.look_at_from_position(Vector3(e * 0.5 - 160, 260, e + 170), Vector3(e * 0.5, 0, e * 0.45))
					cam.current = true
				"city_traffic", "city_skyline":
					var cam := Camera3D.new()
					s.add_child(cam)
					cam.far = 2000.0
					var j := CityGenerator.junction(2, 3)
					if shot == "city_traffic":
						cam.look_at_from_position(j + Vector3(-16, 5.5, -13), j + Vector3(2, 0.5, 4))
						await _frames(40)
					else:
						var j0 := CityGenerator.junction(0, 3)
						cam.look_at_from_position(j0 + Vector3(-2, 3.0, 2.6), j0 + Vector3(300, 8, 2.6))
					cam.current = true
				"city_docks", "city_downtown":
					var cam := Camera3D.new()
					s.add_child(cam)
					cam.far = 2000.0
					if shot == "city_docks":
						cam.look_at_from_position(Vector3(130, 30, e + 40), Vector3(170, 0, e - 40))
					else:
						cam.look_at_from_position(Vector3(70, 22, 100), Vector3(160, 6, 160))
					cam.current = true
				"city_inside":
					var b: Dictionary = s.gen.buildings.filter(func(x): return x.type == "office" and x.storeys >= 3)[0]
					o.global_position = b.origin + b.u * ((b.w - 0.5) * 4.0) + b.v * ((b.d - 1.5) * 4.0) + Vector3(0, 0.05, 0)
					s._furnish_near(false)
					s.cam.tp_pitch = -12.0
			await _frames(90)
			await _save()
		"drag":
			# v0.2.11: dragging a downed teammate by the collar.
			var root := _plain_stage(Vector3(4.5, 2.2, 4.5), Vector3(2.5, 0.4, 0))
			var a := Officer.new()
			root.add_child(a)
			a.global_position = Vector3(0, 0.05, 0)
			var b := Officer.new()
			root.add_child(b)
			b.global_position = Vector3(0.8, 0.05, 0)
			b.holstered = true
			for i in 5:
				a.sim_step({"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}, 1.0 / 60.0)
				await get_tree().physics_frame
			a.take_damage(150.0, Vector3.BACK)
			for i in 200:
				a.sim_step({"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}, 1.0 / 60.0)
				var drag := i > 60
				b.sim_step({"move": Vector2(1, 0) if drag else Vector2.ZERO, "buttons": PlayerInput.DRAG if drag else 0, "aim_yaw": 0.0}, 1.0 / 60.0)
				await get_tree().physics_frame
			print("drag: a ", a.global_position, " ", Officer.S.keys()[a.state], " b ", b.global_position, " ", Officer.S.keys()[b.state], " yaw ", rad_to_deg(b.rotation.y), " chest ", a.rig.bone_body("chest_2").global_position)
			await _save()
		"fallen":
			# v0.2.11: how bodies lie after going down (beenster: "collapse
			# in a heap"). Three suspects shot from different sides and one
			# shot while running, seen from the side.
			var root := Node3D.new()
			get_tree().root.add_child(root)
			ProtoWorld.ground(root, 60.0)
			var sun := DirectionalLight3D.new()
			sun.rotation_degrees = Vector3(-50, 30, 0)
			root.add_child(sun)
			var env := WorldEnvironment.new()
			env.environment = Environment.new()
			env.environment.background_mode = Environment.BG_COLOR
			env.environment.background_color = Color(0.55, 0.6, 0.68)
			env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
			env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			root.add_child(env)
			var cam := Camera3D.new()
			root.add_child(cam)
			cam.look_at_from_position(Vector3(0, 3.5, 7.5), Vector3(0, 0.2, 0.5))
			cam.current = true
			var pushes := [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3.ZERO]
			var sps := []
			for k in 4:
				var sp := Suspect.new()
				root.add_child(sp)
				sp.global_position = Vector3(-4.5 + k * 3.0, 0.05, 0)
				sps.append(sp)
			await _frames(20)
			for k in 4:
				if k == 3:
					sps[k].velocity = Vector3(0, 0, 6)
				sps[k].hp = 1.0   # a pistol round finishes them
				sps[k].take_damage(35.0, pushes[k])
			await _frames(int(args_extra) if args_extra != "" else 200)
			await _save()
		"look_day", "look_night", "look_inside", "look_rotated":
			var s := await _scene("res://prototypes/p05_look/look.tscn")
			await _frames(5)
			var p: Node3D = s.sync.my_pawn()
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			if shot == "look_night":
				s.set_night(true)
			if shot == "look_inside":
				p.global_position = s.SHOP_A + Vector3(4.6, 0.3, 2.0)
			if shot == "look_rotated":
				s.cam._yaw_target = 135.0
			await _frames(90)
			await _save()
		"destruction":
			var s := await _scene("res://prototypes/p03_destruction/destruction.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			s.cam.zoom = 20.0
			await _frames(30)
			s.world.damage_piece(1, 9999.0, Vector3(-11, 1.5, -2), 3.0)
			s.world.explode(Vector3(7, 1, -4.5), 3.0, 300.0, 8.0)
			await _frames(40)
			await _save()
		"car":
			var s := await _scene("res://prototypes/p04_car/car.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			var c: Car = s.cars.cars[0]
			c.apply_dent(Vector3(0.5, 0.2, 2.1), Vector3(-0.3, 0, -1).normalized(), 0.3)
			c.apply_dent(Vector3(0.93, 0.1, -0.5), Vector3(-1, 0, 0), 0.2)
			c.detach_bumper()
			s.cam.zoom = 9.0
			await _frames(60)
			await _save()
		"sound":
			# Keeps the HUD so the shot shows which bus and how many walls.
			var s := await _scene("res://prototypes/p07_sound/sound.tscn")
			s.cam.zoom = 22.0
			await _frames(200)
			await _save()
		"officer_poses":
			# One officer, several moves: saves out-<n>.png per pose.
			var s := await _scene("res://prototypes/p06_movement/movement.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			s.cam.zoom = 4.5
			await _frames(5)
			var o: Officer = s.sync.my_pawn()
			# Lambdas capture locals by value, so the command lives in a shared dict.
			var box := {"cmd": {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}}
			s.sync.input_source = func(): return box.cmd
			var poses := [
				["idle", Vector2.ZERO, 0, 40],
				["run", Vector2(0, 1), 0, 35],
				["aim_run", Vector2(1, 0), PlayerInput.AIM, 35],
				["crouch", Vector2.ZERO, PlayerInput.CROUCH, 40],
				["prone", Vector2.ZERO, PlayerInput.PRONE, 50],
			]
			var base := out.get_basename()
			for ps in poses:
				o.global_position = Vector3(-2, 0.05, -1)
				o._set_state(Officer.S.MOVE)
				o.velocity = Vector3.ZERO
				box.cmd = {"move": ps[1], "buttons": ps[2], "aim_yaw": 0.0}
				await _frames(2)
				box.cmd = {"move": ps[1], "buttons": ps[2] & ~(PlayerInput.CROUCH | PlayerInput.PRONE), "aim_yaw": 0.0}
				await _frames(ps[3])
				var pos := o.global_position
				o.global_position = Vector3(-2, 0.05, -1)  # keep in frame
				s.cam.global_position = o.global_position
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s-%s.png" % [base, ps[0]])
				print("saved ", ps[0], " pos ", o.global_position, " state ", Officer.S.keys()[o.state])
			# Mid-vault over the first wall.
			o.global_position = Vector3(-6, 0.05, 3.3)
			o.rotation.y = 0.0
			o.state = Officer.S.MOVE
			box.cmd = {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}
			for i in 10: await get_tree().physics_frame
			box.cmd = {"move": Vector2(0, 1), "buttons": PlayerInput.JUMP, "aim_yaw": 0.0}
			for i in 2: await get_tree().physics_frame
			box.cmd = {"move": Vector2(0, 1), "buttons": 0, "aim_yaw": 0.0}
			for i in 40: await get_tree().physics_frame
			s.cam.global_position = o.global_position
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s-vault.png" % base)
			print("saved vault")
		"tp_street", "tp_inside", "tp_aim":
			# Third-person test view (Tab): street, a room, aiming down the sight line.
			var s := await _scene("res://prototypes/p08_block/block.tscn")
			await _frames(10)
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			var o: Officer = s.sync.my_pawn()
			IsoCamera.third_person = true
			if shot == "tp_inside":
				var b: Dictionary = s.gen.buildings.filter(func(x): return x.enterable and x.storeys >= 2)[0]
				o.global_position = b.origin + b.u * ((b.w - 0.5) * 4.0) + b.v * ((b.d - 1.5) * 4.0) + Vector3(0, 0.05, 0)
			if shot == "tp_aim":
				s.sync.input_source = func(): return {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": o.rotation.y, "aim_point": PlayerInput.sample(s.cam, o).aim_point}
			await _frames(60)
			await _save()
			IsoCamera.third_person = false
		"tp_far", "tp_far_gore":
			# Third person down the street: buildings in the middle distance
			# and another officer some way off (the v0.2.10-tp1 "black" bug).
			Block.next_seed = 4242
			var s := await _scene("res://prototypes/p08_block/block.tscn")
			await _frames(10)
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			(s.dispatch as Dispatcher).enabled = false
			var o: Officer = s.sync.my_pawn()
			o.global_position = Vector3(-2, 0.2, -3)
			var mate := Officer.new()
			mate.peer_id = 99
			s.add_child(mate)
			mate.global_position = Vector3(12, 0.2, 8)
			s.cam._yaw = 220.0
			s.cam._yaw_target = 220.0
			s.cam.tp_pitch = -6.0
			if shot == "tp_far_gore":
				var sp := Suspect.new()
				s.add_child(sp)
				sp.global_position = Vector3(1.5, 0.2, 3.0)
				await _frames(20)
				var wall_side := Vector3(1.5, 1.3, 3.0)
				for k in 3:
					Gore.hit(s, wall_side + Vector3(-3, 0.1 * k, -4), wall_side + Vector3(0, 0.1 * k, 0))
				Gore.hit(s, Vector3(1.5, 1.7, -2), Vector3(1.5, 1.68, 2.9))
				sp.take_damage(500.0, Vector3(0.3, 0, 1).normalized())
				await _frames(200)
			await _frames(60)
			await _save()
		"gore_close":
			# 2026-11-23: wounds sit on the body (no dark ball off the head,
			# no stain on the road by a shot suspect).
			Block.next_seed = 4242
			var s := await _scene("res://prototypes/p08_block/block.tscn")
			await _frames(10)
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			(s.dispatch as Dispatcher).enabled = false
			s.sync.my_pawn().global_position = Vector3(-20, 0.2, -20)
			var sp := Suspect.new()
			s.add_child(sp)
			sp.global_position = Vector3(1.5, 0.2, 3.0)
			sp.rotation.y = PI
			await _frames(20)
			# Shot from the front: chest, belly, head (on the capsule's skin).
			for y in [1.25, 1.0, 1.62]:
				Gore.hit(s, Vector3(1.5, y, -3.0), Vector3(1.5, y, 2.72))
			var cam := Camera3D.new()
			s.add_child(cam)
			cam.global_position = Vector3(2.3, 1.55, 1.4)
			cam.look_at(Vector3(1.5, 1.3, 3.0))
			cam.fov = 40.0
			cam.current = true
			await _frames(40)
			await _save()
		"block_overview", "block_street", "block_inside":
			var s := await _scene("res://prototypes/p08_block/block.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			await _frames(20)
			var o: Officer = s.sync.my_pawn()
			match shot:
				"block_overview":
					s.cam.target = null
					s.cam.zoom = 48.0
					s.cam.global_position = Vector3(24, 0, 24)
				"block_street":
					s.cam.zoom = 22.0
				"block_inside":
					var b: Dictionary = s.gen.buildings.filter(func(x): return x.enterable and x.storeys >= 2)[0]
					o.global_position = b.origin + b.u * ((b.w - 0.5) * 4.0) + b.v * ((b.d - 1.5) * 4.0) + Vector3(0, 0.05, 0)
					s.cam.zoom = 12.0
			await _frames(90)
			await _save()
		"mayhem_inside", "mayhem_fire", "mayhem_car":
			# Phase 1.5: furniture indoors, a fire spreading, a car burning.
			var s := await _scene("res://prototypes/p08_block/block.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			await _frames(20)
			var o: Officer = s.sync.my_pawn()
			var b: Dictionary = s.gen.buildings.filter(func(x): return x.enterable)[0]
			var mid: Vector3 = b.origin + b.u * (b.w * 2.0) + b.v * (b.d * 2.0)
			match shot:
				"mayhem_inside":
					o.global_position = b.origin + b.u * 2.0 + b.v * 2.0 + Vector3(0, 0.05, 0)
					s.cam.zoom = 14.0
				"mayhem_fire":
					o.global_position = b.origin + b.u * 2.0 + b.v * 1.5 + Vector3(0, 0.05, 0)
					s.cam.zoom = 14.0
					await _frames(30)
					var near: Array = s.props.intact().filter(func(p): return PropWorld.KINDS[p.kind].get("flammable", false))
					near.sort_custom(func(x, y): return (x.body as Node3D).global_position.distance_to(o.global_position) < (y.body as Node3D).global_position.distance_to(o.global_position))
					print("igniting ", near[0].kind, " id ", s.fire.ignite((near[0].body as Node3D).global_position, 0.6, 30.0, near[0].id))
					s.fire.ignite(o.global_position + Vector3(2.5, 0, 0), 1.0, 30.0)
					await _frames(25)
					print("fires ", s.fire.fires.size(), " visuals ", s.fire._visuals.size())
				"mayhem_car":
					var c: Car = s.cars.cars[0]
					o.global_position = c.global_position + Vector3(-6, 0, 4)
					s.cam.target = null
					s.cam.global_position = c.global_position
					s.cam.zoom = 14.0
					s.cars.damage_car(c, 30.0 + 50.0)
					await _frames(60)
					s.cars.damage_car(c, 100.0)
					await _frames(40)
			await _frames(30)
			await _save()
		"prone_side":
			# Side-on views of prone idle, prone aiming and crawling.
			var s := await _scene("res://prototypes/p06_movement/movement.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			await _frames(5)
			var o: Officer = s.sync.my_pawn()
			var box := {"cmd": {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}}
			s.sync.input_source = func(): return box.cmd
			var cam := Camera3D.new()
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = 2.6
			s.add_child(cam)
			o.global_position = Vector3(-14, 0.05, -10)
			o.rotation.y = 0.0
			box.cmd = {"move": Vector2.ZERO, "buttons": PlayerInput.PRONE, "aim_yaw": 0.0}
			await _frames(2)
			var base := out.get_basename()
			for ps in [["idle", Vector2.ZERO, 0], ["aim", Vector2.ZERO, PlayerInput.AIM], ["crawl", Vector2(0, 1), 0]]:
				box.cmd = {"move": ps[1], "buttons": ps[2], "aim_yaw": 0.0, "aim_point": o.global_position + Vector3(0, 0.3, 8)}
				await _frames(70)
				cam.global_position = o.global_position + Vector3(6, 0.25, 0)
				cam.look_at(o.global_position + Vector3(0, 0.25, 0), Vector3.UP)
				cam.current = true
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s-%s.png" % [base, ps[0]])
				print("saved ", ps[0], " pos ", o.global_position, " state ", Officer.S.keys()[o.state])
		"menu":
			await _scene("res://game/ui/main_menu.tscn")
			await _frames(10)
			await _save()
		"settings":
			var s := await _scene("res://game/ui/main_menu.tscn")
			await _frames(3)
			s.call("_open_settings")
			await _frames(10)
			await _save()
		"cover_back":
			# Back-to-wall cover at a tall wall and a low wall, and a reload.
			var s := await _scene("res://prototypes/p06_movement/movement.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			await _frames(5)
			var o: Officer = s.sync.my_pawn()
			var box := {"cmd": {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}}
			s.sync.input_source = func(): return box.cmd
			var base := out.get_basename()
			var spot := Vector3(-30, 0.05, 25)
			ProtoWorld.block(s, Vector3(3, 2.2, 0.3), spot + Vector3(0, 1.1, 1.0), Color("8a8f96"))
			ProtoWorld.block(s, Vector3(3, 1.0, 0.3), spot + Vector3(6, 0.5, 1.0), Color("8a8f96"))
			var cam := Camera3D.new()
			cam.fov = 40.0
			s.add_child(cam)
			for ps in [["tall", Vector3.ZERO, 0], ["low", Vector3(6, 0, 0), 0], ["reload", Vector3.ZERO, PlayerInput.RELOAD]]:
				o.global_position = spot + ps[1]
				o.state = Officer.S.MOVE
				o.ammo = 5
				box.cmd = {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}
				await _frames(10)
				box.cmd = {"move": Vector2.ZERO, "buttons": PlayerInput.COVER, "aim_yaw": 0.0}
				await _frames(2)
				box.cmd = {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}
				await _frames(40)
				if ps[2]:
					box.cmd = {"move": Vector2.ZERO, "buttons": ps[2], "aim_yaw": 0.0}
					await _frames(2)
					box.cmd = {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}
					while o.reload_t > 0.95:   # the fresh magazine on its way up
						await _frames(1)
				cam.global_position = o.global_position + Vector3(3.4, 0.9, -0.3)
				cam.look_at(o.global_position + Vector3(0, 0.8, 0.2), Vector3.UP)
				cam.current = true
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s-%s.png" % [base, ps[0]])
				print("saved ", ps[0], " state ", Officer.S.keys()[o.state], " low ", o._cover_low, " rot ", o.rotation.y, " n ", o._cover_n, " pos ", o.global_position, " lower ", o.rig._lower, " upper ", o.rig._upper, " rl ", o.reload_t, " ammo ", o.ammo)
		"patrol":
			# The police car: parked, then driven with the lights on, then beaten up.
			var s := await _scene("res://prototypes/p10_patrol/patrol.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			await _frames(20)
			var o: Officer = s.sync.my_pawn()
			var pc: PoliceCar = s.cars.cars[0]
			var box := {"cmd": {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}}
			s.sync.input_source = func(): return box.cmd
			var base := out.get_basename()
			s.cam.zoom = 9.0
			o.global_position = pc.door_point(1) * Vector3(1, 0, 1) + Vector3(0, 0.05, 0)
			await _frames(40)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s-parked.png" % base)
			box.cmd = {"move": Vector2.ZERO, "buttons": PlayerInput.INTERACT, "aim_yaw": 0.0}
			await _frames(3)
			box.cmd = {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}
			pc.lights = true
			pc.siren = 1
			await _frames(4)
			# Lean out and aim to the right.
			box.cmd = {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": PI * 0.5, "aim_point": pc.global_position + Vector3(8, 1, 0)}
			await _frames(40)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s-leanout.png" % base)
			print("seat ", o.seat, " state ", Officer.S.keys()[o.state])
			box.cmd = {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}
			for d in [[Vector3(-0.95, 0.1, 0.4), Vector3.RIGHT, 0.3], [Vector3(-0.95, 0.0, 0.3), Vector3.RIGHT, 0.3],
					[Vector3(0, 0.0, 2.1), Vector3.BACK * -1, 0.3], [Vector3(0.9, 0.2, -1.2), Vector3.LEFT, 0.25]]:
				pc.apply_dent(d[0], d[1], d[2])
			pc.shatter("win_front")
			pc.shatter("win_fl")
			await _frames(40)
			s.cam.zoom = 11.0
			await _frames(20)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s-wrecked.png" % base)
			print("saved patrol")
		"dispatch":
			# Phase 1.4: a robbery call, a suspect giving up, one cuffed, and
			# the custody bay.
			var s := await _scene("res://prototypes/p08_block/block.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			var o: Officer = null
			for i in 400:
				await get_tree().physics_frame
				o = s.sync.my_pawn()
				if o and s.nav.ready_to_use and not s.dispatch.hide_spots.is_empty():
					break
			var box := {"cmd": {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}}
			s.sync.input_source = func(): return box.cmd
			var base := out.get_basename()
			var id: int = s.dispatch.start_call(Dispatcher.Kind.ROBBERY)
			var call: Dictionary = s.dispatch.calls[id]
			var a: Suspect = s.dispatch.suspects[call.suspects[0]]
			var b: Suspect = s.dispatch.suspects[call.suspects[1]]
			s.cam.zoom = 20.0
			await _frames(60)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s-call.png" % base)
			# Close up: one on their knees, one cuffed behind the officer.
			var spot: Vector3 = s.nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, -1.5))
			o.global_position = spot
			o.rotation.y = 0.0
			a.global_position = spot + Vector3(1.6, 0, 1.4)
			a.rotation.y = PI
			a.set_state(Suspect.S.SURRENDER)
			b.global_position = spot + Vector3(-0.3, 0, -1.2)
			b.cuff(o)
			s.cam.zoom = 7.0
			s.cam.global_position = spot
			await _frames(90)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s-arrest.png" % base)
			# Prisoner in the back of a police car at the custody bay.
			var pc: PoliceCar = s.cars.cars[0]
			var bay: Vector3 = s.dispatch.bay_position()
			pc.global_position = Vector3(bay.x, 1.0, bay.z + 6.0)
			pc.rotation.y = PI
			b.put_in_car(pc, 2)
			o.global_position = bay + Vector3(-3.0, 0.2, 3.0)
			s.cam.zoom = 14.0
			await _frames(60)
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s-bay.png" % base)
			print("saved dispatch ", Suspect.S.keys()[a.state], " ", Suspect.S.keys()[b.state])
		"yard":
			var s := await _scene("res://prototypes/p09_yard/yard.tscn")
			s.find_children("*", "NetOverlay", false, false)[0].queue_free()
			await _frames(20)
			s.cam.target = null
			s.cam.zoom = 30.0
			s.cam.global_position = Vector3(0, 0, 2)
			await _frames(90)
			await _save()
		_:
			var s := await _scene(shot)
			await _frames(90)
			await _save()
