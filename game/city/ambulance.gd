class_name AmbulanceService
extends Node
## The dead don't stay in the street. A little while after someone is
## killed, an ambulance comes for them: blue lights and siren through the
## traffic (which pulls over for it), the siren off as it pulls up at the
## kerb, then two paramedics get out the back with a trolley stretcher,
## wheel it to the body, load it in a body bag, wheel it back and drive off.
## Bodies lying close together go in the same trip. Blood stays where it
## is (that's for the Gore setting, not the ambulance).
##
## Like the council crews (RepairCrews): paramedics who are shot at run and
## hide, and the job waits until it's quiet; if they're both down or gone,
## a fresh pair gets out of the ambulance after a while. A body nobody can
## get to (up on a roof, behind a locked door) is taken once no officer is
## close by to see it.
##
## Every machine builds the same ambulances (ordinary CarSync cars, so they
## drive for everyone). The host runs the jobs; the paramedics are
## civilians, so they sync like anyone else, and the stretcher and the
## driver go out in MSG_AMBULANCE.

const MSG_AMBULANCE := 150      # host -> all: per ambulance: driver, stretcher (10 a second)
const COUNT := 2
const WAIT := 25.0              # seconds after a death before the ambulance is sent
const GROUP := 22.0             # bodies this close go in the same trip
const UNSEEN := 110.0           # nobody within this: it can be moved about unseen
const START := Vector2(80.0, 170.0)   # how far off it starts its run (out of sight)
const ARRIVE := 32.0            # this close to the kerb spot: pull in
const LOAD_TIME := 4.5          # seconds loading a body
const STOW_TIME := 2.0          # seconds putting the trolley in the back
const REACH := 2.2              # at the body / at the back doors
const GIVE_UP := 45.0           # can't reach a body: taken when nobody's looking
const NEW_CREW := 40.0          # both paramedics down or gone: a fresh pair
const LEAVE_MAX := 70.0         # off back to the station after this, seen or not

var gen: CityGenerator
var cars: CarSync
var traffic: TrafficSystem
var dispatch: Dispatcher
var enabled := true
var ambos: Array = []           # [{car, dr, state, ...}] (every machine; jobs on the host)
var collected := 0              # bodies taken away (host)
var _down := {}                 # Suspect -> seconds dead (host)
var _rng := RandomNumberGenerator.new()
var _send_t := 0.0

static var _stretcher_scene: PackedScene


func _ready() -> void:
	_rng.randomize()
	Net.register(MSG_AMBULANCE, _on_msg)


func _exit_tree() -> void:
	Net.unregister(MSG_AMBULANCE)


# --- building (every machine, same order) -----------------------------------------------

## The ambulances, parked at the kerb at the far edges of the city.
func build(g: CityGenerator, c: CarSync, t: TrafficSystem, d: Dispatcher) -> void:
	gen = g
	cars = c
	traffic = t
	dispatch = d
	var homes := [CityGenerator.junction(CityGenerator.GRID - 1, 1), CityGenerator.junction(1, CityGenerator.GRID - 1)]
	for i in COUNT:
		var slot: Array = traffic._kerb_near(homes[i % homes.size()] + Vector3(14.0, 0, 0))
		var at: Vector3 = slot[0] if not slot.is_empty() else homes[i] + Vector3(10, 0, 10)
		var dir: Vector3 = slot[1] if not slot.is_empty() else Vector3.FORWARD
		var v := CivilianVehicle.make("ambulance", i)
		v.name = "Ambulance%d" % i
		v.position = at + Vector3(0, 1.3, 0)
		v.rotation.y = atan2(dir.x, dir.z)
		v.add_to_group("emergency")
		traffic.add_child(v)
		cars.add_car(v)
		var dr := {"car": v, "idx": v.net_id, "a": Vector2i.ZERO, "b": Vector2i.ZERO, "pts": [], "wi": 0, "mode": "parked",
			"t": 0.0, "stuck": 0.0, "wait": 0.0, "rev": 0.0, "yield": 0.0, "pace": 1.3,
			"off": 0.0, "off_want": 0.0, "pass": 0.0, "tries": 0, "blk": null, "rev_steer": 0.0, "lost": 0.0, "look": SuspectLook.PARAMEDIC + i,
			"rig": null, "wb": traffic._wheelbase(v), "seen": false, "hold": true}
		var stretcher := _make_stretcher()
		add_child(stretcher)
		var a := {"i": i, "car": v, "dr": dr, "state": "idle", "bodies": [], "medics": [], "goal": Vector3.ZERO, "kerb_dir": Vector3.FORWARD, "lane": [Vector2i.ZERO, Vector2i.ZERO],
			"t": 0.0, "crew_t": 0.0, "stage": "", "load_t": 0.0, "body": null, "said": false,
			"stretcher": stretcher, "st_on": false, "st_loaded": false, "st_pos": Vector3.ZERO, "st_yaw": 0.0, "driver": false}
		v.commandeered.connect(_on_commandeered.bind(a))
		ambos.append(a)


static func _make_stretcher() -> Node3D:
	if _stretcher_scene == null:
		_stretcher_scene = load("res://assets/models/vehicles/stretcher.glb")
	var s: Node3D = _stretcher_scene.instantiate()
	s.name = "Stretcher"
	Cel.apply(s)
	s.visible = false
	return s


static func _bag(stretcher: Node3D) -> Node3D:
	return stretcher.find_child("body_bag", true, false) as Node3D


# --- host: the dead --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_show(delta)
	if not Net.is_host() or dispatch == null:
		return
	_count_dead(delta)
	if enabled:
		_send_out()
	for a in ambos:
		_run(a, delta)
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 0.1
		_send()


## How long each body has been lying there.
func _count_dead(delta: float) -> void:
	for s in _down.keys():
		if not is_instance_valid(s) or (s as Suspect).state != Suspect.S.DOWN:
			_down.erase(s)
	for s in dispatch.suspects.values():
		var su := s as Suspect
		if su.state == Suspect.S.DOWN:
			_down[su] = float(_down.get(su, 0.0)) + delta


## Where a body is: the ragdoll's middle, not where they were standing.
static func body_pos(s: Suspect) -> Vector3:
	if s.rig:
		var pb := s.rig.bone_body("spine")
		if pb and pb.is_inside_tree():
			return pb.global_position
	return s.global_position


## Still part of a job in progress (left for the call to finish with).
func _in_live_call(s: Suspect) -> bool:
	for c in dispatch.calls.values():
		if c.state == Dispatcher.CallState.ACTIVE and (c.suspects as Array).has(s.net_id):
			return true
	return false


func _taken(s: Suspect) -> bool:
	for a in ambos:
		if (a.bodies as Array).has(s) or a.body == s:
			return true
	return false


## Bodies that have waited long enough get an ambulance: joined to one
## already there if it's close, or the free one that can get there first.
func _send_out() -> void:
	for s in _down.keys():
		if float(_down[s]) < WAIT or _taken(s) or _in_live_call(s):
			continue
		var at := body_pos(s)
		var joined := false
		for a in ambos:
			if a.state in ["go", "arrive", "work"] and Vector2(at.x - a.goal.x, at.z - a.goal.z).length() < GROUP + 10.0:
				a.bodies.append(s)
				joined = true
				break
		if joined:
			continue
		var free := ambos.filter(func(a): return a.state == "idle" and _usable(a))
		if free.is_empty():
			return
		free.sort_custom(func(x, y): return (x.car as Node3D).global_position.distance_to(at) < (y.car as Node3D).global_position.distance_to(at))
		_dispatch(free[0], s, at)


func _usable(a: Dictionary) -> bool:
	var car: CivilianVehicle = a.car
	return is_instance_valid(car) and not car.wrecked and car.occupants().is_empty() \
		and int(cars.fire_state.get(car.net_id, 0)) == CarSync.Fire.OK and car.global_transform.basis.y.dot(Vector3.UP) > 0.6


func _dispatch(a: Dictionary, s: Suspect, at: Vector3) -> void:
	a.bodies = [s]
	for o in _down.keys():
		if o != s and float(_down[o]) >= WAIT * 0.5 and not _taken(o) and not _in_live_call(o) and body_pos(o).distance_to(at) < GROUP:
			a.bodies.append(o)
	var car: CivilianVehicle = a.car
	var dr: Dictionary = a.dr
	var slot := _kerb_for(at, car)
	a.goal = slot[0]
	a.kerb_dir = slot[1]
	a.lane = [slot[2], slot[3]]
	if _unseen(car.global_position):
		_start_out_of_sight(a)
	dr.goal_lane = a.lane
	dr.blues = true
	dr.mode = "drive"
	dr.pace = 1.35
	dr.erase("hold")
	traffic._reroute(dr, car.global_position)
	_seat(a, true)
	car.lights = true
	car.siren = 1 if _rng.randf() < 0.5 else 2
	a.state = "go"
	a.t = 0.0
	a.said = false
	dispatch.say("CONTROL: ambulance on its way to %s for the deceased." % CityGenerator.street_at(a.goal))


## Out of everyone's sight, it can start its run from somewhere closer:
## a lane well away from the officers, a few streets from the body.
func _start_out_of_sight(a: Dictionary) -> void:
	var car: CivilianVehicle = a.car
	var lanes := traffic._all_lanes()
	for tries in 40:
		var ln: Array = lanes[_rng.randi_range(0, lanes.size() - 1)]
		var l2 := TrafficSystem._lane(ln[0], ln[1])
		var p: Vector3 = (l2[0] as Vector3).lerp(l2[1], 0.3)
		var d := Vector2(p.x - a.goal.x, p.z - a.goal.z).length()
		if d < START.x or d > START.y or not _unseen(p, 70.0):
			continue
		var clear := true
		for c in cars.cars:
			if c != car and (c as Node3D).global_position.distance_to(p) < 10.0:
				clear = false
				break
		if not clear:
			continue
		var dir: Vector3 = ((l2[1] as Vector3) - (l2[0] as Vector3)).normalized()
		car.global_transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.z)), p + Vector3(0, 1.3, 0))
		car.linear_velocity = Vector3.ZERO
		car.angular_velocity = Vector3.ZERO
		return


func _unseen(p: Vector3, reach := UNSEEN) -> bool:
	for o in get_tree().get_nodes_in_group("officers"):
		if (o as Node3D).global_position.distance_to(p) < reach:
			return false
	return true


## A paramedic at the wheel (drawn sat down), or nobody.
func _seat(a: Dictionary, on: bool) -> void:
	a.driver = on
	if on:
		traffic._seat_driver(a.dr)
	else:
		traffic._clear_driver(a.dr)


## Host: one ambulance's job, a step at a time.
func _run(a: Dictionary, delta: float) -> void:
	var car: CivilianVehicle = a.car
	var dr: Dictionary = a.dr
	if a.state == "idle":
		return
	a.t += delta
	if not is_instance_valid(car) or car.wrecked or car.global_transform.basis.y.dot(Vector3.UP) < 0.55 or dr.mode == "taken":
		_abort(a)
		return
	a.bodies = (a.bodies as Array).filter(func(s): return is_instance_valid(s) and (s as Suspect).state == Suspect.S.DOWN)
	match a.state:
		"go":
			if a.bodies.is_empty() and a.body == null:
				_leave(a)
				return
			traffic._drive(dr, delta)
			var to: Vector3 = a.goal - car.global_position
			var d := Vector2(to.x, to.z).length()
			if d < 70.0 and car.siren != 0:
				car.siren = 0          # the siren goes off as it gets close
			var ahead: float = (a.goal - car.global_position).dot(a.kerb_dir)
			if ahead > 1.0 and d < ARRIVE and _on_lane(a):
				a.state = "arrive"
				a.t = 0.0
			# Boxed in where nobody can see (the traffic's own passing
			# and backing off didn't free it): start again from closer in.
			a.stall = float(a.get("stall", 0.0)) + delta if car.linear_velocity.length() < 0.8 else 0.0
			if a.stall > 20.0 and _unseen(car.global_position):
				a.stall = 0.0
				_start_out_of_sight(a)
				traffic._reroute(dr, car.global_position)
			elif a.t > 150.0 and _unseen(car.global_position):
				# Stuck somewhere nobody can see: try again from closer in.
				_start_out_of_sight(a)
				traffic._reroute(dr, car.global_position)
				a.t = 0.0
		"arrive":
			if _pull_in(a):
				cars.ai_inputs[dr.idx] = {"throttle": 0.0, "steer": 0.0, "handbrake": true, "horn": false}
				a.state = "work"
				a.t = 0.0
				a.stage = "out"
				a.crew_t = 0.0
		"work":
			cars.ai_inputs[dr.idx] = {"throttle": 0.0, "steer": 0.0, "handbrake": true, "horn": false}
			_work(a, delta)
		"leave":
			traffic._drive(dr, delta)
			if a.t > 8.0 and (_unseen(car.global_position) or a.t > LEAVE_MAX):
				_park(a)


## In the lane the kerb spot is on, going its way (the traffic's own
## a and b run ahead of the car, so this goes by where the car is).
func _on_lane(a: Dictionary) -> bool:
	var car: CivilianVehicle = a.car
	var l2 := TrafficSystem._lane(a.lane[0], a.lane[1])
	var s: Vector3 = l2[0]
	var dir: Vector3 = a.kerb_dir
	var rel := car.global_position - s
	var side := absf(rel.x * dir.z - rel.z * dir.x)
	return side < 3.5 and rel.dot(dir) > -2.0 and car.global_transform.basis.z.dot(dir) > 0.7


## The last bit: out of the lane to the kerb, and stop by the spot. True
## once it has stopped.
func _pull_in(a: Dictionary) -> bool:
	var car: CivilianVehicle = a.car
	var xf := car.global_transform
	var fwd := xf.basis.z
	var v := car.linear_velocity.dot(fwd)
	var kd: Vector3 = a.kerb_dir
	var ahead: float = (a.goal - xf.origin).dot(kd)
	if ahead < 0.6 or a.t > 25.0:
		cars.ai_inputs[a.dr.idx] = {"throttle": 0.0, "steer": 0.0, "handbrake": true, "horn": false}
		return absf(v) < 0.5
	var look := clampf(ahead, 3.0, 9.0)
	var local: Vector3 = xf.affine_inverse() * (a.goal + kd * (look - ahead if ahead < look else 0.0) - kd * maxf(0.0, ahead - look))
	var alpha := atan2(local.x, local.z)
	var want := atan2(2.0 * float(a.dr.wb) * sin(alpha), maxf(local.length(), 2.0))
	var steer := clampf(want / car.steer_max, -1.0, 1.0)
	var vt := clampf(ahead * 0.45, 1.5, 9.0)
	var thr := clampf((vt - v) * 0.5, -1.0, 1.0)
	cars.ai_inputs[a.dr.idx] = {"throttle": thr, "steer": steer, "handbrake": false, "horn": false}
	return false


## The kerb spot nearest p, clear of other cars: [position, facing, lane
## start junction, lane end junction]. The spot is on the lane's kerb
## (kerb) side, so driving that lane brings the ambulance up beside it.
func _kerb_for(p: Vector3, car: Car) -> Array:
	var best := INF
	var out := [p, Vector3.FORWARD, Vector2i.ZERO, Vector2i(1, 0)]
	for ln in traffic._all_lanes():
		var l2 := TrafficSystem._lane(ln[0], ln[1])
		var s: Vector3 = l2[0]
		var e: Vector3 = l2[1]
		var dir := (e - s).normalized()
		var length := s.distance_to(e)
		var t := clampf((p - s).dot(dir), 10.0, length - 4.0)
		var q := s + dir * t + Vector3(-dir.z, 0, dir.x) * (CityGenerator.PARK_LANE - CityGenerator.LANE)
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d >= best:
			continue
		var clear := true
		for c in cars.cars:
			if c != car and (c as Node3D).global_position.distance_to(q) < 5.5:
				clear = false
				break
		if clear:
			best = d
			out = [q, dir, ln[0], ln[1]]
	return out


# --- host: the paramedics ---------------------------------------------------------------

func _work(a: Dictionary, delta: float) -> void:
	var car: CivilianVehicle = a.car
	var back := car.boot_point()
	back.y = car.global_position.y - 0.6
	if dispatch.nav and dispatch.nav.ready_to_use:
		var q := dispatch.nav.closest(back)
		if q.distance_to(back) < 3.0:
			back = q
	_keep_crew(a, delta, back)
	var up: Array = (a.medics as Array).filter(func(m): return is_instance_valid(m) and (m as Suspect).state not in [Suspect.S.DOWN, Suspect.S.BOOKED])
	if up.is_empty():
		return
	# Anyone running or hiding from something: the job waits.
	if up.any(func(m): return (m as Suspect).state != Suspect.S.WANDER):
		return
	var lead: Suspect = up[0]
	var mate: Suspect = up[1] if up.size() > 1 else null
	match a.stage:
		"out":
			# Out the back with the trolley.
			if a.bodies.is_empty():
				_finish(a)
				return
			a.bodies.sort_custom(func(x, y): return body_pos(x).distance_to(back) < body_pos(y).distance_to(back))
			a.body = a.bodies[0]
			a.bodies.remove_at(0)
			a.st_on = true
			a.st_loaded = false
			a.stage = "fetch"
			a.load_t = 0.0
		"fetch":
			var s: Suspect = a.body
			if not is_instance_valid(s) or s.state != Suspect.S.DOWN:
				a.body = null
				a.stage = "return"
				return
			var bp := body_pos(s)
			var foot := Vector3(bp.x, s.global_position.y, bp.z)
			var from_van := (foot - back)
			from_van.y = 0.0
			var dir := from_van.normalized() if from_van.length() > 0.1 else Vector3.FORWARD
			_walk(lead, foot - dir * 1.9)
			if mate:
				_walk(mate, foot + Vector3(-dir.z, 0, dir.x) * 0.9)
			_trolley(a, lead)
			a.load_t += delta
			var there := _flat(lead.global_position, foot - dir * 1.9) < REACH
			if there:
				a.stage = "load"
				a.load_t = 0.0
			elif a.load_t > GIVE_UP and _unseen(foot, 35.0):
				_take(a, s)       # out of reach: taken once nobody's watching
				a.stage = "return"
		"load":
			var s: Suspect = a.body
			if not is_instance_valid(s):
				a.stage = "return"
				return
			lead._face(body_pos(s))
			if mate:
				mate._face(body_pos(s))
			a.load_t += delta
			if a.load_t >= LOAD_TIME:
				_take(a, s)
				a.stage = "return"
		"return":
			_walk(lead, back)
			if mate:
				_walk(mate, back + car.global_transform.basis.x * 1.0)
			_trolley(a, lead)
			if _flat(lead.global_position, back) < REACH:
				a.stage = "stow"
				a.load_t = 0.0
		"stow":
			a.load_t += delta
			var into := car.global_transform.origin - car.global_transform.basis.z * (car.size.z * 0.5 - 0.6)
			a.st_pos = (a.st_pos as Vector3).lerp(Vector3(into.x, back.y + 0.4, into.z), minf(1.0, delta * 2.0))
			if a.load_t >= STOW_TIME:
				a.st_on = false
				a.st_loaded = false
				a.body = null
				a.stage = "out"


## The body goes in the bag and on the trolley, and out of the world.
func _take(a: Dictionary, s: Suspect) -> void:
	a.st_loaded = true
	a.body = null
	_down.erase(s)
	collected += 1
	if dispatch.suspects.get(s.net_id) == s:
		dispatch.suspects.erase(s.net_id)
	s.queue_free()


## The trolley, pushed along in front of the lead paramedic.
func _trolley(a: Dictionary, lead: Suspect) -> void:
	var f := Vector3(sin(lead.rotation.y), 0, cos(lead.rotation.y))
	a.st_pos = lead.global_position + f * 1.25
	a.st_yaw = lead.rotation.y


func _walk(m: Suspect, to: Vector3) -> void:
	if m.route.is_empty() or (m.route[0] as Vector3).distance_to(to) > 0.4:
		m.route = [to]
		m._route_i = 0


static func _flat(p: Vector3, q: Vector3) -> float:
	return Vector2(p.x - q.x, p.z - q.z).length()


## Two paramedics out of the back; a fresh pair if both are down or gone.
func _keep_crew(a: Dictionary, delta: float, back: Vector3) -> void:
	var alive: Array = (a.medics as Array).filter(func(m): return is_instance_valid(m) and (m as Suspect).state not in [Suspect.S.DOWN, Suspect.S.BOOKED])
	if not alive.is_empty():
		a.crew_t = NEW_CREW
		return
	# The first pair gets straight out; a fresh pair after a wait.
	if not (a.medics as Array).is_empty():
		a.crew_t -= delta
		if a.crew_t > 0.0:
			return
	a.crew_t = NEW_CREW
	_remove_medics(a)
	if a.body != null and not a.st_loaded:
		a.bodies.push_front(a.body)
		a.body = null
	a.st_on = false
	a.stage = "out"
	var side: Vector3 = (a.car as Node3D).global_transform.basis.x
	for k in 2:
		var m := dispatch.spawn_suspect(back + side * (0.6 if k == 0 else -0.6), Suspect.S.WANDER, false)
		m.civilian = true
		m.part = "paramedic"
		m.look = SuspectLook.PARAMEDIC + _rng.randi_range(0, 7)
		SuspectLook.apply(m.rig.model if m.rig else null, m.look)
		m.route = [m.global_position]
		m._route_i = 0
		m._pace = 1.0
		a.medics.append(m)
	if a.driver:
		_seat(a, false)
	if not a.said:
		a.said = true
		dispatch.say("AMBULANCE: on scene at %s." % CityGenerator.street_at(a.goal))


func _remove_medics(a: Dictionary) -> void:
	for m in a.medics:
		if is_instance_valid(m) and (m as Suspect).state != Suspect.S.DOWN:
			dispatch.suspects.erase((m as Suspect).net_id)
			(m as Node).queue_free()
	a.medics = []


## Everyone's in: lights on, no siren, off back into the traffic.
func _finish(a: Dictionary) -> void:
	_remove_medics(a)
	a.st_on = false
	_leave(a)


func _leave(a: Dictionary) -> void:
	var car: CivilianVehicle = a.car
	var dr: Dictionary = a.dr
	dr.erase("goal_lane")
	dr.blues = false
	dr.pace = 1.0
	dr.mode = "drive"
	traffic._reroute(dr, car.global_position)
	_seat(a, true)
	car.lights = true
	car.siren = 0
	a.state = "leave"
	a.t = 0.0


## Back on standby: parked at the kerb wherever it got to, out of sight.
func _park(a: Dictionary) -> void:
	var car: CivilianVehicle = a.car
	a.dr.mode = "parked"
	a.dr.hold = true
	a.dr.erase("goal_lane")
	cars.ai_inputs.erase(a.dr.idx)
	car.lights = false
	car.siren = 0
	_seat(a, false)
	a.state = "idle"
	a.bodies = []
	a.body = null


## Wrecked, burning, upside down or taken by an officer: the job's off and
## the bodies wait for the other ambulance (or this one, once it's back).
func _abort(a: Dictionary) -> void:
	_remove_medics(a)
	a.st_on = false
	var car: CivilianVehicle = a.car
	if is_instance_valid(car):
		car.lights = false
		car.siren = 0
	if a.dr.mode != "taken":
		a.dr.mode = "parked"
		a.dr.hold = true
		cars.ai_inputs.erase(a.dr.idx)
	_seat(a, false)
	a.state = "idle"
	a.bodies = []
	a.body = null


func _on_commandeered(_by: Node, a: Dictionary) -> void:
	if not Net.is_host():
		return
	a.dr.mode = "taken"
	cars.ai_inputs.erase(a.dr.idx)


# --- every machine: the stretcher and the driver -------------------------------------------

func _send() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(ambos.size())
	for a in ambos:
		_put(b, a)
	if Net.is_online():
		Net.broadcast(MSG_AMBULANCE, b.data_array, Net.UNRELIABLE)


func _put(b: StreamPeerBuffer, a: Dictionary) -> void:
	b.put_u8((1 if a.st_on else 0) | (2 if a.st_loaded else 0) | (4 if a.driver else 0))
	var p: Vector3 = a.st_pos
	b.put_float(p.x)
	b.put_float(p.y)
	b.put_float(p.z)
	b.put_half(a.st_yaw)


func _on_msg(from: int, data: PackedByteArray) -> void:
	if from != 1 or Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var n := b.get_u8()
	for i in n:
		var f := b.get_u8()
		var p := Vector3(b.get_float(), b.get_float(), b.get_float())
		var yaw := b.get_half()
		if i >= ambos.size():
			continue
		var a: Dictionary = ambos[i]
		a.st_on = (f & 1) != 0
		a.st_loaded = (f & 2) != 0
		a.st_pos = p
		a.st_yaw = yaw
		var drv := (f & 4) != 0
		if drv != a.driver:
			_seat(a, drv)


## The trolley where it should be (eased along on the clients).
func _show(delta: float) -> void:
	for a in ambos:
		var st: Node3D = a.stretcher
		if not a.st_on:
			st.visible = false
			continue
		var want := Transform3D(Basis(Vector3.UP, a.st_yaw), a.st_pos)
		if not st.visible or Net.is_host():
			st.global_transform = want
		else:
			st.global_transform = st.global_transform.interpolate_with(want, minf(1.0, delta * 12.0))
		st.visible = true
		var bag := _bag(st)
		if bag:
			bag.visible = a.st_loaded
