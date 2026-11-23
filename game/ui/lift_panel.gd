class_name LiftPanel
extends CanvasLayer
## v0.9.0: the buttons inside a lift. Click one, press its number (0 for
## G), or pick one with the pad and press A. Esc / B closes it.

static var _open: LiftPanel

var lifts: Lifts
var index := 0


static func open(tree: SceneTree, l: Lifts, li: int) -> void:
	if is_instance_valid(_open):
		return
	var p := LiftPanel.new()
	p.lifts = l
	p.index = li
	tree.root.add_child(p)


static func is_open() -> bool:
	return is_instance_valid(_open)


func _ready() -> void:
	_open = self
	layer = 70
	PlayerInput.blocked = true
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(UiTheme.title("LIFT", 26, UiTheme.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	var L: Dictionary = lifts.lifts[index]
	var here := Lifts.floor_of(L)
	var first: Button = null
	# Top floor first, like the panel in a real lift.
	var order: Array = range(int(L.floors))
	order.reverse()
	for f in order:
		var b := Button.new()
		b.text = Lifts.floor_name(f)
		b.custom_minimum_size = Vector2(90, 54)
		b.disabled = f == here
		var fl: int = f
		b.pressed.connect(func(): _go(fl))
		grid.add_child(b)
		if first == null and not b.disabled:
			first = b
	box.add_child(UiTheme.title("Number keys too (0 = G). Esc / B to close.", 14, UiTheme.DIM))
	if first:
		first.grab_focus.call_deferred()


func _go(f: int) -> void:
	lifts.ask(index, f)
	close_panel()


func close_panel() -> void:
	PlayerInput.blocked = false
	_open = null
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_launcher") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()
		return
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode >= KEY_0 and k.keycode <= KEY_9:
		var f := int(k.keycode - KEY_0)
		if f < int(lifts.lifts[index].floors):
			get_viewport().set_input_as_handled()
			_go(f)
