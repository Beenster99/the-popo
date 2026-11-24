class_name PauseMenu
extends CanvasLayer
## Esc (Start on a controller) in a game: Resume, Help, Settings, Key binds,
## Leave.
## Playing alone, the game pauses underneath; online it keeps running and
## your officer just stands still.

static var _open: PauseMenu

var _box: VBoxContainer


static func toggle(tree: SceneTree) -> void:
	if is_instance_valid(_open):
		_open.resume()
	else:
		var m := PauseMenu.new()
		tree.root.add_child(m)


static func is_open() -> bool:
	return is_instance_valid(_open)


func _ready() -> void:
	_open = self
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerInput.blocked = true
	if not Net.is_online():
		get_tree().paused = true
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 12)
	panel.add_child(_box)
	_box.add_child(UiTheme.title("PAUSED" if not Net.is_online() else "MENU (the game carries on)", 30, UiTheme.ACCENT))
	var resume_b := UiTheme.big_button("Resume", resume)
	resume_b.tooltip_text = "Back to the game (Esc)."
	_box.add_child(resume_b)
	var help := UiTheme.big_button("Help", func(): _open_sub(root, HelpScreen.new(), 2))
	help.tooltip_text = "How to play: controls, fighting, arrests, driving, jobs, kit and playing online."
	_box.add_child(help)
	var settings := UiTheme.big_button("Settings", func(): _open_sub(root, SettingsScreen.new(), 3))
	settings.tooltip_text = "Graphics, sound, gameplay and key binds. Changes apply straight away."
	_box.add_child(settings)
	var keys := UiTheme.big_button("Key binds", func(): _open_sub(root, KeyBindsScreen.new(), 4))
	keys.tooltip_text = "Change any key, mouse button or controller button."
	_box.add_child(keys)
	var leave_b := UiTheme.big_button("Leave to main menu", leave)
	leave_b.tooltip_text = "Back to the title screen. The city is saved as you go. Online, the host leaving ends the game for everyone."
	_box.add_child(leave_b)
	(_box.get_child(1) as Button).grab_focus.call_deferred()


## Opens Help, Settings or Key binds over the menu; focus comes back to
## the button at index when it closes.
func _open_sub(root: Control, screen: Control, index: int) -> void:
	screen.connect("closed", func():
		_box.visible = true
		(_box.get_child(index) as Button).grab_focus())
	_box.visible = false
	root.add_child(screen)


func resume() -> void:
	get_tree().paused = false
	PlayerInput.blocked = false
	_open = null
	queue_free()


func leave() -> void:
	resume()
	Net.leave()
	get_tree().change_scene_to_file("res://game/ui/main_menu.tscn")


func _unhandled_input(event: InputEvent) -> void:
	if not _box.visible:
		return
	if event.is_action_pressed("back_to_launcher") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume()
