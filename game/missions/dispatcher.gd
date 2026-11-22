class_name Dispatcher
extends Node
## Phase 1.4: dispatch, crimes and the crime level for one city block.
##
## The host runs it all and tells the clients. Every so often a call comes in
## from one of three templates:
##   Robbery in progress: two suspects turning over a shop. When officers
##     arrive (or they have what they came for) they run and hide.
##   Armed suspect: someone waving a gun about on the street. Runs or shoots.
##   Traffic stop: a speeding car laps the block. Pull it over with the roof
##     lights on behind it; walk up to it and it goes wrong: the driver bails
##     and runs, sometimes shooting.
## A call is closed when every suspect in it is booked into custody (cuffed,
## put in a police car and driven to the custody bay) or down. Calls left too
## long are lost: the suspects get away.
##
## The crime level (0 to 100) creeps up all the time, faster for every open
## call, and drops for each suspect dealt with and each call closed. Arrests
## and suspects shot count the same: there is no conduct score.

enum Kind { ROBBERY, ARMED, TRAFFIC }
enum CallState { ACTIVE, CLOSED, LOST }

const MSG_STATE := 80        # host -> all: crime, calls, suspects (10 a second)
const MSG_RADIO := 81        # host -> all: a line of radio chatter
const MSG_SHOT := 82         # host -> all: a suspect fired (origin, end)

const FIRST_CALL := 20.0     # s after the block loads
const CALL_GAP := Vector2(25.0, 50.0)
const MAX_CALLS := 2
const CALL_TIMEOUT := 300.0
const CRIME_START := 35.0
const CRIME_DRIFT := 0.04    # per second, always
const CRIME_PER_CALL := 0.12 # per second, for each open call
const CRIME_DEALT := 5.0     # each suspect booked or down
const CRIME_CLOSED := 10.0   # each call closed
const CRIME_LOST := 8.0      # each call lost
const SHOT_DAMAGE := 16.0
## The custody bay: drive prisoners here (east road, half way along).
const BAY := Vector3(56.5, 0.0, 24.0)
const BAY_RADIUS := 4.5
const BOOK_TIME := 1.2
## The speeding car's lap: the middle of the ring road.
const LAP := [Vector3(-6, 0, -6), Vector3(54, 0, -6), Vector3(54, 0, 54), Vector3(-6, 0, 54)]
const KIND_NAMES := ["Robbery in progress", "Armed suspect", "Traffic stop"]

signal radio(text: String)

var gen: BlockGenerator
var world: DestructionWorld
var cars: CarSync
var nav: BlockNav
## The civilian car the traffic stop uses (its index in cars).
var civ_car: Car
var crime := CRIME_START
## id -> {id, kind, state, pos, marker, t, suspects: Array[int], text}
var calls := {}
var suspects := {}           # net id -> Suspect
var hide_spots: Array = []
var enabled := true          # host: whether calls come in at all (tests turn it off)

var _next_call_t := FIRST_CALL
var _next_call_id := 1
var _next_suspect_id := 1
var _tick := 0
var _clock := 0.0
var _rng := RandomNumberGenerator.new()
var _book_t := {}            # car or suspect -> seconds at the bay
var _buffers := {}           # client: suspect id -> [[time, pos, yaw, speed]]
var _markers := {}           # call id -> Node3D
var _bay_node: Node3D
var _traffic := {}           # host: {call, phase, t, near_t}
var _look_counter := 0


func _ready() -> void:
	_rng.randomize()
	Net.register(MSG_STATE, _on_state)
	Net.register(MSG_RADIO, _on_radio)
	Net.register(MSG_SHOT, _on_shot)
	_build_bay()


func _exit_tree() -> void:
	Net.unregister(MSG_STATE)
	Net.unregister(MSG_RADIO)
	Net.unregister(MSG_SHOT)


func setup(g: BlockGenerator, w: DestructionWorld, c: CarSync, n: BlockNav, civ: Car) -> void:
	gen = g
	world = w
	cars = c
	nav = n
	civ_car = civ
	if civ_car and Net.is_host():
		civ_car.dented.connect(func(_p, _d, _a): _traffic_bail("rammed"))


func bay_position() -> Vector3:
	return Vector3(BAY.x, BlockGenerator.BASE_Y - 0.15, BAY.z)


# --- host: the loop ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_tick += 1
	_clock += delta
	if not Net.is_host():
		_interpolate()
		_update_markers()
		return
	if nav and nav.ready_to_use and hide_spots.is_empty() and gen:
		_find_hide_spots()
	# Calls coming in.
	if enabled and gen and nav and nav.ready_to_use:
		_next_call_t -= delta
		if _next_call_t <= 0.0 and _active_count() < MAX_CALLS:
			_next_call_t = _rng.randf_range(CALL_GAP.x, CALL_GAP.y)
			start_call(_pick_kind())
	# Crime creeps up.
	crime = clampf(crime + (CRIME_DRIFT + CRIME_PER_CALL * _active_count()) * delta, 0.0, 100.0)
	_traffic_step(delta)
	_booking(delta)
	_check_calls()
	_update_markers()
	if _tick % 6 == 0 and Net.is_online():
		Net.broadcast(MSG_STATE, _encode_state(), Net.ORDERED, 4)


func _active_count() -> int:
	var n := 0
	for c in calls.values():
		if c.state == CallState.ACTIVE:
			n += 1
	return n


func _pick_kind() -> Kind:
	var kinds := [Kind.ROBBERY, Kind.ARMED, Kind.TRAFFIC]
	for c in calls.values():
		if c.state == CallState.ACTIVE:
			kinds.erase(c.kind)
	if civ_car == null:
		kinds.erase(Kind.TRAFFIC)
	if kinds.is_empty():
		return Kind.ROBBERY
	return kinds[_rng.randi_range(0, kinds.size() - 1)]


## Host: opens a call of this kind. Returns its id (or -1).
func start_call(kind: Kind) -> int:
	var c := {"id": _next_call_id, "kind": kind, "state": CallState.ACTIVE, "pos": Vector3.ZERO,
		"marker": Vector3.ZERO, "t": 0.0, "suspects": [], "text": "", "seen_t": 0.0}
	match kind:
		Kind.ROBBERY:
			var b := _shop()
			if b.is_empty():
				return -1
			var inside: Vector3 = b.origin + b.u * (b.w * BlockGenerator.M * 0.5) + b.v * (BlockGenerator.M * 0.9) + Vector3(0, 0.05, 0)
			c.pos = inside
			c.text = "Robbery in progress at the %s on the %s side. Two suspects." % [b.type, b.side]
			for i in 2:
				var p: Vector3 = inside + b.u * (1.4 * (i * 2 - 1))
				c.suspects.append(spawn_suspect(p, Suspect.S.ROB, _rng.randf() < 0.25, c.id).net_id)
		Kind.ARMED:
			var p := _street_spot()
			c.pos = p
			c.text = "Armed suspect seen on the street, %s. Approach with care." % _side_name(p)
			c.suspects.append(spawn_suspect(p, Suspect.S.LOITER, true, c.id).net_id)
		Kind.TRAFFIC:
			if civ_car == null or not _traffic.is_empty():
				return -1
			var s := spawn_suspect(civ_car.global_position, Suspect.S.DRIVE, _rng.randf() < 0.4, c.id)
			c.suspects.append(s.net_id)
			c.pos = civ_car.global_position
			c.text = "Speeding car lapping the block. Get behind it with your lights on and pull it over."
			_traffic = {"call": c.id, "phase": "drive", "t": 0.0, "near_t": 0.0, "suspect": s.net_id}
	c.marker = c.pos
	calls[c.id] = c
	_next_call_id += 1
	say("DISPATCH: %s" % c.text)
	return c.id


func spawn_suspect(p: Vector3, st: Suspect.S, armed: bool, call_id := -1) -> Suspect:
	var s := Suspect.new()
	s.net_id = _next_suspect_id
	_next_suspect_id += 1
	_look_counter += 1
	s.look = (_look_counter * 37 + _rng.randi_range(0, 200)) % 256
	s.armed = armed
	s.call_id = call_id
	s.home = p
	s.nav = nav
	s.dispatcher = self
	s.hide_spots = hide_spots
	s.name = "Suspect%d" % s.net_id
	get_parent().add_child(s)
	s.global_position = p
	s.set_state(st)
	suspects[s.net_id] = s
	return s


## An enterable shop if there is one, else any enterable building.
func _shop() -> Dictionary:
	var pick: Dictionary = {}
	for b in gen.buildings:
		if b.enterable and (pick.is_empty() or (b.type == "shop" and pick.type != "shop")):
			pick = b
	return pick


## A pavement spot near the street, away from the officers.
func _street_spot() -> Vector3:
	var e := BlockGenerator.N * BlockGenerator.M
	var best := Vector3(e * 0.5, BlockGenerator.BASE_Y, 1.0)
	var best_d := -1.0
	for i in 8:
		var along := _rng.randf_range(4.0, e - 4.0)
		var side := _rng.randi_range(0, 3)
		var p: Vector3 = [Vector3(along, 0, 1.2), Vector3(along, 0, e - 1.2), Vector3(1.2, 0, along), Vector3(e - 1.2, 0, along)][side]
		p.y = BlockGenerator.BASE_Y + 0.05
		p = nav.closest(p)
		var d := INF
		for o in get_tree().get_nodes_in_group("officers"):
			d = minf(d, (o as Node3D).global_position.distance_to(p))
		if d > best_d:
			best_d = d
			best = p
	return best


func _side_name(p: Vector3) -> String:
	var e := BlockGenerator.N * BlockGenerator.M
	var dn := [p.z, e - p.z, p.x, e - p.x]
	var names := ["north", "south", "west", "east"]
	var i := 0
	for k in 4:
		if dn[k] < dn[i]:
			i = k
	return "%s side" % names[i]


## Places to hide: every room of the enterable buildings (upstairs too), and
## yards and alleys behind the others.
func _find_hide_spots() -> void:
	var M := BlockGenerator.M
	for b in gen.buildings:
		if not b.enterable:
			continue
		for s in b.storeys:
			for i in b.w:
				for j in b.d:
					var p: Vector3 = b.origin + b.u * ((i + 0.5) * M) + b.v * ((j + 0.5) * M) + Vector3(0, s * BlockGenerator.STOREY + 0.05, 0)
					var q := nav.closest(p)
					if q.distance_to(p) < 0.8:
						hide_spots.append(q)
	var e := BlockGenerator.N * M
	for i in 6:
		for j in 6:
			var p := Vector3(6.0 + i * (e - 12.0) / 5.0, BlockGenerator.BASE_Y + 0.05, 6.0 + j * (e - 12.0) / 5.0)
			var inside := false
			for b in gen.buildings:
				if (b.bounds as AABB).grow(0.5).has_point(p + Vector3(0, 0.5, 0)):
					inside = true
			if inside:
				continue
			var q := nav.closest(p)
			if q.distance_to(p) < 1.0:
				hide_spots.append(q)
	for s in suspects.values():
		(s as Suspect).hide_spots = hide_spots


# --- host: shots ---------------------------------------------------------------------

## A suspect fires: hits officers, cars and the world, and everyone hears it.
func suspect_shot(s: Suspect, origin: Vector3, dir: Vector3) -> void:
	var space := s.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * 60.0, 1 | 2 | 16, [s.get_rid()])
	var hit := space.intersect_ray(q)
	var end: Vector3 = hit.position if hit else origin + dir * 60.0
	if hit and hit.collider is Officer:
		var o := hit.collider as Officer
		o.take_damage(SHOT_DAMAGE, dir, o.body_part_at(hit.position))
	elif hit and hit.collider is Car and cars:
		var surface := cars.bullet_hit(hit.collider, hit.position, dir)
		Sfx.impact(get_parent(), hit.position, surface, 0.8)
	elif hit and hit.collider is Suspect:
		(hit.collider as Suspect).take_damage(SHOT_DAMAGE, dir)
	elif hit and world:
		world.bullet_hit(hit.collider, hit.position, hit.normal, dir)
	var b := StreamPeerBuffer.new()
	for v in [origin, end]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	if Net.is_online():
		Net.broadcast(MSG_SHOT, b.data_array, Net.UNRELIABLE)
	_shot_fx(origin, end)


func _on_shot(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var a := Vector3(b.get_float(), b.get_float(), b.get_float())
	var e := Vector3(b.get_float(), b.get_float(), b.get_float())
	_shot_fx(a, e)


## A bang, a muzzle flash and a short-lived tracer.
func _shot_fx(a: Vector3, e: Vector3) -> void:
	var parent := get_parent()
	if parent == null:
		return
	Sfx.gunshot(parent, a)
	var flash := OmniLight3D.new()
	flash.light_color = Color("ffcf7a")
	flash.light_energy = 4.0
	flash.omni_range = 5.0
	parent.add_child(flash)
	flash.global_position = a
	var line := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(e)
	im.surface_end()
	line.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("ffe9a8")
	line.material_override = mat
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(line)
	var tree := get_tree()
	tree.create_timer(0.06).timeout.connect(flash.queue_free)
	tree.create_timer(0.08).timeout.connect(line.queue_free)


# --- host: custody ----------------------------------------------------------------------

## Prisoners in a police car stopped at the bay, or walked into it, are booked.
func _booking(delta: float) -> void:
	var bay := bay_position()
	var seen := {}
	for s in suspects.values():
		var sp := s as Suspect
		var key: Object = null
		if sp.state == Suspect.S.IN_CAR and sp.car and is_instance_valid(sp.car):
			var c := sp.car
			if _flat(c.global_position, bay) < BAY_RADIUS and c.linear_velocity.length() < 2.5:
				key = c
		elif sp.state == Suspect.S.CUFFED and _flat(sp.global_position, bay) < BAY_RADIUS:
			key = sp
		if key == null:
			continue
		seen[key] = true
		_book_t[key] = float(_book_t.get(key, 0.0)) + delta / _count_for(key)
		if _book_t[key] >= BOOK_TIME:
			book(sp)
	for k in _book_t.keys():
		if not seen.has(k):
			_book_t.erase(k)


func _count_for(key: Object) -> float:
	if key is Car:
		var n := 0
		for s in suspects.values():
			if (s as Suspect).car == key and (s as Suspect).state == Suspect.S.IN_CAR:
				n += 1
		return maxf(1.0, n)
	return 1.0


func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func book(s: Suspect) -> void:
	if s.state == Suspect.S.BOOKED:
		return
	s.set_state(Suspect.S.BOOKED)
	s.car = null
	crime = maxf(0.0, crime - CRIME_DEALT)
	say("CUSTODY: suspect booked in. Good work.")


# --- host: calls --------------------------------------------------------------------------

func _check_calls() -> void:
	for c in calls.values():
		if c.state != CallState.ACTIVE:
			continue
		c.t += 1.0 / Engine.physics_ticks_per_second
		var all_done := true
		for id in c.suspects:
			var s: Suspect = suspects.get(id)
			if s == null:
				continue
			if s.state == Suspect.S.DOWN and not s.has_meta("counted"):
				s.set_meta("counted", true)
				crime = maxf(0.0, crime - CRIME_DEALT)
				say("DISPATCH: suspect down.")
			if not s.is_done():
				all_done = false
		# Dispatch keeps the marker on the latest sighting.
		c.seen_t -= 1.0 / Engine.physics_ticks_per_second
		if c.seen_t <= 0.0:
			c.seen_t = 6.0
			for id in c.suspects:
				var s: Suspect = suspects.get(id)
				if s and not s.is_done() and s.state != Suspect.S.IN_CAR:
					c.marker = s.global_position if s.state != Suspect.S.DRIVE or civ_car == null else civ_car.global_position
					break
		if all_done:
			c.state = CallState.CLOSED
			crime = maxf(0.0, crime - CRIME_CLOSED)
			say("DISPATCH: %s call closed. Thanks, units." % KIND_NAMES[c.kind].to_lower())
			if c.kind == Kind.TRAFFIC:
				_traffic.clear()
		elif c.t > CALL_TIMEOUT:
			c.state = CallState.LOST
			crime = minf(100.0, crime + CRIME_LOST)
			for id in c.suspects:
				var s: Suspect = suspects.get(id)
				if s and s.is_free():
					s.set_state(Suspect.S.BOOKED)   # gone: off the map
			if c.kind == Kind.TRAFFIC:
				var tr: Suspect = suspects.get(_traffic.get("suspect", -1))
				if tr and tr.state == Suspect.S.DRIVE:
					tr.set_state(Suspect.S.BOOKED)
				_traffic.clear()
			say("DISPATCH: we've lost them. %s call closed, suspects got away." % KIND_NAMES[c.kind])


func active_calls() -> Array:
	return calls.values().filter(func(c): return c.state == CallState.ACTIVE)


## Everyone: a line on the radio (host sends it to the clients too).
func say(text: String) -> void:
	if Net.is_host() and Net.is_online():
		var b := StreamPeerBuffer.new()
		b.put_utf8_string(text)
		Net.broadcast(MSG_RADIO, b.data_array)
	radio.emit(text)


func _on_radio(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	radio.emit(b.get_utf8_string())


# --- host: the traffic stop ----------------------------------------------------------------

func _traffic_step(delta: float) -> void:
	if _traffic.is_empty() or civ_car == null or cars == null:
		if civ_car and cars:
			cars.ai_inputs.erase(civ_car.net_id)
		return
	_traffic.t += delta
	var car := civ_car
	var inp := {"throttle": 0.0, "steer": 0.0, "handbrake": false, "horn": false}
	var fwd := car.global_transform.basis.z
	var speed := car.linear_velocity.dot(fwd)
	match _traffic.phase:
		"drive":
			var drive := lap_input(car)
			inp.throttle = drive.throttle
			inp.steer = drive.steer
			# A police car close behind with its lights on: pull over.
			var behind := false
			for pc in get_tree().get_nodes_in_group("police_cars"):
				var p := pc as PoliceCar
				var to := p.global_position - car.global_position
				if p.lights and to.length() < 20.0 and to.normalized().dot(fwd) < -0.3:
					behind = true
			_traffic.near_t = _traffic.near_t + delta if behind else 0.0
			if _traffic.near_t > 1.5:
				_traffic.phase = "pulled"
				_traffic.t = 0.0
				say("DISPATCH: the car is pulling over. Go and talk to the driver.")
		"pulled":
			inp.throttle = -1.0 if speed > 1.0 else 0.0
			inp.handbrake = speed < 1.5
			var near := false
			for o in get_tree().get_nodes_in_group("officers"):
				var off := o as Officer
				if off.state != Officer.S.VEHICLE and off.global_position.distance_to(car.global_position) < 3.6:
					near = true
			_traffic.near_t = _traffic.near_t + delta if near else 0.0
			if _traffic.near_t > 1.0:
				_traffic_bail("stop")
			elif _traffic.t > 45.0 and not near:
				_traffic.phase = "drive"
				_traffic.near_t = 0.0
				say("DISPATCH: nobody came, and the car has driven off again.")
		"bailed":
			inp.handbrake = true
			inp.throttle = -1.0 if speed > 1.0 else 0.0
	cars.ai_inputs[car.net_id] = inp


## Steering and throttle that drive a car round the lap, clockwise.
func lap_input(car: Car) -> Dictionary:
	var p := car.global_position
	# Nearest point on the lap, then a point some way ahead along it.
	var best_i := 0
	var best_t := 0.0
	var best_d := INF
	for i in LAP.size():
		var a: Vector3 = LAP[i]
		var b: Vector3 = LAP[(i + 1) % LAP.size()]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var q := a + ab * t
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < best_d:
			best_d = d
			best_i = i
			best_t = t
	var ahead := 7.0
	var i := best_i
	var a0: Vector3 = LAP[i]
	var b0: Vector3 = LAP[(i + 1) % LAP.size()]
	var pos := a0.lerp(b0, best_t)
	var left := (b0 - pos).length()
	var target := pos
	var to_corner := left
	while ahead > 0.0:
		var bb: Vector3 = LAP[(i + 1) % LAP.size()]
		var seg := (bb - pos).length()
		if seg >= ahead:
			target = pos + (bb - pos).normalized() * ahead
			ahead = 0.0
		else:
			ahead -= seg
			pos = bb
			i = (i + 1) % LAP.size()
	var lt := car.global_transform.affine_inverse() * Vector3(target.x, car.global_position.y, target.z)
	var steer := clampf(atan2(lt.x, lt.z) * 1.8, -1.0, 1.0)
	var want := 5.0 if to_corner < 12.0 else 10.0
	var fwd_speed := car.linear_velocity.dot(car.global_transform.basis.z)
	var throttle := clampf((want - fwd_speed) * 0.35, -1.0, 1.0)
	return {"throttle": throttle, "steer": steer}


## The traffic stop goes wrong: the driver jumps out and runs (or shoots).
func _traffic_bail(_why: String) -> void:
	if _traffic.is_empty() or _traffic.phase == "bailed" or civ_car == null:
		return
	var s: Suspect = suspects.get(_traffic.suspect)
	_traffic.phase = "bailed"
	if s == null or s.state != Suspect.S.DRIVE:
		return
	# Out of the driver's door (left side of the car).
	var door := civ_car.global_transform * Vector3(1.5, 0.0, 0.3)
	door.y = civ_car.global_position.y - 0.6
	if nav and nav.ready_to_use:
		door = nav.closest(door)
	s.global_position = door
	s.home = door
	s.set_state(Suspect.S.LOITER)
	var t := {"o": null, "d": INF, "los": false}
	var best := INF
	for o in get_tree().get_nodes_in_group("officers"):
		var d := (o as Node3D).global_position.distance_to(door)
		if d < best:
			best = d
			t = {"o": o, "d": d, "los": true}
	s._bolt(t)
	say("DISPATCH: driver's out and running!" if not s.armed else "DISPATCH: shots fired at the traffic stop!")


# --- network ----------------------------------------------------------------------------

func _encode_state() -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_double(_clock)
	b.put_half(crime)
	var act := calls.values().filter(func(c): return c.state == CallState.ACTIVE)
	b.put_u8(act.size())
	for c in act:
		b.put_u16(c.id)
		b.put_u8(c.kind)
		b.put_float(c.marker.x)
		b.put_float(c.marker.y)
		b.put_float(c.marker.z)
	var live := suspects.values().filter(func(s): return (s as Suspect).state != Suspect.S.BOOKED)
	b.put_u16(live.size())
	for s in live:
		(s as Suspect).encode(b)
	return b.data_array


func _on_state(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var t := b.get_double()
	crime = b.get_half()
	var n := b.get_u8()
	var keep := {}
	for i in n:
		var id := b.get_u16()
		var kind := b.get_u8()
		var m := Vector3(b.get_float(), b.get_float(), b.get_float())
		if not calls.has(id):
			calls[id] = {"id": id, "kind": kind, "state": CallState.ACTIVE, "pos": m, "marker": m, "t": 0.0, "suspects": [], "text": ""}
		calls[id].marker = m
		calls[id].state = CallState.ACTIVE
		keep[id] = true
	for id in calls.keys():
		if not keep.has(id):
			calls[id].state = CallState.CLOSED
	var count := b.get_u16()
	var alive := {}
	for i in count:
		var d := Suspect.decode(b)
		alive[d.id] = true
		var s: Suspect = suspects.get(d.id)
		if s == null:
			s = Suspect.new()
			s.net_id = d.id
			s.look = d.look
			s.armed = d.armed
			s.name = "Suspect%d" % d.id
			get_parent().add_child(s)
			s.global_position = d.pos
			suspects[d.id] = s
		s.apply_net(d)
		if not _buffers.has(d.id):
			_buffers[d.id] = []
		_buffers[d.id].append([t, d.pos, d.yaw, d.speed])
		if _buffers[d.id].size() > 12:
			_buffers[d.id].pop_front()
	for id in suspects.keys():
		if not alive.has(id):
			var s: Suspect = suspects[id]
			s.queue_free()
			suspects.erase(id)
			_buffers.erase(id)
	if _clock < t - 0.5 or _clock > t + 0.5:
		_clock = t


func _interpolate() -> void:
	var rt := _clock - 0.12
	for id in _buffers:
		var buf: Array = _buffers[id]
		var s: Suspect = suspects.get(id)
		if s == null or buf.is_empty():
			continue
		if s.state in [Suspect.S.DOWN]:
			continue
		var a: Array = buf[0]
		var bb: Array = buf[buf.size() - 1]
		for k in buf.size() - 1:
			if buf[k][0] <= rt and buf[k + 1][0] >= rt:
				a = buf[k]
				bb = buf[k + 1]
				break
		var span: float = bb[0] - a[0]
		var f := clampf((rt - a[0]) / span, 0.0, 1.0) if span > 0.0001 else 1.0
		s.global_position = (a[1] as Vector3).lerp(bb[1], f)
		s.rotation.y = lerp_angle(a[2], bb[2], f)
		s.net_speed = lerpf(a[3], bb[3], f)


# --- markers on the map --------------------------------------------------------------------

func _update_markers() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for c in calls.values():
		var m: Node3D = _markers.get(c.id)
		if c.state != CallState.ACTIVE:
			if m:
				m.queue_free()
				_markers.erase(c.id)
			continue
		if m == null:
			m = _make_marker(Color("ff4040") if c.kind != Kind.TRAFFIC else Color("ffb030"))
			parent.add_child(m)
			_markers[c.id] = m
		m.global_position = m.global_position.lerp(c.marker, 0.1) if m.global_position != Vector3.ZERO else c.marker


func _make_marker(col: Color) -> Node3D:
	var root := Node3D.new()
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	# Starts above head height so it never tints the people at the call.
	cm.top_radius = 0.25
	cm.bottom_radius = 0.25
	cm.height = 27.0
	beam.mesh = cm
	beam.position.y = 2.6 + 13.5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.22)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.6
	tm.outer_radius = 1.9
	ring.mesh = tm
	ring.position.y = 0.2
	var rm := mat.duplicate() as StandardMaterial3D
	rm.albedo_color = Color(col.r, col.g, col.b, 0.7)
	ring.material_override = rm
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	return root


## The custody bay: yellow box on the road, a sign and a blue lamp.
func _build_bay() -> void:
	_bay_node = Node3D.new()
	_bay_node.name = "CustodyBay"
	add_child(_bay_node)
	var bay := bay_position()
	var box := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(BAY_RADIUS * 1.2, BAY_RADIUS * 2.0)
	box.mesh = pm
	box.material_override = Cel.material(Color("e8c22a"), false)
	box.position = bay + Vector3(0, 0.02, 0)
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bay_node.add_child(box)
	var inner := MeshInstance3D.new()
	var pm2 := PlaneMesh.new()
	pm2.size = Vector2(BAY_RADIUS * 1.2 - 0.5, BAY_RADIUS * 2.0 - 0.5)
	inner.mesh = pm2
	inner.material_override = Cel.material(Color("3a3f4a"), false)
	inner.position = bay + Vector3(0, 0.03, 0)
	inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bay_node.add_child(inner)
	var sign := Label3D.new()
	sign.text = "CUSTODY"
	sign.font_size = 160
	sign.pixel_size = 0.008
	sign.modulate = Color("e8c22a")
	sign.rotation_degrees = Vector3(-90, 90, 0)
	sign.position = bay + Vector3(0, 0.05, 0)
	_bay_node.add_child(sign)
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.08
	cm.height = 3.2
	post.mesh = cm
	post.material_override = Cel.material(Color("2a2e38"))
	post.position = bay + Vector3(BAY_RADIUS * 0.75, 1.6, 0)
	_bay_node.add_child(post)
	var lamp := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	lamp.mesh = sm
	lamp.material_override = Cel.material(Color("4a8cff") * 1.4, false)
	lamp.position = bay + Vector3(BAY_RADIUS * 0.75, 3.3, 0)
	_bay_node.add_child(lamp)
	var light := OmniLight3D.new()
	light.light_color = Color("4a8cff")
	light.omni_range = 7.0
	light.light_energy = 1.5
	light.position = lamp.position
	_bay_node.add_child(light)
