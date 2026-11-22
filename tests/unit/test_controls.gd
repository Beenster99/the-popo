extends Node
var t


func test_every_action_is_bound() -> void:
	for a in Controls.KEYS.keys() + Controls.MOUSE.keys():
		t.check(InputMap.has_action(a) and InputMap.action_get_events(a).size() > 0, a)


func test_controller_is_bound() -> void:
	for a in ["move_forward", "aim_left", "aim", "fire", "jump", "crouch", "dive", "cover", "interact", "horn"]:
		var pad := InputMap.action_get_events(a).any(func(e): return e is InputEventJoypadButton or e is InputEventJoypadMotion)
		t.check(pad, "controller binding for " + a)


func test_rebinding_saves_and_reloads() -> void:
	Controls.rebind("punch", Controls.key_event(KEY_T))
	t.check(Controls.describe(Controls.pc_event("punch")) == "T", "rebound to T")
	Controls.register()   # as on the next start
	t.check(Controls.describe(Controls.pc_event("punch")) == "T", "kept after reload")
	Controls.reset_to_defaults()
	t.check(Controls.describe(Controls.pc_event("punch")) == "V", "defaults back")
