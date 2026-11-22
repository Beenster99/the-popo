extends SceneTree
## Phase 1.5 network check: a host and a client on this machine, in the city
## block. The host knocks a chair across the floor, shoots out a crate,
## starts a fire and sets a car burning; each side writes what it sees.
##   godot --headless --path . -s res://tools/capture/net_check.gd -- host <out.json>
##   godot --headless --path . -s res://tools/capture/net_check.gd -- client <out.json>


func _init() -> void:
	(func(): root.add_child(load("res://tools/capture/net_check_node.gd").new())).call_deferred()
