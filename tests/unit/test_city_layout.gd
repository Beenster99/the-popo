extends Node
## v0.10.0: city blocks of different sizes, so the streets aren't an even grid.
var t


func test_blocks_vary_in_size_and_fit_together() -> void:
	var g := CityGenerator.generate_city(4242)
	var widths := {}
	for c in CityGenerator.cols:
		widths[c] = true
	for r in CityGenerator.rows:
		widths[r] = true
	print("    columns %s, rows %s, city %.0f x %.0f m" % [CityGenerator.cols, CityGenerator.rows, CityGenerator.extent_x(), CityGenerator.extent_z()])
	t.check(widths.size() >= 4, "at least four different lot sizes (%d)" % widths.size())
	t.check(CityGenerator.extent_x() < 480.0 and CityGenerator.extent_z() < 480.0, "the city stays under 480 m (net positions)")
	t.check(CityGenerator.cols[CityGenerator.STATION.x] == 12 and CityGenerator.rows[CityGenerator.STATION.y] == 12, "the station's lot is the standard size")
	var bad_lots := 0
	var bad_buildings := 0
	var bad_lookup := 0
	for k in g.blocks.size():
		var blk: Dictionary = g.blocks[k]
		var r: Rect2 = blk.rect
		for k2 in range(k + 1, g.blocks.size()):
			if r.grow(-0.01).intersects((g.blocks[k2].rect as Rect2).grow(-0.01)):
				bad_lots += 1
		for road in CityGenerator.roads():
			if r.grow(-0.01).intersects((road.rect as Rect2).grow(-0.01)):
				bad_lots += 1
		for bi in range(blk.buildings_from, blk.buildings_to):
			var bb: AABB = g.buildings[bi].bounds
			if not r.grow(0.5).encloses(Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z).grow(-0.4)):
				bad_buildings += 1
		var c := CityGenerator.block_at(Vector3(r.get_center().x, 0, r.get_center().y))
		if c != Vector2i(blk.bx, blk.bz):
			bad_lookup += 1
	t.check(bad_lots == 0, "lots don't overlap each other or the roads (%d)" % bad_lots)
	t.check(bad_buildings == 0, "every building sits on its own lot (%d)" % bad_buildings)
	t.check(bad_lookup == 0, "block_at finds each block (%d wrong)" % bad_lookup)
	var j := CityGenerator.junction(3, 2)
	var on := 0
	for road in CityGenerator.roads():
		if (road.rect as Rect2).has_point(Vector2(j.x, j.z)):
			on += 1
	t.check(on == 2, "a junction is where two roads cross")
	var g2 := CityGenerator.generate_city(4242)
	t.check(g2.pieces.size() == g.pieces.size() and g2.fingerprint() == g.fingerprint(), "same seed, same city")
	CityGenerator.generate_city(777)
	var other: Array = CityGenerator.cols.duplicate()
	CityGenerator.generate_city(4242)
	t.check(other != CityGenerator.cols, "a different seed, different streets")
