extends Node
## Grenades: officers throw smoke, CS gas and flashbangs; enemies throw frags.
var t
var cars: CarSync
var dispatch: Dispatcher
var nav: BlockNav
var gen: BlockGenerator
var world: DestructionWorld


func _block() -> void:
	ProtoWorld.ground(self, 400.0)
	world = DestructionWorld.new()
	add_child(world)
	gen = CityBlock.build(world, 4242)
	cars = CarSync.new()
	cars.use_seats = true
	cars.destruction = world
	add_child(cars)
	nav = BlockNav.new()
	add_child(nav)
	await get_tree().physics_frame
	nav.bake_from(self)
	dispatch = Dispatcher.new()
	dispatch.enabled = false
	add_child(dispatch)
	dispatch.setup(gen, world, cars, nav, null)
	for i in 120:
		await get_tree().physics_frame
		if nav.ready_to_use and not dispatch.hide_spots.is_empty():
			break


func _flat() -> void:
	ProtoWorld.ground(self, 200.0)
	await get_tree().physics_frame


func _officer(pos: Vector3, id := 1) -> Officer:
	var o := Officer.new()
	o.peer_id = id
	o.holstered = false
	o.position = pos
	add_child(o)
	return o


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _cmd(buttons := 0, aim := Vector3.ZERO) -> Dictionary:
	return {"move": Vector2.ZERO, "buttons": buttons, "aim_yaw": 0.0, "aim_point": aim}


func _own_all() -> void:
	for i in Armoury.NADE_ITEMS:
		Armoury.owned |= 1 << i


func _street() -> Vector3:
	return nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))


func test_pouch_bits() -> void:
	var p := Grenades.with_count(0, Grenades.Kind.GAS, 2)
	p = Grenades.with_count(p, Grenades.Kind.FLASH, 1)
	t.check(Grenades.count(p, Grenades.Kind.SMOKE) == 0 and Grenades.count(p, Grenades.Kind.GAS) == 2 and Grenades.count(p, Grenades.Kind.FLASH) == 1, "two bits a kind")
	t.check(Grenades.pick(p, Grenades.Kind.SMOKE) == Grenades.Kind.GAS, "none of the picked kind: the next one there is")
	t.check(Grenades.pick(0, 0) == -1, "nothing at all")
	Armoury.owned = 1
	t.check(Grenades.full_pouch() == 0, "nothing bought, nothing carried")
	_own_all()
	t.check(Grenades.count(Grenades.full_pouch(), Grenades.Kind.FLASH) == Grenades.CARRY, "bought: two of each")
	Armoury.owned = 1


func test_officer_throws_smoke_and_it_blocks_sight() -> void:
	await _flat()
	_own_all()
	var o := _officer(Vector3(0, 0.05, 0))
	await _frames(2)
	t.check(Grenades.count(o.nades, Grenades.Kind.SMOKE) == 2, "an officer carries two smoke")
	var aim := Vector3(0, 0, 9)
	var b := PlayerInput.THROW | (Grenades.Kind.SMOKE << PlayerInput.NADE_SHIFT)
	o.sim_step(_cmd(b, aim), 1.0 / 60.0)
	t.check(o.throw_t > 0.0 and Grenades.count(o.nades, Grenades.Kind.SMOKE) == 1, "pressing throw starts the throw and uses one")
	for i in 40:
		o.sim_step(_cmd(0, aim), 1.0 / 60.0)
		await get_tree().physics_frame
	var g := Grenades.current
	t.check(g != null and g.live.size() == 1, "a grenade is in the air")
	await _frames(int(60 * (Grenades.FUSE[0] + 4.5)))
	t.check(g.clouds.size() == 1, "it pops into a cloud")
	if g.clouds.size() == 1:
		var c: Dictionary = g.clouds[0]
		var pos: Vector3 = c.pos
		t.check(Vector2(pos.x, pos.z).distance_to(Vector2(0, 9)) < 4.0, "near where they aimed: %s" % pos)
		var a := pos + Vector3(-8, 1.5, 0)
		var z := pos + Vector3(8, 1.4, 0)
		t.check(Grenades.blocks_sight(a, z), "can't see through it")
		t.check(not Grenades.blocks_sight(a + Vector3(0, 0, 20), z + Vector3(0, 0, 20)), "but can round it")
	Armoury.owned = 1


func test_flashbang_stuns_a_suspect() -> void:
	await _block()
	var p := _street()
	var s := dispatch.spawn_suspect(p, Suspect.S.LOITER, true)
	s.fighter = true
	await _frames(3)
	var o := _officer(nav.closest(p + Vector3(-14, 0, 0)))
	o.hp = 1.0e6
	# Thrown right at their feet.
	var fwd := Vector3(sin(s.rotation.y), 0, cos(s.rotation.y))
	Grenades.throw(o, Grenades.Kind.FLASH, p + fwd * 2.0 + Vector3(0, 0.5, 0), Vector3.ZERO)
	var stunned := false
	for i in int(60 * (Grenades.FUSE[2] + 0.5)):
		await get_tree().physics_frame
		if s.state in [Suspect.S.STAGGER, Suspect.S.SURRENDER]:
			stunned = true
	t.check(stunned and s._stun_t > -0.5, "stunned by the flash: %s" % Suspect.S.keys()[s.state])
	t.check(s.weapon == EnemyGuns.NONE or s.state == Suspect.S.STAGGER, "not shooting: %s stun %.1f" % [Suspect.S.keys()[s.state], s._stun_t])


func test_gas_makes_a_suspect_give_up() -> void:
	await _block()
	var p := _street()
	var s := dispatch.spawn_suspect(p, Suspect.S.LOITER, false)
	await _frames(3)
	var o := _officer(nav.closest(p + Vector3(-40, 0, 0)))
	o.hp = 1.0e6
	Grenades.throw(o, Grenades.Kind.GAS, p + Vector3(0, 0.4, 0), Vector3.ZERO)
	var gave_up := false
	var coughs := false
	for i in 60 * 10:
		await get_tree().physics_frame
		if s.state == Suspect.S.SURRENDER:
			gave_up = true
			break
	t.check(gave_up, "a crook in the gas gives up: %s, gas %.2f" % [Suspect.S.keys()[s.state], s._gas])


func test_frag_hurts_officers_nearby() -> void:
	await _flat()
	var near_o := _officer(Vector3(0, 0.05, 0))
	var far_o := _officer(Vector3(30, 0.05, 0), 2)
	await _frames(2)
	var thrower := Node3D.new()
	add_child(thrower)
	Grenades.throw(thrower, Grenades.Kind.FRAG, Vector3(1.2, 0.3, 0), Vector3.ZERO)
	await _frames(int(60 * (Grenades.FUSE[3] + 0.5)))
	t.check(near_o.hp < Officer.MAX_HP - 30.0, "the one next to it is badly hurt: %.0f" % near_o.hp)
	t.check(far_o.hp == Officer.MAX_HP, "the one across the street is fine")
	t.check(Grenades.current.live.is_empty(), "it's gone")


func test_fighter_lobs_a_frag_at_dug_in_officers() -> void:
	await _block()
	var p := _street()
	var s := dispatch.spawn_suspect(p, Suspect.S.LOITER, true)
	s.fighter = true
	s.frags = 1
	var o := _officer(nav.closest(p + Vector3(-12, 0, 0)))
	o.hp = 1.0e6
	await _frames(3)
	var threw := false
	for i in 40:
		s._frag_cd = 0.0
		var tt := s._threat()
		tt.los = false   # dug in: out of sight
		if s._try_frag(tt):
			break
	t.check(s.state == Suspect.S.THROW and s._nade, "winds up a frag")
	for i in 120:
		await get_tree().physics_frame
		if Grenades.current and not Grenades.current.live.is_empty():
			threw = true
			break
	t.check(threw and s.frags == 0, "and throws it")
	if threw:
		var rb: RigidBody3D = Grenades.current.live.values()[0]
		t.check(rb.get_meta("kind") == Grenades.Kind.FRAG, "a frag")
		t.check(rb.linear_velocity.dot(o.global_position - s.global_position) > 0.0, "toward the police")
