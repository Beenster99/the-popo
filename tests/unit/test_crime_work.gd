extends Node
## v0.24 (beenster: "when a suspect is committing a crime, don't just have them
## stand there in the room or in the road: they are active, doing the crime
## and hiding from the police"). Crooks go between work spots doing the job
## (rummaging, smashing, jimmying, dealing), lookouts watch the street and
## shout a warning, and the rest duck out of sight or creep off unseen.
var t


func _city() -> City:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.enabled = false
	s.dispatch.missions.enabled = false
	s.dispatch.stories.enabled = false
	for i in 60 * 12:
		await get_tree().physics_frame
	return s


func test_rig_has_the_work_moves() -> void:
	var rig := OfficerRig.new()
	add_child(rig)
	await get_tree().process_frame
	for n in ["rummage", "rummage_low", "smash", "jimmy", "deal", "lookout"]:
		t.check(rig.anim_player.has_animation(n), "clip %s" % n)
		t.check(n in OfficerRig.UPPER_STATES, "%s is an upper-body state" % n)
	rig.queue_free()


func test_act_goes_over_the_network() -> void:
	var s := Suspect.new()
	add_child(s)
	s.act = Suspect.ACT.JIMMY
	var b := StreamPeerBuffer.new()
	s.encode(b)
	b.seek(0)
	var d := Suspect.decode(b)
	t.check(d.act == Suspect.ACT.JIMMY, "what the hands are doing is sent")
	s.queue_free()


func test_robbers_loot_and_keep_watch() -> void:
	var s := await _city()
	var d := s.dispatch
	var o: Officer = s.sync.my_pawn()
	var id := d.start_call(Dispatcher.Kind.ROBBERY)
	t.check(id > 0, "a robbery")
	if id <= 0:
		s.queue_free()
		return
	var c: Dictionary = d.calls[id]
	o.global_position = c.pos + Vector3(150, 0, 0)   # nobody about
	var crew: Array = c.suspects.map(func(n): return d.suspects[n])
	var looter: Suspect = crew.filter(func(x): return x.job == "loot")[0] if crew.any(func(x): return x.job == "loot") else null
	var watch: Suspect = crew.filter(func(x): return x.job == "lookout")[0] if crew.any(func(x): return x.job == "lookout") else null
	t.check(looter != null and watch != null, "one loots, one keeps watch")
	if looter == null or watch == null:
		s.queue_free()
		return
	t.check(looter.work.size() >= 3, "%d places to turn over" % looter.work.size())
	var start := looter.global_position
	var acts := {}
	var moved := 0.0
	var spots := {}
	for i in 60 * 20:
		await get_tree().physics_frame
		acts[looter.act] = true
		acts[watch.act + 100] = true
		spots[looter._work_i] = true
		moved = maxf(moved, looter.global_position.distance_to(start))
	print("    looter acts %s, %d spots, moved up to %.1f m" % [str(acts.keys()), spots.size(), moved])
	t.check(acts.has(Suspect.ACT.RUMMAGE) or acts.has(Suspect.ACT.RUMMAGE_LOW), "the looter rummages")
	t.check(spots.size() >= 2 and moved > 0.8, "and moves round the shop")
	t.check(acts.has(Suspect.ACT.LOOKOUT + 100), "the lookout watches the street")
	t.check(looter.state == Suspect.S.ROB and watch.state == Suspect.S.ROB, "still at it with nobody about")
	# The lookout spots the police: a shout, and the crew is off.
	Voices.history.clear()
	o.global_position = watch.global_position + Vector3(0, 0, 24)
	watch._react({"o": o, "d": 24.0, "los": true})
	for i in 60 * 2:
		await get_tree().physics_frame
	var warned := Voices.history.any(func(h): return Voices.LINES[h.line][2] == Voices.Kind.WARN)
	t.check(warned, "the lookout shouts a warning")
	t.check(looter.state != Suspect.S.ROB, "the looter hears it and goes (%s)" % Suspect.S.keys()[looter.state])
	s.queue_free()
	await get_tree().process_frame


func test_unseen_they_creep_off_seen_they_run() -> void:
	var s := await _city()
	var d := s.dispatch
	var o: Officer = s.sync.my_pawn()
	var id := d.start_call(Dispatcher.Kind.THEFT)
	t.check(id > 0, "a car theft")
	if id <= 0:
		s.queue_free()
		return
	var th: Suspect = d.suspects[d.calls[id].suspects[0]]
	o.global_position = th.global_position + Vector3(120, 0, 0)
	for i in 60 * 3:
		await get_tree().physics_frame
	t.check(th.job == "jimmy" and th.act == Suspect.ACT.JIMMY, "working the car door (%s)" % Suspect.ACT.keys()[th.act])
	th.armed = false
	th._last_seen = o.global_position
	th._react({"o": o, "d": 30.0, "los": false})
	t.check(th.state == Suspect.S.FLEE and th._sneak, "not seen yet: creeping away")
	var top := 0.0
	for i in 60 * 2:
		await get_tree().physics_frame
		if th.state == Suspect.S.FLEE:
			top = maxf(top, Vector2(th.velocity.x, th.velocity.z).length())
	t.check(top <= Suspect.SNEAK + 0.2, "slow and low (%.1f m/s)" % top)
	if th.state == Suspect.S.FLEE:
		t.check(th.act == Suspect.ACT.SNEAK, "crouched")
		# Seen close: they run for it.
		o.global_position = th.global_position + Vector3(6, 0, 0)
		for i in 30:
			await get_tree().physics_frame
		t.check(not th._sneak, "seen: running now")
	s.queue_free()
	await get_tree().process_frame


func test_dealers_hand_off_and_look_round() -> void:
	var s := await _city()
	var d := s.dispatch
	d.missions.enabled = true
	var o: Officer = s.sync.my_pawn()
	var id := d.start_call(Dispatcher.Kind.DEAL)
	t.check(id > 0, "a drug deal")
	if id <= 0:
		s.queue_free()
		return
	o.global_position = d.calls[id].pos + Vector3(150, 0, 0)
	var pair: Array = d.calls[id].suspects.map(func(n): return d.suspects[n])
	var acts := {}
	for i in 60 * 25:
		await get_tree().physics_frame
		for x in pair:
			acts[(x as Suspect).act] = true
	t.check(acts.has(Suspect.ACT.DEAL) and acts.has(Suspect.ACT.LOOKOUT), "the hand-off and a look round: %s" % str(acts.keys()))
	s.queue_free()
	await get_tree().process_frame
