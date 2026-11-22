extends Node
## Settings, the main menu, the settings screen and the pause menu.
var t


func _settings() -> Node:
	return get_tree().root.get_node("Settings")


func test_every_option_has_a_value_and_applies() -> void:
	var st := _settings()
	for e in st.SCHEMA:
		if e[3] in ["bool", "enum", "range"]:
			t.check(st.values.has(e[1]), "value for " + e[1])
		if e[3] == "enum":
			t.check(st.options(e).size() > 0 or e[5] == "@devices", "options for " + e[1])
	var errs: int = t.errors.count
	for name in st.PRESETS:
		st.apply_preset(name)
	st.set_value("render_scale", 0.75)
	t.near(get_tree().root.scaling_3d_scale, 0.75, 0.001, "render scale reaches the viewport")
	st.set_value("msaa", 2)
	t.check(get_tree().root.msaa_3d == Viewport.MSAA_4X, "MSAA 4x")
	# A scene's environment and sun follow the settings as they appear.
	st.set_value("ssao", true)
	st.set_value("sun_shadow_distance", 120.0)
	var we := ProtoWorld.environment(self)
	var sun := ProtoWorld.sun(self)
	await get_tree().process_frame
	t.check(we.environment.ssao_enabled, "SSAO on in the new scene's environment")
	t.near(sun.directional_shadow_max_distance, 120.0, 0.01, "sun shadow distance")
	st.set_value("vol_master", 50)
	t.near(AudioServer.get_bus_volume_db(0), linear_to_db(0.5), 0.01, "master volume")
	st.set_value("fake_latency", 80)
	t.near(Net.sim_latency_ms, 80.0, 0.01, "fake latency")
	t.check(t.errors.count == errs, "no errors applying settings: %s" % t.errors.last)
	for tab in st.TABS:
		st.reset_tab(tab)
	t.near(get_tree().root.scaling_3d_scale, 1.0, 0.001, "reset")


func test_friendly_fire_off_lets_bullets_pass_teammates() -> void:
	var st := _settings()
	ProtoWorld.ground(self, 40.0)
	var a := Officer.new()
	var b := Officer.new()
	b.position = Vector3(0, 0, 3)
	add_child(a)
	add_child(b)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := a.get_world_3d().direct_space_state
	var hit := Melee.bullet_ray(space, Vector3(0, 1.2, 0.5), Vector3.BACK, a)
	t.check(hit and hit.collider == b, "friendly fire on: the teammate is hit")
	st.set_value("friendly_fire", false)
	hit = Melee.bullet_ray(space, Vector3(0, 1.2, 0.5), Vector3.BACK, a)
	t.check(not hit or hit.collider != b, "friendly fire off: the bullet passes him")
	st.set_value("friendly_fire", true)


func test_menus_open() -> void:
	var errs: int = t.errors.count
	var menu: Control = load("res://game/ui/main_menu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	menu.call("_show_single")
	menu.call("_open_settings")
	await get_tree().process_frame
	var ss := menu.find_children("*", "SettingsScreen", true, false)
	t.check(ss.size() == 1, "settings screen opens")
	var rows: Dictionary = ss[0].get("_rows")
	t.check(rows.size() > 80, "settings rows: %d" % rows.size())
	(ss[0] as SettingsScreen).close()
	menu.queue_free()
	await get_tree().process_frame
	PauseMenu.toggle(get_tree())
	await get_tree().process_frame
	t.check(PauseMenu.is_open() and get_tree().paused and PlayerInput.blocked, "pause menu pauses and holds the officer still")
	PauseMenu.toggle(get_tree())
	await get_tree().process_frame
	t.check(not PauseMenu.is_open() and not get_tree().paused and not PlayerInput.blocked, "resumed")
	t.check(t.errors.count == errs, "menus without errors: %s" % t.errors.last)
