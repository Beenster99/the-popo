class_name BlockGenerator
extends RefCounted
## Phase 1.1: lays out one city block from a seed, as a list of kit pieces.
##
## The block is a square of pavement (12 x 12 modules of 4 m) ringed by a
## road three lanes wide. Buildings stand along the four sides of the block
## facing the street, 4 to 6 of them, 1 to 3 storeys, with a yard or alley
## where a side is not filled. Two buildings are enterable: open doorways,
## a partition wall with a door making simple rooms, and stairs between
## floors. The rest have closed doors.
##
## Everything comes from one RandomNumberGenerator seeded with the block's
## seed, and pieces are listed in a fixed order, so the same seed gives the
## same block, with the same piece ids, on every machine.
## Grid standard: docs/wave1/grid.md.

const M := 4.0              # module: wall length, slab and tile size
const STOREY := 3.25        # 3 m walls plus a 0.25 m slab
const BASE_Y := 0.15        # buildings stand on the pavement
const N := 12               # pavement modules across the block
const ROAD := 3             # road modules around it
const WALL_COLORS := [Color("8a3b2a"), Color("a04a33"), Color("d8cba8"), Color("c9b48a"), Color("7d8790"),
	Color("5e6f7f"), Color("b98a4e"), Color("e2dccf"), Color("6e4a3a")]

## One kit piece to place: {kind, xform, bears, tint, held_by (index into the
## piece list, or -1), building (index, or -1)}.
var pieces: Array = []
## One entry per building: {origin, u, v, w, d, storeys, type, enterable,
## bounds (AABB), door (world position just outside the front door)}.
var buildings: Array = []
var seed_value := 0
var _rng := RandomNumberGenerator.new()

## Wave 2: where this block's lot starts in the city (its north-west pavement
## corner), its district style, and whether it lays its own ground and road
## ring (a lone block does; in the city the CityGenerator lays one road grid).
## Styles: "block" (the Wave 1 block), "downtown", "residential",
## "industrial", "docks", "station", "park", "carpark".
var offset := Vector3.ZERO
var style := "block"
var own_ground := true
## v0.7.0: the lot's size in modules (city lots vary; a lone block is N x N).
var nx := N
var nz := N


static func generate(seed_value: int, opts := {}) -> BlockGenerator:
	var g := BlockGenerator.new()
	g.seed_value = seed_value
	g._rng.seed = seed_value
	g.offset = opts.get("offset", Vector3.ZERO)
	g.style = opts.get("style", "block")
	g.own_ground = opts.get("ground", true)
	g.nx = int(opts.get("nx", N))
	g.nz = int(opts.get("nz", N))
	g._build()
	return g


## A short fingerprint of the whole layout, to compare machines and runs.
func fingerprint() -> int:
	var parts := PackedStringArray()
	for p in pieces:
		var o: Vector3 = p.xform.origin
		var z: Vector3 = p.xform.basis.z
		parts.append("%s %.2f %.2f %.2f %.2f %.2f %s %d" % [p.kind, o.x, o.y, o.z, z.x, z.z, (p.tint as Color).to_html(), p.held_by])
	return "|".join(parts).hash()


## Size of the whole block including its roads, in metres.
static func extent() -> float:
	return (N + ROAD * 2) * M


func _add(kind: String, xform: Transform3D, bears := true, tint := Color(0, 0, 0, 0), held_by := -1, building := -1) -> int:
	xform.origin += offset
	pieces.append({"kind": kind, "xform": xform, "bears": bears, "tint": tint, "held_by": held_by, "building": building})
	return pieces.size() - 1


func _build() -> void:
	if own_ground:
		_ground()
	if style == "block":
		_plan_buildings()
	else:
		CityStyles.plan(self, _rng)
	for i in buildings.size():
		if style == "block":
			_building(i)
		else:
			CityStyles.building(self, i, _rng)
	if style == "block":
		_street_furniture()
	else:
		CityStyles.furniture(self, _rng)
	# Into city coordinates.
	for b in buildings:
		b.origin += offset
		b.start += offset
		b.door += offset
		b.bounds.position += offset


# --- Ground -------------------------------------------------------------------

func _ground() -> void:
	# Pavement over the whole block (buildings stand on it).
	for x in N:
		for z in N:
			_add("pavement", Transform3D(Basis(), Vector3((x + 0.5) * M, 0, (z + 0.5) * M)))
	# The road ring: a centre lane with dashes, crossings mid-way along each side.
	var r90 := Basis(Vector3.UP, PI / 2)
	for x in range(-ROAD, N + ROAD):
		for z in range(-ROAD, N + ROAD):
			if x >= 0 and x < N and z >= 0 and z < N:
				continue
			var pos := Vector3((x + 0.5) * M, 0, (z + 0.5) * M)
			var in_x_road := z < 0 or z >= N     # roads running along X (north and south)
			var in_z_road := x < 0 or x >= N
			var kind := "road"
			var basis := Basis()
			if in_x_road and not in_z_road:
				if x == N / 2:
					kind = "road_crossing"
					basis = r90
				elif z == -2 or z == N + 1:
					kind = "road_line"
			elif in_z_road and not in_x_road:
				if z == N / 2:
					kind = "road_crossing"
				elif x == -2 or x == N + 1:
					kind = "road_line"
					basis = r90
			_add(kind, Transform3D(basis, pos))


# --- Building plan ------------------------------------------------------------

## Sides of the block: where the strip of lots starts, which way it runs (u),
## and which way is inward (v). The front of each building faces -v.
func _sides(d_north: int, d_south: int) -> Array:
	var lo := 1
	var hx := nx - 1
	var hz := nz - 1
	return [
		{"start": Vector3(lo * M, 0, lo * M), "u": Vector3.RIGHT, "v": Vector3.BACK, "len": hx - lo, "name": "north"},
		{"start": Vector3(hx * M, 0, hz * M), "u": Vector3.LEFT, "v": Vector3.FORWARD, "len": hx - lo, "name": "south"},
		{"start": Vector3(lo * M, 0, (hz - d_south) * M), "u": Vector3.FORWARD, "v": Vector3.RIGHT, "len": hz - lo - d_north - d_south, "name": "west"},
		{"start": Vector3(hx * M, 0, (lo + d_north) * M), "u": Vector3.BACK, "v": Vector3.LEFT, "len": hz - lo - d_north - d_south, "name": "east"},
	]


func _plan_buildings() -> void:
	for attempt in 50:
		buildings.clear()
		var d_n := _rng.randi_range(2, 3)
		var d_s := _rng.randi_range(2, 3)
		for side in _sides(d_n, d_s):
			var depth: int = d_n if side.name == "north" else (d_s if side.name == "south" else _rng.randi_range(2, 3))
			var at := 0
			while at < side.len:
				var room: int = side.len - at
				if room < 2:
					break
				# Sometimes leave a yard or an alley.
				if _rng.randf() < 0.3:
					at += _rng.randi_range(1, 3)
					continue
				var w := mini(_rng.randi_range(3, 6), room)
				buildings.append({"start": side.start + side.u * (at * M), "u": side.u, "v": side.v,
					"w": w, "d": depth, "side": side.name})
				at += w
		if buildings.size() >= 4 and buildings.size() <= 6:
			break
	# Still too many after every try: the extra lots become yards.
	while buildings.size() > 6:
		buildings.remove_at(_rng.randi_range(0, buildings.size() - 1))
	# Types, heights, colours, and the two enterable ones.
	var order := range(buildings.size())
	for i in order.size():
		var j := _rng.randi_range(i, order.size() - 1)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for i in buildings.size():
		var b: Dictionary = buildings[i]
		b.type = ["shop", "house", "shop", "garage", "house"][_rng.randi_range(0, 4)] if b.w >= 2 else "house"
		b.storeys = _rng.randi_range(1, 3)
		b.tint = WALL_COLORS[_rng.randi_range(0, WALL_COLORS.size() - 1)]
		b.enterable = false
		b.basis = Basis(b.u, Vector3.UP, b.v)
		b.origin = b.start + Vector3(0, BASE_Y, 0)
	for k in mini(2, order.size()):
		var b: Dictionary = buildings[order[k]]
		b.enterable = true
		b.storeys = clampi(b.storeys, 2, 2) if k == 0 else clampi(b.storeys, 1, 2)
		if b.type == "garage":
			b.type = "shop"
	for b in buildings:
		var corner_a: Vector3 = b.origin
		var corner_b: Vector3 = b.origin + b.u * (b.w * M) + b.v * (b.d * M)
		var lo := Vector3(minf(corner_a.x, corner_b.x), 0, minf(corner_a.z, corner_b.z))
		var hi := Vector3(maxf(corner_a.x, corner_b.x), BASE_Y + b.storeys * STOREY + 1.0, maxf(corner_a.z, corner_b.z))
		b.bounds = AABB(lo, hi - lo).grow(0.3)


## Building-local position (x along the front, y up, z inward) to world.
func _w(b: Dictionary, x: float, y: float, z: float) -> Vector3:
	return b.origin + b.u * x + Vector3.UP * y + b.v * z


func _xf(b: Dictionary, local_basis: Basis, x: float, y: float, z: float) -> Transform3D:
	return Transform3D(b.basis * local_basis, _w(b, x, y, z))


# --- One building ---------------------------------------------------------------

func _building(bi: int) -> void:
	var b: Dictionary = buildings[bi]
	var w: int = b.w
	var d: int = b.d
	var r90 := Basis(Vector3.UP, PI / 2)
	var r180 := Basis(Vector3.UP, PI)
	var tint: Color = b.tint
	var door_at := _rng.randi_range(0, w - 1)
	var partition := _rng.randi_range(1, w - 1) if w >= 2 else -1
	var partition_door := _rng.randi_range(0, d - 1)
	var stair_floors: int = b.storeys - 1 if b.enterable else 0
	b.door = _w(b, (door_at + 0.5) * M, 0.0, -1.0)
	for s in b.storeys:
		var y: float = s * STOREY
		# Front (z = 0, facing the street).
		for i in w:
			var cx := (i + 0.5) * M
			if s == 0:
				_opening_front(b, bi, cx, y, i == door_at)
			else:
				_window_wall(b, bi, Basis(), cx, y, 0.0, _rng.randf() < 0.8)
		# Back (z = d * M).
		for i in w:
			_window_wall(b, bi, r180, (i + 0.5) * M, y, d * M, _rng.randf() < (0.5 if s > 0 else 0.3))
		# Sides (x = 0 and x = w * M).
		for j in d:
			var cz := (j + 0.5) * M
			_window_wall(b, bi, r90, 0.0, y, cz, _rng.randf() < 0.35)
			_window_wall(b, bi, r90 * r180, w * M, y, cz, _rng.randf() < 0.35)
		# Corner pillars close the notch where the walls meet.
		for cx in [0.0, w * M]:
			for cz in [0.0, d * M]:
				_add("column", _xf(b, Basis(), cx, y, cz), true, Color(0, 0, 0, 0), -1, bi)
		# Columns at inner grid points carry the middle of the floor above.
		for i in range(1, w):
			for j in range(1, d):
				_add("column", _xf(b, Basis(), i * M, y, j * M), true, Color(0, 0, 0, 0), -1, bi)
		# Rooms: one partition with a door, across the depth.
		if b.enterable and partition > 0:
			for j in d:
				var kind := "int_wall_door" if j == partition_door else "int_wall"
				_add(kind, _xf(b, r90, partition * M, y, (j + 0.5) * M), false, Color(0, 0, 0, 0), -1, bi)
		# Stairs up from this floor, in the back corner, and the floor above
		# with its stairwell.
		if s < stair_floors:
			# The stairs run front to back along the right-hand wall.
			_add("stairs", _xf(b, r180, (w - 0.5) * M + 1.35, y, (d - 0.5) * M), true, Color(0, 0, 0, 0), -1, bi)
		# Floor (or roof) above this storey.
		var top: float = y + STOREY
		var roof: bool = s == b.storeys - 1
		for i in w:
			for j in d:
				var kind := "roof" if roof else "slab"
				var basis := Basis()
				if not roof and s < stair_floors and i == w - 1 and j == d - 1:
					kind = "slab_stairwell"
					basis = r180
				_add(kind, _xf(b, basis, (i + 0.5) * M, top, (j + 0.5) * M), true, Color(0, 0, 0, 0), -1, bi)
	# Parapet round the roof.
	var ry: float = b.storeys * STOREY
	for i in w:
		_add("parapet", _xf(b, Basis(), (i + 0.5) * M, ry, 0.0), true, tint, -1, bi)
		_add("parapet", _xf(b, r180, (i + 0.5) * M, ry, d * M), true, tint, -1, bi)
	for j in d:
		_add("parapet", _xf(b, r90, 0.0, ry, (j + 0.5) * M), true, tint, -1, bi)
		_add("parapet", _xf(b, r90 * r180, w * M, ry, (j + 0.5) * M), true, tint, -1, bi)


## A plain wall or a window wall (with its glass) at a module of the outside.
func _window_wall(b: Dictionary, bi: int, local: Basis, x: float, y: float, z: float, window: bool) -> void:
	var xf := _xf(b, local, x, y, z)
	if window:
		var wi := _add("wall_window", xf, true, b.tint, -1, bi)
		_add("glass_window", xf, false, Color(0, 0, 0, 0), wi, bi)
	else:
		_add("wall", xf, true, b.tint, -1, bi)


## The ground-floor front: shop windows, a garage door, or house windows,
## and the front door. Doors of buildings you cannot enter stay shut.
func _opening_front(b: Dictionary, bi: int, x: float, y: float, is_door: bool) -> void:
	var xf := _xf(b, Basis(), x, y, 0.0)
	var t: Color = b.tint
	match b.type:
		"shop":
			if is_door:
				var wi := _add("wall_shopdoor", xf, true, t, -1, bi)
				_add("glass_shopdoor", xf, false, Color(0, 0, 0, 0), wi, bi)
				if not b.enterable:
					_add("door_closed", _xf(b, Basis(), x - 0.9, y, 0.0), false, Color(0, 0, 0, 0), wi, bi)
			else:
				var wi := _add("wall_shopfront", xf, true, t, -1, bi)
				_add("glass_shopfront", xf, false, Color(0, 0, 0, 0), wi, bi)
		"garage":
			if is_door:
				var wi := _add("wall_door", xf, true, t, -1, bi)
				_add("door_closed", xf, false, Color(0, 0, 0, 0), wi, bi)
			else:
				var wi := _add("wall_garage", xf, true, t, -1, bi)
				_add("garage_door", xf, false, Color(0, 0, 0, 0), wi, bi)
		_:
			if is_door:
				var wi := _add("wall_door", xf, true, t, -1, bi)
				if not b.enterable:
					_add("door_closed", xf, false, Color(0, 0, 0, 0), wi, bi)
			else:
				_window_wall(b, bi, Basis(), x, y, 0.0, true)


# --- Street furniture -----------------------------------------------------------

func _street_furniture() -> void:
	# Lamp posts near each corner of the block, on the kerb, arms over the road.
	var e := N * M
	var spots := [
		[Vector3(1.0, BASE_Y, 0.6), Basis(Vector3.UP, PI / 2)],
		[Vector3(e - 1.0, BASE_Y, 0.6), Basis(Vector3.UP, PI / 2)],
		[Vector3(1.0, BASE_Y, e - 0.6), Basis(Vector3.UP, -PI / 2)],
		[Vector3(e - 1.0, BASE_Y, e - 0.6), Basis(Vector3.UP, -PI / 2)],
		[Vector3(e * 0.5 + 6.0, BASE_Y, 0.6), Basis(Vector3.UP, PI / 2)],
		[Vector3(e * 0.5 - 6.0, BASE_Y, e - 0.6), Basis(Vector3.UP, -PI / 2)],
	]
	for sp in spots:
		_add("lamp_post", Transform3D(sp[1], sp[0]), false)
	# Bollards either side of each crossing.
	for k in [-1.0, 1.0]:
		var c: float = e * 0.5 + k * 2.4
		_add("bollard", Transform3D(Basis(), Vector3(c, BASE_Y, 0.4)), false)
		_add("bollard", Transform3D(Basis(), Vector3(c, BASE_Y, e - 0.4)), false)
		_add("bollard", Transform3D(Basis(), Vector3(0.4, BASE_Y, c)), false)
		_add("bollard", Transform3D(Basis(), Vector3(e - 0.4, BASE_Y, c)), false)
