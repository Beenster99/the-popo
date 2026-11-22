class_name ChunkSplit
extends RefCounted
## Phase 1.7 (beenster: "any chance of making the physics parts a little
## smaller?"): cuts the pre-fractured kit chunks into smaller convex pieces at
## load time, so walls break into finer rubble without re-exporting the kit.
## Each chunk is sliced by planes through its middle at seeded random angles;
## the cut faces get the chunk's inner (broken concrete or brick) surface.
## The same seed on every machine gives the same pieces.


## A convex mesh as triangles per surface: [{verts, normals, uvs}] with three
## entries per triangle.
static func _triangles(m: Mesh) -> Array:
	var out := []
	for s in m.get_surface_count():
		var arr := m.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV] if arr[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var tv := PackedVector3Array()
		var tn := PackedVector3Array()
		var tu := PackedVector2Array()
		var count := idx.size() if not idx.is_empty() else v.size()
		for k in count:
			var i := idx[k] if not idx.is_empty() else k
			tv.append(v[i])
			tn.append(n[i] if i < n.size() else Vector3.UP)
			tu.append(uv[i] if i < uv.size() else Vector2.ZERO)
		out.append({"verts": tv, "normals": tn, "uvs": tu})
	return out


## Splits triangle soup by a plane; returns [front, back], each with the same
## surfaces, plus the cut points (on the plane) for the caps.
static func _slice(surfs: Array, plane: Plane) -> Array:
	var front := []
	var back := []
	var cut := PackedVector3Array()
	for sf in surfs:
		var f := {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array()}
		var b := {"verts": PackedVector3Array(), "normals": PackedVector3Array(), "uvs": PackedVector2Array()}
		var v: PackedVector3Array = sf.verts
		var n: PackedVector3Array = sf.normals
		var u: PackedVector2Array = sf.uvs
		for t in range(0, v.size(), 3):
			var poly_f := []
			var poly_b := []
			for e in 3:
				var i0 := t + e
				var i1 := t + (e + 1) % 3
				var d0 := plane.distance_to(v[i0])
				var d1 := plane.distance_to(v[i1])
				var p0 := [v[i0], n[i0], u[i0]]
				if d0 >= 0.0:
					poly_f.append(p0)
				else:
					poly_b.append(p0)
				if (d0 >= 0.0) != (d1 >= 0.0):
					var k := d0 / (d0 - d1)
					var q := [v[i0].lerp(v[i1], k), n[i0].lerp(n[i1], k).normalized(), u[i0].lerp(u[i1], k)]
					poly_f.append(q)
					poly_b.append(q)
					cut.append(q[0])
			_fan(poly_f, f)
			_fan(poly_b, b)
		front.append(f)
		back.append(b)
	return [front, back, cut]


static func _fan(poly: Array, into: Dictionary) -> void:
	var v: PackedVector3Array = into.verts
	var n: PackedVector3Array = into.normals
	var u: PackedVector2Array = into.uvs
	for i in range(1, poly.size() - 1):
		for p in [poly[0], poly[i], poly[i + 1]]:
			v.append(p[0])
			n.append(p[1])
			u.append(p[2])
	into.verts = v
	into.normals = n
	into.uvs = u


## Closes a cut: the cross-section of a convex chunk is a convex polygon, so
## the cut points sorted round their middle make a fan. facing: the outward
## normal of this half's cap.
static func _cap(cut: PackedVector3Array, facing: Vector3, into: Dictionary) -> void:
	if cut.size() < 3:
		return
	var c := Vector3.ZERO
	for p in cut:
		c += p
	c /= cut.size()
	var ax := (cut[0] - c).normalized()
	if ax.length() < 0.5:
		ax = facing.cross(Vector3.UP if absf(facing.y) < 0.9 else Vector3.RIGHT).normalized()
	var ay := facing.cross(ax)
	var pts := []
	for p in cut:
		var d := p - c
		pts.append([atan2(d.dot(ay), d.dot(ax)), p])
	pts.sort_custom(func(a, b): return a[0] < b[0])
	# Drop near-duplicates (each edge cut shows up from both triangles).
	var ring := []
	for e in pts:
		if ring.is_empty() or (ring[-1][1] as Vector3).distance_to(e[1]) > 0.002:
			ring.append(e)
	if ring.size() >= 2 and (ring[0][1] as Vector3).distance_to(ring[-1][1]) < 0.002:
		ring.pop_back()
	var vv: PackedVector3Array = into.verts
	var nn: PackedVector3Array = into.normals
	var uu: PackedVector2Array = into.uvs
	for i in range(1, ring.size() - 1):
		var a: Vector3 = ring[0][1]
		var b: Vector3 = ring[i][1]
		var d: Vector3 = ring[i + 1][1]
		var tri := [a, b, d] if (b - a).cross(d - a).dot(facing) < 0.0 else [a, d, b]
		for p in tri:
			vv.append(p)
			nn.append(facing)
			uu.append(Vector2((p as Vector3).dot(ax), (p as Vector3).dot(ay)) * 0.5)
	into.verts = vv
	into.normals = nn
	into.uvs = uu


## Cuts one kit chunk into up to 2^cuts pieces. Returns chunk dictionaries
## like KitLibrary's (mesh, offset, shape, volume, radius, surfaces).
static func split(chunk: Dictionary, cuts: int, seed_value: int, min_volume: float) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var mesh: ArrayMesh = chunk.mesh
	var surfaces: PackedStringArray = chunk.surfaces
	var inner := surfaces.size() - 1
	for i in surfaces.size():
		if surfaces[i].ends_with("_inner"):
			inner = i
	var mats := []
	for i in mesh.get_surface_count():
		mats.append(mesh.surface_get_material(i))
	var parts := [_triangles(mesh)]
	for c in cuts:
		var next := []
		for p in parts:
			var aabb := _bounds(p)
			if _volume(p) < min_volume * 2.0 or aabb.size == Vector3.ZERO:
				next.append(p)
				continue
			# Cut across the longest side, tilted at random, near the middle.
			var sz := aabb.size
			var axis := Vector3.RIGHT if sz.x >= sz.y and sz.x >= sz.z else (Vector3.UP if sz.y >= sz.z else Vector3.BACK)
			var nrm := (axis + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6), rng.randf_range(-0.6, 0.6))).normalized()
			var mid := aabb.get_center() + axis * sz * rng.randf_range(-0.15, 0.15)
			var plane := Plane(nrm, mid)
			var r := _slice(p, plane)
			_cap(r[2], -nrm, r[0][inner])
			_cap(r[2], nrm, r[1][inner])
			for half in [r[0], r[1]]:
				if _count(half) >= 12:
					next.append(half)
		parts = next
	if parts.size() <= 1:
		return [chunk]
	var out := []
	for p in parts:
		var centre := _centroid(p)
		var m := ArrayMesh.new()
		var pts := PackedVector3Array()
		for i in p.size():
			var sf: Dictionary = p[i]
			if (sf.verts as PackedVector3Array).is_empty():
				continue
			var vv := PackedVector3Array()
			for q in sf.verts:
				vv.append(q - centre)
				pts.append(q - centre)
			var arr := []
			arr.resize(Mesh.ARRAY_MAX)
			arr[Mesh.ARRAY_VERTEX] = vv
			arr[Mesh.ARRAY_NORMAL] = sf.normals
			arr[Mesh.ARRAY_TEX_UV] = sf.uvs
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			m.surface_set_material(m.get_surface_count() - 1, mats[i])
			m.surface_set_name(m.get_surface_count() - 1, surfaces[i])
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var a := m.get_aabb()
		var names := PackedStringArray()
		for i in m.get_surface_count():
			names.append(m.surface_get_name(i))
		out.append({"mesh": m, "offset": (chunk.offset as Vector3) + centre, "shape": shape,
			"volume": KitLibrary._hull_volume(m), "radius": a.size.length() * 0.5, "surfaces": names})
	return out


static func _count(p: Array) -> int:
	var n := 0
	for sf in p:
		n += (sf.verts as PackedVector3Array).size()
	return n


static func _bounds(p: Array) -> AABB:
	var first := true
	var box := AABB()
	for sf in p:
		for q in sf.verts:
			if first:
				box = AABB(q, Vector3.ZERO)
				first = false
			else:
				box = box.expand(q)
	return box


static func _centroid(p: Array) -> Vector3:
	return _bounds(p).get_center()


static func _volume(p: Array) -> float:
	var v := 0.0
	for sf in p:
		var vv: PackedVector3Array = sf.verts
		for k in range(0, vv.size(), 3):
			v += vv[k].dot(vv[k + 1].cross(vv[k + 2]))
	return absf(v) / 6.0
