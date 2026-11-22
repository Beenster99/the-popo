extends Node
var t  # the runner


func test_jolt_is_the_physics_engine() -> void:
	t.check(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics", "Jolt must be enabled")


func test_blender_prop_imports_with_collision() -> void:
	var scene: PackedScene = load("res://assets/models/props/dumpster.glb")
	t.check(scene != null, "dumpster.glb should import")
	var inst := scene.instantiate()
	var bodies := inst.find_children("*", "StaticBody3D", true, false)
	t.check(bodies.size() == 1, "one static body from the -convcolonly hint, got %d" % bodies.size())
	var shapes := inst.find_children("*", "CollisionShape3D", true, false)
	t.check(shapes.size() >= 1 and shapes[0].shape is ConvexPolygonShape3D, "convex collider")
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	t.check(meshes.size() >= 3, "visible parts present")
	inst.free()


func test_a_crate_lands_on_the_prop() -> void:
	var d: Node3D = load("res://assets/models/props/dumpster.glb").instantiate()
	add_child(d)
	var crate := ProtoWorld.rigid_box(self, Vector3.ONE * 0.4, Vector3(0, 3, 0), Color.WHITE, 2.0)
	for i in 120:
		await get_tree().physics_frame
	t.check(crate.position.y > 1.2 and crate.position.y < 1.6, "crate should rest on the lid, y=%f" % crate.position.y)
