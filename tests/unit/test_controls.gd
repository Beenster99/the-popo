extends Node
var t


func test_every_action_is_bound() -> void:
	for a in Controls.KEYS.keys() + Controls.MOUSE.keys():
		t.check(InputMap.has_action(a) and InputMap.action_get_events(a).size() > 0, a)
