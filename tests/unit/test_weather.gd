extends Node
## Wave 4, Phase 4.3: the light follows the clock, lamps at night, rain wets
## the roads and costs grip.
var t


func _city() -> City:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	s.dispatch.enabled = false
	s.dispatch.missions.enabled = false
	s.dispatch.stories.enabled = false
	for i in 20:
		await get_tree().physics_frame
	return s


func test_day_night_and_rain() -> void:
	var s := await _city()
	var w := s.weather
	var m := s.dispatch.missions
	m.minute = 13 * 60.0
	for i in 70:
		await get_tree().physics_frame
	var day_sun := s.sun.light_energy
	t.check(w.night < 0.05 and day_sun > 1.0, "1 pm: broad daylight (sun %.2f)" % day_sun)
	t.check(w._lamps.all(func(l): return not l.visible), "no street lamps by day")
	m.minute = 1 * 60.0
	for i in 70:
		await get_tree().physics_frame
	var lit: int = w._lamps.filter(func(l): return l.visible).size()
	print("    1 am: night %.2f, sun %.2f, %d lamps lit, sky %s" % [w.night, s.sun.light_energy, lit, s.env.background_color])
	t.check(w.night > 0.9 and s.sun.light_energy < 0.4, "1 am: dark")
	t.check(lit >= 4, "street lamps on round the station (%d)" % lit)
	# Rain.
	w.set_weather(CityWeather.W.RAIN)
	w.rain = 0.8
	for i in 120:
		await get_tree().physics_frame
	t.check(w.wet > 0.0, "the roads are getting wet (%.3f)" % w.wet)
	w.wet = 1.0
	await get_tree().physics_frame
	t.check(is_equal_approx(Car.grip_k, 0.7), "soaked roads: grip down to %.2f" % Car.grip_k)
	t.check(w._rain_fx.emitting, "it's raining")
	s.queue_free()
	await get_tree().process_frame
	t.check(Car.grip_k == 1.0, "grip back to normal once the city's gone")
