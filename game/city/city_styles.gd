class_name CityStyles
extends RefCounted
## Wave 2 (Phases 2.1 and 2.2): how a block looks in each district, and the
## rooms inside every building.
##
## A BlockGenerator with a style other than "block" calls in here to plan its
## lots, build each building and add its street furniture. The same kit and
## grid as Wave 1 (docs/wave1/grid.md); districts differ in building types,
## widths, heights and how often a lot is left as a yard.
##
## Every building is enterable (Phase 2.2): rooms laid out on the 4 m grid for
## its type, a door between them, and stairs to every floor in the back
## right-hand corner. About a third keep their front door shut; kick it in.
##
## Building types and their rooms:
##   house      one or two partitions with doors
##   flats      a row of flats, a partition every two modules, upper floors
##   shop       shop floor at the front, stock room behind, flats above
##   office     glass lobby, open-plan floors with a meeting room at the back
##   warehouse  one open hall with garage doors and an office in the corner
##   garage     the Wave 1 lock-up: garage doors, open inside
##   station    the police station: front desk, cells at the back, offices

const M := BlockGenerator.M
const STOREY := BlockGenerator.STOREY

## Per style: building count, widths, depths, storeys, gap chance, types.
const STYLES := {
	"downtown": {"count": [5, 8], "w": [3, 6], "d": [2, 3], "storeys": [3, 5], "gap": 0.12,
		"types": ["office", "office", "shop", "flats", "shop"]},
	"residential": {"count": [5, 9], "w": [2, 4], "d": [2, 3], "storeys": [1, 3], "gap": 0.35,
		"types": ["house", "house", "flats", "shop", "house"]},
	"industrial": {"count": [2, 5], "w": [4, 8], "d": [3, 4], "storeys": [1, 2], "gap": 0.3,
		"types": ["warehouse", "warehouse", "garage", "warehouse", "office"]},
	"docks": {"count": [1, 3], "w": [5, 8], "d": [3, 4], "storeys": [1, 1], "gap": 0.45,
		"types": ["warehouse"]},
	"station": {"count": [1, 1], "w": [7, 7], "d": [3, 3], "storeys": [2, 2], "gap": 0.0, "types": ["station"]},
	"park": {"count": [0, 0], "w": [0, 0], "d": [0, 0], "storeys": [0, 0], "gap": 1.0, "types": []},
	"carpark": {"count": [0, 0], "w": [0, 0], "d": [0, 0], "storeys": [0, 0], "gap": 1.0, "types": []},
}
## v0.10.0: tall downtown buildings with a lift beside the stairs.
const MAX_TOWERS := 2
const TOWER_CHANCE := 0.7
const TOWER_STOREYS := Vector2i(7, 10)
const WALL_COLORS := {
	"downtown": [Color("7d8790"), Color("5e6f7f"), Color("e2dccf"), Color("9aa3a8"), Color("b9b2a2"), Color("4e5a66")],
	"residential": [Color("8a3b2a"), Color("a04a33"), Color("d8cba8"), Color("c9b48a"), Color("b98a4e"), Color("6e4a3a")],
	"industrial": [Color("8f8a7d"), Color("6b6f72"), Color("a7a08c"), Color("5d6b5a"), Color("7a5a44")],
	"docks": [Color("6b7d8a"), Color("8a6a4a"), Color("5f6f5a"), Color("9a8f7d")],
	"station": [Color("2c3e66")],
	"carpark": [Color("b9b2a2")],
}


static func plan(g: BlockGenerator, rng: RandomNumberGenerator) -> void:
	var st: Dictionary = STYLES.get(g.style, STYLES.residential)
	if g.style == "station":
		# One big building along the north side, the yard and car park behind.
		g.buildings.append({"start": Vector3(2 * M, 0, 1 * M), "u": Vector3.RIGHT, "v": Vector3.BACK,
			"w": 7, "d": 3, "side": "north"})
	elif st.count[1] > 0:
		for attempt in 50:
			g.buildings.clear()
			var d_n := rng.randi_range(st.d[0], st.d[1])
			var d_s := rng.randi_range(st.d[0], st.d[1])
			for side in g._sides(d_n, d_s):
				var depth: int = d_n if side.name == "north" else (d_s if side.name == "south" else rng.randi_range(st.d[0], st.d[1]))
				var at := 0
				while at < side.len:
					var room: int = side.len - at
					if room < 2:
						break
					if rng.randf() < st.gap:
						at += rng.randi_range(1, 3)
						continue
					var w := mini(rng.randi_range(st.w[0], st.w[1]), room)
					if w < 2:
						break
					g.buildings.append({"start": side.start + side.u * (at * M), "u": side.u, "v": side.v,
						"w": w, "d": depth, "side": side.name})
					at += w
			if g.buildings.size() >= st.count[0] and g.buildings.size() <= st.count[1]:
				break
		while g.buildings.size() > st.count[1]:
			g.buildings.remove_at(rng.randi_range(0, g.buildings.size() - 1))
	var colours: Array = WALL_COLORS.get(g.style, WALL_COLORS.residential)
	var towers := 0
	for b in g.buildings:
		var types: Array = st.types
		b.type = types[rng.randi_range(0, types.size() - 1)]
		if b.w < 3 and b.type in ["warehouse", "office", "station"]:
			b.type = "house"
		b.storeys = rng.randi_range(st.storeys[0], st.storeys[1])
		if b.type == "warehouse" or b.type == "garage":
			b.storeys = 1
		if b.type == "house":
			b.storeys = mini(b.storeys, 2)
		# v0.10.0: downtown towers, up to ten storeys, with a lift.
		b.lift = false
		if g.style == "downtown" and towers < MAX_TOWERS and b.w >= 4 and b.d >= 3 \
				and b.type in ["office", "flats"] and rng.randf() < TOWER_CHANCE:
			towers += 1
			b.type = "tower"
			b.storeys = rng.randi_range(TOWER_STOREYS.x, TOWER_STOREYS.y)
			b.lift = true
		# v0.10.0: stairs up to a hut on the roof, so roofs can be reached
		# from inside as well as by grapple.
		b.roof_access = b.storeys >= 2 and b.type not in ["house", "station"]
		b.tint = colours[rng.randi_range(0, colours.size() - 1)]
		b.enterable = true
		b.locked = b.type != "station" and rng.randf() < 0.33
		b.basis = Basis(b.u, Vector3.UP, b.v)
		b.origin = b.start + Vector3(0, BlockGenerator.BASE_Y, 0)
		b.rooms = []
		var corner_a: Vector3 = b.origin
		var corner_b: Vector3 = b.origin + b.u * (b.w * M) + b.v * (b.d * M)
		var lo := Vector3(minf(corner_a.x, corner_b.x), 0, minf(corner_a.z, corner_b.z))
		var top: float = b.storeys * STOREY + (STOREY if b.roof_access else 1.0)
		var hi := Vector3(maxf(corner_a.x, corner_b.x), BlockGenerator.BASE_Y + top, maxf(corner_a.z, corner_b.z))
		b.bounds = AABB(lo, hi - lo).grow(0.3)


# --- One building -----------------------------------------------------------------

static func building(g: BlockGenerator, bi: int, rng: RandomNumberGenerator) -> void:
	var b: Dictionary = g.buildings[bi]
	var w: int = b.w
	var d: int = b.d
	var r90 := Basis(Vector3.UP, PI / 2)
	var r180 := Basis(Vector3.UP, PI)
	var tint: Color = b.tint
	var door_at := rng.randi_range(0, w - 2) if w >= 2 else 0
	if b.type == "station":
		door_at = 3
	b.door = g._w(b, (door_at + 0.5) * M, 0.0, -1.0)
	var roof_access: bool = b.get("roof_access", false)
	var stair_floors: int = b.storeys if roof_access else b.storeys - 1
	var lift: bool = b.get("lift", false)
	var windows: float = {"office": 0.95, "tower": 0.95, "station": 0.7, "warehouse": 0.25, "garage": 0.2}.get(b.type, 0.75)
	var shaft_back := -1    # the shaft's back wall has no floor under it: each hangs on the one below
	for s in b.storeys:
		var y: float = s * STOREY
		for i in w:
			var cx := (i + 0.5) * M
			if s == 0:
				_front(g, b, bi, cx, y, i, door_at, rng)
			else:
				g._window_wall(b, bi, Basis(), cx, y, 0.0, rng.randf() < windows)
		for i in w:
			var back_window: bool = rng.randf() < windows * (0.6 if s > 0 else 0.35)
			if lift and i == w - 2:
				shaft_back = g._add("wall", g._xf(b, r180, (i + 0.5) * M, y, d * M), true, tint, shaft_back, bi)
				continue
			g._window_wall(b, bi, r180, (i + 0.5) * M, y, d * M, back_window)
		for j in d:
			var cz := (j + 0.5) * M
			g._window_wall(b, bi, r90, 0.0, y, cz, rng.randf() < windows * 0.4)
			g._window_wall(b, bi, r90 * r180, w * M, y, cz, rng.randf() < windows * 0.4)
		for cx in [0.0, w * M]:
			for cz in [0.0, d * M]:
				g._add("column", g._xf(b, Basis(), cx, y, cz), true, Color(0, 0, 0, 0), -1, bi)
		for i in range(1, w):
			for j in range(1, d):
				g._add("column", g._xf(b, Basis(), i * M, y, j * M), true, Color(0, 0, 0, 0), -1, bi)
		_rooms(g, b, bi, s, y, rng)
		if lift:
			_shaft(g, b, bi, y)
		if s < stair_floors:
			g._add("stairs", g._xf(b, r180, (w - 0.5) * M + 1.35, y, (d - 0.5) * M), true, Color(0, 0, 0, 0), -1, bi)
		var top: float = y + STOREY
		var roof: bool = s == b.storeys - 1
		for i in w:
			for j in d:
				var kind := "roof" if roof else "slab"
				var basis := Basis()
				if s < stair_floors and i == w - 1 and j == d - 1:
					kind = "slab_stairwell"
					basis = r180
				if not roof and lift and i == w - 2 and j == d - 1:
					continue    # the lift shaft
				g._add(kind, g._xf(b, basis, (i + 0.5) * M, top, (j + 0.5) * M), true, Color(0, 0, 0, 0), -1, bi)
	var ry: float = b.storeys * STOREY
	for i in w:
		g._add("parapet", g._xf(b, Basis(), (i + 0.5) * M, ry, 0.0), true, tint, -1, bi)
		if not (roof_access and i == w - 1):
			g._add("parapet", g._xf(b, r180, (i + 0.5) * M, ry, d * M), true, tint, -1, bi)
	for j in d:
		g._add("parapet", g._xf(b, r90, 0.0, ry, (j + 0.5) * M), true, tint, -1, bi)
		if not (roof_access and j == d - 1):
			g._add("parapet", g._xf(b, r90 * r180, w * M, ry, (j + 0.5) * M), true, tint, -1, bi)
	if roof_access:
		_roof_hut(g, b, bi, ry, rng)


## v0.10.0: the hut over the stairs on the roof, with a door out onto it.
## About a third are locked: kick it in, or come up the stairs.
static func _roof_hut(g: BlockGenerator, b: Dictionary, bi: int, ry: float, rng: RandomNumberGenerator) -> void:
	var w: int = b.w
	var d: int = b.d
	var t: Color = b.tint
	var none := Color(0, 0, 0, 0)
	var r90 := Basis(Vector3.UP, PI / 2)
	var r180 := Basis(Vector3.UP, PI)
	var fx := g._xf(b, Basis(), (w - 0.5) * M, ry, (d - 1) * M)
	var wi := g._add("wall_door", fx, true, t, -1, bi)
	if rng.randf() < 0.33:
		g._add("door_closed", fx, false, none, wi, bi)
	g._add("wall", g._xf(b, r90, (w - 1) * M, ry, (d - 0.5) * M), true, t, -1, bi)
	g._add("wall", g._xf(b, r180, (w - 0.5) * M, ry, d * M), true, t, -1, bi)
	g._add("wall", g._xf(b, r90 * r180, w * M, ry, (d - 0.5) * M), true, t, -1, bi)
	for cx in [(w - 1) * M, w * M]:
		for cz in [(d - 1) * M, d * M]:
			g._add("column", g._xf(b, Basis(), cx, ry, cz), true, none, -1, bi)
	g._add("roof", g._xf(b, Basis(), (w - 0.5) * M, ry + STOREY, (d - 0.5) * M), true, none, -1, bi)
	b.roof_door = g._w(b, (w - 0.5) * M, ry, (d - 1) * M - 1.0)


## v0.10.0: the lift shaft walls on one storey: the module left of the
## stairs at the back, with a doorway at the front for the lift doors.
static func _shaft(g: BlockGenerator, b: Dictionary, bi: int, y: float) -> void:
	var w: int = b.w
	var d: int = b.d
	var r90 := Basis(Vector3.UP, PI / 2)
	var none := Color(0, 0, 0, 0)
	g._add("int_wall", g._xf(b, r90, (w - 2) * M, y, (d - 0.5) * M), false, none, -1, bi)
	g._add("int_wall", g._xf(b, r90, (w - 1) * M, y, (d - 0.5) * M), false, none, -1, bi)
	g._add("int_wall_door", g._xf(b, Basis(), (w - 1.5) * M, y, (d - 1) * M), false, none, -1, bi)


## The lift shaft's module in building-local metres (x, z), or an empty rect.
static func shaft_rect(b: Dictionary) -> Rect2:
	if not b.get("lift", false):
		return Rect2()
	return Rect2((b.w - 2) * M, (b.d - 1) * M, M, M)


## The ground-floor front module i: door, shop window, lobby glass, garage
## door or house window, by type.
static func _front(g: BlockGenerator, b: Dictionary, bi: int, x: float, y: float, i: int, door_at: int, rng: RandomNumberGenerator) -> void:
	var xf := g._xf(b, Basis(), x, y, 0.0)
	var t: Color = b.tint
	var none := Color(0, 0, 0, 0)
	var is_door := i == door_at
	match b.type:
		"shop", "office", "station", "tower":
			if is_door:
				var wi := g._add("wall_shopdoor", xf, true, t, -1, bi)
				g._add("glass_shopdoor", xf, false, none, wi, bi)
				if b.locked:
					g._add("door_closed", g._xf(b, Basis(), x - 0.9, y, 0.0), false, none, wi, bi)
			elif b.type == "station" and i == 0:
				var wi := g._add("wall_garage", xf, true, t, -1, bi)
				g._add("garage_door", xf, false, none, wi, bi)
			elif b.type == "shop" or rng.randf() < 0.7:
				var wi := g._add("wall_shopfront", xf, true, t, -1, bi)
				g._add("glass_shopfront", xf, false, none, wi, bi)
			else:
				g._window_wall(b, bi, Basis(), x, y, 0.0, true)
		"warehouse", "garage":
			if is_door:
				var wi := g._add("wall_door", xf, true, t, -1, bi)
				if b.locked:
					g._add("door_closed", xf, false, none, wi, bi)
			elif b.type == "garage" or i % 2 == 0:
				var wi := g._add("wall_garage", xf, true, t, -1, bi)
				g._add("garage_door", xf, false, none, wi, bi)
			else:
				g._window_wall(b, bi, Basis(), x, y, 0.0, false)
		_:
			if is_door:
				var wi := g._add("wall_door", xf, true, t, -1, bi)
				if b.locked:
					g._add("door_closed", xf, false, none, wi, bi)
			else:
				g._window_wall(b, bi, Basis(), x, y, 0.0, true)


## Interior walls on storey s, and the list of rooms for furnishing:
## b.rooms gets {floor, rect (building-local x, z in metres), kind}.
static func _rooms(g: BlockGenerator, b: Dictionary, bi: int, s: int, y: float, rng: RandomNumberGenerator) -> void:
	var w: int = b.w
	var d: int = b.d
	var kind: String = b.type
	if s > 0 and kind in ["shop", "flats"]:
		kind = "flats"
	if s > 0 and kind == "station":
		kind = "office"
	if kind == "tower":
		kind = "lobby" if s == 0 else "open_office"
	var cuts_x: Array = []     # partitions across the depth at x = k * M
	var cut_z := -1             # a partition along the width at z = cut_z * M
	var cut_z_to := w           # ...from module 0 up to this one
	var room_kinds: Array = []
	match kind:
		"house":
			if w >= 2:
				cuts_x.append(rng.randi_range(1, w - 1))
			if w >= 4:
				cuts_x.append(clampi(cuts_x[0] + 2, 1, w - 1))
			room_kinds = ["living", "kitchen", "bedroom"] if s == 0 else ["bedroom", "bedroom", "bathroom"]
		"flats":
			for k in range(2, w, 2):
				cuts_x.append(k)
			if cuts_x.is_empty() and w >= 2:
				cuts_x.append(1)
			room_kinds = ["living", "bedroom", "kitchen", "living"]
		"shop":
			if d >= 2:
				cut_z = d - 1
				cut_z_to = w - 1
			room_kinds = ["shopfloor", "stock"]
		"office":
			if d >= 3 and w >= 3:
				cut_z = d - 1
				cut_z_to = 2
				cuts_x.append(2)
			room_kinds = ["office", "meeting"]
		"station":
			cut_z = d - 1
			cut_z_to = w - 1
			for k in range(1, w - 1):
				cuts_x.append(k)
			room_kinds = ["lobby", "cell"]
		"lobby":
			room_kinds = ["lobby"]
		"open_office":
			room_kinds = ["office"]
		"warehouse":
			if s == 0 and w >= 3 and d >= 2:
				cut_z = 1
				cut_z_to = 1
				cuts_x.append(1)
			room_kinds = ["hall", "office"]
		_:
			room_kinds = ["hall"]
	var none := Color(0, 0, 0, 0)
	var r90 := Basis(Vector3.UP, PI / 2)
	# Walls along the width.
	if cut_z > 0:
		var door_i := rng.randi_range(0, maxi(cut_z_to - 1, 0))
		for i in cut_z_to:
			if i == w - 1:
				continue    # the stairs' module stays open
			var k := "int_wall_door" if i == door_i else "int_wall"
			g._add(k, g._xf(b, Basis(), (i + 0.5) * M, y, cut_z * M), false, none, -1, bi)
	# Walls across the depth (only back of cut_z for station cells and
	# warehouse offices, the full depth otherwise).
	for cx in cuts_x:
		var j_from := 0
		var j_to := d
		if kind == "station":
			j_from = d - 1
		elif kind == "warehouse" or kind == "office":
			j_from = cut_z if kind == "office" else 0
			j_to = d if kind == "office" else cut_z
		var door_j := rng.randi_range(j_from, j_to - 1)
		for j in range(j_from, j_to):
			if cx == w - 1 and j == d - 1:
				continue
			var k := "int_wall_door" if j == door_j else "int_wall"
			if kind == "station":
				k = "int_wall"    # cells open through the front bars (the wall along the width)
			g._add(k, g._xf(b, r90, cx * M, y, (j + 0.5) * M), false, none, -1, bi)
	if kind == "station" and cut_z > 0:
		pass
	# Rooms for the furniture: the strips between the partitions.
	var xs: Array = [0]
	for cx in cuts_x:
		xs.append(cx)
	xs.append(w)
	xs.sort()
	var ri := 0
	for k in xs.size() - 1:
		var x0: int = xs[k]
		var x1: int = xs[k + 1]
		if x1 <= x0:
			continue
		var rk: String = room_kinds[ri % room_kinds.size()]
		ri += 1
		if cut_z > 0 and x0 < cut_z_to:
			b.rooms.append({"floor": s, "rect": Rect2(x0 * M, 0, (x1 - x0) * M, cut_z * M), "kind": rk})
			b.rooms.append({"floor": s, "rect": Rect2(x0 * M, cut_z * M, (x1 - x0) * M, (d - cut_z) * M), "kind": room_kinds[mini(1, room_kinds.size() - 1)]})
		else:
			b.rooms.append({"floor": s, "rect": Rect2(x0 * M, 0, (x1 - x0) * M, d * M), "kind": rk})


# --- Street furniture ---------------------------------------------------------------

static func furniture(g: BlockGenerator, _rng: RandomNumberGenerator) -> void:
	# Lamp posts round the kerb, arms over the road.
	var ex := g.nx * M
	var ez := g.nz * M
	var y := BlockGenerator.BASE_Y
	var spots := [
		[Vector3(1.0, y, 0.6), Basis(Vector3.UP, PI / 2)],
		[Vector3(ex - 1.0, y, 0.6), Basis(Vector3.UP, PI / 2)],
		[Vector3(1.0, y, ez - 0.6), Basis(Vector3.UP, -PI / 2)],
		[Vector3(ex - 1.0, y, ez - 0.6), Basis(Vector3.UP, -PI / 2)],
		[Vector3(ex * 0.5 + 6.0, y, 0.6), Basis(Vector3.UP, PI / 2)],
		[Vector3(ex * 0.5 - 6.0, y, ez - 0.6), Basis(Vector3.UP, -PI / 2)],
		[Vector3(0.6, y, ez * 0.5 + 6.0), Basis()],
		[Vector3(ex - 0.6, y, ez * 0.5 - 6.0), Basis(Vector3.UP, PI)],
	]
	for sp in spots:
		g._add("lamp_post", Transform3D(sp[1], sp[0]), false)
	# Bollards either side of the crossings (half way along each side; the
	# crossing is on the middle module, or the pair either side of the
	# middle on an even side).
	for k in [-1.0, 1.0]:
		var cx: float = _crossing(g.nx) + k * 2.4
		var cz: float = _crossing(g.nz) + k * 2.4
		g._add("bollard", Transform3D(Basis(), Vector3(cx, y, 0.4)), false)
		g._add("bollard", Transform3D(Basis(), Vector3(cx, y, ez - 0.4)), false)
		g._add("bollard", Transform3D(Basis(), Vector3(0.4, y, cz)), false)
		g._add("bollard", Transform3D(Basis(), Vector3(ex - 0.4, y, cz)), false)
	# Parks and car parks get low walls round them.
	if g.style == "park" or g.style == "carpark":
		for i in range(1, g.nx - 1):
			if i == g.nx / 2 or i == g.nx / 2 - 1:
				continue    # the ways in
			var c := (i + 0.5) * M
			g._add("low_wall", Transform3D(Basis(), Vector3(c, y, 2.0)), true)
			g._add("low_wall", Transform3D(Basis(), Vector3(c, y, ez - 2.0)), true)
		for i in range(1, g.nz - 1):
			if i == g.nz / 2 or i == g.nz / 2 - 1:
				continue
			var c := (i + 0.5) * M
			g._add("low_wall", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(2.0, y, c)), true)
			g._add("low_wall", Transform3D(Basis(Vector3.UP, PI / 2), Vector3(ex - 2.0, y, c)), true)


## Where the zebra crossing sits along a lot side of n modules (its centre,
## in metres from the lot corner): module n / 2, as CityGround lays it.
static func _crossing(n: int) -> float:
	return (n / 2 + 0.5) * M
