extends SceneTree
## Headless destruction stress benchmark:
##   godot --headless --fixed-fps 60 --path . -s res://tests/bench/destruction_bench.gd
## (--fixed-fps makes each frame one physics step with no waiting, so the
## time per frame is the real cost of the step.)
## For each wall count, shatters every wall at once and records, over 4 s,
## the worst and average physics step time, the peak number of awake synced
## chunks, and the peak snapshot size and bandwidth at 20 snapshots a second.

func _init() -> void:
	(func(): root.add_child(load("res://tests/bench/destruction_bench_node.gd").new())).call_deferred()
