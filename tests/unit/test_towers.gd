extends Node
## v0.10.0: downtown towers up to ten storeys, with a lift shaft beside the stairs.
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_downtown_has_towers_with_a_shaft() -> void:
	var g := CityGenerator.generate_city(4242)
	var towers: Array = g.buildings.filter(func(b): return b.get("lift", false))
	var tallest := 0
	for b in towers:
		tallest = maxi(tallest, b.storeys)
	print("    %d towers, tallest %d storeys" % [towers.size(), tallest])
	t.check(towers.size() >= 3, "a few towers downtown (%d)" % towers.size())
	t.check(tallest >= 9, "the tallest is nine or ten storeys (%d)" % tallest)
	var bad := 0
	for b in towers:
		t.check(b.storeys >= CityStyles.TOWER_STOREYS.x and b.storeys <= CityStyles.TOWER_STOREYS.y and b.type == "tower", "tower size and type")
		if bad > 0:
			break
		# No floor slab in the shaft below the roof; a doorway on every storey.
		var sr := CityStyles.shaft_rect(b)
		var centre: Vector3 = b.origin + b.u * sr.get_center().x + b.v * sr.get_center().y
		var slabs := 0
		var doors := 0
		for p in g.pieces:
			var o: Vector3 = p.xform.origin
			if p.kind == "slab" and Vector2(o.x - centre.x, o.z - centre.z).length() < 0.5:
				slabs += 1
			if p.kind == "int_wall_door" and Vector2(o.x - centre.x, o.z - centre.z).length() < 2.2 and Vector2(o.x - centre.x, o.z - centre.z).length() > 1.8:
				doors += 1
		if slabs != 0 or doors < b.storeys:
			bad += 1
			print("    shaft: %d slabs, %d doorways for %d storeys" % [slabs, doors, b.storeys])
	t.check(bad == 0, "every shaft is open top to bottom with a doorway per floor")


func test_lift_carries_an_officer_up() -> void:
	BlockState.save_path = City.SAVE_PATH
	BlockState.delete_save()
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	await _frames(30)
	var lifts := s.lifts
	t.check(lifts != null and lifts.lifts.size() >= 3, "a lift in every tower (%d)" % (lifts.lifts.size() if lifts else 0))
	if lifts == null or lifts.lifts.is_empty():
		s.queue_free()
		return
	var stable := s.world.compute_stable()
	var intact := s.world.pieces.values().filter(func(p): return p.state == "intact").size()
	if stable.size() != intact:
		var kinds := {}
		for p in s.world.pieces.values():
			if p.state == "intact" and not stable.has(p.id):
				kinds[p.kind] = kinds.get(p.kind, 0) + 1
				if kinds[p.kind] < 4:
					print("    %s at %s below %s %s" % [p.kind, p.aabb, p.below, p.below.map(func(i): return [s.world.pieces[i].kind, s.world.pieces[i].aabb, s.world.pieces[i].group])])
		print("    unstable: %s" % kinds)
	t.check(stable.size() == intact, "the whole city stands up, towers and roof huts too (%d of %d)" % [stable.size(), intact])
	var huts: Array = s.gen.buildings.filter(func(b): return b.has("roof_door"))
	t.check(huts.size() > 20, "stairs up to a roof hut on most buildings (%d)" % huts.size())
	var L: Dictionary = lifts.lifts[0]
	var o: Officer = s.sync.my_pawn()
	# Call it from the ground floor door: the doors open.
	var cp := Lifts.call_point(L, 0) + Vector3(0, 0.1, 0)
	t.check(lifts.door_near(cp) == [0, 0], "standing at the ground floor door (%s)" % [lifts.door_near(cp)])
	t.check(lifts.prompt_for(cp) != "", "the HUD offers the lift: %s" % lifts.prompt_for(cp))
	lifts.ask(0, 0)
	await _frames(60)
	t.check(float(L.open) > 0.9, "the doors open when it's called to where it is")
	# Step in and ride to the fourth floor.
	o.global_position = (L.origin as Vector3) + Vector3(0, 0.3, 0)
	o.velocity = Vector3.ZERO
	await _frames(10)
	t.check(lifts.lift_inside(o.global_position) == 0, "the officer is in the car")
	lifts.ask(0, 4)
	var top := Lifts.floor_height(4) + (L.origin as Vector3).y
	for i in 400:
		await get_tree().physics_frame
		if Lifts.floor_of(L) == 4 and not Lifts.moving(L) and float(L.open) > 0.9:
			break
	print("    car at %.2f, officer at %.2f (floor 4 at %.2f)" % [(L.car as Node3D).global_position.y, o.global_position.y, top])
	t.check(Lifts.floor_of(L) == 4 and not Lifts.moving(L), "the car stops at the fourth floor")
	t.check(absf(o.global_position.y - top) < 0.5, "and the officer rode up with it")
	var d4: Node3D = L.doors[4]
	var d0: Node3D = L.doors[0]
	t.check(d4.global_position.distance_to(Lifts._door_base(L, 4)) > 0.8, "the fourth floor doors are open")
	t.check(d0.global_position.distance_to(Lifts._door_base(L, 0)) < 0.05, "the ground floor doors are shut over the empty shaft")
	s.queue_free()
	await _frames(2)


func test_grapple_up_abseil_down_and_crash_in() -> void:
	BlockState.save_path = City.SAVE_PATH
	BlockState.delete_save()
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	await _frames(30)
	Armoury.owned |= 1 << Armoury.GRAPPLE
	var b: Dictionary = s.gen.buildings.filter(func(x): return x.get("lift", false))[0]
	var W: float = int(b.w) * BlockGenerator.M
	var top := Rooftops.roof_y(b)
	var o: Officer = s.sync.my_pawn()
	var cmd := {"move": Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0, "aim_point": Vector3.ZERO}
	s.sync.input_source = func(): return cmd
	o.global_position = Rooftops.to_world(b, W * 0.5, 0.05, -7.0)
	o.velocity = Vector3.ZERO
	await _frames(10)
	# Aim at the wall and fire the grapple.
	var wall := Rooftops.to_world(b, W * 0.5, 8.0, 0.0)
	cmd.aim_point = wall
	cmd.aim_yaw = atan2(wall.x - o.global_position.x, wall.z - o.global_position.z)
	t.check(not o.grapple_plan(wall).is_empty(), "the grapple can reach that roof")
	cmd.buttons = PlayerInput.AIM | PlayerInput.INTERACT
	await _frames(1)
	cmd.buttons = PlayerInput.AIM
	await _frames(2)
	t.check(o.state == Officer.S.GRAPPLE, "the grapple fires (state %d)" % o.state)
	t.check(o.rope_line().size() == 2, "a line out to the hook")
	cmd.buttons = 0
	for i in 400:
		await get_tree().physics_frame
		if o.state != Officer.S.GRAPPLE:
			break
	await _frames(20)
	print("    after the grapple: y %.2f (roof %.2f), state %d" % [o.global_position.y, top, o.state])
	t.check(absf(o.global_position.y - top) < 0.4 and Rooftops.inside_footprint(b, o.global_position), "hauled up onto the roof")
	# At the front edge facing out: abseil.
	var v: Vector3 = b.v
	o.global_position = Rooftops.to_world(b, W * 0.5 - 1.5, top - (b.origin as Vector3).y + 0.05, 1.0)
	o.rotation.y = atan2(-v.x, -v.z)
	await _frames(10)
	t.check(not o.abseil_plan().is_empty(), "at the roof edge, the rope can go over")
	cmd.buttons = PlayerInput.INTERACT
	await _frames(1)
	cmd.buttons = 0
	await _frames(60)
	t.check(o.state == Officer.S.ROPE, "on the rope (state %d)" % o.state)
	t.check(o.global_position.y < top - 1.0, "over the edge and hanging")
	# Slide down a couple of floors, then swing in through a window.
	cmd.move = Vector2(-v.x, -v.z)
	await _frames(75)
	cmd.move = Vector2.ZERO
	var y_rope := o.global_position.y
	t.check(y_rope < top - 4.0, "slid down the rope (%.1f m below the roof)" % (top - y_rope))
	var glass_before := s.world.pieces.values().filter(func(p): return String(p.kind).begins_with("glass") and p.state == "intact").size()
	var tries := 0
	while tries < 6 and o.state == Officer.S.ROPE:
		cmd.buttons = PlayerInput.JUMP
		await _frames(1)
		cmd.buttons = 0
		await _frames(2)
		if o.state == Officer.S.ROPE:
			cmd.move = Vector2(-v.x, -v.z)    # a blank wall here: a bit lower
			await _frames(25)
			cmd.move = Vector2.ZERO
		tries += 1
	t.check(o.state == Officer.S.SWING, "kicked off and swinging in (state %d)" % o.state)
	await _frames(80)
	var glass_after := s.world.pieces.values().filter(func(p): return String(p.kind).begins_with("glass") and p.state == "intact").size()
	print("    inside at y %.2f, glass %d -> %d" % [o.global_position.y, glass_before, glass_after])
	t.check(Rooftops.inside_footprint(b, o.global_position, -0.3) and o.state in [Officer.S.CROUCH, Officer.S.MOVE], "crashed in through the window, inside the tower")
	t.check(glass_after < glass_before, "and the window went")
	s.queue_free()
	await _frames(2)
