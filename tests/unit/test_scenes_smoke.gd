extends Node
## Every prototype in the launcher loads and runs for a second without errors.
var t


func test_every_prototype_runs() -> void:
	var protos: Array = Scenes.TESTS
	for p in protos:
		var path: String = p[1]
		if not ResourceLoader.exists(path):
			continue  # not built yet
		var errs_before: int = t.errors.count
		var scene: PackedScene = load(path)
		t.check(scene != null, "loads: " + path)
		if scene == null:
			continue
		var inst := scene.instantiate()
		add_child(inst)
		for i in 60:
			await get_tree().physics_frame
		inst.queue_free()
		await get_tree().process_frame
		t.check(t.errors.count == errs_before, "%s ran with %d error(s): %s" % [path, t.errors.count - errs_before, t.errors.last])
