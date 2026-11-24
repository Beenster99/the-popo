extends Node
var t


func test_every_action_is_bound() -> void:
	for a in Controls.KEYS.keys() + Controls.MOUSE.keys():
		var unbound_by_default: bool = Controls.KEYS.get(a, [0]).is_empty()
		t.check(InputMap.has_action(a) and (unbound_by_default or InputMap.action_get_events(a).size() > 0), a)


func test_controller_is_bound() -> void:
	for a in ["move_forward", "aim_left", "aim", "fire", "jump", "stance", "reload", "holster", "cover", "interact", "horn"]:
		var pad := InputMap.action_get_events(a).any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion)
		t.check(pad, "controller binding for " + a)


func test_rebinding_saves_and_reloads() -> void:
	Controls.rebind("punch", Controls.key_event(KEY_T))
	t.check(Controls.describe(Controls.pc_event("punch")) == "T", "rebound to T")
	Controls.register()   # as on the next start
	t.check(Controls.describe(Controls.pc_event("punch")) == "T", "kept after reload")
	Controls.reset_to_defaults()
	t.check(Controls.describe(Controls.pc_event("punch")) == "V", "defaults back")


## Ctrl: tap crouches / stands, hold lies prone, hold while running rolls.
func test_ctrl_stance_key() -> void:
	t.check(Controls.describe(Controls.pc_event("stance")) == "Ctrl", "stance on Ctrl")
	t.check(Controls.describe(Controls.pc_event("ping")) == "Middle mouse", "ping on middle mouse")
	ProtoWorld.ground(self, 40.0)
	var o := Officer.new()
	add_child(o)
	await get_tree().process_frame
	var P := PlayerInput
	# Tap while standing: crouch.
	t.check(P.stance_buttons(true, 10.0, o) == 0, "nothing on the press itself")
	t.check(P.stance_buttons(false, 10.1, o) == P.CROUCH, "tap crouches")
	o._set_state(Officer.S.CROUCH)
	P.stance_buttons(true, 11.0, o)
	t.check(P.stance_buttons(false, 11.1, o) == P.STAND, "tap again stands")
	# Hold while standing still: prone (once), and letting go does nothing more.
	o._set_state(Officer.S.MOVE)
	P.stance_buttons(true, 12.0, o)
	t.check(P.stance_buttons(true, 12.2, o) == 0, "not yet prone")
	t.check(P.stance_buttons(true, 12.35, o) == P.PRONE, "hold goes prone")
	t.check(P.stance_buttons(true, 12.5, o) == 0 and P.stance_buttons(false, 12.6, o) == 0, "only once")
	o._set_state(Officer.S.PRONE)
	P.stance_buttons(true, 13.0, o)
	t.check(P.stance_buttons(false, 13.1, o) == P.STAND, "tap stands up from prone")
	# Hold while running: roll.
	o._set_state(Officer.S.MOVE)
	o.velocity = Vector3(0, 0, 3.6)
	P.stance_buttons(true, 14.0, o)
	t.check(P.stance_buttons(true, 14.15, o) == P.DIVE, "hold while running rolls")
	P.stance_buttons(false, 14.3, o)
	# The officer stands from crouch / prone on STAND.
	o.velocity = Vector3.ZERO
	o._set_state(Officer.S.PRONE)
	o.sim_step({"move": Vector2.ZERO, "buttons": P.STAND, "aim_yaw": 0.0}, 1.0 / 60.0)
	t.check(o.state == Officer.S.MOVE, "officer stands")


func test_ping_reaches_everyone() -> void:
	var n := Pings.history.size()
	Pings.request(Vector3(2, 0, 3))
	t.check(Pings.history.size() == n + 1 and Pings.history[-1][1] == Vector3(2, 0, 3), "ping shown")
	var m := Pings._make_marker(1)
	t.check(m.get_child_count() == 3, "beam, ring and name")
	m.free()


## Key binds screen: controller buttons rebind, save and reload too.
func test_pad_rebinding_saves_and_reloads() -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = JOY_BUTTON_DPAD_UP
	Controls.rebind_pad("kick", ev)
	t.check(Controls.describe_pad(Controls.pad_event("kick"), true) == "D-pad up", "kick on d-pad up")
	var lt := InputEventJoypadMotion.new()
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 0.8
	Controls.rebind_pad("punch", lt)
	Controls.register()
	t.check(Controls.describe_pad(Controls.pad_event("kick"), true) == "D-pad up", "kept after reload")
	t.check(Controls.describe_pad(Controls.pad_event("punch"), true) == "LT", "trigger kept after reload")
	t.check("kick" in Controls.clashes("shout", true), "shout and kick both on d-pad up: a clash")
	Controls.rebind_pad("kick", null)
	Controls.register()
	t.check(Controls.pad_event("kick") == null, "cleared stays cleared")
	Controls.rebind("punch", Controls.key_event(KEY_U))
	Controls.reset_pad()
	t.check(Controls.describe_pad(Controls.pad_event("kick"), true) == "R3", "pad defaults back")
	t.check(Controls.describe(Controls.pc_event("punch")) == "U", "keyboard change kept by a pad reset")
	Controls.reset_keys()
	t.check(Controls.describe(Controls.pc_event("punch")) == "V", "keyboard defaults back")
	Controls.reset_to_defaults()


func test_clashes() -> void:
	Controls.reset_to_defaults()
	for pair in Controls.REBINDABLE:
		t.check(Controls.clashes(pair[0]).is_empty(), "no clash by default (keys): " + pair[0])
		t.check(Controls.clashes(pair[0], true).is_empty(), "no clash by default (pad): " + pair[0])
	Controls.rebind("kick", Controls.key_event(KEY_R))
	t.check(Controls.clashes("kick") == ["reload"], "kick on R clashes with reload")
	Controls.reset_to_defaults()


func test_key_names_follow_the_device() -> void:
	PlayerInput.using_pad = true
	t.check(Controls.key_name("jump") == "A", "pad: A")
	PlayerInput.using_pad = false
	t.check(Controls.key_name("jump") == "Space", "keyboard: Space")


func test_every_rebindable_action_has_a_group_and_a_tip() -> void:
	var grouped := []
	for g in Controls.GROUPS:
		grouped.append_array(g[1])
	for pair in Controls.REBINDABLE:
		t.check(pair[0] in grouped, "in a group: " + pair[0])
		t.check(Controls.TIPS.has(pair[0]), "has a tip: " + pair[0])
