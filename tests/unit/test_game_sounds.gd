extends Node
## Phase 1.6: the game's sound. Firing makes a layered shot (this was
## silent in the city before), footsteps follow surfaces, the reload and
## brass play, bullets crack past your head, close shots duck the background
## and ring your ears, and breaking things sounds like what broke.
var t
var sounds: GameSounds
var world: DestructionWorld
var me: Officer


func _scene() -> void:
	Sfx.history.clear()
	var g := ProtoWorld.ground(self, 200.0)
	g.set_meta("surface", "dirt")
	world = DestructionWorld.new()
	add_child(world)
	sounds = GameSounds.new()
	sounds.world = world
	sounds.pawn_getter = func(): return me
	add_child(sounds)


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
		await get_tree().process_frame


func _cmd(buttons := 0, move := Vector2.ZERO, aim := Vector3.ZERO) -> Dictionary:
	return {"move": move, "buttons": buttons, "aim_yaw": 0.0, "aim_point": aim}


func _stems() -> Array:
	return Sfx.history.map(func(s): return s.stem)


func test_every_new_sound_loads_and_loops_loop() -> void:
	for stem in ["amb_street", "amb_air", "amb_far_traffic", "room_tone", "car_engine", "tyre_skid"]:
		var w := Sfx.loop_stream(stem)
		t.check(w.loop_mode == AudioStreamWAV.LOOP_FORWARD and w.loop_end > 44100, stem + " loops")
	Sfx.ensure_buses()
	for b in [Sfx.BUS_AMBIENCE, Sfx.BUS_AMBIENCE_OUT, Sfx.BUS_VEHICLES]:
		t.check(AudioServer.get_bus_index(b) != -1, "bus " + b)


func test_firing_makes_a_layered_shot_and_brass() -> void:
	await _scene()
	me = _officer(Vector3(0, 0.05, 0))
	sounds.set_meta("casings_in_headless", true)
	for i in 3:
		await get_tree().process_frame
	Sfx.history.clear()
	await _run(me, _cmd(PlayerInput.AIM | PlayerInput.FIRE, Vector2.ZERO, Vector3(0, 1.2, 10)), 12)
	var stems := _stems()
	t.check(stems.has("gun_near"), "the shot itself: %s" % [stems])
	t.check(stems.has("gun_thump"), "and the low-end thump")
	t.check(stems.has("gun_mech"), "and the slide, right next to the gun")
	t.check(sounds._casings.size() > 0, "a case flew out")
	# It lands and rings.
	for i in 90:
		await get_tree().physics_frame
		if _stems().has("casing_concrete") or _stems().has("casing_wood"):
			break
	t.check(_stems().has("casing_concrete"), "the case bounces on the ground: %s" % [_stems()])


func test_reload_plays_mag_out_drop_in_and_slide() -> void:
	await _scene()
	me = _officer(Vector3(0, 0.05, 0))
	me.ammo = 0
	for i in 3:
		await get_tree().process_frame
	Sfx.history.clear()
	await _run(me, _cmd(PlayerInput.RELOAD), 2)
	await _run(me, _cmd(), int(Officer.RELOAD_TIME * 60.0) + 10)
	var stems := _stems()
	for s in ["mag_out", "mag_in", "slide_rack"]:
		t.check(stems.has(s), s + ": %s" % [stems])
	t.check(stems.any(func(x): return String(x).begins_with("mag_drop_")), "the empty mag hits the floor")


func test_footsteps_follow_the_surface() -> void:
	await _scene()
	me = _officer(Vector3(0, 0.05, 0))
	ProtoWorld.block(self, Vector3(6, 0.2, 6), Vector3(0, -0.1, 20), Color.GRAY, "Boards").set_meta("surface", "wood")
	await get_tree().process_frame
	Sfx.history.clear()
	var p0 := me.global_position
	await _run(me, _cmd(0, Vector2(0, -1)), 150)
	print("    walked %s -> %s" % [p0, me.global_position])
	var stems := _stems()
	t.check(stems.count("step_dirt") >= 3, "steps on the grass: %s" % [stems])
	me.global_position = Vector3(0, 0.1, 22.5)
	await get_tree().process_frame
	Sfx.history.clear()
	await _run(me, _cmd(0, Vector2(0, -1)), 120)
	t.check(_stems().has("step_wood"), "steps on the boards: %s" % [_stems()])


func test_near_miss_cracks_past_your_head() -> void:
	await _scene()
	me = _officer(Vector3(0, 0.05, 0))
	for i in 3:
		await get_tree().process_frame
	Sfx.history.clear()
	var head := me.global_position + Vector3(0, 1.6, 0)
	Sfx.bullet(self, head + Vector3(-20, 0, 0.6), head + Vector3(20, 0, 0.6), "concrete", 0)
	t.check(_stems().has("bullet_crack"), "a bullet 0.6 m away cracks: %s" % [_stems()])
	Sfx.history.clear()
	Sfx.bullet(self, head + Vector3(-20, 0, 2.0), head + Vector3(20, 0, 2.0), "concrete", 0)
	t.check(_stems().has("bullet_whizz"), "2 m away whizzes")
	Sfx.history.clear()
	Sfx.bullet(self, head + Vector3(-20, 0, 0.6), head + Vector3(20, 0, 0.6), "concrete", 0, true)
	t.check(not _stems().has("bullet_crack"), "not for your own shots")
	Sfx.history.clear()
	Sfx.bullet(self, head + Vector3(0, 0, 10), head + Vector3(0, 0, 30), "metal", 1)
	t.check(_stems().slice(0, 2) == ["body_hit", "gore_hit"], "a hit on a person is a body hit and a wet hit: %s" % [_stems()])


func test_close_shot_ducks_and_rings() -> void:
	await _scene()
	me = _officer(Vector3(0, 0.05, 0))
	for i in 3:
		await get_tree().process_frame
	Sfx.shot(self, me.global_position + Vector3(1.0, 1.4, 0), 1, false)
	t.check(sounds._duck > 0.9, "the background ducks: %.2f" % sounds._duck)
	t.check(sounds._ring > 0.3, "ears ring after a shot right by your head")
	await get_tree().process_frame
	var lp := AudioServer.get_bus_effect(0, sounds._ring_fx) as AudioEffectLowPassFilter
	t.check(AudioServer.is_bus_effect_enabled(0, sounds._ring_fx) and lp.cutoff_hz < 5000.0, "and everything is muffled for a moment")
	for i in 200:
		await get_tree().process_frame
	t.check(sounds._ring < 0.3, "it fades")
	sounds._ring = 0.0
	Sfx.shot(self, me.global_position + Vector3(1.0, 1.4, 0), 1, true)
	t.check(sounds._ring == 0.0, "your own shots do not ring")


func test_echoes_off_buildings() -> void:
	await _scene()
	me = _officer(Vector3(0, 0.05, 0))
	ProtoWorld.block(self, Vector3(30, 10, 1), Vector3(0, 5, 25), Color.GRAY, "Wall")
	for i in 3:
		await get_tree().physics_frame
		await get_tree().process_frame
	Sfx.history.clear()
	Sfx.shot(self, Vector3(0, 1.3, 2), 0, true)
	var before := Sfx.history.size()
	for i in 30:
		await get_tree().physics_frame
		await get_tree().process_frame
	var late := Sfx.history.slice(before).map(func(s): return s.stem)
	t.check(late.has("gun_far"), "the shot slaps back off the wall 23 m away: %s" % [late])
	var echo: Dictionary = Sfx.history.slice(before).filter(func(e): return e.stem == "gun_far")[0]
	t.check((echo.pos as Vector3).z > 20.0, "from the wall")
	t.check(late.has("gun_tail_city"), "and rolls on down the street (Wave 2)")


func test_breaking_sounds_like_what_broke() -> void:
	await _scene()
	var wi := world.add_piece("wall_window", Transform3D(Basis(), Vector3(0, 0, 10)), true)
	var gi := world.add_piece("glass_window", Transform3D(Basis(), Vector3(0, 0, 10)), false, Color(0, 0, 0, 0), wi)
	var di := world.add_piece("door_closed", Transform3D(Basis(), Vector3(8, 0, 10)), false)
	world.finalize()
	Sfx.history.clear()
	world.damage_piece(gi, 100.0, Vector3(0, 1.5, 9), 1.0)
	t.check(_stems().has("glass_break"), "a pane shatters: %s" % [_stems()])
	for i in 50:
		await get_tree().physics_frame
		await get_tree().process_frame
	t.check(_stems().has("glass_settle"), "and the shards settle")
	Sfx.history.clear()
	world.damage_piece(di, 500.0, Vector3(8, 1.0, 9), 1.0)
	t.check(_stems().has("break_wood"), "a door splinters: %s" % [_stems()])
	Sfx.history.clear()
	world.damage_piece(wi, 1000.0, Vector3(0, 1.0, 9), 2.0)
	t.check(_stems().has("break_concrete"), "a wall crumbles: %s" % [_stems()])


func test_engine_and_skid() -> void:
	await _scene()
	var cs := CarSync.new()
	cs.use_seats = true
	add_child(cs)
	sounds.cars = cs
	var c := Car.new()
	c.position = Vector3(0, 1.0, 0)
	add_child(c)
	cs.add_car(c)
	for i in 30:
		await get_tree().physics_frame
	for i in 90:
		c.linear_velocity = -c.global_transform.basis.z * (4.0 + i * 0.2)
		await get_tree().physics_frame
		await get_tree().process_frame
	var a: Dictionary = sounds._car_audio.get(c.get_instance_id(), {})
	t.check(not a.is_empty() and a.on, "engine running when driven")
	t.check((a.engine as AudioStreamPlayer3D).pitch_scale > 0.8, "pitch rises with speed: %.2f" % (a.engine as AudioStreamPlayer3D).pitch_scale)


## The regression from v0.2.5: the city made no sound when you fired.
func test_the_city_block_has_sound() -> void:
	Sfx.history.clear()
	var scene: Node = load("res://prototypes/p08_block/block.tscn").instantiate()
	add_child(scene)
	var gs: GameSounds = null
	var o: Officer = null
	for i in 240:
		await get_tree().physics_frame
		await get_tree().process_frame
		gs = scene.get_node_or_null("GameSounds") as GameSounds
		o = scene.sync.my_pawn() if scene.sync else null
		if gs and o and i > 20:
			break
	t.check(gs != null and gs.world != null and gs.cars != null, "the block has its sound, with the world and cars")
	t.check(o != null, "and the player's officer")
	if o == null:
		scene.queue_free()
		return
	t.check(gs.listener.is_current(), "the ears are ours")
	t.check((gs._amb.street as AudioStreamPlayer).playing, "the street is in the background")
	Sfx.history.clear()
	o.ammo -= 1     # as if a shot went off
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(_stems().has("gun_near") or _stems().has("gun_dry"), "a shot makes a bang: %s" % [_stems()])
	scene.queue_free()
	await get_tree().process_frame
