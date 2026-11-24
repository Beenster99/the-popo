extends Node
## Registers every input action in code, so bindings live in one place:
## keyboard and mouse defaults, game controller (Xbox layout) defaults, and
## the player's own keyboard, mouse and controller changes from the Key
## binds screen (Settings > Gameplay), saved in user://controls.cfg.

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
	"shout": [KEY_Y],             # shouted orders; hold: prisoner stay / follow
	"interact": [KEY_F],
	"drag": [KEY_G],              # hold: drag a downed teammate
	"horn": [KEY_H],
	"weapon_1": [KEY_1],
	"weapon_2": [KEY_2],
	"grenade_next": [KEY_3],      # smoke, CS gas, flashbang
	"throw": [KEY_Q],             # throw the picked grenade at the crosshair
	"cam_rotate_left": [],
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
	"grenade_next": [JOY_BUTTON_DPAD_LEFT],
	"throw": [JOY_BUTTON_DPAD_RIGHT],
	"shout": [JOY_BUTTON_DPAD_UP],
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
## Actions the player can rebind on the Key binds screen, with their names.
const REBINDABLE := [
	["move_forward", "Move forward"], ["move_back", "Move back"], ["move_left", "Move left"],
	["move_right", "Move right"], ["sprint", "Sprint"], ["walk", "Run / walk (toggle; controller: tap L3)"], ["jump", "Jump / vault / climb"],
	["stance", "Tap crouch / stand, hold prone, hold while running roll"],
	["crouch", "Crouch"], ["prone", "Lie prone"], ["dive", "Roll (slide when sprinting)"],
	["cover", "Take cover (with a direction: run to the next cover)"], ["reload", "Reload"],
	["holster", "Holster / draw"], ["torch", "Torch on / off"], ["punch", "Punch"], ["kick", "Kick"], ["shout", "Shout orders (hold: prisoner stay / follow)"], ["interact", "Use / revive (hold)"], ["drag", "Drag a downed teammate (hold)"],
	["aim", "Aim / peek from cover"], ["fire", "Fire"], ["ping", "Ping a spot for everyone"], ["horn", "Car horn"], ["handbrake", "Handbrake"],
	["throw", "Throw grenade"], ["grenade_next", "Pick grenade: smoke, CS gas, flashbang"],
	["weapon_1", "Pistol"], ["weapon_2", "Charge / second gear slot"],
	["cam_zoom_in", "Camera closer"], ["cam_zoom_out", "Camera further out"],
]
## The Key binds and Help screens list the actions in these groups.
const GROUPS := [
	["On foot", ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "jump", "stance", "crouch", "prone", "dive", "cover"]],
	["Guns and fighting", ["aim", "fire", "reload", "holster", "weapon_1", "weapon_2", "throw", "grenade_next", "punch", "kick"]],
	["Police work", ["shout", "interact", "drag", "torch", "ping"]],
	["In a car", ["horn", "handbrake"]],
	["Camera", ["cam_zoom_in", "cam_zoom_out"]],
]
## A longer word on each action, shown as its tooltip.
const TIPS := {
	"move_forward": "Moves you the way the camera looks. In a car: accelerate.",
	"move_back": "Backs off. In a car: brake, then reverse.",
	"move_left": "Steps left (in a car: steer left).",
	"move_right": "Steps right (in a car: steer right).",
	"sprint": "Hold to sprint. A leg wound stops you sprinting. On the rope: slide down fast.",
	"walk": "Switches between walking and running. Walking is quieter and steadier; the gun shakes less.",
	"jump": "Jump. Running at a low wall, car bonnet or smashed window vaults it; at a ledge you climb up. On the rope: kick off and swing in through the window.",
	"stance": "Tap to crouch, tap again to stand. Hold to lie prone. Hold while running to roll (slide when sprinting). In a car: move to the next seat.",
	"crouch": "Crouch only (unbound by default; the stance key does this too).",
	"prone": "Lie flat. Hard to hit, slow to move.",
	"dive": "Roll when moving, slide when sprinting.",
	"cover": "Put your back to the nearest wall, car or ledge. In cover, hold a direction and press it again to run to the next cover that way.",
	"reload": "Reload. When you're down: respawn back at the start once the wait is over.",
	"holster": "Draw or put away your pistol. People get nervous round a drawn gun. Holding a picked-up gun: drop it.",
	"torch": "Your torch on and off. In a police car: lights, then lights and wail, then yelp, then off.",
	"punch": "Punch. While sprinting: a shoulder barge. A punch makes most suspects give up.",
	"kick": "Kick. Kicks locked doors in.",
	"shout": "Shout an order at whoever you're facing: they might obey, or not. Next to your cuffed prisoner: stay put / with me.",
	"interact": "Use whatever is in front of you: doors, cars, lifts, the armoury, guns on the floor. Hold to cuff, revive or give first aid.",
	"drag": "Hold next to a downed teammate to drag them by the collar, walking backwards. Let go to drop them.",
	"aim": "Hold to aim down the sights. In cover: peek out. A passenger leans out of the window.",
	"fire": "Fire where the dot is. Moving or just after raising the gun, shots go wide. In cover without aiming: blind fire.",
	"ping": "Puts a marker on a spot for every officer to see.",
	"horn": "Car horn (the driver).",
	"handbrake": "Handbrake: swings the tail out.",
	"throw": "Throw the picked grenade at the dot in the middle of the screen.",
	"grenade_next": "Picks which grenade you throw: smoke, CS gas or flashbang.",
	"weapon_1": "Back to your pistol.",
	"weapon_2": "Your second gear slot: breach charge or C4 when your loadout has them (aim and fire to stick one on).",
	"cam_zoom_in": "Moves the camera in closer behind you.",
	"cam_zoom_out": "Moves the camera further out.",
}
## Pairs that may share a key: one is a hold and one a tap, or one only
## works in a car. Anything else sharing a key is flagged as a clash.
const SHARE_OK := [["holster", "drag"], ["jump", "handbrake"], ["holster", "horn"], ["drag", "horn"]]
const CAR_ONLY := ["horn", "handbrake"]
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
	if not InputMap.has_action(action):
		return null
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventMouseButton:
			return ev
	return null


## The controller button, trigger or stick direction bound to an action.
static func pad_event(action: String) -> InputEvent:
	if not InputMap.has_action(action):
		return null
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
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
			MOUSE_BUTTON_WHEEL_UP: return "Wheel up"
			MOUSE_BUTTON_WHEEL_DOWN: return "Wheel down"
			MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
			MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
		return "Mouse %d" % (ev as InputEventMouseButton).button_index
	if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
		return describe_pad(ev)
	return "-"


## Xbox names, with PlayStation in brackets unless short is asked for.
const PAD_NAMES := {
	JOY_BUTTON_A: ["A", "Cross"], JOY_BUTTON_B: ["B", "Circle"], JOY_BUTTON_X: ["X", "Square"],
	JOY_BUTTON_Y: ["Y", "Triangle"], JOY_BUTTON_BACK: ["View", "Share"], JOY_BUTTON_GUIDE: ["Xbox button", "PS"],
	JOY_BUTTON_START: ["Menu", "Options"], JOY_BUTTON_LEFT_STICK: ["L3", "L3"], JOY_BUTTON_RIGHT_STICK: ["R3", "R3"],
	JOY_BUTTON_LEFT_SHOULDER: ["LB", "L1"], JOY_BUTTON_RIGHT_SHOULDER: ["RB", "R1"],
	JOY_BUTTON_DPAD_UP: ["D-pad up", "D-pad up"], JOY_BUTTON_DPAD_DOWN: ["D-pad down", "D-pad down"],
	JOY_BUTTON_DPAD_LEFT: ["D-pad left", "D-pad left"], JOY_BUTTON_DPAD_RIGHT: ["D-pad right", "D-pad right"],
	JOY_BUTTON_MISC1: ["Share", "Mic"], JOY_BUTTON_TOUCHPAD: ["Touchpad", "Touchpad"],
	JOY_BUTTON_PADDLE1: ["Paddle 1", "Paddle 1"], JOY_BUTTON_PADDLE2: ["Paddle 2", "Paddle 2"],
	JOY_BUTTON_PADDLE3: ["Paddle 3", "Paddle 3"], JOY_BUTTON_PADDLE4: ["Paddle 4", "Paddle 4"],
}


static func describe_pad(ev: InputEvent, short := false) -> String:
	if ev is InputEventJoypadButton:
		var n: Array = PAD_NAMES.get((ev as InputEventJoypadButton).button_index, ["Button %d" % (ev as InputEventJoypadButton).button_index, ""])
		if short or n[1] == "" or n[1] == n[0]:
			return n[0]
		return "%s (%s)" % [n[0], n[1]]
	if ev is InputEventJoypadMotion:
		var m := ev as InputEventJoypadMotion
		var neg := m.axis_value < 0.0
		match m.axis:
			JOY_AXIS_TRIGGER_LEFT: return "LT" if short else "LT (L2)"
			JOY_AXIS_TRIGGER_RIGHT: return "RT" if short else "RT (R2)"
			JOY_AXIS_LEFT_X: return "Left stick left" if neg else "Left stick right"
			JOY_AXIS_LEFT_Y: return "Left stick up" if neg else "Left stick down"
			JOY_AXIS_RIGHT_X: return "Right stick left" if neg else "Right stick right"
			JOY_AXIS_RIGHT_Y: return "Right stick up" if neg else "Right stick down"
		return "Axis %d%s" % [m.axis, "-" if neg else "+"]
	return "-"


## The name of the key for an action as the player plays now: the
## controller button when the last thing touched was a controller, the
## keyboard key or mouse button otherwise. For on-screen prompts.
static func key_name(action: String) -> String:
	if PlayerInput.using_pad:
		var pe := pad_event(action)
		if pe:
			return describe_pad(pe, true)
	return describe(pc_event(action))


## The name an action has on the Key binds screen.
static func action_name(action: String) -> String:
	for pair in REBINDABLE:
		if pair[0] == action:
			return pair[1]
	return action.capitalize()


## "Shift sprint   Space jump ..." for on-screen help, from the live bindings.
static func help(actions: Array) -> String:
	var parts: PackedStringArray = []
	for a in actions:
		for pair in REBINDABLE:
			if pair[0] == a:
				parts.append("%s %s" % [key_name(a), String(pair[1]).to_lower()])
	return "   ".join(parts)


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventKey and b is InputEventKey:
		return (a as InputEventKey).physical_keycode == (b as InputEventKey).physical_keycode
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return (a as InputEventMouseButton).button_index == (b as InputEventMouseButton).button_index
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return (a as InputEventJoypadMotion).axis == (b as InputEventJoypadMotion).axis \
			and signf((a as InputEventJoypadMotion).axis_value) == signf((b as InputEventJoypadMotion).axis_value)
	return false


static func _share_ok(a: String, b: String) -> bool:
	if (a in CAR_ONLY) != (b in CAR_ONLY):
		return true
	for p in SHARE_OK:
		if (p[0] == a and p[1] == b) or (p[0] == b and p[1] == a):
			return true
	return false


## Other actions on the same key (pad: on the same controller button) that
## would get in each other's way.
static func clashes(action: String, pad := false) -> Array:
	var ev := pad_event(action) if pad else pc_event(action)
	var out := []
	if ev == null:
		return out
	for pair in REBINDABLE:
		var other: String = pair[0]
		if other == action or _share_ok(action, other):
			continue
		if _same(ev, pad_event(other) if pad else pc_event(other)):
			out.append(other)
	return out


## Replaces the keyboard/mouse binding of an action and saves it.
static func rebind(action: String, ev: InputEvent) -> void:
	var old := pc_event(action)
	if old:
		InputMap.action_erase_event(action, old)
	if ev != null:
		var clean: InputEvent = key_event((ev as InputEventKey).physical_keycode) if ev is InputEventKey else mouse_event((ev as InputEventMouseButton).button_index)
		InputMap.action_add_event(action, clean)
	_save()


## Replaces the controller binding of an action and saves it. ev null
## leaves the action with no controller binding.
static func rebind_pad(action: String, ev: InputEvent) -> void:
	var old := pad_event(action)
	if old:
		InputMap.action_erase_event(action, old)
	if ev != null:
		InputMap.action_add_event(action, _clean_pad(ev))
	_save()


static func _clean_pad(ev: InputEvent) -> InputEvent:
	if ev is InputEventJoypadButton:
		var b := InputEventJoypadButton.new()
		b.button_index = (ev as InputEventJoypadButton).button_index
		b.device = -1
		return b
	var m := InputEventJoypadMotion.new()
	m.axis = (ev as InputEventJoypadMotion).axis
	m.axis_value = 1.0 if (ev as InputEventJoypadMotion).axis_value > 0.0 else -1.0
	m.device = -1
	return m


static func reset_to_defaults() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	register()


## Puts back the default keyboard and mouse keys, keeping controller changes.
static func reset_keys() -> void:
	_reset_part(false)


## Puts back the default controller buttons, keeping keyboard changes.
static func reset_pad() -> void:
	_reset_part(true)


static func _reset_part(pad: bool) -> void:
	var keep := {}
	for pair in REBINDABLE:
		keep[pair[0]] = pc_event(pair[0]) if pad else pad_event(pair[0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	register()
	for a in keep:
		if pad:
			rebind(a, keep[a])
		else:
			rebind_pad(a, keep[a])
	_save()


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("meta", "version", SAVE_VERSION)
	for pair in REBINDABLE:
		var ev := pc_event(pair[0])
		if ev is InputEventKey:
			cfg.set_value("keys", pair[0], "key:%d" % (ev as InputEventKey).physical_keycode)
		elif ev is InputEventMouseButton:
			cfg.set_value("keys", pair[0], "mouse:%d" % (ev as InputEventMouseButton).button_index)
		else:
			cfg.set_value("keys", pair[0], "none")
		var pe := pad_event(pair[0])
		if pe is InputEventJoypadButton:
			cfg.set_value("pad", pair[0], "button:%d" % (pe as InputEventJoypadButton).button_index)
		elif pe is InputEventJoypadMotion:
			cfg.set_value("pad", pair[0], "axis:%d:%d" % [(pe as InputEventJoypadMotion).axis, signi(roundi((pe as InputEventJoypadMotion).axis_value))])
		else:
			cfg.set_value("pad", pair[0], "none")
	cfg.save(SAVE_PATH)


static func _load_overrides() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if int(cfg.get_value("meta", "version", 1)) != SAVE_VERSION:
		return
	if cfg.has_section("keys"):
		for action in cfg.get_section_keys("keys"):
			if not InputMap.has_action(action):
				continue
			var parts: PackedStringArray = String(cfg.get_value("keys", action)).split(":")
			if parts[0] != "none" and parts.size() != 2:
				continue
			var old := pc_event(action)
			if old:
				InputMap.action_erase_event(action, old)
			if parts[0] == "key":
				InputMap.action_add_event(action, key_event(int(parts[1]) as Key))
			elif parts[0] == "mouse":
				InputMap.action_add_event(action, mouse_event(int(parts[1]) as MouseButton))
	if cfg.has_section("pad"):
		for action in cfg.get_section_keys("pad"):
			if not InputMap.has_action(action):
				continue
			var parts: PackedStringArray = String(cfg.get_value("pad", action)).split(":")
			var ev: InputEvent = null
			if parts[0] == "button" and parts.size() == 2:
				var b := InputEventJoypadButton.new()
				b.button_index = int(parts[1]) as JoyButton
				ev = b
			elif parts[0] == "axis" and parts.size() == 3:
				var m := InputEventJoypadMotion.new()
				m.axis = int(parts[1]) as JoyAxis
				m.axis_value = float(parts[2])
				ev = m
			elif parts[0] != "none":
				continue
			var old := pad_event(action)
			if old:
				InputMap.action_erase_event(action, old)
			if ev:
				InputMap.action_add_event(action, _clean_pad(ev))


## Whichever the player last touched, controller or keyboard and mouse,
## decides which key names the on-screen prompts show.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		PlayerInput.using_pad = true
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.5:
		PlayerInput.using_pad = true
	elif (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed):
		PlayerInput.using_pad = false


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
		if ArmouryScreen.is_open():
			return   # it closes itself
		PauseMenu.toggle(tree)
