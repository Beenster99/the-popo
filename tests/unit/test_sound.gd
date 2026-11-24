extends Node
## Phase 0.7: buses exist, zones pick the reverb, walls muffle, layers play.
var t


func _wall(pos: Vector3, size: Vector3) -> StaticBody3D:
	return ProtoWorld.block(self, size, pos, Color.GRAY, "Wall")


func test_buses_are_made_once() -> void:
	Sfx.ensure_buses()
	var n := AudioServer.bus_count
	Sfx.ensure_buses()
	t.check(AudioServer.bus_count == n, "no duplicate buses")
	for b in [Sfx.BUS_SFX, Sfx.BUS_INDOOR, Sfx.BUS_OUTDOOR]:
		t.check(AudioServer.get_bus_index(b) != -1, "bus " + b)
	t.check(AudioServer.get_bus_send(AudioServer.get_bus_index(Sfx.BUS_INDOOR)) == Sfx.BUS_SFX, "indoor feeds SFX")
	t.check(AudioServer.get_bus_effect_count(AudioServer.get_bus_index(Sfx.BUS_OUTDOOR)) >= 2, "outdoor has echo and reverb")


func test_every_sound_file_loads() -> void:
	for stem in Sfx.COUNTS:
		for v in range(1, Sfx.COUNTS[stem] + 1):
			t.check(Sfx.stream(stem, v) is AudioStreamWAV, "%s_%d" % [stem, v])
	for s in Sfx.SURFACES:
		t.check(Sfx.COUNTS.has("impact_" + s), "impacts for " + s)


func test_muffled_buses_filter_and_feed_their_room() -> void:
	Sfx.ensure_buses()
	for base in [Sfx.BUS_SFX, Sfx.BUS_INDOOR, Sfx.BUS_OUTDOOR]:
		for w in [1, 2]:
			var i := AudioServer.get_bus_index(Sfx.muffled_bus(base, w))
			t.check(i != -1, Sfx.muffled_bus(base, w))
			t.check(AudioServer.get_bus_send(i) == base, "feeds " + base)
			t.check(AudioServer.get_bus_effect(i, 0) is AudioEffectLowPassFilter, "low-pass on " + Sfx.muffled_bus(base, w))
	t.check(Sfx.muffled_bus(Sfx.BUS_INDOOR, 5) == "Indoor_Muffled2", "3+ walls use the strongest")


func test_zone_picks_indoor_bus() -> void:
	var z := SoundZone.new()
	z.size = Vector3(4, 3, 4)
	z.position = Vector3(10, 1.5, 0)
	add_child(z)
	t.check(Sfx.bus_at(get_tree(), Vector3(10, 1, 0)) == Sfx.BUS_INDOOR, "inside is indoor")
	t.check(Sfx.bus_at(get_tree(), Vector3(10, 1, 3)) == Sfx.BUS_OUTDOOR, "outside is outdoor")
	t.check(Sfx.zone_at(get_tree(), Vector3(11.9, 1, 1.9)) != null, "corner inside before rotating")
	z.rotation_degrees.y = 45
	t.check(Sfx.zone_at(get_tree(), Vector3(11.9, 1, 1.9)) == null, "rotated zone corner is outside")
	z.queue_free()


func test_walls_muffle() -> void:
	_wall(Vector3(0, 1.5, 2), Vector3(6, 3, 0.3))
	_wall(Vector3(0, 1.5, 4), Vector3(6, 3, 0.3))
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	t.check(Sfx.walls_between(space, Vector3(0, 1, 0), Vector3(0, 1, 1)) == 0, "clear line")
	t.check(Sfx.walls_between(space, Vector3(0, 1, 0), Vector3(0, 1, 3)) == 1, "one wall")
	t.check(Sfx.walls_between(space, Vector3(0, 1, 0), Vector3(0, 1, 6)) == 2, "two walls")
	var a := Sfx.occlusion(0)
	var b := Sfx.occlusion(1)
	var c := Sfx.occlusion(2)
	t.check(a.cutoff > b.cutoff and b.cutoff > c.cutoff, "cutoff drops per wall")
	t.check(a.db > b.db and b.db > c.db, "volume drops per wall")


func test_gunshot_layers_and_tail() -> void:
	Sfx.history.clear()
	var listener_spot := Node3D.new()
	add_child(listener_spot)
	listener_spot.position = Vector3(0, 0, 30)
	Sfx.attach_listener(listener_spot)
	Sfx.forget_spaces()
	Sfx.gunshot(self, Vector3(0, 1.3, 30))
	var stems := Sfx.history.map(func(s): return s.stem)
	t.check(stems == ["gun_9mm_near"], "outdoor close shot: %s" % [stems])
	t.check(Sfx.history[-1].bus in Sfx.OUTDOOR_BUSES, "outdoor bus")
	Sfx.history.clear()
	Sfx.gunshot(self, Vector3(0, 1.3, 80))
	t.check(Sfx.history[-1].stem == "gun_far", "distant shot uses the far recording")
	var z := SoundZone.new()
	z.position = Vector3(0, 1.5, 30)
	add_child(z)
	Sfx.history.clear()
	Sfx.forget_spaces()
	Sfx.gunshot(self, Vector3(0, 1.3, 30))
	t.check(Sfx.history.size() == 1 and Sfx.history[0].stem == "gun_9mm_room", "indoors the room take: %s" % [Sfx.history])
	t.check(Sfx.history[0].bus in Sfx.INDOOR_BUSES, "indoor shot on an indoor bus")
	z.queue_free()
	listener_spot.queue_free()


func test_shot_behind_a_wall_goes_through_a_muffled_bus() -> void:
	var ears := Node3D.new()
	add_child(ears)
	ears.position = Vector3(40, 0, 0)
	Sfx.attach_listener(ears)
	_wall(Vector3(40, 1.5, -2), Vector3(6, 3.5, 0.6))
	await get_tree().physics_frame
	await get_tree().physics_frame
	Sfx.history.clear()
	Sfx.forget_spaces()
	Sfx.gunshot(self, Vector3(40, 1.3, -4))
	var base: String = Sfx.history[-1].bus
	t.check(Sfx.history[-1].played_on == base + "_Muffled1", "played on %s" % Sfx.history[-1].played_on)
	Sfx.gunshot(self, Vector3(40, 1.3, 3))
	t.check(Sfx.history[-1].played_on == Sfx.history[-1].bus, "clear shot is not muffled (%s)" % Sfx.history[-1].played_on)
	ears.queue_free()


## v0.13.0: the space a shot is fired in picks its sound.
func test_spaces() -> void:
	Sfx.forget_spaces()
	# An alley: walls 3 m either side, open along it.
	_wall(Vector3(200, 4, -3), Vector3(40, 8, 0.4))
	_wall(Vector3(200, 4, 3), Vector3(40, 8, 0.4))
	# A small room: a box 3 x 3 with a ceiling, inside a zone.
	var rx := 300.0
	_wall(Vector3(rx, 1.5, -1.5), Vector3(3.4, 3, 0.2))
	_wall(Vector3(rx, 1.5, 1.5), Vector3(3.4, 3, 0.2))
	_wall(Vector3(rx - 1.5, 1.5, 0), Vector3(0.2, 3, 3.4))
	_wall(Vector3(rx + 1.5, 1.5, 0), Vector3(0.2, 3, 3.4))
	_wall(Vector3(rx, 3.1, 0), Vector3(3.4, 0.2, 3.4))
	var z := SoundZone.new()
	z.size = Vector3(3, 3, 3)
	z.position = Vector3(rx, 1.5, 0)
	add_child(z)
	await get_tree().physics_frame
	await get_tree().physics_frame
	t.check(Sfx.space_at(self, Vector3(200, 1.3, 0)).kind == "alley", "between close walls: %s" % [Sfx.space_at(self, Vector3(200, 1.3, 0))])
	t.check(Sfx.space_at(self, Vector3(200, 1.3, 0)).bus == Sfx.BUS_ALLEY, "alley bus")
	t.check(Sfx.space_at(self, Vector3(rx, 1.3, 0)).kind == "room_small", "a box room: %s" % [Sfx.space_at(self, Vector3(rx, 1.3, 0))])
	t.check(Sfx.space_at(self, Vector3(rx, 1.3, 0)).indoor, "is indoors")
	t.check(Sfx.space_at(self, Vector3(400, 12.0, 0)).kind == "rooftop", "high up outside is a rooftop")
	t.check(Sfx.space_at(self, Vector3(400, 1.3, 400)).kind == "open", "nothing near is open ground")
	t.check(Sfx.family(2, 1.0) == "shotgun" and Sfx.family(0, 1.6) == "heavy" and Sfx.family(0, 0.8) == "smg"
		and Sfx.family(0, 1.0) == "9mm" and Sfx.family(1, 1.0) == "9mm", "gun families")
	z.queue_free()


func test_surface_lookup() -> void:
	var b := ProtoWorld.block(self, Vector3.ONE, Vector3(50, 0, 0), Color.WHITE)
	t.check(Sfx.surface_of(b) == "concrete", "default concrete")
	b.set_meta("surface", "glass")
	t.check(Sfx.surface_of(b) == "glass", "meta surface")
	t.check(Sfx.surface_of(b.get_child(0)) == "glass", "child inherits surface")
	Sfx.history.clear()
	Sfx.impact(self, Vector3(50, 0, 0), "plastic")
	t.check(Sfx.history[-1].stem == "impact_concrete", "unknown surface falls back")
