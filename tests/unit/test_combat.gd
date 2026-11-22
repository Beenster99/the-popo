extends Node
## Phase 1.5: enemies fight from cover (peek, blind fire, reload), keep their
## heads down when bullets pass close, flank, call backup, throw what is to
## hand, and drop their guns, which officers can pick up and use.
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


func _officer(pos: Vector3, id := 1) -> Officer:
	var o := Officer.new()
	o.peer_id = id
	o.holstered = false
	o.position = pos
	add_child(o)
	return o


func _run(o: Officer, cmd: Dictionary, frames: int) -> void:
	for i in frames:
		o.sim_step(cmd, 1.0 / 60.0)
		await get_tree().physics_frame


func _cmd(buttons := 0, move := Vector2.ZERO, aim := Vector3.ZERO) -> Dictionary:
	return {"move": move, "buttons": buttons, "aim_yaw": 0.0, "aim_point": aim}


func _st(s: Suspect) -> String:
	return Suspect.S.keys()[s.state]


func _street() -> Vector3:
	return nav.closest(Vector3(24, BlockGenerator.BASE_Y + 0.05, 1.5))


func test_fighter_takes_cover_and_shoots_from_it() -> void:
	await _block()
	var p := _street()
	var s := dispatch.spawn_suspect(p, Suspect.S.LOITER, true)
	s.fighter = true
	s._rng.seed = 3
	var o := _officer(nav.closest(p + Vector3(-11, 0, 0)))
	o.hp = 1.0e6   # stays up for the whole fight
	var seen_cover := false
	var shots := 0
	var last_mag := s.mag
	var phases := {}
	for i in 1500:
		await get_tree().physics_frame
		if s.state == Suspect.S.COVER:
			seen_cover = true
			phases[s.cphase] = true
		if s.mag < last_mag:
			shots += last_mag - s.mag
		last_mag = s.mag
		if seen_cover and shots >= 3 and phases.size() >= 2:
			break
	t.check(seen_cover, "the armed one gets into cover: %s, spot %s" % [_st(s), s.cover_spot])
	if s.cover_spot != Vector3.INF:
		var space := s.get_world_3d().direct_space_state
		var low := s.cover_spot + Vector3(0, 0.85, 0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(low, o.global_position + Vector3(0, 1.4, 0), Suspect.COVER_MASK, [s.get_rid()]))
		t.check(not hit.is_empty(), "crouched there, something solid is between them and the officer")
	t.check(shots >= 3, "and shoots from it: %d shots" % shots)
	t.check(phases.size() >= 2, "ducking and peeking in turn: %s" % [phases.keys().map(func(k): return Suspect.C.keys()[k])])


func test_close_bullets_keep_their_heads_down() -> void:
	await _block()
	var p := _street()
	var s := dispatch.spawn_suspect(p, Suspect.S.LOITER, true)
	s.fighter = true
	s.set_state(Suspect.S.COVER)
	s.cover_spot = s.global_position
	s.cphase = Suspect.C.PEEK
	s._ct = 2.0
	await get_tree().physics_frame
	var c := s.global_position + Vector3(0, 1.0, 0)
	Gunfire.whizz(get_tree(), c + Vector3(-15, 0.4, 0.5), c + Vector3(15, 0.4, 0.5), null)
	t.check(s._suppressed_t > 0.0, "a bullet past their head pins them")
	var mag0 := s.mag
	for i in 40:
		await get_tree().physics_frame
	t.check(s.cphase == Suspect.C.HIDE or s.state != Suspect.S.COVER, "they duck back down: %s" % Suspect.C.keys()[s.cphase])
	t.check(s.mag == mag0, "and don't shoot while pinned")


func test_shots_fired_call_flanks_and_brings_backup() -> void:
	await _block()
	var o := _officer(_street())
	var id := dispatch.start_call(Dispatcher.Kind.GANG)
	t.check(id >= 0, "a 'shots fired' call opens")
	var c: Dictionary = dispatch.calls[id]
	var gang: Array = c.suspects.map(func(n): return dispatch.suspects[n])
	t.check(gang.size() >= 3 and gang.all(func(g): return g.fighter), "three or four fighters: %d" % gang.size())
	t.check(gang.filter(func(g): return g.armed).size() >= 3, "at least three armed")
	t.check(gang.any(func(g): return g.weapon == EnemyGuns.SHOTGUN), "one with a shotgun")
	t.check(gang.any(func(g): return g.role == Suspect.ROLE_FLANK) and gang.any(func(g): return g.role == Suspect.ROLE_PIN), "some pin you down, some go round")
	var before: int = c.suspects.size()
	dispatch.call_backup(gang[0])
	dispatch.call_backup(gang[1])   # only once per call
	for i in int((Dispatcher.BACKUP_DELAY + 1.0) * 60.0):
		await get_tree().physics_frame
	t.check(c.suspects.size() == before + 2, "two more turn up later: %d -> %d" % [before, c.suspects.size()])
	if c.suspects.size() == before + 2:
		var b: Suspect = dispatch.suspects[c.suspects[-1]]
		t.check(b.global_position.distance_to(o.global_position) > 12.0, "from somewhere out of the way: %.1f m" % b.global_position.distance_to(o.global_position))


func test_flanker_goes_round_the_side() -> void:
	await _block()
	var p := _street()
	var o := _officer(nav.closest(p + Vector3(-10, 0, 0)))
	var s := dispatch.spawn_suspect(p, Suspect.S.LOITER, true)
	s.fighter = true
	s.role = Suspect.ROLE_FLANK
	s._rng.seed = 3
	var spot := Vector3.INF
	s._last_seen = o.global_position
	for k in 3:   # each look round samples a little differently
		var c: Dictionary = s._find_cover(o.global_position, "flank")
		if not c.is_empty():
			spot = c.p
			break
	t.check(spot != Vector3.INF, "finds a flanking spot")
	if spot != Vector3.INF:
		var a := Vector2(p.x - o.global_position.x, p.z - o.global_position.z)
		var b := Vector2(spot.x - o.global_position.x, spot.z - o.global_position.z)
		t.check(rad_to_deg(absf(a.angle_to(b))) > 35.0, "off to the side of the officer: %.0f deg round" % rad_to_deg(absf(a.angle_to(b))))


func test_unarmed_fighter_throws_things() -> void:
	await _block()
	var p := _street()
	var s := dispatch.spawn_suspect(p, Suspect.S.LOITER, false)
	s.fighter = true
	var box := ProtoWorld.rigid_box(self, Vector3(0.4, 0.4, 0.4), p + Vector3(1.2, 0.3, 0), Color.BROWN, 4.0)
	box.add_to_group("throwable")
	var o := _officer(nav.closest(p + Vector3(-8, 0, 0)))
	var held := false
	var flew := false
	for i in 600:
		await get_tree().physics_frame
		held = held or s.holding
		if held and not s.holding and box.linear_velocity.length() > 4.0:
			flew = true
			break
	t.check(held, "picks the box up: %s" % _st(s))
	t.check(flew, "and throws it")
	if flew:
		var v := box.linear_velocity
		var to := o.global_position - box.global_position
		t.check(Vector2(v.x, v.z).normalized().dot(Vector2(to.x, to.z).normalized()) > 0.8, "at the officer")
	t.check(box.has_meta("thrown_t"), "it hurts whoever it hits")


func test_dropped_guns_can_be_picked_up() -> void:
	await _block()
	var p := _street()
	var s := dispatch.spawn_suspect(p, Suspect.S.HIDE, true)
	s.weapon = EnemyGuns.SHOTGUN
	s.mag = 3
	s.set_state(Suspect.S.SURRENDER)
	await get_tree().physics_frame
	var guns := get_tree().get_nodes_in_group("dropped_guns")
	t.check(guns.size() == 1, "giving up, they drop the gun")
	if guns.is_empty():
		return
	var g := guns[0] as DroppedGun
	t.check(g.kind == EnemyGuns.SHOTGUN and g.rounds == 3, "with the 3 rounds left in it")
	for i in 30:
		await get_tree().physics_frame
	t.check(g.global_position.distance_to(s.global_position) > 1.2, "tossed away from them")
	var away := g.global_position - s.global_position
	away.y = 0.0
	var o := _officer(g.global_position + away.normalized() * 0.6)
	await _run(o, _cmd(), 3)
	t.check(o.gun_on_floor() == g, "an officer standing over it can take it")
	await _run(o, _cmd(PlayerInput.INTERACT), 2)
	await _run(o, _cmd(), 2)
	t.check(o.gun == EnemyGuns.SHOTGUN and o.gun_ammo == 3, "takes it, with only its rounds: %d" % o.gun_ammo)
	t.check(get_tree().get_nodes_in_group("dropped_guns").filter(func(n): return not n.is_queued_for_deletion()).is_empty(), "gone from the floor")
	var service := o.ammo
	var aim := o.global_position + Vector3(0, 1.2, 10)
	for k in 3:
		await _run(o, _cmd(PlayerInput.AIM | PlayerInput.FIRE, Vector2.ZERO, aim), 2)
		await _run(o, _cmd(PlayerInput.AIM, Vector2.ZERO, aim), 70)
	t.check(o.gun_ammo == 0 and o.ammo == service, "three shots use its rounds, not the service mag")
	await _run(o, _cmd(PlayerInput.AIM | PlayerInput.FIRE, Vector2.ZERO, aim), 2)
	t.check(o.gun == EnemyGuns.NONE, "empty, it is dropped for the service pistol")
	# H drops a picked-up gun that still has rounds.
	dispatch.drop_gun(o.global_position + Vector3(0.3, 0.1, 0), EnemyGuns.PISTOL, 5)
	for i in 20:
		await get_tree().physics_frame
	await _run(o, _cmd(PlayerInput.INTERACT), 2)
	await _run(o, _cmd(), 2)
	t.check(o.gun == EnemyGuns.PISTOL and o.gun_ammo == 5, "picks up a pistol")
	await _run(o, _cmd(PlayerInput.HOLSTER), 2)
	await _run(o, _cmd(), 2)
	t.check(o.gun == EnemyGuns.NONE, "H puts it down")
	var left := get_tree().get_nodes_in_group("dropped_guns").filter(func(n): return not n.is_queued_for_deletion())
	t.check(left.size() == 1 and (left[0] as DroppedGun).rounds == 5, "where it stays, with its 5 rounds")


func test_shotgun_fires_pellets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var dirs := EnemyGuns.pellet_dirs(EnemyGuns.SHOTGUN, Vector3.FORWARD, rng)
	t.check(dirs.size() == EnemyGuns.PELLETS[EnemyGuns.SHOTGUN], "a spread of pellets: %d" % dirs.size())
	var widest := 0.0
	for d in dirs:
		widest = maxf(widest, rad_to_deg((d as Vector3).angle_to(Vector3.FORWARD)))
	t.check(widest > 1.0 and widest <= EnemyGuns.SPREAD_DEG[EnemyGuns.SHOTGUN] + 0.5, "spread out a little: %.1f deg" % widest)


## beenster (v0.2.9): when you go down you can respawn.
func test_downed_officer_can_respawn() -> void:
	ProtoWorld.ground(self, 100.0)
	var o := _officer(Vector3(3, 0.05, 2))
	await _run(o, _cmd(), 5)
	var start := o.home
	o.global_position = Vector3(20, 0.05, 15)
	o.injuries = Officer.BLEED | Officer.LEG
	o.ammo = 2
	o.reserve = 0
	o.take_damage(500.0, Vector3.FORWARD, "torso")
	t.check(o.state == Officer.S.DOWNED, "down")
	await _run(o, _cmd(PlayerInput.RELOAD), 2)
	await _run(o, _cmd(), 2)
	t.check(o.state == Officer.S.DOWNED, "R does nothing straight away")
	await _run(o, _cmd(), int(Officer.RESPAWN_AFTER * 60.0))
	await _run(o, _cmd(PlayerInput.RELOAD), 2)
	t.check(o.state == Officer.S.MOVE, "after a moment R gets you back up: %s" % Officer.S.keys()[o.state])
	t.check(Vector2(o.global_position.x - start.x, o.global_position.z - start.z).length() < 0.5, "back where you started: %s" % o.global_position)
	t.check(o.hp == Officer.MAX_HP and o.injuries == 0, "healed and patched up")
	t.check(o.ammo == Officer.MAG and o.reserve == Officer.RESERVE_MAX, "with full ammo")
