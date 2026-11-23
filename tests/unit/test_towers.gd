extends Node
## v0.7.0: downtown towers up to ten storeys, with a lift shaft beside the stairs.
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_downtown_has_towers_with_a_shaft() -> void:
	var g := CityGenerator.generate_city(4242)
	var towers: Array = g.buildings.filter(func(b): return b.get("lift", false))
	var tallest := 0
	for b in towers:
		tallest = maxi(tallest, b.storeys)
	print("    %d towers, tallest %d storeys" % [towers.size(), tallest])
	t.check(towers.size() >= 3, "a few towers downtown (%d)" % towers.size())
	t.check(tallest >= 9, "the tallest is nine or ten storeys (%d)" % tallest)
	var bad := 0
	for b in towers:
		t.check(b.storeys >= CityStyles.TOWER_STOREYS.x and b.storeys <= CityStyles.TOWER_STOREYS.y and b.type == "tower", "tower size and type")
		if bad > 0:
			break
		# No floor slab in the shaft below the roof; a doorway on every storey.
		var sr := CityStyles.shaft_rect(b)
		var centre: Vector3 = b.origin + b.u * sr.get_center().x + b.v * sr.get_center().y
		var slabs := 0
		var doors := 0
		for p in g.pieces:
			var o: Vector3 = p.xform.origin
			if p.kind == "slab" and Vector2(o.x - centre.x, o.z - centre.z).length() < 0.5:
				slabs += 1
			if p.kind == "int_wall_door" and Vector2(o.x - centre.x, o.z - centre.z).length() < 2.2 and Vector2(o.x - centre.x, o.z - centre.z).length() > 1.8:
				doors += 1
		if slabs != 0 or doors < b.storeys:
			bad += 1
			print("    shaft: %d slabs, %d doorways for %d storeys" % [slabs, doors, b.storeys])
	t.check(bad == 0, "every shaft is open top to bottom with a doorway per floor")
