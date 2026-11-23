class_name Rooftops
extends RefCounted
## v0.9.0: what the grapple hook and the abseil rope need to know about the
## city's buildings: which one a point is on or against, its roof height,
## and the nearest outside wall (a point on it and which way it faces).
## The city sets the list when it's built (one city at a time).

static var buildings: Array = []
static var world: DestructionWorld

const M := BlockGenerator.M
const STOREY := BlockGenerator.STOREY


static func roof_y(b: Dictionary) -> float:
	return (b.origin as Vector3).y + int(b.storeys) * STOREY


## The building whose box (grown by grow) holds p, or {}.
static func building_at(p: Vector3, grow := 0.0) -> Dictionary:
	for b in buildings:
		if int(b.get("storeys", 0)) < 1:
			continue
		var bb: AABB = b.bounds
		if bb.grow(grow).has_point(p):
			return b
	return {}


## Building-local (x along the front, z inward) of a world point.
static func local(b: Dictionary, p: Vector3) -> Vector2:
	var rel := p - (b.origin as Vector3)
	return Vector2(rel.dot(b.u), rel.dot(b.v))


static func to_world(b: Dictionary, x: float, y: float, z: float) -> Vector3:
	return (b.origin as Vector3) + (b.u as Vector3) * x + Vector3.UP * y + (b.v as Vector3) * z


## The outside wall nearest p: {point (on the wall face, at p's height along
## it, kept a little in from the corners), normal (outward), dist (from p)}.
static func nearest_face(b: Dictionary, p: Vector3) -> Dictionary:
	var l := local(b, p)
	var W: float = int(b.w) * M
	var D: float = int(b.d) * M
	var faces := [
		[absf(l.y), Vector2(clampf(l.x, 0.8, W - 0.8), 0.0), -(b.v as Vector3)],
		[absf(D - l.y), Vector2(clampf(l.x, 0.8, W - 0.8), D), b.v as Vector3],
		[absf(l.x), Vector2(0.0, clampf(l.y, 0.8, D - 0.8)), -(b.u as Vector3)],
		[absf(W - l.x), Vector2(W, clampf(l.y, 0.8, D - 0.8)), b.u as Vector3],
	]
	var best: Array = faces[0]
	for f in faces:
		if f[0] < best[0]:
			best = f
	var q: Vector2 = best[1]
	return {"point": to_world(b, q.x, p.y - (b.origin as Vector3).y, q.y), "normal": best[2], "dist": best[0]}


## Whether p (feet) stands inside b's footprint.
static func inside_footprint(b: Dictionary, p: Vector3, margin := 0.0) -> bool:
	var l := local(b, p)
	return l.x > -margin and l.y > -margin and l.x < int(b.w) * M + margin and l.y < int(b.d) * M + margin
