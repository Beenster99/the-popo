extends Node
## Wave 5, Phase 5.4: a busy shift run fast: calls, stories, things that
## just happen, weather, the clock rolling over midnight, blasts and repair
## crews, all at once. Nothing should pile up or fall over.
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_a_busy_shift_stays_steady() -> void:
	City.next_seed = 5151
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	await _frames(30)
	var d := s.dispatch
	var nodes0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans0 := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	var most_suspects := 0
	var calls := 0
	var blasts := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 51
	d.missions.minute = 22 * 60.0
	for step in 8:
		# A new job every round, a blast every third, weather every fourth.
		if d.start_call(d._pick_kind()) > 0:
			calls += 1
		if step % 3 == 1:
			var b: Dictionary = s.gen.buildings[rng.randi_range(0, s.gen.buildings.size() - 1)]
			s.world.explode((b.origin as Vector3) + Vector3(1, 1, 0), 3.0, 350.0, 5.0)
			blasts += 1
		if step % 4 == 0:
			s.weather.set_weather(step / 4 % 4)
		for id in s.repairs._broken:
			s.repairs._broken[id] = RepairCrews.WAIT
		d.missions.minute = fposmod(d.missions.minute + 40.0, Missions.DAY_MINUTES)
		await _frames(180)
		most_suspects = maxi(most_suspects, d.suspects.size())
	var nodes1 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var orphans1 := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	print("    %d calls, %d blasts, most suspects %d, nodes %d -> %d, orphans %d -> %d, sites %d, fps-ish %d" % [
		calls, blasts, most_suspects, nodes0, nodes1, orphans0, orphans1, s.repairs.sites.size(), Engine.get_frames_per_second()])
	t.check(calls >= 4, "calls kept coming (%d)" % calls)
	t.check(most_suspects < 80, "people don't pile up (%d at most)" % most_suspects)
	t.check(orphans1 - orphans0 < 200, "no leak of loose nodes (%d new)" % (orphans1 - orphans0))
	t.check(nodes1 < nodes0 * 1.6 + 2000, "the scene doesn't balloon (%d -> %d)" % [nodes0, nodes1])
	t.check(s.repairs.sites.size() <= RepairCrews.MAX_SITES, "repair sites capped")
	s.queue_free()
	await _frames(3)
