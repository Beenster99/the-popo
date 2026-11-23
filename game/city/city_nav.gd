class_name CityNav
extends BlockNav
## Wave 2: where people can walk, for the whole city, one region per block.
##
## Baking a 370 m city in one go would stall the game, so each block (its lot
## and half of the roads round it) is baked on its own in the background,
## nearest the officers first. The regions meet on the road centre lines and
## the navigation map joins them, so a suspect can run from one block into
## the next. The geometry comes straight from the destruction world's intact
## pieces and the ground slabs (no scene parsing on the main thread).

const MARGIN := CityGenerator.ROAD_W * 0.5

var world: DestructionWorld
var city: CityGenerator
var _regions := {}       # block index -> NavigationRegion3D
var _pending: Array = [] # block indices still to bake, nearest first
var _baking := -1
var _focus := Vector3.ZERO


func bake_city(w: DestructionWorld, g: CityGenerator, focus: Vector3) -> void:
	world = w
	city = g
	_focus = focus
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, CELL)
	NavigationServer3D.map_set_cell_height(map, CELL_H)
	_pending = range(g.blocks.size())
	_sort_pending()


## Bake the blocks nearest here first (the host's officers move about).
func set_focus(p: Vector3) -> void:
	_focus = p


func block_ready(k: int) -> bool:
	return _regions.has(k)


func baked_count() -> int:
	return _regions.size()


func _sort_pending() -> void:
	var f := _focus
	_pending.sort_custom(func(a, b):
		return (city.blocks[a].rect as Rect2).get_center().distance_squared_to(Vector2(f.x, f.z)) \
			< (city.blocks[b].rect as Rect2).get_center().distance_squared_to(Vector2(f.x, f.z)))


func _physics_process(_delta: float) -> void:
	if city == null:
		return
	if _baking < 0 and not _pending.is_empty():
		_sort_pending()
		_start(_pending.pop_front())
	if not ready_to_use and not _regions.is_empty() and is_inside_tree():
		var map := get_world_3d().navigation_map
		if NavigationServer3D.map_get_iteration_id(map) > _map_iteration:
			ready_to_use = true


func _start(k: int) -> void:
	_baking = k
	var blk: Dictionary = city.blocks[k]
	var r: Rect2 = blk.rect
	var nm := NavigationMesh.new()
	nm.agent_radius = CELL
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 45.0
	nm.cell_size = CELL
	nm.cell_height = CELL_H
	nm.filter_baking_aabb = AABB(Vector3(r.position.x - MARGIN, -1.0, r.position.y - MARGIN),
		Vector3(r.size.x + MARGIN * 2.0, 36.0, r.size.y + MARGIN * 2.0))
	var src := NavigationMeshSourceGeometryData3D.new()
	# The road under it all and the lot's pavement slab.
	_add_box(src, Vector3(r.get_center().x, -0.25, r.get_center().y), Vector3(r.size.x + MARGIN * 2.0 + 2.0, 0.5, r.size.y + MARGIN * 2.0 + 2.0))
	_add_box(src, Vector3(r.get_center().x, 0.075, r.get_center().y), Vector3(r.size.x, 0.15, r.size.y))
	# The block's pieces as they stand now.
	for id in range(blk.pieces_from + 1, blk.pieces_to + 1):
		var p: Dictionary = world.pieces.get(id, {})
		if p.is_empty() or p.state != "intact":
			continue
		if String(p.kind).begins_with("glass"):
			continue
		src.add_faces(_faces(p.kind), p.xform)
	# Neighbouring blocks' pieces that stand within the margin (lamp posts
	# on the far kerb and so on) don't matter: the roads are open.
	NavigationServer3D.bake_from_source_geometry_data_async(nm, src, _baked.bind(k, nm))
	_map_iteration = NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)


func _baked(k: int, nm: NavigationMesh) -> void:
	_finish.call_deferred(k, nm)


func _finish(k: int, nm: NavigationMesh) -> void:
	if not is_inside_tree():
		return
	var region := NavigationRegion3D.new()
	region.name = "Nav%d" % k
	region.navigation_mesh = nm
	add_child(region)
	_regions[k] = region
	if navigation_mesh == null:
		navigation_mesh = nm
		region_ref = region
	_baking = -1


var region_ref: NavigationRegion3D


func _add_box(src: NavigationMeshSourceGeometryData3D, centre: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var c: Array = []
	for i in 8:
		c.append(Vector3(h.x if i & 1 else -h.x, h.y if i & 2 else -h.y, h.z if i & 4 else -h.z))
	var f := PackedVector3Array()
	for q in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]:
		f.append_array([c[q[0]], c[q[1]], c[q[2]], c[q[0]], c[q[2]], c[q[3]]])
	src.add_faces(f, Transform3D(Basis(), centre))


## A kit piece's triangles, read once from its mesh and kept (handing the
## mesh itself to the baker reads it back from the GPU every time).
static var _face_cache := {}

static func _faces(kind: String) -> PackedVector3Array:
	if not _face_cache.has(kind):
		_face_cache[kind] = (KitLibrary.get_piece(kind).mesh as Mesh).get_faces()
	return _face_cache[kind]
