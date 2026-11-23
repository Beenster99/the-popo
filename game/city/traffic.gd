class_name TrafficSystem
extends Node3D
## Wave 2, Phase 2.3: the city's traffic.
##
## Cars, vans, buses, bikes, a bin lorry and a couple of artics drive round
## the road grid on the right, one lane each way, turning at random at the
## junctions. Every junction with three or four roads has traffic lights on
## a shared clock; drivers stop at red and on amber when they can. They keep
## their distance from whatever is in front (cars, people, rubble is left to
## the crash physics), sound the horn when stuck, pull over and stop for a
## police car with its siren going, and when shots or blasts go off near
## them they either floor it or leave the car where it is and run.
##
## Kerbside parked cars line the streets. Any of them, moving or parked, can
## be commandeered: the driver is pulled out and runs off.
##
## The host drives (the cars are ordinary CarSync cars, so everyone sees
## them move); every machine builds the same cars in the same order from
## the city seed. The host sends the light clock and who is still at the
## wheel once a second.
##
## Anything a car hits at speed (officers, suspects, people out walking) is
## knocked down and hurt (run over): cars no longer stop dead against a
## person as if against a post.

const MSG_TRAFFIC := 73
const CYCLE := 26.0
const GREEN := 10.5
const AMBER := 2.0
const MOVING := 22
const PARKED := 30
const CRUISE := 11.5           # m/s, about 40 km/h
const TURN_SPEED := 5.0
const STOP_BACK := 7.8         # m from the junction centre to the stop line
const LANE := CityGenerator.LANE
const KINDS := [["sedan", 30], ["hatchback", 26], ["van_panel", 10], ["van_box", 7], ["minibus", 5],
	["motorbike", 8], ["trash_truck", 3]]
const PARKED_KINDS := [["sedan", 40], ["hatchback", 34], ["van_panel", 12], ["van_box", 5], ["minibus", 4], ["motorbike", 5]]
enum L { GO, AMBER_L, RED }

var gen: CityGenerator
var cars: CarSync
var dispatch: Dispatcher
var clock := 0.0
## Moving traffic, in build order: {car, idx, a, b, pts, wi, mode, t, ...}
var drivers: Array = []
var parked: Array = []
var trailers: Array = []
var _rng := RandomNumberGenerator.new()
var _lit := {}                 # junction -> true
var _heads: Array = []         # [{j, along_x, lamps: [red, amber, green]}]
var _shown := {}               # head index -> light shown
var _mats := {}
var _sync_t := 0.0
var _hits := {}                # "car|person" -> time of the last hit
var _people: Array = []


func _ready() -> void:
	add_to_group("alarm_listeners")
	Net.register(MSG_TRAFFIC, _on_traffic)


func _exit_tree() -> void:
	Net.unregister(MSG_TRAFFIC)


# --- building (every machine, same order) ----------------------------------------------

func build(g: CityGenerator, c: CarSync, d: Dispatcher) -> void:
	gen = g
	cars = c
	dispatch = d
	_rng.seed = g.seed_value * 13 + 5
	_build_lights()
	var lanes := _all_lanes()
	_shuffle(lanes)
	var used := {}
	var n := 0
	for ln in lanes:
		if n >= MOVING:
			break
		var key := "%s>%s" % [ln[0], ln[1]]
		var back := "%s>%s" % [ln[1], ln[0]]
		if used.has(key) or (n % 2 == 0 and used.has(back)):
			continue
		used[key] = true
		var kind: String = "hgv_tractor" if n < 2 else _pick(KINDS)
		_spawn_moving(kind, ln[0], ln[1], n)
		n += 1
	_spawn_parked()


func _spawn_moving(kind: String, a: Vector2i, b: Vector2i, n: int) -> void:
	var pts := _lane(a, b)
	var d: Vector3 = (pts[1] - pts[0]).normalized()
	var at: Vector3 = (pts[0] as Vector3).lerp(pts[1], 0.75 if kind == "hgv_tractor" else _rng.randf_range(0.2, 0.7))
	var v := CivilianVehicle.make(kind, gen.seed_value + n * 17)
	v.name = "Traffic%d" % n
	v.position = at + Vector3(0, 1.3 if v.size.y < 0.9 else 1.6, 0)
	v.rotation.y = atan2(d.x, d.z)
	add_child(v)
	cars.add_car(v)
	var dr := {"car": v, "idx": v.net_id, "a": a, "b": b, "pts": [], "wi": 0, "mode": "drive", "t": 0.0,
		"stuck": 0.0, "wait": 0.0, "rev": 0.0, "yield": 0.0, "pace": _rng.randf_range(0.85, 1.1),
		"look": _rng.randi_range(0, 255), "rig": null, "wb": _wheelbase(v), "seen": true}
	dr.pts = [[at, 0, Vector2i.ZERO, false]]
	_append_lane(dr, a, b, 0.0)
	drivers.append(dr)
	v.commandeered.connect(_on_commandeered.bind(dr))
	_seat_driver(dr)
	if kind == "hgv_tractor":
		var tr := Trailer.make(["box", "tanker", "flatbed"][n % 3], gen.seed_value + n)
		tr.name = "Trailer%d" % n
		add_child(tr)
		tr.hitch(v)
		cars.add_car(tr)
		trailers.append(tr)


func _spawn_parked() -> void:
	var slots: Array = []
	for ln in _all_lanes():
		var a: Vector2i = ln[0]
		var b: Vector2i = ln[1]
		var pa := CityGenerator.junction(a.x, a.y)
		var pb := CityGenerator.junction(b.x, b.y)
		var d := (pb - pa).normalized()
		var r := Vector3(-d.z, 0, d.x)
		var length := pa.distance_to(pb)
		var t := 11.0
		while t < length - 11.0:
			if absf(t - length * 0.5) > 4.5:   # not on the zebra crossing
				slots.append([pa + d * t + r * CityGenerator.PARK_LANE, d])
			t += 7.2
	_shuffle(slots)
	var taken: Array = []
	for c in cars.cars:
		taken.append((c as Node3D).position)
	for s in slots:
		if parked.size() >= PARKED:
			break
		var p: Vector3 = s[0]
		var ok := true
		for q in taken:
			if Vector2(q.x - p.x, q.z - p.z).length() < 8.0:
				ok = false
				break
		if not ok:
			continue
		taken.append(p)
		var v := CivilianVehicle.make(_pick(PARKED_KINDS), gen.seed_value + 500 + parked.size() * 13)
		v.name = "Parked%d" % parked.size()
		var d: Vector3 = s[1]
		v.position = p + Vector3(0, 1.3, 0)
		v.rotation.y = atan2(d.x, d.z)
		add_child(v)
		cars.add_car(v)
		parked.append(v)


func _pick(table: Array) -> String:
	var total := 0
	for e in table:
		total += int(e[1])
	var x := _rng.randi_range(0, total - 1)
	for e in table:
		x -= int(e[1])
		if x < 0:
			return e[0]
	return table[0][0]


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _wheelbase(v: Car) -> float:
	var lo := INF
	var hi := -INF
	for w in v.wheel_mounts:
		lo = minf(lo, (w as Vector3).z)
		hi = maxf(hi, (w as Vector3).z)
	return maxf(hi - lo, 1.2)


# --- the road graph --------------------------------------------------------------------

static func neighbours(j: Vector2i) -> Array:
	var out: Array = []
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var n: Vector2i = j + d
		if n.x >= 0 and n.y >= 0 and n.x <= CityGenerator.GRID and n.y <= CityGenerator.GRID:
			out.append(n)
	return out


## Every one-way lane [from junction, to junction].
func _all_lanes() -> Array:
	var out: Array = []
	for i in CityGenerator.GRID + 1:
		for j in CityGenerator.GRID + 1:
			for n in neighbours(Vector2i(i, j)):
				out.append([Vector2i(i, j), n])
	return out


## A lane's start (just out of junction a) and stop line (before b).
static func _lane(a: Vector2i, b: Vector2i) -> Array:
	var pa := CityGenerator.junction(a.x, a.y)
	var pb := CityGenerator.junction(b.x, b.y)
	var d := (pb - pa).normalized()
	var r := Vector3(-d.z, 0, d.x)
	return [pa + d * STOP_BACK + r * LANE, pb - d * STOP_BACK + r * LANE]


## Adds lane a -> b to a driver's points: every 10 m, then the stop line.
func _append_lane(dr: Dictionary, a: Vector2i, b: Vector2i, from_t := 0.0) -> void:
	var ln := _lane(a, b)
	var s: Vector3 = ln[0]
	var e: Vector3 = ln[1]
	var length := s.distance_to(e)
	var along_x := a.y == b.y
	var k := from_t
	while k < length - 5.0:
		k += 10.0
		if k < length - 5.0:
			dr.pts.append([s.lerp(e, k / length), 0, Vector2i.ZERO, along_x])
	dr.pts.append([e, 1, b, along_x])
	dr.a = a
	dr.b = b


## At the end of its lane: pick where next and add the turn through the
## junction (a curve from one lane to the next) and the next lane.
func _extend(dr: Dictionary) -> void:
	var a: Vector2i = dr.a
	var b: Vector2i = dr.b
	var opts: Array = []
	for n in neighbours(b):
		if n != a:
			opts.append(n)
	var straight := b + (b - a)
	var c: Vector2i = opts[0]
	if dr.mode == "getaway":
		# Away from the police: the junction furthest from the nearest officer.
		var best := -INF
		for n in opts:
			var q := CityGenerator.junction(n.x, n.y)
			var d := INF
			for o in get_tree().get_nodes_in_group("officers"):
				d = minf(d, (o as Node3D).global_position.distance_to(q))
			d += _rng.randf_range(0.0, 25.0)
			if d > best:
				best = d
				c = n
	elif opts.has(straight) and _rng.randf() < 0.5:
		c = straight
	else:
		c = opts[_rng.randi_range(0, opts.size() - 1)]
	var pb := CityGenerator.junction(b.x, b.y)
	var l1 := _lane(a, b)
	var l2 := _lane(b, c)
	var p0: Vector3 = l1[1]
	var p2: Vector3 = l2[0]
	var d1 := (pb - CityGenerator.junction(a.x, a.y)).normalized()
	var d2 := (CityGenerator.junction(c.x, c.y) - pb).normalized()
	if c == straight:
		dr.pts.append([pb + Vector3(-d1.z, 0, d1.x) * LANE, 2, b, d1.x != 0.0])
	else:
		var ctrl := pb + Vector3(-d1.z, 0, d1.x) * LANE + Vector3(-d2.z, 0, d2.x) * LANE
		for k in [0.25, 0.5, 0.75]:
			var q: Vector3 = p0.lerp(ctrl, k).lerp(ctrl.lerp(p2, k), k)
			dr.pts.append([q, 2, b, d1.x != 0.0])
	dr.pts.append([p2, 0, c, d2.x != 0.0])
	_append_lane(dr, b, c)


# --- traffic lights --------------------------------------------------------------------

## What the light shows to traffic running along X (or Z) into junction j.
func light(j: Vector2i, along_x: bool) -> int:
	if not _lit.has(j):
		return L.GO
	var t := fposmod(clock + float(j.x * 5 + j.y * 3), CYCLE)
	if not along_x:
		t = fposmod(t - CYCLE * 0.5, CYCLE)
	if t < GREEN:
		return L.GO
	if t < GREEN + AMBER:
		return L.AMBER_L
	return L.RED


func _build_lights() -> void:
	var off := StandardMaterial3D.new()
	off.albedo_color = Color(0.12, 0.12, 0.12)
	_mats["off"] = off
	for n in ["red", "amber", "green"]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = {"red": Color(1.0, 0.15, 0.1), "amber": Color(1.0, 0.65, 0.1), "green": Color(0.2, 1.0, 0.45)}[n]
		_mats[n] = m
	var pole_mat := Cel.material(Color("2b2d31"), true, 0.015)
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.08
	pole_mesh.height = 3.2
	pole_mesh.radial_segments = 8
	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.34, 0.95, 0.26)
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.11
	lamp_mesh.height = 0.12
	lamp_mesh.radial_segments = 10
	lamp_mesh.rings = 4
	for i in CityGenerator.GRID + 1:
		for j in CityGenerator.GRID + 1:
			var jn := Vector2i(i, j)
			var ns := neighbours(jn)
			if ns.size() < 3:
				continue
			_lit[jn] = true
			var c := CityGenerator.junction(i, j)
			for n in ns:
				# Traffic coming from n: its light on the near right corner.
				var d := (c - CityGenerator.junction(n.x, n.y)).normalized()
				var r := Vector3(-d.z, 0, d.x)
				var base := c - d * 6.7 + r * 6.7 + Vector3(0, BlockGenerator.BASE_Y, 0)
				var pole := MeshInstance3D.new()
				pole.mesh = pole_mesh
				pole.material_override = pole_mat
				pole.position = base + Vector3(0, 1.6, 0)
				pole.visibility_range_end = 160.0
				add_child(pole)
				var head := Node3D.new()
				head.position = base + Vector3(0, 3.0, 0)
				head.basis = Basis.looking_at(d, Vector3.UP)   # -Z of the head faces where the cars come from
				add_child(head)
				var box := MeshInstance3D.new()
				box.mesh = head_mesh
				box.material_override = pole_mat
				box.visibility_range_end = 160.0
				head.add_child(box)
				var lamps: Array = []
				for k in 3:
					var lm := MeshInstance3D.new()
					lm.mesh = lamp_mesh
					lm.rotation.x = PI / 2
					lm.position = Vector3(0, 0.3 - k * 0.3, 0.13)
					lm.material_override = off
					lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					lm.visibility_range_end = 160.0
					head.add_child(lm)
					lamps.append(lm)
				_heads.append({"j": jn, "along_x": absf(d.x) > 0.5, "lamps": lamps})


func _update_lights() -> void:
	for i in _heads.size():
		var h: Dictionary = _heads[i]
		var s := light(h.j, h.along_x)
		if _shown.get(i, -1) == s:
			continue
		_shown[i] = s
		var lamps: Array = h.lamps
		(lamps[0] as MeshInstance3D).material_override = _mats["red"] if s == L.RED else _mats["off"]
		(lamps[1] as MeshInstance3D).material_override = _mats["amber"] if s == L.AMBER_L else _mats["off"]
		(lamps[2] as MeshInstance3D).material_override = _mats["green"] if s == L.GO else _mats["off"]


# --- the drivers -----------------------------------------------------------------------

## A person at the wheel (drawn sat down, posed once and left still).
func _seat_driver(dr: Dictionary) -> void:
	var v: CivilianVehicle = dr.car
	if dr.rig == null:
		var rig := OfficerRig.new()
		rig.name = "Driver"
		v.add_child(rig)
		rig.position = v.seats[0]
		SuspectLook.apply(rig.model, dr.look)
		for mi in rig.model.find_children("*", "GeometryInstance3D", true, false):
			(mi as GeometryInstance3D).visibility_range_end = 90.0
		rig.update_pose("sit", "drive", 0.0, 0.016)
		dr.rig = rig
		get_tree().create_timer(0.4).timeout.connect(func():
			if is_instance_valid(rig) and rig.tree:
				rig.tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL)
	else:
		SuspectLook.apply((dr.rig as OfficerRig).model, dr.look)
	(dr.rig as Node3D).visible = true
	dr.seen = true


func _clear_driver(dr: Dictionary) -> void:
	if dr.rig and is_instance_valid(dr.rig):
		(dr.rig as Node3D).visible = false
	dr.seen = false


func active_count() -> int:
	var n := 0
	for dr in drivers:
		if dr.mode in ["drive", "flee"]:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	clock += delta
	_update_lights()
	if not Net.is_host() or gen == null:
		return
	_people.clear()
	for o in get_tree().get_nodes_in_group("officers"):
		if (o as Officer).state != Officer.S.VEHICLE:
			_people.append(o)
	for s in get_tree().get_nodes_in_group("suspects"):
		if (s as Suspect).state not in [Suspect.S.IN_CAR, Suspect.S.DRIVE, Suspect.S.BOOKED]:
			_people.append(s)
	for dr in drivers:
		_drive(dr, delta)
	_run_over_step()
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 1.0
		_recycle()
		if Net.is_online():
			Net.broadcast(MSG_TRAFFIC, _encode(), Net.UNRELIABLE)


func _drive(dr: Dictionary, delta: float) -> void:
	var car: CivilianVehicle = dr.car
	if not is_instance_valid(car) or dr.mode in ["parked", "taken"]:
		return
	var xf := car.global_transform
	if car.wrecked or xf.basis.y.dot(Vector3.UP) < 0.55:
		_abandon(dr, xf.origin, true)
		return
	if dr.mode == "getaway" and _getaway_over(dr, delta):
		return
	if dr.mode == "leaving":
		dr.t -= delta
		cars.ai_inputs[dr.idx] = {"throttle": 0.0, "steer": 0.0, "handbrake": true, "horn": false}
		if dr.t <= 0.0:
			_driver_out(dr, dr.get("from", xf.origin))
		return
	var pos := xf.origin
	var fwd := xf.basis.z
	var v := car.linear_velocity.dot(fwd)
	# Along the points: past one when it is behind us (or close).
	var pts: Array = dr.pts
	while dr.wi < pts.size():
		var p: Vector3 = pts[dr.wi][0]
		var to := p - pos
		to.y = 0.0
		var seg := fwd
		if dr.wi > 0:
			seg = (p - (pts[dr.wi - 1][0] as Vector3))
			seg.y = 0.0
			seg = seg.normalized()
		if to.length() < 2.0 or to.dot(seg) < 0.0:
			dr.wi += 1
		else:
			break
	if pts.size() - dr.wi < 8:
		_extend(dr)
	if dr.wi > 8:
		pts = pts.slice(dr.wi - 1)
		dr.pts = pts
		dr.wi = 1
	# Off the route (shunted, spun): pick it up again from the nearest lane.
	var nxt: Vector3 = pts[mini(dr.wi, pts.size() - 1)][0]
	if Vector2(nxt.x - pos.x, nxt.z - pos.z).length() > 22.0:
		_reroute(dr, pos)
		return
	var look := 4.5 + absf(v) * 0.55
	var target: Vector3 = pts[pts.size() - 1][0]
	for i in range(dr.wi, pts.size()):
		var p: Vector3 = pts[i][0]
		if Vector2(p.x - pos.x, p.z - pos.z).length() >= look:
			target = p
			break
	dr.yield = maxf(0.0, dr.yield - delta)
	var vt: float = CRUISE * dr.pace
	var getaway: bool = dr.mode == "getaway"
	if getaway:
		vt = 21.0
	if dr.mode == "flee":
		dr.t -= delta
		vt = 17.0
		if dr.t <= 0.0:
			dr.mode = "drive"
	# Sirens: pull over to the kerb and stop for a police car coming through.
	var siren_behind := _siren_near(car)
	if siren_behind >= 0.0 and dr.mode == "drive" and not dr.has("suspect"):
		dr.yield = 3.0
	if dr.yield > 0.0:
		target += -xf.basis.x * 2.3
		vt = minf(vt, 0.0 if siren_behind >= 0.0 and siren_behind < 25.0 else 2.5)
	var local := xf.affine_inverse() * target
	var alpha := atan2(local.x, local.z)
	var want := atan2(2.0 * float(dr.wb) * sin(alpha), look)
	var max_a := lerpf(car.steer_max, car.steer_min, clampf(absf(v) / car.top_speed, 0.0, 1.0))
	var steer := clampf(want / max_a, -1.0, 1.0)
	# Slow for the turns ahead and stop for red lights.
	var dist := 0.0
	var last := pos
	for i in range(dr.wi, mini(pts.size(), dr.wi + 8)):
		var e: Array = pts[i]
		dist += Vector2(e[0].x - last.x, e[0].z - last.z).length()
		last = e[0]
		if dist > 45.0:
			break
		# A turn coming up, or under way (straight on is a single point).
		if e[1] == 2 and ((i + 1 < pts.size() and pts[i + 1][1] == 2) or (i > 0 and pts[i - 1][1] == 2)):
			vt = minf(vt, (8.0 if getaway else TURN_SPEED) + maxf(0.0, dist - 6.0) * 0.4)
		if e[1] == 1 and dr.mode != "flee" and not getaway:
			var s := light(e[2], e[3])
			if s == L.RED or (s == L.AMBER_L and dist > 9.0):
				vt = minf(vt, maxf(0.0, dist - 1.2) * 0.6)
				break
	# Whatever is in front.
	var gap := _gap_ahead(car, steer * max_a)
	if getaway:
		vt = minf(vt, maxf(5.0, gap * 1.3))   # shoves its way through
	elif gap < 40.0:
		vt = minf(vt, maxf(0.0, gap - 2.2) * 0.85)
	var horn := false
	if vt < 0.5 and gap < 8.0 and absf(v) < 0.5:
		dr.wait += delta
		horn = fmod(dr.wait, 6.0) > 4.0 and fmod(dr.wait, 6.0) < 4.6
	else:
		dr.wait = 0.0
	# Stuck against something with nothing in the way: back off a bit.
	if vt > 2.0 and absf(v) < 0.6:
		dr.stuck += delta
		if dr.stuck > 4.0:
			dr.stuck = 0.0
			dr.rev = 1.6
	else:
		dr.stuck = maxf(0.0, dr.stuck - delta)
	var inp := {"throttle": 0.0, "steer": steer, "handbrake": false, "horn": horn or dr.mode == "flee" or (getaway and gap < 15.0)}
	if dr.rev > 0.0:
		dr.rev -= delta
		inp.throttle = -0.7
		inp.steer = -steer
	elif vt < 0.3 and absf(v) < 1.0:
		inp.handbrake = true
	else:
		inp.throttle = clampf((vt - v) * 0.45, -1.0, 1.0)
		if inp.throttle < 0.0 and v < 1.0:
			inp.throttle = 0.0
	cars.ai_inputs[dr.idx] = inp


## m to the nearest thing in this car's path (INF for none), looking ahead
## along its heading bent by the steering.
func _gap_ahead(car: Car, steer_angle: float) -> float:
	var inv := car.global_transform.affine_inverse()
	var half_l := car.size.z * 0.5
	var half_w := car.size.x * 0.5
	var best := INF
	var bend := tan(steer_angle) * 0.5
	for c in cars.cars:
		if c == car or (c is Trailer and (c as Trailer).tractor == car):
			continue
		var cn := c as Car
		if cn.global_position.distance_squared_to(car.global_position) > 1600.0:
			continue
		var lp := inv * cn.global_position
		var ahead := lp.z - half_l - cn.size.z * 0.4
		if lp.z <= 0.0 or ahead > best:
			continue
		var side := absf(lp.x - lp.z * bend)
		if side < half_w + cn.size.x * 0.5 + 0.4:
			best = ahead
	for p in _people:
		var pn := p as Node3D
		if pn.global_position.distance_squared_to(car.global_position) > 900.0:
			continue
		var lp := inv * pn.global_position
		var ahead := lp.z - half_l - 0.3
		if lp.z <= 0.0 or ahead > best:
			continue
		if absf(lp.x - lp.z * bend) < half_w + 0.8:
			best = ahead
	return best


## A police car with its siren on: how far behind us it is (m), or -1.
## Ahead of us and coming this way counts too (we pull over for it).
func _siren_near(car: Car) -> float:
	for pc in get_tree().get_nodes_in_group("police_cars"):
		var p := pc as PoliceCar
		if p.siren <= 0 or p == car:
			continue
		var d := p.global_position.distance_to(car.global_position)
		if d > 40.0:
			continue
		var lp := car.global_transform.affine_inverse() * p.global_position
		var closing := (p.linear_velocity - car.linear_velocity).dot((car.global_position - p.global_position).normalized())
		if lp.z < 0.0 or closing > 2.0:
			return d
	return -1.0


## Back on the road from wherever it ended up: the nearest lane going the
## way it points.
func _reroute(dr: Dictionary, pos: Vector3) -> void:
	var best := INF
	var pick: Array = []
	var fwd: Vector3 = (dr.car as Car).global_transform.basis.z
	for ln in _all_lanes():
		var l2 := _lane(ln[0], ln[1])
		var s: Vector3 = l2[0]
		var e: Vector3 = l2[1]
		var dir := (e - s).normalized()
		var t := clampf((pos - s).dot(dir), 0.0, s.distance_to(e))
		var q := s + dir * t
		var d := Vector2(q.x - pos.x, q.z - pos.z).length() + (0.0 if dir.dot(fwd) > 0.3 else 15.0)
		if d < best:
			best = d
			pick = [ln[0], ln[1], q, t]
	if pick.is_empty():
		return
	dr.pts = [[pick[2], 0, Vector2i.ZERO, false]]
	dr.wi = 0
	_append_lane(dr, pick[0], pick[1], pick[3])


# --- alarms, commandeering, abandoning -------------------------------------------------

## Shots, blasts, a building coming down: drivers near it put their foot
## down, or stop and get out and run.
func on_alarm(at: Vector3, radius: float) -> void:
	if not Net.is_host():
		return
	for dr in drivers:
		if dr.mode != "drive" or not is_instance_valid(dr.car):
			continue
		var d := (dr.car as Node3D).global_position.distance_to(at)
		if d > radius * 0.8:
			continue
		var slow := (dr.car as Car).linear_velocity.length() < 6.0
		if (d < 18.0 or slow) and _rng.randf() < 0.45:
			_abandon(dr, at, false)
		else:
			dr.mode = "flee"
			dr.t = _rng.randf_range(6.0, 10.0)


## The driver gives up on the car: stops and gets out (now, if it is a wreck).
func _abandon(dr: Dictionary, from: Vector3, now: bool) -> void:
	if dr.mode in ["parked", "taken", "leaving"]:
		return
	dr.from = from
	if now:
		_driver_out(dr, from)
	else:
		dr.mode = "leaving"
		dr.t = _rng.randf_range(0.6, 1.4)


func _driver_out(dr: Dictionary, from: Vector3, door := 0) -> void:
	dr.mode = "parked"
	cars.ai_inputs.erase(dr.idx)
	if not dr.seen:
		return
	_clear_driver(dr)
	var car: CivilianVehicle = dr.car
	if dispatch == null or car.wrecked and _rng.randf() < 0.5:
		return   # didn't make it out
	var at := car.door_point(mini(door, car.doors.size() - 1))
	at.y = maxf(at.y - 0.6, BlockGenerator.BASE_Y - 0.15)
	var s := dispatch.spawn_suspect(at, Suspect.S.WANDER, false)
	s.look = dr.look
	s.civilian = true
	s.route = PedSystem.route_near(gen, at, _rng)
	s.on_alarm(from, 999.0)
	if s.state != Suspect.S.PANIC:
		s.set_state(Suspect.S.PANIC)
		var away := at - from
		away.y = 0.0
		s._goal = s._near(at + away.normalized() * 22.0, 3.0)
	if PedSystem.current:
		PedSystem.current.adopt(s)


## Host: an officer is getting in. Whoever is driving gets out the other
## side and runs.
func _on_commandeered(by: Node, dr: Dictionary) -> void:
	if not Net.is_host():
		return
	if dr.mode == "getaway":
		_bail(dr)
	elif dr.mode in ["drive", "flee", "leaving"]:
		_driver_out(dr, (by as Node3D).global_position, 1)
	dr.mode = "taken"
	cars.ai_inputs.erase(dr.idx)


## Host, once a second: abandoned cars well away from everyone get a new
## driver and go back into the traffic, so the streets don't empty.
func _recycle() -> void:
	if active_count() >= MOVING:
		return
	var eyes: Array = []
	for o in get_tree().get_nodes_in_group("officers"):
		eyes.append((o as Node3D).global_position)
	for dr in drivers:
		if dr.mode not in ["parked", "taken"] or dr.get("hold", false):
			continue
		var car: CivilianVehicle = dr.car
		if car.wrecked or car.kind == "hgv_tractor" or not car.occupants().is_empty():
			continue
		if int(cars.fire_state.get(dr.idx, 0)) != CarSync.Fire.OK:
			continue
		var far := true
		for e in eyes:
			if (e as Vector3).distance_to(car.global_position) < 110.0:
				far = false
		if not far:
			continue
		# A lane well away from every officer.
		for tries in 12:
			var lanes := _all_lanes()
			var ln: Array = lanes[_rng.randi_range(0, lanes.size() - 1)]
			var l2 := _lane(ln[0], ln[1])
			var p: Vector3 = (l2[0] as Vector3).lerp(l2[1], 0.3)
			var ok := true
			for e in eyes:
				if (e as Vector3).distance_to(p) < 110.0:
					ok = false
			for c in cars.cars:
				if (c as Node3D).global_position.distance_to(p) < 9.0:
					ok = false
			if not ok:
				continue
			var d: Vector3 = ((l2[1] as Vector3) - (l2[0] as Vector3)).normalized()
			car.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), p + Vector3(0, 1.2, 0))
			car.linear_velocity = Vector3.ZERO
			car.angular_velocity = Vector3.ZERO
			dr.pts = [[p, 0, Vector2i.ZERO, false]]
			dr.wi = 0
			_append_lane(dr, ln[0], ln[1], (l2[0] as Vector3).distance_to(p))
			dr.mode = "drive"
			dr.look = _rng.randi_range(0, 255)
			_seat_driver(dr)
			return


# --- car thieves and chases (Wave 2 jobs) ---------------------------------------------

## Host: a car for a theft call: a moving one well out of sight, parked at
## the kerb near p with nobody in it. Returns its driver record ({} if none).
func borrow_car(p: Vector3) -> Dictionary:
	var eyes := _eyes()
	var slot := _kerb_near(p)
	if slot.is_empty():
		return {}
	for dr in drivers:
		var car: CivilianVehicle = dr.car
		if dr.mode != "drive" or car.kind in ["hgv_tractor", "trash_truck"]:
			continue
		if PedSystem._nearest(eyes, car.global_position) < 90.0:
			continue
		var d: Vector3 = slot[1]
		car.global_transform = Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), (slot[0] as Vector3) + Vector3(0, 1.2, 0))
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		dr.mode = "parked"
		dr.hold = true    # not back into the traffic: it's the thief's
		cars.ai_inputs.erase(dr.idx)
		_clear_driver(dr)
		return dr
	return {}


## Host: a moving car for a chase: out of sight but not far off.
func pick_for_pursuit() -> Dictionary:
	var eyes := _eyes()
	var best: Dictionary = {}
	var best_s := INF
	for dr in drivers:
		var car: CivilianVehicle = dr.car
		if dr.mode != "drive" or car.kind in ["hgv_tractor", "trash_truck"]:
			continue
		var d := PedSystem._nearest(eyes, car.global_position)
		if d < 70.0 or d > 230.0:
			continue
		var score := absf(d - 120.0) + _rng.randf_range(0.0, 30.0)
		if score < best_s:
			best_s = score
			best = dr
	return best


## Host: suspect s takes the car and drives it like they stole it.
func getaway(dr: Dictionary, s: Suspect) -> void:
	dr.mode = "getaway"
	dr.erase("hold")
	dr.suspect = s
	dr.still = 0.0
	dr.look = s.look
	s.set_meta("getaway", dr.car)
	s.set_state(Suspect.S.DRIVE)
	_seat_driver(dr)
	_reroute(dr, (dr.car as Node3D).global_position)


## Host: whether the getaway has ended (stopped, wrecked, burning, boxed in
## with officers there: the driver bails out and runs).
func _getaway_over(dr: Dictionary, delta: float) -> bool:
	var car: CivilianVehicle = dr.car
	var s: Suspect = dr.suspect
	if not is_instance_valid(s) or s.state != Suspect.S.DRIVE:
		# Off the map (the call timed out) or dealt with some other way.
		dr.mode = "parked"
		dr.erase("suspect")
		cars.ai_inputs.erase(dr.idx)
		_clear_driver(dr)
		return true
	s.global_position = car.global_position
	var near := PedSystem._nearest(_eyes(), car.global_position)
	dr.still = dr.still + delta if car.linear_velocity.length() < 1.5 and near < 18.0 else 0.0
	var hurt: int = cars.fire_state.get(dr.idx, CarSync.Fire.OK)
	if dr.still > 2.5 or hurt != CarSync.Fire.OK or float(cars.car_hp.get(dr.idx, CarSync.CAR_HP)) < 55.0:
		_bail(dr)
		return true
	return false


func _bail(dr: Dictionary) -> void:
	var car: CivilianVehicle = dr.car
	var s: Suspect = dr.get("suspect")
	dr.mode = "parked"
	dr.erase("suspect")
	cars.ai_inputs.erase(dr.idx)
	_clear_driver(dr)
	if s == null or not is_instance_valid(s) or s.state != Suspect.S.DRIVE:
		return
	s.remove_meta("getaway")
	var door := car.door_point(0)
	door.y = car.global_position.y - 0.6
	if dispatch and dispatch.nav and dispatch.nav.ready_to_use:
		var q := dispatch.nav.closest(door)
		if q.distance_to(door) < 4.0:
			door = q
	s.global_position = door
	s.home = door
	s.set_state(Suspect.S.LOITER)
	var t := {"o": null, "d": INF, "los": false}
	for o in get_tree().get_nodes_in_group("officers"):
		var d := (o as Node3D).global_position.distance_to(door)
		if d < t.d:
			t = {"o": o, "d": d, "los": true}
	s._bolt(t)
	if dispatch:
		dispatch.say("DISPATCH: the driver's out and running!" if not s.armed else "DISPATCH: driver's out, and armed. Watch yourselves.")


func _eyes() -> Array:
	var out: Array = []
	for o in get_tree().get_nodes_in_group("officers"):
		out.append((o as Node3D).global_position)
	return out


## The nearest kerbside parking spot to p: [position, facing].
func _kerb_near(p: Vector3) -> Array:
	var best := INF
	var out: Array = []
	for ln in _all_lanes():
		var l2 := _lane(ln[0], ln[1])
		var s: Vector3 = l2[0]
		var e: Vector3 = l2[1]
		var dir := (e - s).normalized()
		var length := s.distance_to(e)
		var t := clampf((p - s).dot(dir), 6.0, length - 6.0)
		var q := s + dir * t + Vector3(-dir.z, 0, dir.x) * (CityGenerator.PARK_LANE - LANE)
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		var clear := true
		for c in cars.cars:
			if (c as Node3D).global_position.distance_to(q) < 6.0:
				clear = false
				break
		if clear and d < best:
			best = d
			out = [q, dir]
	return out


# --- run over --------------------------------------------------------------------------

## Host: anyone a moving car drives into is knocked flying and hurt.
func _run_over_step() -> void:
	var now := Time.get_ticks_msec()
	for c in cars.cars:
		var car := c as Car
		var vel := car.linear_velocity
		var spd := vel.length()
		if spd < 3.5:
			continue
		var inv := car.global_transform.affine_inverse()
		var hx := car.size.x * 0.5 + 0.35
		var hz := car.size.z * 0.5 + 0.35
		for p in _people:
			var pn := p as Node3D
			if pn.global_position.distance_squared_to(car.global_position) > 64.0:
				continue
			var lp := inv * (pn.global_position + Vector3(0, 0.9, 0))
			if absf(lp.x) > hx or absf(lp.z) > hz or lp.y < -1.6 or lp.y > 2.2:
				continue
			var pv: Vector3 = (pn as CharacterBody3D).velocity
			var rel := (vel - pv).dot(vel / spd)
			if rel < 3.0:
				continue
			var key := "%d|%d" % [car.get_instance_id(), pn.get_instance_id()]
			if now - int(_hits.get(key, 0)) < 1200:
				continue
			_hits[key] = now
			var dmg := rel * rel * 0.32
			var dir := (vel / spd + Vector3(0, 0.35, 0)).normalized()
			if pn is Officer:
				(pn as Officer).take_damage(dmg, dir, "torso")
				(pn as Officer).shove(dir * rel * 0.7)
			elif pn is Suspect:
				var s := pn as Suspect
				s.take_damage(dmg, dir)
				if s.state != Suspect.S.DOWN and s.is_free():
					s.velocity = dir * rel * 0.6
					s.set_state(Suspect.S.STAGGER)
			if rel > 7.0 and Gore.level() > 0:
				Gore.hit(get_parent(), car.global_position, pn.global_position + Vector3(0, 1.0, 0))
			if cars.simulates_locally(cars.cars.find(car)):
				car.apply_central_impulse(-vel / spd * minf(rel * 70.0, 1400.0))


# --- network ---------------------------------------------------------------------------

func _encode() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_float(clock)
	b.put_u8(drivers.size())
	for dr in drivers:
		b.put_u8(1 if dr.seen else 0)
		b.put_u8(dr.look)
	return b.data_array


func _on_traffic(from: int, data: PackedByteArray) -> void:
	if from != 1 or Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var c := b.get_float()
	if absf(c - clock) > 0.3:
		clock = c
	var n := b.get_u8()
	for i in n:
		var seen := b.get_u8() == 1
		var look := b.get_u8()
		if i >= drivers.size():
			continue
		var dr: Dictionary = drivers[i]
		if seen and (not dr.seen or dr.look != look):
			dr.look = look
			_seat_driver(dr)
		elif not seen and dr.seen:
			_clear_driver(dr)
