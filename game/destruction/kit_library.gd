class_name KitLibrary
extends RefCounted
## Reads the pre-fractured building kit exported by
## tools/blender/build_kit_fractured.py and caches, per piece type:
##   mesh          intact mesh
##   chunks        [{mesh, offset: Vector3, shape: ConvexPolygonShape3D, volume}]
##   aabb          local bounds of the intact piece
##   surfaces      the glTF material name of each surface (kit_wall, kit_glass...)
##
## Glass is drawn see-through, and the ground pieces (road, pavement, paint)
## without outlines so the street does not show a tile grid.

const KIT_PATH := "res://assets/models/kit/kit_fractured.glb"

static var _pieces := {}


## Phase 1.7: how finely things break (Settings > Graphics > Debris detail):
## 0 the kit's own chunks, 1 big ones cut once, 2 most cut up to twice, 3 up
## to three times. The host picks it for everyone, since chunk numbers must
## match on every machine.
static var detail := 2
const DETAIL_CUTS := [0, 1, 2, 3]
const DETAIL_MIN_VOLUME := [0.0, 0.04, 0.012, 0.004]
static var _split := {}   # "kind|detail" -> chunks


## The piece: mesh, aabb, surfaces, "solid" (the kit's own chunks, for the
## intact piece's collision) and "chunks" (what it breaks into at the
## current detail).
static func get_piece(kind: String) -> Dictionary:
	if _pieces.is_empty():
		_load()
	var p: Dictionary = _pieces[kind]
	var key := "%s|%d" % [kind, detail]
	if not _split.has(key):
		var out := []
		var d := clampi(detail, 0, 3)
		# A chunk's index is part of its net id, below RELEASED_BIT (63): if a
		# piece would break into more, cut it less.
		for cuts in range(DETAIL_CUTS[d], -1, -1):
			out = []
			for i in (p.solid as Array).size():
				var ch: Dictionary = p.solid[i]
				if cuts == 0 or kind.begins_with("glass") or ch.volume < DETAIL_MIN_VOLUME[d] * 2.0:
					out.append(ch)
				else:
					out.append_array(ChunkSplit.split(ch, cuts, hash(key) + i * 7919, DETAIL_MIN_VOLUME[d]))
			if out.size() <= 63:
				break
		_split[key] = out
	p.chunks = _split[key]
	return p


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
			_pieces[String(mi.name)] = {"mesh": cel_mesh, "chunks": [], "solid": [], "aabb": cel_mesh.get_aabb(), "surfaces": surface_names(mi.mesh)}
	for mi: MeshInstance3D in nodes:
		var n := String(mi.name)
		if not n.contains("__"):
			continue
		var base := n.get_slice("__", 0)
		var m := _celify(mi.mesh)
		var shape: ConvexPolygonShape3D = m.create_convex_shape(true, false)
		var a := m.get_aabb()
		_pieces[base].solid.append({
			"mesh": m,
			"offset": mi.transform.origin - origins[base],
			"shape": shape,
			"volume": _hull_volume(m),
			"radius": a.size.length() * 0.5,
			"surfaces": surface_names(mi.mesh),
		})
	root.free()
	_thin_stairs()


## v0.24.0: a flight of stairs is thin treads, not solid blocks down to the
## floor. The kit's steps were columns standing on the floor, so in a building
## of three or more storeys the flight above sat on the flight below and left
## no headroom: nobody (officers or suspects) could get past the first floor.
const STAIR_THICK := 0.45
const STAIR_RUN := 0.22


static func _thin_stairs() -> void:
	if not _pieces.has("stairs"):
		return
	var p: Dictionary = _pieces.stairs
	p.mesh = _thin(p.mesh, (p.aabb as AABB).position.z)
	p.aabb = (p.mesh as Mesh).get_aabb()
	for ch: Dictionary in p.solid:
		var m := _thin(ch.mesh, INF)
		ch.mesh = m
		ch.shape = m.create_convex_shape(true, false)
		ch.volume = _hull_volume(m)
		ch.radius = m.get_aabb().size.length() * 0.5


## Raises every step's underside to STAIR_THICK below its tread. run0 is the
## low end of the flight along z for the whole piece (steps STAIR_RUN apart),
## or INF for one step on its own.
static func _thin(src: ArrayMesh, run0: float) -> ArrayMesh:
	var surf: Array = []
	var tops := {}
	for si in src.get_surface_count():
		var arr := src.surface_get_arrays(si)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(verts.size())
			for k in verts.size():
				idx[k] = k
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var tu := PackedVector2Array()
		var tv := PackedVector3Array()
		var tn := PackedVector3Array()
		var step := PackedInt32Array()
		for k in range(0, idx.size(), 3):
			var a := verts[idx[k]]
			var b := verts[idx[k + 1]]
			var c := verts[idx[k + 2]]
			var n := (b - a).cross(c - a).normalized()
			var i := 0
			if run0 != INF:
				# Nudge the centre inwards so a riser between two steps counts
				# for the step it belongs to.
				var cz := (a.z + b.z + c.z) / 3.0 - n.z * 0.01
				i = floori((cz - run0) / STAIR_RUN)
			tops[i] = maxf(tops.get(i, -INF), maxf(a.y, maxf(b.y, c.y)))
			for v in [idx[k], idx[k + 1], idx[k + 2]]:
				tv.append(verts[v])
				tn.append(norms[v] if not norms.is_empty() else n)
				if not uvs.is_empty():
					tu.append(uvs[v])
				step.append(i)
		surf.append([tv, tn, step, src.surface_get_material(si), tu])
	var out := ArrayMesh.new()
	for s in surf:
		var tv: PackedVector3Array = s[0]
		for k in tv.size():
			var floor_y: float = float(tops[s[2][k]]) - STAIR_THICK
			if tv[k].y < floor_y:
				tv[k].y = floor_y
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = tv
		arr[Mesh.ARRAY_NORMAL] = s[1]
		if not (s[4] as PackedVector2Array).is_empty():
			arr[Mesh.ARRAY_TEX_UV] = s[4]
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(out.get_surface_count() - 1, s[3])
	return out


## Copy of the mesh with each surface's glTF material swapped for cel shading.
static func _celify(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for i in src.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(i))
		var mat := src.surface_get_material(i)
		var col := (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color(0.7, 0.7, 0.7)
		var mname := mat.resource_name if mat else ""
		out.surface_set_material(i, material_for(mname, col))
	return out


## The cel material for a kit surface, by its glTF material name.
static func material_for(mname: String, col: Color) -> Material:
	if mname.begins_with("kit_glass"):
		return Cel.material(col, false, 0.02, null, 0.4)
	if mname.begins_with("kit_road") or mname.begins_with("kit_pave") or mname.begins_with("kit_paint"):
		return Cel.material(col, false, 0.025, null, 1.0, true)
	if mname.begins_with("kit_roof"):
		return Cel.material(col, true, 0.02, null, 1.0, true)
	return Cel.material(col, true, 0.02)


static func surface_names(m: Mesh) -> PackedStringArray:
	var out := PackedStringArray()
	for i in m.get_surface_count():
		var mat := m.surface_get_material(i)
		out.append(mat.resource_name if mat else "")
	return out


## Recolours the outer surface of exterior walls (kit_wall) on one mesh
## instance, so buildings can differ while sharing one kit.
static func tint(mi: MeshInstance3D, surfaces: PackedStringArray, color: Color) -> void:
	if color.a <= 0.0:
		return
	for i in surfaces.size():
		if surfaces[i] == "kit_wall":
			mi.set_surface_override_material(i, Cel.material(color, true, 0.02))


static func _hull_volume(m: Mesh) -> float:
	var v := 0.0
	for i in m.get_surface_count():
		var arr := m.surface_get_arrays(i)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for k in range(0, verts.size(), 3):
				v += verts[k].dot(verts[k + 1].cross(verts[k + 2]))
		else:
			for k in range(0, idx.size(), 3):
				v += verts[idx[k]].dot(verts[idx[k + 1]].cross(verts[idx[k + 2]]))
	return absf(v) / 6.0
