class_name BlockNav
extends Node3D
## Phase 1.4: where people can walk in a city block, for suspects that run
## and hide. Baked once at load (host only) from the block's static
## colliders: pavements, roads, rooms, doorways and stairs. Doors that are
## shut and walls block it; the mesh is not rebaked when things break.

const CELL := 0.25
const CELL_H := 0.1

var ready_to_use := false
var navigation_mesh: NavigationMesh
var region: NavigationRegion3D
var _map_iteration := -1


## Bakes from every static collider under root, inside the block's extent.
func bake_from(root: Node) -> void:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.agent_radius = CELL          # doorways stay open
	nm.agent_height = 1.7
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 45.0
	nm.cell_size = CELL
	nm.cell_height = CELL_H
	var e := BlockGenerator.extent()
	var lo := -BlockGenerator.ROAD * BlockGenerator.M - 1.0
	nm.filter_baking_aabb = AABB(Vector3(lo, -1.0, lo), Vector3(e + 2.0, 14.0, e + 2.0))
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, root)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var map := get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, CELL)
	NavigationServer3D.map_set_cell_height(map, CELL_H)
	navigation_mesh = nm
	# A fresh region with its mesh already set (assigning a mesh to a region
	# that is already in the tree did not reach the map).
	if region:
		region.queue_free()
	region = NavigationRegion3D.new()
	region.navigation_mesh = nm
	add_child(region)
	_map_iteration = NavigationServer3D.map_get_iteration_id(map)


func _physics_process(_delta: float) -> void:
	if not ready_to_use and navigation_mesh and is_inside_tree():
		# The map picks up the region a physics step or two later.
		var it := NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)
		if it > _map_iteration and NavigationServer3D.map_get_regions(get_world_3d().navigation_map).size() > 0 \
				and NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, Vector3(20, 0, -6)) != Vector3.ZERO:
			ready_to_use = true


func path(from: Vector3, to: Vector3) -> PackedVector3Array:
	if not ready_to_use:
		return PackedVector3Array()
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map, from, to, true)


## The nearest walkable point.
func closest(p: Vector3) -> Vector3:
	if not ready_to_use:
		return p
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, p)


## Can someone walk from a to b (the path ends close to b)?
func reaches(a: Vector3, b: Vector3) -> bool:
	var p := path(a, b)
	return p.size() > 0 and p[p.size() - 1].distance_to(b) < 0.8
