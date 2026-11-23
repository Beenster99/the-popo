extends Node
## Wave 3, Phases 3.5 and 3.6: the station armoury (pistols, upgrades,
## ammo, gear, vehicles, the station growing), loadouts and the range.
var t


func _city() -> City:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.enabled = false
	s.dispatch.missions.enabled = false
	s.dispatch.stories.enabled = false
	for i in 30:
		await get_tree().physics_frame
	return s


func test_armoury_buys_kit() -> void:
	var s := await _city()
	var d := s.dispatch
	var a := s.armoury
	var o: Officer = s.sync.my_pawn()
	t.check(Armoury.owned == 1 and o.mag_size() == 15 and o.weapon_name() == "Service pistol", "start with the service pistol only")
	t.check(not a._buy(2), "can't buy on no pay")
	d.pay = 20000
	t.check(a._buy(2), "buy the heavy .45")
	o.set_kit(Armoury.make_kit(2, 0))
	t.check(o.weapon_name() == "Heavy .45" and o.ammo == 8 and is_equal_approx(o.shot_damage(), 40.0), "carrying it: %s, %d rounds" % [o.weapon_name(), o.ammo])
	o.set_kit(Armoury.make_kit(3, 0))
	t.check(o.weapon_name() == "Heavy .45", "can't carry a pistol nobody's bought")
	a._buy(Armoury.EXT_MAG)
	a._buy(Armoury.HOLLOW)
	o.set_kit(Armoury.make_kit(2, Armoury.Ammo.HOLLOW))
	t.check(o.mag_size() == 12 and o.shot_damage() > 50.0, "extended mags and hollow points: %d rounds, %.0f damage" % [o.mag_size(), o.shot_damage()])
	print("    pay left £%d" % d.pay)
	t.check(d.pay == 20000 - 1200 - 800 - 500, "paid for out of the station's pay")
	# Armour.
	var hp0 := o.hp
	o.take_damage(30.0)
	var plain := hp0 - o.hp
	a._buy(Armoury.ARMOUR)
	hp0 = o.hp
	o.take_damage(30.0)
	t.check(hp0 - o.hp < plain, "body armour takes the edge off (%.0f vs %.0f)" % [hp0 - o.hp, plain])
	# Vehicles wait locked in the yard until there's a garage and they're bought.
	var van: PoliceCar = s.yard_cars[Armoury.VAN]
	t.check(not van.can_enter(), "the prisoner van is locked")
	t.check(Armoury.why_not(Armoury.VAN, d.pay) == "needs the Garage", "needs a garage first")
	a._buy(Armoury.GARAGE)
	a._buy(Armoury.VAN)
	await get_tree().physics_frame
	t.check(van.can_enter() and s.get_node_or_null("Garage") != null, "garage built, van unlocked")
	s.queue_free()
	await get_tree().process_frame


func test_loadouts_and_range() -> void:
	var s := await _city()
	var d := s.dispatch
	var a := s.armoury
	var o: Officer = s.sync.my_pawn()
	d.pay = 20000
	a._buy(Armoury.GEAR_ITEM[Armoury.Gear.C4])
	o.set_kit(Armoury.make_kit(0, 0, Armoury.Gear.C4))
	t.check(o.charges == 2, "C4: two charges")
	a._buy(Armoury.GEAR_ITEM[Armoury.Gear.BACKPACK])
	o.set_kit(Armoury.make_kit(0, 0, Armoury.Gear.BACKPACK))
	t.check(o.reserve_max() == 180 and o.charges == 0, "ammo backpack: %d spare rounds" % o.reserve_max())
	# A charge on the station wall.
	var broken: Array = []
	s.world.piece_broken.connect(func(id): broken.append(id))
	var st := s.gen.station()
	var wall: Vector3 = (st.origin as Vector3) + (st.u as Vector3) * 3.0 + Vector3(0, 1.2, -0.2)
	Charge.place(get_tree(), s, s.world, s.cars, wall, Armoury.charge_blast(Armoury.make_kit(0, 0, Armoury.Gear.C4)), true)
	for i in int(3.3 * 60):
		await get_tree().physics_frame
	t.check(broken.size() > 0, "the C4 goes off: %d pieces broken" % broken.size())
	# The range.
	var said: Array = []
	d.radio.connect(func(x): said.append(x))
	a._buy(Armoury.RANGE)
	await get_tree().physics_frame
	var r := s.get_node_or_null("Range") as FiringRange
	t.check(r != null and r.targets_list().size() == FiringRange.LANES, "a firing range out the back")
	if r:
		r.begin()
		var shot := 0
		for i in 60 * 31:
			await get_tree().physics_frame
			for tg in r.targets_list():
				if tg.up and not tg.civilian and i % 20 == 0:
					tg.on_bullet(tg.global_position, o)
					shot += 1
		print("    range: score %d from %d shots; %s" % [r.score, shot, said.filter(func(x): return String(x).begins_with("RANGE: ") and not String(x).contains("starts"))])
		t.check(r.score > 0 and not r.running, "a run scored %d" % r.score)
		t.check(said.any(func(x): return String(x).contains("points")), "the score goes out on the radio")
	s.queue_free()
	await get_tree().process_frame


func test_undercover_and_stings() -> void:
	var s := await _city()
	var d := s.dispatch
	var a := s.armoury
	var o: Officer = s.sync.my_pawn()
	for i in 60 * 10:
		await get_tree().physics_frame   # walk routes for the call area
	d.pay = 20000
	a._buy(Armoury.PLAIN)
	o.set_plain(true)
	for i in 3:
		await get_tree().physics_frame
	t.check(o.plain and o.undercover(), "in plain clothes")
	# The fake buy: walk up in plain clothes and buy.
	var id := d.start_call(Dispatcher.Kind.BUY)
	t.check(id > 0, "a sting: %s" % (d.calls[id].text if id > 0 else "-"))
	if id > 0:
		var dealer: Suspect = d.suspects[d.calls[id].suspects[0]]
		dealer.armed = true   # armed dealers hold their corner too
		o.global_position = dealer.global_position + Vector3(1.4, 0, 0)
		var src := s.sync.input_source
		s.sync.input_source = func(): return {"buttons": PlayerInput.INTERACT, "move": Vector2.ZERO, "aim_yaw": 0.0, "aim_point": Vector3.ZERO}
		for i in int(2.5 * 60):
			await get_tree().physics_frame
		s.sync.input_source = src
		print("    dealer %s, suspicion %.2f" % [Suspect.S.keys()[dealer.state], dealer.suspicion])
		t.check(d.calls[id].get("bought", false), "made the buy without him clocking us")
		t.check(dealer.state == Suspect.S.LOITER and dealer.suspicion < Suspect.MADE, "and he's none the wiser")
		# Draw the gun: he knows.
		o.holstered = false
		for i in 5:
			await get_tree().physics_frame
		t.check(dealer.suspicion >= Suspect.MADE, "gun out: he's made us")
		o.holstered = true
	# The bait car.
	o.global_position = s._spawn_point(0)
	var bid := d.start_call(Dispatcher.Kind.BAITCAR)
	t.check(bid > 0, "bait car: %s" % (d.calls[bid].text if bid > 0 else "-"))
	if bid > 0:
		var th: Suspect = d.suspects[d.calls[bid].suspects[0]]
		o.global_position = th.global_position + Vector3(150, 0, 0)
		d._thefts[bid].t = Dispatcher.BREAK_IN_TIME - 0.5
		for i in 60 * 2:
			await get_tree().physics_frame
		t.check(th.state == Suspect.S.DRIVE, "he takes it (%s)" % Suspect.S.keys()[th.state])
		for i in int((Missions.BAIT_LOCK + 1.0) * 60):
			await get_tree().physics_frame
		t.check(th.state == Suspect.S.SURRENDER, "locked down: hands up in the car (%s)" % Suspect.S.keys()[th.state])
	s.queue_free()
	await get_tree().process_frame


## Wave 4, Phase 4.4: Continue brings the career back: pay, kit bought,
## the stories, the clock and weather, and what each officer carried.
func test_continue_keeps_the_career() -> void:
	BlockState.save_path = City.SAVE_PATH
	BlockState.delete_save()
	var s := await _city()
	var d := s.dispatch
	var o: Officer = s.sync.my_pawn()
	d.pay = 30000
	s.armoury._buy(2)
	s.armoury._buy(Armoury.HOLLOW)
	s.armoury._buy(Armoury.PLAIN)
	o.set_kit(Armoury.make_kit(2, Armoury.Ammo.HOLLOW))
	o.set_plain(true)
	var pay := d.pay
	var owned := Armoury.owned
	d.missions.minute = 22 * 60.0 + 30.0
	s.weather.set_weather(CityWeather.W.STORM)
	s.weather.wet = 0.8
	var chain: String = d.stories.progress.keys()[0]
	d.stories.progress[chain].step = 1
	d.stories.progress[chain].escapes = 2
	t.check(s.state.save(), "the host saves")
	var seed_was: int = s.state.seed_value
	s.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	t.check(Armoury.owned == 1, "the city's gone: back to the service pistol")
	City.resume = true
	var c: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(c)
	c.dispatch.enabled = false
	c.dispatch.missions.enabled = false
	c.dispatch.stories.enabled = false
	for i in 30:
		await get_tree().physics_frame
	var o2: Officer = c.sync.my_pawn()
	t.check(c.state.seed_value == seed_was, "the same city")
	t.check(c.dispatch.pay == pay and Armoury.owned == owned, "pay £%d and the kit bought are back" % c.dispatch.pay)
	t.check(absf(c.dispatch.missions.minute - (22 * 60.0 + 30.0)) < 2.0, "the clock carries on from 22:30 (%.0f)" % c.dispatch.missions.minute)
	t.check(c.weather.kind == CityWeather.W.STORM and c.weather.wet > 0.7, "still stormy, roads still wet")
	t.check(c.dispatch.stories.progress[chain].step == 1 and c.dispatch.stories.progress[chain].escapes == 2, "the story picks up where it was")
	t.check(o2 != null and (o2.kit & 7) == 2 and Armoury.ammo_of(o2.kit) == Armoury.Ammo.HOLLOW and o2.plain, "the officer has the same kit on")
	c.queue_free()
	await get_tree().process_frame
	BlockState.delete_save()
