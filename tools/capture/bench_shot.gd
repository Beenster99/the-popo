extends Node
## Screenshots of the armoury's gun bench, every pistol bare and fully fitted,
## then the armoury screen. Run as a scene so the autoloads are there:
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . res://tools/capture/bench_shot.tscn -- <out_dir>

var root: Window


func _ready() -> void:
	root = get_tree().root
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var b := GunBench.new()
	b.custom_minimum_size = Vector2(1200, 800)
	c.add_child(b)
	var all := (1 << Armoury.EXT_MAG) | (1 << Armoury.COMPENSATOR) | (1 << Armoury.MATCH_BARREL) | (1 << Armoury.SPEED_LOAD) | (1 << GunBench.TORCH)
	for p in Armoury.PISTOLS.size():
		for fitted in [0, all]:
			b.show_gun(p, fitted)
			b.set("_yaw", 0.0 if fitted == 0 else -0.7)
			b.set("_idle", 0.0)
			for i in 8:
				await get_tree().process_frame
			var img := root.get_texture().get_image()
			img.save_png("%s/bench_p%d_%s.png" % [out, p, "full" if fitted else "bare"])
	# The whole armoury screen, on the Bench tab, with two upgrades bought.
	c.queue_free()
	Armoury.owned = 1 | (1 << Armoury.EXT_MAG) | (1 << Armoury.COMPENSATOR)
	ArmouryScreen.open(get_tree(), null, Callable())
	await get_tree().process_frame
	var s: ArmouryScreen = root.get_children().filter(func(n): return n is ArmouryScreen)[0]
	s.set("_cat", Armoury.Cat.UPGRADE)
	s.call("_fill")
	s.set("_look_pistol", 2)
	s.set("_try", Armoury.MATCH_BARREL)
	s.call("_show_bench")
	for i in 10:
		await get_tree().process_frame
	root.get_texture().get_image().save_png("%s/armoury_screen.png" % out)
	get_tree().quit()
