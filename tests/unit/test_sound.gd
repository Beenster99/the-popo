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
	for l in Sfx.GUN_LAYERS + [Sfx.GUN_TAIL]:
		for v in range(1, l[1] + 1):
			t.check(Sfx.stream(l[0], v) is AudioStreamWAV, "%s_%d" % [l[0], v])
	for s in Sfx.SURFACES:
		for v in range(1, 4):
			t.check(Sfx.stream("impact_" + s, v) is AudioStreamWAV, "impact_%s_%d" % [s, v])


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
	Sfx.gunshot(self, Vector3(0, 1.3, 30))
	var stems := Sfx.history.map(func(s): return s.stem)
	t.check(stems == ["gun_mech", "gun_crack", "gun_body", "gun_tail_outdoor"], "outdoor shot layers: %s" % [stems])
	t.check(Sfx.history[-1].bus == Sfx.BUS_OUTDOOR, "tail on outdoor bus")
	var z := SoundZone.new()
	z.position = Vector3(0, 1.5, 30)
	add_child(z)
	Sfx.history.clear()
	Sfx.gunshot(self, Vector3(0, 1.3, 30))
	t.check(Sfx.history.size() == 3, "no outdoor tail indoors")
	t.check(Sfx.history.all(func(s): return s.bus == Sfx.BUS_INDOOR), "indoor shot on indoor bus")
	z.queue_free()
	listener_spot.queue_free()


func test_surface_lookup() -> void:
	var b := ProtoWorld.block(self, Vector3.ONE, Vector3(50, 0, 0), Color.WHITE)
	t.check(Sfx.surface_of(b) == "concrete", "default concrete")
	b.set_meta("surface", "glass")
	t.check(Sfx.surface_of(b) == "glass", "meta surface")
	t.check(Sfx.surface_of(b.get_child(0)) == "glass", "child inherits surface")
	Sfx.history.clear()
	Sfx.impact(self, Vector3(50, 0, 0), "plastic")
	t.check(Sfx.history[-1].stem == "impact_concrete", "unknown surface falls back")
