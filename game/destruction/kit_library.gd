class_name KitLibrary
extends RefCounted
## Reads the pre-fractured building kit exported by
## tools/blender/build_kit_fractured.py and caches, per piece type:
##   mesh          intact mesh
##   chunks        [{mesh, offset: Vector3, shape: ConvexPolygonShape3D, volume}]
##   aabb          local bounds of the intact piece

const KIT_PATH := "res://assets/models/kit/kit_fractured.glb"

static var _pieces := {}


static func get_piece(kind: String) -> Dictionary:
	if _pieces.is_empty():
		_load()
	return _pieces[kind]


static func kinds() -> Array:
	if _pieces.is_empty():
		_load()
	return _pieces.keys()


static func _load() -> void:
	var root: Node = (load(KIT_PATH) as PackedScene).instantiate()
	var origins := {}
	var nodes: Array = root.find_children("*", "MeshInstance3D", true, false)
	for mi: MeshInstance3D in nodes:
		if not String(mi.name).contains("__"):
			origins[String(mi.name)] = mi.global_transform.origin if mi.is_inside_tree() else mi.transform.origin
			var cel_mesh := _celify(mi.mesh)
			_pieces[String(mi.name)] = {"mesh": cel_mesh, "chunks": [], "aabb": cel_mesh.get_aabb()}
	for mi: MeshInstance3D in nodes:
		var n := String(mi.name)
		if not n.contains("__"):
			continue
		var base := n.get_slice("__", 0)
		var m := _celify(mi.mesh)
		var shape: ConvexPolygonShape3D = m.create_convex_shape(true, false)
		var a := m.get_aabb()
		_pieces[base].chunks.append({
			"mesh": m,
			"offset": mi.transform.origin - origins[base],
			"shape": shape,
			"volume": _hull_volume(m),
			"radius": a.size.length() * 0.5,
		})
	root.free()


## Copy of the mesh with each surface's glTF material swapped for cel shading.
static func _celify(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
		var mat := src.surface_get_material(i)
		var col := (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color(0.7, 0.7, 0.7)
		out.surface_set_material(i, Cel.material(col, true, 0.02))
	return out


static func _hull_volume(m: Mesh) -> float:
	var v := 0.0
	for i in m.get_surface_count():
		var arr := m.surface_get_arrays(i)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			for k in range(0, verts.size(), 3):
				v += verts[k].dot(verts[k + 1].cross(verts[k + 2]))
		else:
			for k in range(0, idx.size(), 3):
				v += verts[idx[k]].dot(verts[idx[k + 1]].cross(verts[idx[k + 2]]))
	return absf(v) / 6.0
