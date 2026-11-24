class_name SettingsScreen
extends Control
## The Settings screen: Graphics, Sound, Gameplay and Debug tabs, built from
## Settings.SCHEMA. Every change applies at once and is saved. Opened from
## the main menu and the pause menu; Back (or Esc) closes it.

signal closed

var _rows := {}         # key -> control, refreshed after presets and resets
var _tabs: TabContainer
var _restart: Button
var _note: Label


const PANEL_WIDTH := 1100.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A centred panel of fixed width, so labels stay next to their controls
	# on wide and 4K screens.
	var centre := func():
		var side := maxi(40, int((size.x - PANEL_WIDTH) / 2.0))
		margin.add_theme_constant_override("margin_left", side)
		margin.add_theme_constant_override("margin_right", side)
	resized.connect(centre)
	centre.call()
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	top.add_child(UiTheme.title("SETTINGS", 34, UiTheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	_restart = Button.new()
	_restart.text = "Restart to switch renderer"
	_restart.pressed.connect(func(): Settings.restart())
	top.add_child(_restart)
	var reset := Button.new()
	reset.text = "Reset this tab"
	reset.pressed.connect(func(): Settings.reset_tab(Settings.TABS[_tabs.current_tab]))
	top.add_child(reset)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size.x = 120
	back.pressed.connect(close)
	top.add_child(back)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tabs)
	for tab in Settings.TABS:
		var scroll := ScrollContainer.new()
		scroll.name = tab
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_tabs.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 30)
		grid.add_theme_constant_override("v_separation", 8)
		scroll.add_child(grid)
		for e in Settings.SCHEMA:
			if e[0] == tab:
				_add_row(grid, e)
	_note = Label.new()
	_note.add_theme_color_override("font_color", UiTheme.DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_note.text = "Changes apply straight away and are saved. Hover an option for more."
	col.add_child(_note)
	Settings.changed.connect(_on_changed)
	_on_changed("")


func close() -> void:
	closed.emit()
	queue_free()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_changed):
		Settings.changed.disconnect(_on_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_launcher") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _add_row(grid: GridContainer, e: Array) -> void:
	var kind: String = e[3]
	if kind == "head":
		var h := UiTheme.title(e[2], 22, UiTheme.ACCENT)
		h.custom_minimum_size.y = 44
		h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		grid.add_child(h)
		grid.add_child(Control.new())
		return
	var l := Label.new()
	l.text = e[2]
	l.custom_minimum_size.x = 420
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	var tip := _tip(e)
	if tip != "":
		l.tooltip_text = tip
	grid.add_child(l)
	var key: String = e[1]
	var c: Control
	match kind:
		"bool":
			var cb := CheckButton.new()
			cb.toggled.connect(func(on): Settings.set_value(key, on))
			c = cb
		"enum":
			var ob := OptionButton.new()
			for o in Settings.options(e):
				ob.add_item(String(o))
			ob.custom_minimum_size.x = 340
			ob.item_selected.connect(func(i): Settings.set_value(key, i))
			c = ob
		"range":
			var h := HBoxContainer.new()
			h.custom_minimum_size.x = 340
			var s := HSlider.new()
			var r: Array = e[5]
			s.min_value = r[0]
			s.max_value = r[1]
			s.step = r[2]
			s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var val := Label.new()
			val.custom_minimum_size.x = 90
			val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			var is_int: bool = typeof(e[4]) == TYPE_INT
			s.value_changed.connect(func(x):
				val.text = _fmt(x, r)
				Settings.set_value(key, int(x) if is_int else x))
			h.add_child(s)
			h.add_child(val)
			h.set_meta("slider", s)
			h.set_meta("value_label", val)
			c = h
		"button":
			var b := Button.new()
			b.text = e[2]
			l.text = ""
			var method: String = e[5]
			b.pressed.connect(func(): call(method, b))
			c = b
	if tip != "":
		c.tooltip_text = tip
	grid.add_child(c)
	_rows[key] = c


## A row's tooltip: its help in SCHEMA, or Settings.TIPS.
static func _tip(e: Array) -> String:
	# Help sits at index 6, or 7 on rows with both options and a spare null.
	for i in range(6, e.size()):
		if e[i] is String:
			return e[i]
	return String(Settings.TIPS.get(e[1], ""))


static func _fmt(x: float, r: Array) -> String:
	var step: float = r[2]
	var txt := str(int(x)) if step >= 1.0 else ("%.2f" % x if step < 0.1 else "%.1f" % x)
	if step < 0.01:
		txt = "%.3f" % x
	return txt + String(r[3])


func _on_changed(_key: String) -> void:
	for key in _rows:
		var c: Control = _rows[key]
		var v = Settings.get_value(key)
		if c is CheckButton:
			(c as CheckButton).set_pressed_no_signal(bool(v))
		elif c is OptionButton:
			(c as OptionButton).select(clampi(int(v), 0, (c as OptionButton).item_count - 1))
		elif c.has_meta("slider"):
			var s: HSlider = c.get_meta("slider")
			s.set_value_no_signal(float(v))
			(c.get_meta("value_label") as Label).text = _fmt(float(v), Settings.entry(key)[5])
	_restart.visible = Settings.needs_restart()


func show_presets(b: Button) -> void:
	var pm := PopupMenu.new()
	for n in Settings.PRESETS:
		pm.add_item(n)
	pm.id_pressed.connect(func(i):
		Settings.apply_preset(Settings.PRESETS.keys()[i])
		_note.text = "Applied the %s preset. Fine-tune anything below." % Settings.PRESETS.keys()[i])
	add_child(pm)
	pm.popup(Rect2i(Vector2i(b.global_position + Vector2(0, b.size.y)), Vector2i(200, 0)))


func open_controls(b: Button) -> void:
	var ks := KeyBindsScreen.new()
	ks.closed.connect(func(): if is_instance_valid(b): b.grab_focus())
	add_child(ks)


func reset_tips(_b: Button) -> void:
	GameTips.reset()
	_note.text = "Every tip will show again (if Tips while playing is on)."


func show_tests(b: Button) -> void:
	var pm := PopupMenu.new()
	for sc in Scenes.TESTS:
		pm.add_item(sc[0])
	pm.id_pressed.connect(func(i):
		close()
		for m in get_tree().root.find_children("*", "PauseMenu", false, false):
			(m as PauseMenu).resume()
		Scenes.load_scene(get_tree(), Scenes.TESTS[i][1]))
	add_child(pm)
	pm.popup(Rect2i(Vector2i(b.global_position + Vector2(0, b.size.y)), Vector2i(420, 0)))
