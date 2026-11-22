extends Node
## Registers every input action in code so project.godot stays readable and
## bindings live in one place. Mouse and keyboard only.

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"jump": [KEY_SPACE],          # jump, mantle, vault, climb
	"crouch": [KEY_C],
	"prone": [KEY_Z],
	"dive": [KEY_CTRL],           # roll when moving, slide when sprinting
	"cover": [KEY_V],
	"punch": [KEY_G],
	"kick": [KEY_H],
	"interact": [KEY_F],          # enter or leave a car
	"cam_rotate_left": [KEY_Q],
	"cam_rotate_right": [KEY_E],
	"handbrake": [KEY_SPACE],
	"toggle_net_overlay": [KEY_F3],
	"toggle_day_night": [KEY_N],
	"back_to_launcher": [KEY_ESCAPE],
}
const MOUSE := {
	"fire": [MOUSE_BUTTON_LEFT],
	"aim": [MOUSE_BUTTON_RIGHT],
	"cam_zoom_in": [MOUSE_BUTTON_WHEEL_UP],
	"cam_zoom_out": [MOUSE_BUTTON_WHEEL_DOWN],
}


func _enter_tree() -> void:
	register()


static func register() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	for action in MOUSE:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for b in MOUSE[action]:
			var ev := InputEventMouseButton.new()
			ev.button_index = b
			InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_launcher"):
		var tree := get_tree()
		if tree.current_scene and tree.current_scene.scene_file_path != "res://prototypes/launcher/launcher.tscn":
			Net.leave()
			tree.change_scene_to_file("res://prototypes/launcher/launcher.tscn")
