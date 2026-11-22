extends SceneTree
## Two-process network test, driven by tests/net/run_net_test.sh.
##   godot --headless -s res://tests/net/net_probe.gd -- host <port> <rtt_ms> <loss>
##   godot --headless -s res://tests/net/net_probe.gd -- client <port> <rtt_ms> <loss>
## The client walks +X for 2 s then stops. Both sides print the client pawn's
## final position as "RESULT x z"; the shell script checks they agree.

func _init() -> void:
	# Autoloads are not visible to this script at compile time, so the real
	# probe lives in a Node script loaded at runtime.
	(func(): root.add_child(load("res://tests/net/probe_node.gd").new())).call_deferred()
