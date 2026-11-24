extends Node
## v0.25 (beenster, 2026-11-24: "add another 50 furniture models and
## increase the quality of all of them again"): every prop kind has a
## Blender model that fits its collision box, and the new pieces turn up in
## the rooms they belong in.
var t


func test_every_kind_has_a_model_that_fits() -> void:
	var missing: Array = []
	var loose: Array = []
	for kind in PropWorld.KINDS:
		var m := PropWorld.model_of(kind)
		if m == null:
			missing.append(kind)
			continue
		var s: Vector3 = PropWorld.KINDS[kind].size
		var box := Vector3(-s.x * 2.0, s.y, -s.x * 2.0) if s.x < 0.0 else s
		# It stands on the floor where the box does, centred on it; bits may
		# stick out a little (a monitor, a headboard, an aerial's arms).
		var a := m.get_aabb()
		var over := a.size - box
		var mid := a.get_center()
		if absf(a.position.y + box.y * 0.5) > 0.03 or over.x > 0.7 or over.y > 0.5 or over.z > 0.7 \
				or Vector2(mid.x, mid.z).length() > 0.3:
			loose.append("%s %s in %s" % [kind, a, box])
	t.check(PropWorld.KINDS.size() >= 90, "%d prop kinds (40 + 50 new)" % PropWorld.KINDS.size())
	t.check(missing.is_empty(), "every kind has a model (missing: %s)" % [missing])
	t.check(loose.is_empty(), "every model stands on the floor in its collision box: %s" % [loose])


func test_kind_mesh_is_the_model() -> void:
	var m := PropWorld._kind_mesh("sofa")
	t.check(m.get_faces().size() / 3 > 100, "the sofa is a proper model (%d triangles)" % (m.get_faces().size() / 3))
	PropWorld._kind_mesh("container")
	var firsts: Array = PropWorld._kind_first["container"]
	t.check(firsts.has(true), "the container's paint is marked so the docks can recolour it")


func test_new_furniture_in_the_city() -> void:
	City.next_seed = 4242
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	for i in 20:
		await get_tree().physics_frame
	var seen := {}
	for id in s.props.props:
		seen[s.props.props[id].kind] = true
	var new_kinds := ["coffee_table", "wardrobe", "toilet", "office_chair", "stove", "steel_shelving", "basin", "nightstand"]
	var found := new_kinds.filter(func(k): return seen.has(k))
	t.check(found.size() >= 6, "new furniture is in the buildings: %s" % [found])
	print("    %d kinds placed in this city" % seen.size())
	s.queue_free()
	await get_tree().process_frame
