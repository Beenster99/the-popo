extends Node
## Screenshots of the Help, Key binds and Settings screens, the main menu
## and an in-game tip. Run as a scene so the autoloads are there:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . res://tools/capture/ui_shot.tscn -- <out_dir>

var root: Window


func _ready() -> void:
	root = get_tree().root
	_run.call_deferred()


func _shot(out: String, name: String) -> void:
	for i in 6:
		await get_tree().process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var menu: Control = load("res://game/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	await _shot(out, "main_menu")
	menu.queue_free()
	var h := HelpScreen.new()
	root.add_child(h)
	await _shot(out, "help_controls")
	for i in [2, 4]:
		h.call("_show", i)
		await _shot(out, "help_%d" % i)
	h.queue_free()
	var k := KeyBindsScreen.new()
	root.add_child(k)
	Controls.rebind("kick", Controls.key_event(KEY_R))
	k.call("_refresh")
	await _shot(out, "keybinds_keys")
	Controls.reset_to_defaults()
	k.get("_tabs").current_tab = 1
	k.call("_refresh")
	await _shot(out, "keybinds_pad")
	k.queue_free()
	var s := SettingsScreen.new()
	root.add_child(s)
	s.get("_tabs").current_tab = 2
	await _shot(out, "settings_gameplay")
	s.queue_free()
	var tips := GameTips.new()
	root.add_child(tips)
	tips.want("driver")
	tips.set("_gap", 0.0)
	await get_tree().process_frame
	tips.set("_t", 5.0)
	await _shot(out, "tip")
	GameTips.reset()
	get_tree().quit()
