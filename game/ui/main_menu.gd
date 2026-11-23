extends Control
## The opening menu: Single Player (straight into the game), Online (the
## host / join lobby), Settings, Quit. Test scenes are under Settings > Debug.

var _home: VBoxContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	get_tree().paused = false
	PlayerInput.blocked = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.texture = _backdrop()
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_top", 90)
	margin.add_theme_constant_override("margin_bottom", 60)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	col.add_child(UiTheme.title("THE POPO", 92, UiTheme.ACCENT))
	var sub := UiTheme.title("Answer the call. Try to keep the city up.", 22, UiTheme.DIM)
	col.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size.y = 40
	col.add_child(gap)

	_home = VBoxContainer.new()
	_home.add_theme_constant_override("separation", 14)
	col.add_child(_home)
	BlockState.save_path = City.SAVE_PATH
	var saved := BlockState.peek()
	if not saved.is_empty():
		var when := Time.get_datetime_string_from_unix_time(int(saved.saved) + _utc_offset(), true)
		_home.add_child(UiTheme.big_button("Continue   (city %d, saved %s)" % [saved.seed, when.substr(5, 11)], func(): _play(Scenes.GAME, true)))
	_home.add_child(UiTheme.big_button("Single Player" if saved.is_empty() else "New City", func(): _play(Scenes.GAME)))
	_home.add_child(UiTheme.big_button("First Shift   (how to play)", func(): City.tutorial = true; _play(Scenes.GAME)))
	_home.add_child(UiTheme.big_button("Online", func(): get_tree().change_scene_to_file("res://prototypes/launcher/launcher.tscn")))
	_home.add_child(UiTheme.big_button("Settings", _open_settings))
	_home.add_child(UiTheme.big_button("Quit", func(): get_tree().quit()))

	var foot := UiTheme.title("v%s   ·   test build for friends   ·   a game controller works too" %
		ProjectSettings.get_setting("application/config/version", "dev"), 16, UiTheme.DIM)
	foot.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	foot.position = Vector2(120, get_viewport_rect().size.y - 44)
	add_child(foot)
	var theme_music := MusicDirector.make_player(MusicDirector.MENU, -8.0)
	add_child(theme_music)
	theme_music.play()
	if Net.is_online():
		Net.leave()
	if Net.last_notice != "":
		var note := UiTheme.title(Net.last_notice, 24, UiTheme.ACCENT)
		col.add_child(note)
		col.move_child(note, 2)
		Net.last_notice = ""
	(_home.get_child(0) as Button).grab_focus.call_deferred()


func _open_settings() -> void:
	var s := SettingsScreen.new()
	s.closed.connect(func(): (_home.get_child(_home.get_child_count() - 2) as Button).grab_focus())
	add_child(s)


func _play(path: String, resume := false) -> void:
	City.resume = resume
	get_tree().change_scene_to_file(path)


static func _utc_offset() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## A night-time city skyline, drawn once into a texture.
static func _backdrop() -> Texture2D:
	var w := 480
	var h := 270
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var top := Color("0b1020")
	var bottom := Color("23304d")
	for y in h:
		var c := top.lerp(bottom, float(y) / h)
		for x in w:
			img.set_pixel(x, y, c)
	var rng := RandomNumberGenerator.new()
	rng.seed = 27015
	for layer in 2:
		var x := 0
		var base := Color("161d2e") if layer == 0 else Color("0e1322")
		while x < w:
			var bw := rng.randi_range(14, 40)
			var bh := rng.randi_range(40, 150) if layer == 0 else rng.randi_range(20, 90)
			if x < w * 0.45 and layer == 1:
				bh = int(bh * 0.6)
			for yy in range(h - bh, h):
				for xx in range(x, mini(x + bw, w)):
					img.set_pixel(xx, yy, base)
			# Lit windows.
			for wy in range(h - bh + 4, h - 4, 7):
				for wx in range(x + 3, mini(x + bw - 3, w - 1), 6):
					if rng.randf() < (0.25 if layer == 0 else 0.4):
						var lit := Color("ffd479") if rng.randf() < 0.8 else Color("8fd3ff")
						img.set_pixel(wx, wy, lit.darkened(0.3 if layer == 0 else 0.0))
						img.set_pixel(wx + 1, wy, lit.darkened(0.3 if layer == 0 else 0.0))
			x += bw + rng.randi_range(0, 6)
	# Red and blue light wash low on the right.
	for y in range(h - 90, h):
		for x in range(w - 200, w):
			var k := clampf(1.0 - Vector2(x - (w - 90), y - h).length() / 140.0, 0.0, 1.0) * 0.35
			var c := img.get_pixel(x, y)
			var tint := Color("ff2d3a") if (x / 40) % 2 == 0 else Color("2d6bff")
			img.set_pixel(x, y, c.lerp(tint, k))
	return ImageTexture.create_from_image(img)
