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
const ROAD := BlockGenerator.ROAD

var gen: CityGenerator
var _mm := {}    # kit kind -> Array of Transform3D


func build(g: CityGenerator) -> void:
	gen = g
	var ex := CityGenerator.extent_x()
	var ez := CityGenerator.extent_z()
	var r90 := Basis(Vector3.UP, PI / 2)
	# Pavement on every lot; parks get grass inside a pavement ring.
	for b in g.blocks:
		var o: Vector3 = b.offset
		var nx := int((b.rect as Rect2).size.x / M)
		var nz := int((b.rect as Rect2).size.y / M)
		for x in nx:
			for z in nz:
				var park: bool = b.style == "park" and x > 0 and z > 0 and x < nx - 1 and z < nz - 1
				if park:
					continue
				_tile("pavement", Transform3D(Basis(), o + Vector3((x + 0.5) * M, 0, (z + 0.5) * M)))
		if b.style == "park":
			var grass := _box(Vector3((nx - 2) * M, 0.1, (nz - 2) * M), o + Vector3(nx * M * 0.5, 0.05, nz * M * 0.5), Color("5d7a4a"), "dirt")
			grass.name = "Park%d" % b.bx
	# Roads: every module that is not a lot. Each road strip is ROAD modules
	# wide; its lane line runs down the middle, and each stretch between
	# junctions has a zebra crossing on the lot's middle module.
	var xs := _strips(0)    # module index -> [road k or -1, offset in the road or lot, lot size]
	var zs := _strips(1)
	for cx in xs.size():
		for cz in zs.size():
			var sx: Array = xs[cx]
			var sz: Array = zs[cz]
			var in_x_road: bool = sz[0] >= 0    # a road running along X
			var in_z_road: bool = sx[0] >= 0
			if not in_x_road and not in_z_road:
				continue
			var pos := Vector3((cx + 0.5) * M, 0, (cz + 0.5) * M)
			var kind := "road"
			var basis := Basis()
			if in_x_road and not in_z_road:
				if sx[1] == int(sx[2]) / 2:
					kind = "road_crossing"
					basis = r90
				elif sz[1] == 1:
					kind = "road_line"
			elif in_z_road and not in_x_road:
				if sz[1] == int(sz[2]) / 2:
					kind = "road_crossing"
				elif sx[1] == 1:
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
	# v0.16.0: 2 m deep (was 0.5) so heavy things pressed into it can't
	# be pushed out of the bottom.
	box.size = Vector3(ex, 2.0, ez)
	cs.shape = box
	cs.position = Vector3(ex * 0.5, -1.0, ez * 0.5)
	road.add_child(cs)
	add_child(road)
	for b in g.blocks:
		var o: Vector3 = b.offset
		var lot := StaticBody3D.new()
		lot.collision_layer = 1
		lot.set_meta("surface", "dirt" if b.style == "park" else "concrete")
		var lcs := CollisionShape3D.new()
		var lb := BoxShape3D.new()
		var sz2: Vector2 = (b.rect as Rect2).size
		# The slab's top is the pavement (0.15 m); it goes 1 m down into the
		# road block below so a heavy prop can't sink through it.
		lb.size = Vector3(sz2.x, 1.15, sz2.y)
		lcs.shape = lb
		lcs.position = o + Vector3(sz2.x * 0.5, 0.15 - 0.575, sz2.y * 0.5)
		lot.add_child(lcs)
		add_child(lot)
	# Grass round the city, and the dock water to the south.
	var outside := _box(Vector3(ex + 1600, 1, ez + 800), Vector3(ex * 0.5, -0.56, (ez - 800) * 0.5), Color("4b5a45"), "dirt", false)
	outside.name = "Outskirts"
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ex + 1600, 800)
	water.mesh = plane
	water.material_override = Cel.material(Color("2f5470"), false, 0.02, null, 1.0, true)
	water.position = Vector3(ex * 0.5, -1.6, ez + 400.0)
	water.name = "Water"
	add_child(water)
	# The quay: a concrete edge with the water below it.
	var quay := _box(Vector3(ex + 1600, 3.0, 1.0), Vector3(ex * 0.5, -1.5, ez + 0.5), Color("8d8a82"), "concrete")
	quay.name = "Quay"
	# The sea bed, so whatever goes in sinks to somewhere.
	var bed := _box(Vector3(ex + 1600, 1.0, 800), Vector3(ex * 0.5, -6.5, ez + 400.0), Color("1d3344"), "dirt", false)
	bed.name = "SeaBed"


## Along one axis, for each module: [road index or -1, the module's place
## in its road (0..ROAD-1) or lot, and the size of the lot it's beside].
static func _strips(axis: int) -> Array:
	var sizes: Array = CityGenerator.cols if axis == 0 else CityGenerator.rows
	var out: Array = []
	for k in CityGenerator.GRID + 1:
		var lot: int = int(sizes[k]) if k < CityGenerator.GRID else int(sizes[k - 1])
		for r in ROAD:
			out.append([k, r, lot])
		if k < CityGenerator.GRID:
			for m in int(sizes[k]):
				out.append([-1, m, int(sizes[k])])
	return out


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
