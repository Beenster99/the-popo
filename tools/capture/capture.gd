extends SceneTree
## Renders screenshots of the prototypes for the Wave 0 report.
## Needs a real renderer (not --headless). In a container without a GPU:
##   source /opt/lavapipe/use-lavapipe.sh   # or any Vulkan driver
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --path . -s res://tools/capture/capture.gd -- <shot> <out.png>

func _init() -> void:
	(func(): root.add_child(load("res://tools/capture/capture_node.gd").new())).call_deferred()
