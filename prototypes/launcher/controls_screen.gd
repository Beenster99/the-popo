extends PanelContainer
## Controls screen: shows every keyboard/mouse binding and lets the player
## change it (click a binding, then press the new key or mouse button).
## Changes are saved and used from then on. Controller buttons are listed too.

var _waiting := ""
var _buttons := {}
var _hint: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var col := VBoxContainer.new()
	margin.add_child(col)
	var title := Label.new()
	title.text = "Controls"
	title.add_theme_font_size_override("font_size", 28)
	col.add_child(title)
	_hint = Label.new()
	_hint.text = "Click a binding, then press the key or mouse button you want."
	col.add_child(_hint)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 40)
	col.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	scroll.add_child(grid)
	for pair in Controls.REBINDABLE:
		var l := Label.new()
		l.text = pair[1]
		grid.add_child(l)
		var b := Button.new()
		b.custom_minimum_size.x = 160
		b.pressed.connect(func(): _start_wait(pair[0]))
		grid.add_child(b)
		_buttons[pair[0]] = b
	var pad := Label.new()
	pad.text = """Game controller (Xbox names, PlayStation in brackets)
Left stick  move        Right stick  aim
LT (L2)  aim            RT (R2)  fire
A (Cross)  jump / vault / climb, handbrake
B (Circle)  crouch      X (Square)  roll / slide
Y (Triangle)  prone, car horn
LB (L1)  cover          RB (R1)  punch
L3  sprint              R3  kick
View (Share)  use / enter car
D-pad left/right  rotate camera
D-pad up/down  zoom
Start  back to the launcher"""
	row.add_child(pad)
	var bottom := HBoxContainer.new()
	col.add_child(bottom)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.pressed.connect(func():
		Controls.reset_to_defaults()
		_refresh())
	bottom.add_child(reset)
	var close := Button.new()
	close.text = "Done"
	close.pressed.connect(queue_free)
	bottom.add_child(close)
	_refresh()


func _start_wait(action: String) -> void:
	_waiting = action
	_buttons[action].text = "press a key..."
	_hint.text = "Press the new key or mouse button (Esc cancels)."


func _input(event: InputEvent) -> void:
	if _waiting == "":
		return
	var ok := (event is InputEventKey and event.pressed and not event.echo) or (event is InputEventMouseButton and event.pressed)
	if not ok:
		return
	get_viewport().set_input_as_handled()
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		_waiting = ""
		_refresh()
		return
	Controls.rebind(_waiting, event)
	_waiting = ""
	_refresh()


func _refresh() -> void:
	_hint.text = "Click a binding, then press the key or mouse button you want."
	for a in _buttons:
		_buttons[a].text = Controls.describe(Controls.pc_event(a))
