extends SceneTree
## Pixel-art look test: the same city shots for the normal look and the
## pixel mock-ups (run once at full size and once at a low window size).
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --resolution 1280x720 --fixed-fps 30 --path . -s res://tools/capture/pixel_shot.gd -- <shot> <out.png>
## shots: street, shootout, night, inside

func _init() -> void:
	(func(): root.add_child(load("res://tools/capture/pixel_shot_node.gd").new())).call_deferred()
