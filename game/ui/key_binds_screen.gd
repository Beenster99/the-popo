class_name KeyBindsScreen
extends Control
## Key binds (Settings > Gameplay > Change keys..., and the Help screen):
## every action with its keyboard / mouse key on one tab and its controller
## button on the other. Click a binding (or press A on it), then press the
## new key, mouse button or controller button. Clear takes a binding off.
## Two actions on the same key are flagged. Changes are saved straight away
## (Controls, user://controls.cfg).

signal closed

const PANEL_WIDTH := 1180.0
const CLASH := Color("ff9a3c")
## Sticks move and aim on a controller; they aren't rebound here.
const PAD_FIXED := ["move_forward", "move_back", "move_left", "move_right"]

var _tabs: TabContainer
var _hint: Label
## [tab][action] -> {"bind": Button, "note": Label}
var _rows := [{}, {}]
var _waiting := ""
var _waiting_pad := false
var _wait_from := 0
var _return_focus: Control


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
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	top.add_child(UiTheme.title("KEY BINDS", 34, UiTheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var reset := Button.new()
	reset.text = "Reset this tab"
	reset.tooltip_text = "Puts every binding on this tab back to the default. The other tab is left alone."
	reset.pressed.connect(func():
		if _tabs.current_tab == 0:
			Controls.reset_keys()
		else:
			Controls.reset_pad()
		_refresh()
		_hint.text = "Defaults back on the %s tab." % ("keyboard and mouse" if _tabs.current_tab == 0 else "controller"))
	top.add_child(reset)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size.x = 120
	back.tooltip_text = "Back to the settings (Esc). Your changes are already saved."
	back.pressed.connect(close)
	top.add_child(back)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_tabs)
	_tabs.add_child(_make_tab("Keyboard and mouse", false))
	_tabs.add_child(_make_tab("Controller", true))
	_tabs.tab_changed.connect(func(_i): _cancel_wait())
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", UiTheme.DIM)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_hint)
	_refresh()
	if PlayerInput.using_pad:
		_tabs.current_tab = 1
	_focus_first.call_deferred()


func _make_tab(title: String, pad: bool) -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	if pad:
		var fixed := Label.new()
		fixed.text = "Left stick moves (tilt it part way to walk), right stick looks round. Menu (Options) opens the game menu. Xbox names first, PlayStation in brackets."
		fixed.autowrap_mode = TextServer.AUTOWRAP_WORD
		fixed.add_theme_color_override("font_color", UiTheme.DIM)
		box.add_child(fixed)
	for g in Controls.GROUPS:
		var h := UiTheme.title(g[0], 22, UiTheme.ACCENT)
		h.custom_minimum_size.y = 40
		h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		box.add_child(h)
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 6)
		box.add_child(grid)
		for a in g[1]:
			if pad and a in PAD_FIXED:
				continue
			_add_row(grid, a, pad)
	return scroll


func _add_row(grid: GridContainer, action: String, pad: bool) -> void:
	var tip: String = Controls.TIPS.get(action, "")
	var l := Label.new()
	l.text = Controls.action_name(action)
	l.custom_minimum_size.x = 470
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = tip
	grid.add_child(l)
	var b := Button.new()
	b.custom_minimum_size.x = 250
	b.tooltip_text = "%s\n\nClick, then press the new %s." % [tip, "controller button" if pad else "key or mouse button"]
	b.pressed.connect(func(): _start_wait(action, pad))
	grid.add_child(b)
	var clear := Button.new()
	clear.text = "Clear"
	clear.tooltip_text = "Take this binding off, leaving the action with no %s." % ("button" if pad else "key")
	clear.pressed.connect(func():
		_cancel_wait()
		if pad:
			Controls.rebind_pad(action, null)
		else:
			Controls.rebind(action, null)
		_refresh())
	grid.add_child(clear)
	var note := Label.new()
	note.add_theme_color_override("font_color", CLASH)
	note.add_theme_font_size_override("font_size", 15)
	note.custom_minimum_size.x = 260
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	grid.add_child(note)
	_rows[1 if pad else 0][action] = {"bind": b, "note": note}


func _focus_first() -> void:
	var rows: Dictionary = _rows[_tabs.current_tab]
	if not rows.is_empty():
		(rows.values()[0].bind as Button).grab_focus()


func close() -> void:
	closed.emit()
	queue_free()


func _start_wait(action: String, pad: bool) -> void:
	_cancel_wait()
	_waiting = action
	_waiting_pad = pad
	_wait_from = Time.get_ticks_msec()
	var b: Button = _rows[1 if pad else 0][action].bind
	b.text = "press a button..." if pad else "press a key..."
	_return_focus = b
	_hint.text = ("Press the controller button or trigger for \"%s\" (Menu cancels)." if pad else
		"Press the key or mouse button for \"%s\" (Esc cancels).") % Controls.action_name(action)


func _cancel_wait() -> void:
	if _waiting == "":
		return
	_waiting = ""
	_refresh()


func _input(event: InputEvent) -> void:
	if _waiting == "":
		return
	# The click or press that started the wait isn't the new binding.
	if Time.get_ticks_msec() - _wait_from < 150:
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	var got: InputEvent = null
	var cancel := false
	if _waiting_pad:
		if event is InputEventJoypadButton and event.pressed:
			if (event as InputEventJoypadButton).button_index == JOY_BUTTON_START:
				cancel = true
			else:
				got = event
		elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
			var ax := (event as InputEventJoypadMotion).axis
			# Triggers, or a stick pushed hard one way (not the move stick).
			if ax in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]:
				got = event
		elif event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			cancel = true
	else:
		if event is InputEventKey and event.pressed and not event.echo:
			if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
				cancel = true
			else:
				got = event
		elif event is InputEventMouseButton and event.pressed:
			got = event
		elif event is InputEventJoypadButton and event.pressed and (event as InputEventJoypadButton).button_index in [JOY_BUTTON_START, JOY_BUTTON_B]:
			cancel = true
	if got == null and not cancel:
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled()
		return
	get_viewport().set_input_as_handled()
	var action := _waiting
	_waiting = ""
	if got:
		if _waiting_pad:
			Controls.rebind_pad(action, got)
		else:
			Controls.rebind(action, got)
	_refresh()
	if got:
		var cl := Controls.clashes(action, _waiting_pad)
		if cl.is_empty():
			_hint.text = "%s is now on %s." % [Controls.action_name(action), _bind_text(action, _waiting_pad)]
		else:
			_hint.text = "%s is now on %s, which %s also uses. Change one of them, or both happen at once." % [
				Controls.action_name(action), _bind_text(action, _waiting_pad), _names(cl)]
	if is_instance_valid(_return_focus):
		_return_focus.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _waiting != "":
		return
	if event.is_action_pressed("back_to_launcher") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


static func _bind_text(action: String, pad: bool) -> String:
	var ev := Controls.pad_event(action) if pad else Controls.pc_event(action)
	if ev == null:
		return "(tap L3)" if pad and action == "walk" else "(none)"
	return Controls.describe_pad(ev) if pad else Controls.describe(ev)


static func _names(actions: Array) -> String:
	var n: PackedStringArray = []
	for a in actions:
		n.append("\"%s\"" % Controls.action_name(a))
	return " and ".join(n)


func _refresh() -> void:
	_hint.text = "Click a binding (or select it and press A), then press the new key or button. Hover any row to see what it does. Saved straight away."
	for t in 2:
		for a in _rows[t]:
			var r: Dictionary = _rows[t][a]
			(r.bind as Button).text = _bind_text(a, t == 1)
			var cl := Controls.clashes(a, t == 1)
			(r.note as Label).text = "" if cl.is_empty() else "Clashes with " + _names(cl)
