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


func _run() -> void:
	match shot:
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
