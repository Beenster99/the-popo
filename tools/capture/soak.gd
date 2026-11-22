extends SceneTree
## Phase 1.7 soak test: the Wave 1 gate, run by bots. Three games on this
## machine play one block for a set time (20 minutes by default): calls come
## in and get dealt with, a building gets blown apart, props smashed, cars
## wrecked, everyone runs about shooting, and one friend drops out half way
## and comes back. Every minute the host calls a checkpoint and all three
## write down what they see, so any desync shows.
##   godot --headless --path . -s res://tools/capture/soak.gd -- host <out.json> [minutes]
##   godot --headless --path . -s res://tools/capture/soak.gd -- a <out.json>
##   godot --headless --path . -s res://tools/capture/soak.gd -- b <out.json>


func _init() -> void:
	(func(): root.add_child(load("res://tools/capture/soak_node.gd").new())).call_deferred()
