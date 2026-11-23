class_name CityGround
extends Node3D
## Wave 2: the city's roads, pavements, parks and the dock water, laid as a
## few merged meshes (one MultiMesh per kit tile) with plain box colliders,
## instead of thousands of breakable tiles. Roads and pavements are not
## destroyed by anything in the game yet, and this keeps a 370 m city cheap.
##
## Road strips are three modules wide: a lane each side and the centre line
## between. Each stretch between junctions has a zebra crossing half way.

const M := BlockGenerator.M
const N := BlockGenerator.N

var gen: CityGenerator
var _mm := {}    # kit kind -> Array of Transform3D


func build(g: CityGenerator) -> void:
	gen = g
	var e := CityGenerator.city_extent()
	var r90 := Basis(Vector3.UP, PI / 2)
	# Pavement on every lot; parks get grass inside a pavement ring.
	for b in g.blocks:
		var o: Vector3 = b.offset
		for x in N:
			for z in N:
				var park: bool = b.style == "park" and x > 0 and z > 0 and x < N - 1 and z < N - 1
				if park:
					continue
				_tile("pavement", Transform3D(Basis(), o + Vector3((x + 0.5) * M, 0, (z + 0.5) * M)))
		if b.style == "park":
			var grass := _box(Vector3((N - 2) * M, 0.1, (N - 2) * M), o + Vector3(N * M * 0.5, 0.05, N * M * 0.5), Color("5d7a4a"), "dirt")
			grass.name = "Park%d" % b.bx
	# Roads: every module of the grid that is not a lot.
	var cells := int(e / M)
	var lots := {}
	for b in g.blocks:
		var o: Vector3 = b.offset
		lots[Vector2i(int(o.x / M), int(o.z / M))] = true
	for cx in cells:
		for cz in cells:
			# Which road strip(s) this module is in: the module index inside
			# the 15-module pitch (0..2 road, 3..14 lot).
			var mx := cx % (N + BlockGenerator.ROAD)
			var mz := cz % (N + BlockGenerator.ROAD)
			var in_x_road := mz < BlockGenerator.ROAD    # a road running along X
			var in_z_road := mx < BlockGenerator.ROAD
			if not in_x_road and not in_z_road:
				continue
			var pos := Vector3((cx + 0.5) * M, 0, (cz + 0.5) * M)
			var kind := "road"
			var basis := Basis()
			if in_x_road and not in_z_road:
				if mx == BlockGenerator.ROAD + N / 2:
					kind = "road_crossing"
					basis = r90
				elif mz == 1:
					kind = "road_line"
			elif in_z_road and not in_x_road:
				if mz == BlockGenerator.ROAD + N / 2:
					kind = "road_crossing"
				elif mx == 1:
					kind = "road_line"
					basis = r90
			_tile(kind, Transform3D(basis, pos))
	for kind in _mm:
		var piece := KitLibrary.get_piece(kind)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = piece.mesh
		var xfs: Array = _mm[kind]
		mm.instance_count = xfs.size()
		for i in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Ground_" + kind
		mmi.multimesh = mm
		add_child(mmi)
	# Colliders: the road surface under everything, a slab per lot.
	var road := StaticBody3D.new()
	road.name = "RoadSurface"
	road.collision_layer = 1
	road.set_meta("surface", "concrete")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(e, 0.5, e)
	cs.shape = box
	cs.position = Vector3(e * 0.5, -0.25, e * 0.5)
	road.add_child(cs)
	add_child(road)
	for b in g.blocks:
		var o: Vector3 = b.offset
		var lot := StaticBody3D.new()
		lot.collision_layer = 1
		lot.set_meta("surface", "dirt" if b.style == "park" else "concrete")
		var lcs := CollisionShape3D.new()
		var lb := BoxShape3D.new()
		lb.size = Vector3(N * M, 0.15, N * M)
		lcs.shape = lb
		lcs.position = o + Vector3(N * M * 0.5, 0.075, N * M * 0.5)
		lot.add_child(lcs)
		add_child(lot)
	# Grass round the city, and the dock water to the south.
	var outside := _box(Vector3(e + 1600, 1, e + 800), Vector3(e * 0.5, -0.56, (e - 800) * 0.5), Color("4b5a45"), "dirt", false)
	outside.name = "Outskirts"
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(e + 1600, 800)
	water.mesh = plane
	water.material_override = Cel.material(Color("2f5470"), false, 0.02, null, 1.0, true)
	water.position = Vector3(e * 0.5, -1.6, e + 400.0)
	water.name = "Water"
	add_child(water)
	# The quay: a concrete edge with the water below it.
	var quay := _box(Vector3(e + 1600, 3.0, 1.0), Vector3(e * 0.5, -1.5, e + 0.5), Color("8d8a82"), "concrete")
	quay.name = "Quay"
	# The sea bed, so whatever goes in sinks to somewhere.
	var bed := _box(Vector3(e + 1600, 1.0, 800), Vector3(e * 0.5, -6.5, e + 400.0), Color("1d3344"), "dirt", false)
	bed.name = "SeaBed"


func _tile(kind: String, xf: Transform3D) -> void:
	if not _mm.has(kind):
		_mm[kind] = []
	_mm[kind].append(xf)


## A plain cel box with a collider.
func _box(size: Vector3, centre: Vector3, col: Color, surface: String, outline := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("surface", surface)
	body.position = centre
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Cel.material(col, outline, 0.025, null, 1.0, true)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	return body
