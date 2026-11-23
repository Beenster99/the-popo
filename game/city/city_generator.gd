class_name CityGenerator
extends BlockGenerator
## Wave 2, Phase 2.1: the whole city from one seed.
##
## A grid of GRID x GRID blocks with a road three modules wide (12 m, one
## lane each way plus kerbside parking) between neighbours and round the
## outside. Since v0.9.0 the lots are not all the same size: each column of
## blocks is 9 to 15 modules wide and each row 9 to 15 deep (36 to 60 m),
## picked from the seed, so the streets are not an even grid. (The station's
## column and row stay 12.) The city is still under about 450 m across.
## Districts:
##   docks        the south row, on the water: warehouses, container yards
##   industrial   the two east columns: warehouses, garages, yards
##   downtown     the middle: offices and shops, three to five storeys, and
##                towers of seven to ten storeys with a lift (v0.9.0)
##   residential  the rest: houses, flats and corner shops
## plus the police station (home base and custody), two parks and a car park.
##
## It is a BlockGenerator (same piece list and building list, in city
## coordinates), so everything written for one block (destruction, roof
## fader, props, sounds, dispatcher) reads a city the same way. Each block's
## pieces are a contiguous range (blocks[k].pieces_from .. pieces_to) and
## carry "group": k, so the support graph is only re-checked in the block
## where something broke.
##
## The ground (roads and pavements) is not made of breakable pieces: it is
## laid as a few merged meshes by CityGround, from lot_rects() and roads().

const GRID := 6
const PITCH := (N + ROAD) * M         # the average distance from one block to the next
const LOT_RANGE := Vector2i(9, 15)    # lot sizes, in modules
const ROAD_W := ROAD * M              # 12 m
const LANE := 2.6                     # m from the road's centre line to a lane's centre
const PARK_LANE := 4.9                # m from the centre line to parked cars
const STATION := Vector2i(2, 4)

## Lot size in modules of each column (x) and row (z) of blocks. Static: the
## city's layout is needed in static helpers everywhere, and there is one
## city at a time. Set by generate_city (all 12 until then).
static var cols: Array = [12, 12, 12, 12, 12, 12]
static var rows: Array = [12, 12, 12, 12, 12, 12]

## [{bx, bz, style, district, offset (lot corner), rect (Rect2 in x/z),
##   pieces_from, pieces_to, buildings_from, buildings_to}]
var blocks: Array = []


static func generate_city(seed_value: int) -> CityGenerator:
	var g := CityGenerator.new()
	g.seed_value = seed_value
	g._rng.seed = seed_value
	pick_sizes(seed_value)
	g._build_city()
	return g


## Lot sizes for a city from its seed (its own generator, so the rest of the
## city's rolls are unchanged by it).
static func pick_sizes(seed_value: int) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = hash(seed_value * 31 + 1717)
	cols = []
	rows = []
	for i in GRID:
		cols.append(N if i == STATION.x else r.randi_range(LOT_RANGE.x, LOT_RANGE.y))
		rows.append(N if i == STATION.y else r.randi_range(LOT_RANGE.x, LOT_RANGE.y))


## Back to the even 12-module grid (tests of the old layout).
static func even_sizes() -> void:
	cols = []
	rows = []
	for i in GRID:
		cols.append(N)
		rows.append(N)


## Where road k (0..GRID) starts, along x (axis 0: the roads running along
## Z) or z (axis 1: the roads running along X), in metres.
static func road_at(k: int, axis: int) -> float:
	var sizes: Array = cols if axis == 0 else rows
	var m := 0
	for i in mini(k, GRID):
		m += int(sizes[i]) + ROAD
	return m * M


## The city's size, roads included (it starts at 0, 0), across x and z.
static func extent_x() -> float:
	return road_at(GRID, 0) + ROAD_W


static func extent_z() -> float:
	return road_at(GRID, 1) + ROAD_W


## The bigger of the two (for things that only need a bound).
static func city_extent() -> float:
	return maxf(extent_x(), extent_z())


## Where block (bx, bz)'s lot starts.
static func lot_origin(bx: int, bz: int) -> Vector3:
	return Vector3(road_at(bx, 0) + ROAD_W, 0, road_at(bz, 1) + ROAD_W)


## A block's lot size in metres (x, z).
static func lot_size(bx: int, bz: int) -> Vector2:
	return Vector2(int(cols[bx]) * M, int(rows[bz]) * M)


## Which block a point is over (its lot or the road north/west of it), or
## Vector2i(-1, -1) off the grid.
static func block_at(p: Vector3) -> Vector2i:
	var bx := _index_at(p.x, 0)
	var bz := _index_at(p.z, 1)
	if bx < 0 or bz < 0:
		return Vector2i(-1, -1)
	return Vector2i(bx, bz)


static func _index_at(v: float, axis: int) -> int:
	if v < ROAD_W * 0.5:
		return -1
	for i in GRID:
		if v < road_at(i + 1, axis) + ROAD_W * 0.5:
			return i
	return -1


func block_index(bx: int, bz: int) -> int:
	return bz * GRID + bx


func district_at(p: Vector3) -> String:
	var c := block_at(p)
	if c.x < 0:
		return "outskirts"
	return blocks[block_index(c.x, c.y)].district


static func _district(bx: int, bz: int) -> String:
	if bz == GRID - 1:
		return "docks"
	if bx >= GRID - 2:
		return "industrial"
	if bx >= 1 and bx <= 3 and bz >= 1 and bz <= 3:
		return "downtown"
	return "residential"


func _build_city() -> void:
	# Pick the specials from the seed: two parks in residential blocks, one
	# downtown car park. The station block is fixed, south of downtown.
	var resi: Array = []
	var down: Array = []
	for bz in GRID:
		for bx in GRID:
			if Vector2i(bx, bz) == STATION:
				continue
			match _district(bx, bz):
				"residential":
					resi.append(Vector2i(bx, bz))
				"downtown":
					down.append(Vector2i(bx, bz))
	var parks: Array = []
	for k in 2:
		if resi.is_empty():
			break
		parks.append(resi.pop_at(_rng.randi_range(0, resi.size() - 1)))
	var carpark: Vector2i = down[_rng.randi_range(0, down.size() - 1)] if not down.is_empty() else Vector2i(-9, -9)
	for bz in GRID:
		for bx in GRID:
			var cell := Vector2i(bx, bz)
			var district := _district(bx, bz)
			var style := district
			if cell == STATION:
				style = "station"
				district = "downtown"
			elif cell in parks:
				style = "park"
			elif cell == carpark:
				style = "carpark"
			var sub := BlockGenerator.generate(hash(seed_value * 7919 + bz * GRID + bx), {
				"offset": lot_origin(bx, bz), "style": style, "ground": false, "nx": cols[bx], "nz": rows[bz]})
			var k := blocks.size()
			var info := {"bx": bx, "bz": bz, "style": style, "district": district, "offset": lot_origin(bx, bz),
				"rect": Rect2(lot_origin(bx, bz).x, lot_origin(bx, bz).z, int(cols[bx]) * M, int(rows[bz]) * M),
				"pieces_from": pieces.size(), "buildings_from": buildings.size()}
			var pbase := pieces.size()
			var bbase := buildings.size()
			for p in sub.pieces:
				var q: Dictionary = p.duplicate()
				if q.held_by >= 0:
					q.held_by += pbase
				if q.building >= 0:
					q.building += bbase
				q.group = k
				pieces.append(q)
			for b in sub.buildings:
				b.block = k
				b.district = district
				buildings.append(b)
			info.pieces_to = pieces.size()
			info.buildings_to = buildings.size()
			blocks.append(info)


# --- What the ground and the traffic need ------------------------------------------

## Every lot's pavement, as x/z rectangles.
func lot_rects() -> Array:
	return blocks.map(func(b): return b.rect)


## Road strips, as x/z rectangles: GRID + 1 running along X (west to east)
## and GRID + 1 along Z. They overlap at the junctions.
static func roads() -> Array:
	var out: Array = []
	var ex := extent_x()
	var ez := extent_z()
	for k in GRID + 1:
		var zk := road_at(k, 1)
		var xk := road_at(k, 0)
		out.append({"axis": "x", "rect": Rect2(0, zk, ex, ROAD_W), "centre": zk + ROAD_W * 0.5})
		out.append({"axis": "z", "rect": Rect2(xk, 0, ROAD_W, ez), "centre": xk + ROAD_W * 0.5})
	return out


## The centre of junction (i, j), i and j from 0 to GRID.
static func junction(i: int, j: int) -> Vector3:
	return Vector3(road_at(i, 0) + ROAD_W * 0.5, 0, road_at(j, 1) + ROAD_W * 0.5)


## The nearest road (0..GRID) to v along an axis.
static func nearest_road(v: float, axis: int) -> int:
	var best := 0
	var bd := INF
	for k in GRID + 1:
		var d := absf(v - (road_at(k, axis) + ROAD_W * 0.5))
		if d < bd:
			bd = d
			best = k
	return best


## Somewhere on the pavement near p (on the kerb strip of the nearest lot),
## for spawning people and spots for calls.
func pavement_near(p: Vector3) -> Vector3:
	var best := Vector3.INF
	for b in blocks:
		var r: Rect2 = b.rect
		var q := Vector3(clampf(p.x, r.position.x + 1.0, r.end.x - 1.0), BASE_Y, clampf(p.z, r.position.y + 1.0, r.end.y - 1.0))
		if q.distance_squared_to(p) < best.distance_squared_to(p):
			best = q
	return best


## The police station's building.
func station() -> Dictionary:
	for b in buildings:
		if b.type == "station":
			return b
	return {}


## Where prisoners are driven: the road in front of the station's garage.
func custody_bay() -> Vector3:
	var s := station()
	if s.is_empty():
		return Vector3(56.5, 0, 24.0)
	return (s.origin as Vector3) + (s.u as Vector3) * (M * 0.5) - (s.v as Vector3) * 7.5 + Vector3(0, -BASE_Y, 0)


# --- Street names, for the radio ---------------------------------------------------

const X_STREETS := ["Northgate Street", "Mercer Street", "Albion Street", "Kingsway", "Market Street", "Foundry Lane", "Harbour Road"]
const Z_STREETS := ["Westbury Avenue", "Chapel Road", "Union Avenue", "Sterling Road", "Canal Street", "Ironworks Road", "Eastern Avenue"]


## "Mercer Street near Chapel Road": the road a point is on (or nearest),
## and the nearest cross street.
static func street_at(p: Vector3) -> String:
	var kx := nearest_road(p.z, 1)
	var kz := nearest_road(p.x, 0)
	var dx := absf(p.z - (road_at(kx, 1) + ROAD_W * 0.5))
	var dz := absf(p.x - (road_at(kz, 0) + ROAD_W * 0.5))
	if dx <= dz:
		return "%s near %s" % [X_STREETS[kx], Z_STREETS[kz]]
	return "%s near %s" % [Z_STREETS[kz], X_STREETS[kx]]
