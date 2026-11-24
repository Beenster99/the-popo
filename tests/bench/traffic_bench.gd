extends SceneTree
## Headless traffic soak: how often AI cars get stuck, and on what.
##   godot --headless --fixed-fps 60 --path . -s res://tests/bench/traffic_bench.gd [-- minutes seed]

func _init() -> void:
	(func(): root.add_child(load("res://tests/bench/traffic_bench_node.gd").new())).call_deferred()
