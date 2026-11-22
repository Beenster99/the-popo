extends SceneTree
## godot --headless -s res://tests/net/car_probe.gd -- host|client <port> <rtt_ms> <loss>

func _init() -> void:
	(func(): root.add_child(load("res://tests/net/car_probe_node.gd").new())).call_deferred()
