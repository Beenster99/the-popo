extends Node
## Registers every input action in code, so bindings live in one place:
## keyboard and mouse defaults, game controller (Xbox layout) defaults, and
## the player's own keyboard/mouse changes from the launcher's Controls
## screen, saved in user://controls.cfg.

const KEYS := {
	"move_forward": [KEY_W],
	"move_back": [KEY_S],
	"move_left": [KEY_A],
	"move_right": [KEY_D],
	"sprint": [KEY_SHIFT],
	"walk": [KEY_ALT],            # toggle walking pace
	"jump": [KEY_SPACE],          # jump, mantle, vault, climb
	"stance": [KEY_CTRL],         # tap crouch / stand, hold prone, hold while running roll
	"crouch": [],
	"prone": [KEY_Z],
	"dive": [KEY_X],              # roll when moving, slide when sprinting
	"cover": [KEY_C],
	"reload": [KEY_R],
	"holster": [KEY_H],
	"torch": [KEY_T],
	"punch": [KEY_V],
	"kick": [KEY_B],
	"interact": [KEY_F],
	"drag": [KEY_G],              # hold: drag a downed teammate
	"horn": [KEY_H],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
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
	"ping": [MOUSE_BUTTON_MIDDLE],
	"cam_zoom_in": [MOUSE_BUTTON_WHEEL_UP],
	"cam_zoom_out": [MOUSE_BUTTON_WHEEL_DOWN],
}
## Game controller buttons (Xbox names; PlayStation in brackets).
const PAD_BUTTONS := {
	"jump": [JOY_BUTTON_A],                 # A (Cross)
	"handbrake": [JOY_BUTTON_A],
	"stance": [JOY_BUTTON_B],               # B (Circle): tap crouch, hold prone, hold running roll
	"reload": [JOY_BUTTON_X],               # X (Square)
	"holster": [JOY_BUTTON_Y],              # Y (Triangle)
	"drag": [JOY_BUTTON_Y],                 # held next to a downed teammate
	"horn": [JOY_BUTTON_Y],
	"torch": [JOY_BUTTON_DPAD_DOWN],
	"cover": [JOY_BUTTON_LEFT_SHOULDER],    # LB (L1)
	"punch": [JOY_BUTTON_RIGHT_SHOULDER],   # RB (R1)
	"kick": [JOY_BUTTON_RIGHT_STICK],       # R3
	"sprint": [JOY_BUTTON_LEFT_STICK],      # L3
	"interact": [JOY_BUTTON_BACK],          # View (Share)
	"ping": [JOY_BUTTON_TOUCHPAD],          # (touchpad)
	"cam_rotate_left": [JOY_BUTTON_DPAD_LEFT],
	"cam_rotate_right": [JOY_BUTTON_DPAD_RIGHT],
	"cam_zoom_in": [JOY_BUTTON_DPAD_UP],
	"cam_zoom_out": [JOY_BUTTON_MISC1],
	"back_to_launcher": [JOY_BUTTON_START],
}
## Game controller sticks and triggers: [axis, direction].
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"aim_left": [JOY_AXIS_RIGHT_X, -1.0],
	"aim_right": [JOY_AXIS_RIGHT_X, 1.0],
	"aim_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"aim_down": [JOY_AXIS_RIGHT_Y, 1.0],
	"aim": [JOY_AXIS_TRIGGER_LEFT, 1.0],    # LT (L2)
	"fire": [JOY_AXIS_TRIGGER_RIGHT, 1.0],  # RT (R2)
}
## Actions the player can rebind on the Controls screen, with their names.
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"],
	["move_right", "Move right"], ["sprint", "Sprint"], ["walk", "Walk / run (toggle)"], ["jump", "Jump / vault / climb"],
	["stance", "Tap crouch / stand, hold prone, hold while running roll"],
	["crouch", "Crouch"], ["prone", "Lie prone"], ["dive", "Roll (slide when sprinting)"],
	["cover", "Take cover (with a direction: run to the next cover)"], ["reload", "Reload"],
	["holster", "Holster / draw"], ["torch", "Torch on / off"], ["punch", "Punch"], ["kick", "Kick"], ["interact", "Use / revive (hold)"], ["drag", "Drag a downed teammate (hold)"],
	["aim", "Aim / peek from cover"], ["fire", "Fire"], ["ping", "Ping a spot for everyone"], ["horn", "Car horn"], ["handbrake", "Handbrake"],
	["cam_rotate_left", "Rotate camera left"], ["cam_rotate_right", "Rotate camera right"],
]
const SAVE_PATH := "user://controls.cfg"
## Bumped when the defaults change in a way that clashes with old saved
## changes (v0.1.2 moved roll off Ctrl, v0.2.1 moved cover to C for reload
## on R), so old files are ignored.
const SAVE_VERSION := 3


func _enter_tree() -> void:
	register()


static func register() -> void:
	for action in KEYS.keys() + MOUSE.keys() + PAD_BUTTONS.keys() + PAD_AXES.keys():
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
	for action in KEYS:
		for k in KEYS[action]:
			InputMap.action_add_event(action, key_event(k))
	for action in MOUSE:
		for b in MOUSE[action]:
			InputMap.action_add_event(action, mouse_event(b))
	for action in PAD_BUTTONS:
		for b in PAD_BUTTONS[action]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			ev.device = -1
			InputMap.action_add_event(action, ev)
	for action in PAD_AXES:
		var ev := InputEventJoypadMotion.new()
		ev.axis = PAD_AXES[action][0]
		ev.axis_value = PAD_AXES[action][1]
		ev.device = -1
		InputMap.action_add_event(action, ev)
	_load_overrides()


static func key_event(k: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = k
	return ev


static func mouse_event(b: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = b
	return ev


## The keyboard or mouse event bound to an action (the one shown and rebound).
static func pc_event(action: String) -> InputEvent:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return ev
	return null


static func describe(ev: InputEvent) -> String:
	if ev is InputEventKey:
		return OS.get_keycode_string((ev as InputEventKey).physical_keycode)
	if ev is InputEventMouseButton:
		match (ev as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT: return "Left mouse"
			MOUSE_BUTTON_RIGHT: return "Right mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle mouse"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % (ev as InputEventMouseButton).button_index
	return "-"


## "Shift sprint   Space jump ..." for on-screen help, from the live bindings.
static func help(actions: Array) -> String:
	var parts: PackedStringArray = []
	for a in actions:
		for pair in REBINDABLE:
			if pair[0] == a:
				parts.append("%s %s" % [describe(pc_event(a)), String(pair[1]).to_lower()])
	return "   ".join(parts)


## Replaces the keyboard/mouse binding of an action and saves it.
static func rebind(action: String, ev: InputEvent) -> void:
	var old := pc_event(action)
	if old:
		InputMap.action_erase_event(action, old)
	var clean: InputEvent = key_event((ev as InputEventKey).physical_keycode) if ev is InputEventKey else mouse_event((ev as InputEventMouseButton).button_index)
	InputMap.action_add_event(action, clean)
	_save()


static func reset_to_defaults() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	register()


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	for pair in REBINDABLE:
		var ev := pc_event(pair[0])
		if ev is InputEventKey:
			cfg.set_value("keys", pair[0], "key:%d" % (ev as InputEventKey).physical_keycode)
		elif ev is InputEventMouseButton:
			cfg.set_value("keys", pair[0], "mouse:%d" % (ev as InputEventMouseButton).button_index)
	cfg.save(SAVE_PATH)


static func _load_overrides() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK or not cfg.has_section("keys"):
		return
	if int(cfg.get_value("meta", "version", 1)) != SAVE_VERSION:
		return
	for action in cfg.get_section_keys("keys"):
		if not InputMap.has_action(action):
			continue
		var parts: PackedStringArray = String(cfg.get_value("keys", action)).split(":")
		if parts.size() != 2:
			continue
		var old := pc_event(action)
		if old:
			InputMap.action_erase_event(action, old)
		if parts[0] == "key":
			InputMap.action_add_event(action, key_event(int(parts[1]) as Key))
		else:
			InputMap.action_add_event(action, mouse_event(int(parts[1]) as MouseButton))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_launcher"):
		var tree := get_tree()
		var path: String = tree.current_scene.scene_file_path if tree.current_scene else ""
		if path == "res://game/ui/main_menu.tscn":
			return
		if path == "res://prototypes/launcher/launcher.tscn":
			Net.leave()
			tree.change_scene_to_file("res://game/ui/main_menu.tscn")
			return
		PauseMenu.toggle(tree)
