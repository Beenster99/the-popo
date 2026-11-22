extends SceneTree
## Phase 1.7 drop-in check: three games on this machine.
##   host:  starts the city block alone, blows a hole in a building, smashes
##          props and wrecks a car, then waits.
##   late:  joins once the damage is done; must see the same block.
##   other: joins too, and is told when the host quits.
## Each writes what it saw to its JSON file.
##   godot --headless --path . -s res://tools/capture/late_join.gd -- host|late|other <out.json>


func _init() -> void:
	(func(): root.add_child(load("res://tools/capture/late_join_node.gd").new())).call_deferred()
