class_name RepairCrews
extends Node
## Wave 4, Phase 4.1: the city mends itself. A while after something gets
## knocked down, the council sends a crew: a flatbed lorry loaded with slabs
## and beams and a mobile crane park up at the kerb (see WorksSite), three
## workers in hi-vis and hard hats, barriers and cones round the site.
## First they cart the rubble away (what's lying in the road goes first),
## then they build what fell back up again, bottom to top, a piece at a
## time: the crane lifts each one off the lorry and sets it in place, a
## banksman guides it in, and a fitter drills, welds or grinds. It's slow while you're watching and quicker while nobody is, but
## never all at once. Workers who get hurt or scared off stop the job until
## the site is quiet again (or a fresh crew turns up).
##
## Blood (beenster, 2026-11-24): the spatter and pools a fight leaves stay
## until a crew comes and cleans them. Blood that has sat a while gets a
## site of its own (or joins a site close by), and while a crew is working
## they scrub the marks away one at a time. Blood under a body still lying
## there is left alone.
##
## The host runs the sites. Workers are civilians, so they sync like anyone
## else; the vehicles, the stage and each worker's job go out in MSG_SITES,
## and each lift's start in MSG_LIFT. No radio message and no chime: you
## just see them turn up (beenster, 2026-11-24).

const MSG_SITES := 108          # host -> all: the sites, vehicles and crew jobs (every 3 s)
const MSG_LIFT := 157           # host -> all: a lift starts (site, piece, length)
const WAIT := 40.0              # real seconds after damage before a crew is sent
const SITE_REACH := 16.0        # rubble and pieces this close belong to one site
const MAX_SITES := 3
const UNSEEN := 120.0           # nobody within this: work goes quicker
const CLEAN_GAP := Vector2(2.5, 0.5)    # seen, unseen: seconds per load carted away
const BUILD_GAP := Vector2(1.5, 1.0)    # seen, unseen: seconds between pieces (a lift takes WorksSite.LIFT_TIME)
const HAND_FIT := 4.0           # s to fit a pane or a door by hand, watched
const CREW := 3                 # slinger, banksman, fitter
const NEW_CREW := 60.0          # crew all down or gone: a new one after this
const BLOOD_WAIT := 90.0        # real seconds blood sits before a crew is sent for it
const SCRUB_GAP := Vector2(0.6, 0.15)   # seen, unseen: seconds per blood mark cleaned
const BODY_CLEAR := 2.5         # blood this close to a body still down is left

var world: DestructionWorld
var dispatch: Dispatcher
var traffic: TrafficSystem
var gen: CityGenerator
var enabled := true
var sites := {}                 # id -> site Dictionary (host)
var _broken := {}               # piece id -> seconds since it went (host, not yet in a site)
var _next_id := 1
var carted := 0                 # loads of rubble carted away (host)
var rebuilt := 0                # pieces put back (host)
var _tick := 0.0
var _send_t := 0.0
var _cones := {}                # site id -> WorksSite (every machine)
var _cone_at := {}              # site id -> [position, working] (every machine)
var scrubbed := 0               # blood marks cleaned (this machine)
var _scrub_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Net.register(MSG_SITES, _on_sites)
	Net.register(MSG_LIFT, _on_lift)
	if world:
		world.piece_broken.connect(_on_broken)


func _exit_tree() -> void:
	Net.unregister(MSG_SITES)
	Net.unregister(MSG_LIFT)


func _on_broken(id: int) -> void:
	if Net.is_host() and not _in_site(id):
		_broken[id] = 0.0


func _in_site(id: int) -> bool:
	for s in sites.values():
		if (s.pieces as Array).has(id):
			return true
	return false


func _physics_process(delta: float) -> void:
	_scrub(delta)
	if not Net.is_host() or world == null:
		return
	for id in _broken:
		_broken[id] += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		if enabled:
			_open_sites()
			_open_blood_sites()
		for s in sites.values():
			_assign_jobs(s)
	for s in sites.values():
		s.age += delta
		_work(s, delta)
	for id in sites.keys():
		if sites[id].stage == "done":
			_close(sites[id])
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 3.0
		_send_sites()


# --- host: sites ---------------------------------------------------------------

## Damage that has sat a while gets a site: joined to one close by, or a new
## one (rubble in the road first, when there's a queue).
func _open_sites() -> void:
	var due: Array = _broken.keys().filter(func(id): return _broken[id] >= WAIT)
	if due.is_empty():
		return
	due.sort_custom(func(a, b): return _road_score(a) > _road_score(b))
	for id in due:
		var at := (world.pieces[id].aabb as AABB).get_center()
		var joined := false
		for s in sites.values():
			if s.stage != "done" and Vector2(at.x - s.at.x, at.z - s.at.z).length() < SITE_REACH:
				s.pieces.append(id)
				if s.stage == "build":
					s.stage = "clean"     # more came down: clear up again first
				joined = true
				break
		if not joined:
			if sites.size() >= MAX_SITES:
				continue
			_new_site(id, at)
		_broken.erase(id)


func _road_score(id: int) -> int:
	var n := 0
	var at := (world.pieces[id].aabb as AABB).get_center()
	for nid in world.rubble_near(at, SITE_REACH):
		if on_road((world.bodies[nid] as Node3D).global_position):
			n += 1
	return n


static func on_road(p: Vector3) -> bool:
	for r in CityGenerator.roads():
		if (r.rect as Rect2).has_point(Vector2(p.x, p.z)):
			return true
	return false


## Blood that has sat a while with no site near it gets one.
func _open_blood_sites() -> void:
	var now := Time.get_ticks_msec()
	for d in get_tree().get_nodes_in_group("blood"):
		var dn := d as Node3D
		if dn == null or dn.is_queued_for_deletion() or now - int(dn.get_meta("t", now)) < BLOOD_WAIT * 1000.0:
			continue
		var at := dn.global_position
		if sites.values().any(func(s): return s.stage != "done" and Vector2(at.x - s.at.x, at.z - s.at.z).length() < SITE_REACH):
			continue
		if near_body(get_tree(), at):
			continue
		if sites.size() >= MAX_SITES:
			return
		_new_site(-1, at)


## Someone still lying here (their blood is left until they're gone).
static func near_body(tree: SceneTree, at: Vector3) -> bool:
	for g in ["suspects", "officers"]:
		for n in tree.get_nodes_in_group(g):
			var rig = n.get("rig")
			if rig and (rig as OfficerRig).downed and (n as Node3D).global_position.distance_to(at) < BODY_CLEAR + 1.5:
				return true
			if n is Suspect and (n as Suspect).state == Suspect.S.DOWN and (n as Node3D).global_position.distance_to(at) < BODY_CLEAR + 1.5:
				return true
	return false


## Blood near a site that a crew can clean (not under a body).
func blood_near(at: Vector3, reach: float) -> Array:
	return get_tree().get_nodes_in_group("blood").filter(func(d):
		var p: Vector3 = (d as Node3D).global_position
		return not (d as Node).is_queued_for_deletion() and Vector2(p.x - at.x, p.z - at.z).length() < reach and not near_body(get_tree(), p))


func _new_site(id: int, at: Vector3) -> Dictionary:
	var ground := Vector3(at.x, BlockGenerator.BASE_Y, at.z)
	if gen:
		ground = gen.pavement_near(at)
	var s := {"id": _next_id, "at": ground, "pieces": [id] if id >= 0 else [], "stage": "clean", "crew": [],
		"t": 1.0, "crew_t": 0.0, "paused": false, "age": 0.0, "lift": {}, "last": -1, "jobs": {}}
	_park(s)
	_next_id += 1
	sites[s.id] = s
	_send_t = 0.0
	return s


## Where the lorry and the crane park: in the parking lane by the site, the
## crane behind the lorry, both facing the way the traffic goes.
func _park(s: Dictionary) -> void:
	var at: Vector3 = s.at
	var slot: Array = traffic._kerb_near(at) if traffic else []
	var q := at + Vector3(0, 0, 6.0)
	var dir := Vector3.FORWARD
	if not slot.is_empty():
		q = slot[0]
		dir = slot[1]
	q.y = 0.0
	var b := Basis(Vector3.UP, atan2(dir.x, dir.z))
	s.lorry = Transform3D(b, q + dir * 6.0)
	s.crane = Transform3D(b, q - dir * 6.0)


## Host: one step of work at a site.
func _work(s: Dictionary, delta: float) -> void:
	if s.stage == "done":
		return
	if s.age < WorksSite.ARRIVE + WorksSite.SET_UP:
		return      # still driving in and setting up
	_keep_crew(s, delta)
	# Everyone still on their feet has to be back at work (not running or
	# hiding from something); the ones who went down are out of it.
	var up: Array = (s.crew as Array).filter(func(w): return is_instance_valid(w) and (w as Suspect).state not in [Suspect.S.DOWN, Suspect.S.BOOKED])
	var was: bool = s.paused
	s.paused = up.is_empty() or up.any(func(w): return (w as Suspect).state != Suspect.S.WANDER)
	if s.paused != was:
		_send_t = 0.0
	if s.paused:
		return
	var unseen := _unseen(s.at)
	if not (s.lift as Dictionary).is_empty():
		_lift_work(s, delta, unseen)
		return
	s.t -= delta
	if s.t > 0.0:
		return
	if s.stage == "clean":
		s.t = CLEAN_GAP.y if unseen else CLEAN_GAP.x
		var near := _rubble(s)
		if near.is_empty():
			# The crew scrubs the blood (see _scrub) before moving on.
			if not blood_near(s.at, SITE_REACH + 6.0).is_empty():
				return
			s.stage = "build"
			_send_t = 0.0
			return
		# Nearest the road first, then nearest the crew.
		near.sort_custom(func(a, b):
			var pa: Vector3 = (world.bodies[a] as Node3D).global_position
			var pb: Vector3 = (world.bodies[b] as Node3D).global_position
			var ra := on_road(pa)
			if ra != on_road(pb):
				return ra
			return pa.distance_squared_to(s.at) < pb.distance_squared_to(s.at))
		var cart := near.slice(0, 4 if unseen else 2)
		carted += cart.size()
		world.clear_bodies(cart)
	elif s.stage == "build":
		s.t = BUILD_GAP.y if unseen else BUILD_GAP.x
		var todo: Array = (s.pieces as Array).filter(func(id): return world.pieces[id].state != "intact")
		if todo.is_empty():
			s.stage = "done"
			return
		# Bottom up; glass and doors after the wall they sit in.
		todo.sort_custom(func(a, b): return _build_key(a) < _build_key(b))
		for id in todo:
			if _someone_in((world.pieces[id].aabb as AABB).grow(0.3)):
				continue
			if unseen or not by_crane(String(world.pieces[id].kind)):
				# Nobody watching: no need to show the crane at it. Glass,
				# doors and inside walls the fitter puts in by hand.
				if not unseen:
					s.t = HAND_FIT
				world.restore_piece(id)
				rebuilt += 1
				s.last = id
				_assign_jobs(s)
			else:
				_start_lift(s, id)
			return


## The big pieces go in on the crane; glass, doors and inside walls by hand.
static func by_crane(kind: String) -> bool:
	for k in ["glass", "door", "int_", "garage_door", "lamp_post", "bollard"]:
		if kind.begins_with(k):
			return false
	return true


func _rubble(s: Dictionary) -> Array:
	var near: Array = world.rubble_near(s.at, SITE_REACH + 6.0)
	for id in s.pieces:
		near.append_array(world.rubble_near((world.pieces[id].aabb as AABB).get_center(), 6.0).filter(func(n): return not near.has(n)))
	return near


## Host: the crane lifts a piece off the lorry and sets it in place; it goes
## back in for everyone part way through, when it's landed.
func _start_lift(s: Dictionary, id: int) -> void:
	s.lift = {"piece": id, "t": 0.0, "len": WorksSite.LIFT_TIME, "done": false}
	var b := StreamPeerBuffer.new()
	b.put_u16(s.id)
	b.put_u32(id)
	b.put_float(WorksSite.LIFT_TIME)
	if Net.is_online():
		Net.broadcast(MSG_LIFT, b.data_array, Net.RELIABLE)
	if _cones.has(s.id):
		(_cones[s.id] as WorksSite).start_lift(id, WorksSite.LIFT_TIME)
	_assign_jobs(s)


func _lift_work(s: Dictionary, delta: float, _unseen_now: bool) -> void:
	var l: Dictionary = s.lift
	var at_k: float = l.len * WorksSite.RESTORE_AT
	if not l.done and l.t + delta >= at_k:
		var id: int = l.piece
		if _someone_in((world.pieces[id].aabb as AABB).grow(0.3)):
			return      # someone's in the way: the load waits over the spot
		world.restore_piece(id)
		rebuilt += 1
		s.last = id
		l.done = true
		_assign_jobs(s)
	l.t += delta
	if l.t >= l.len:
		s.lift = {}


func _build_key(id: int) -> float:
	var p: Dictionary = world.pieces[id]
	return (p.aabb as AABB).position.y + (0.5 if int(p.held_by) >= 0 else 0.0)


## Tools and screenshots: act as if someone is always watching.
static var watch_all := false


func _unseen(p: Vector3) -> bool:
	if watch_all:
		return false
	for o in get_tree().get_nodes_in_group("officers"):
		if (o as Node3D).global_position.distance_to(p) < UNSEEN:
			return false
	return true


## Officers or people standing where a piece would go back.
func _someone_in(box: AABB) -> bool:
	for g in ["officers", "suspects"]:
		for n in get_tree().get_nodes_in_group(g):
			var q := (n as Node3D).global_position + Vector3(0, 0.9, 0)
			if box.has_point(q):
				return true
	return false


## Host: who does what, and where. Building: the slinger at the lorry, the
## banksman under the load, the fitter at the last piece set (or grinding a
## beam on the trestles when that's out of reach). Clearing: shovels and a
## broom in the rubble.
func _assign_jobs(s: Dictionary) -> void:
	var crew: Array = (s.crew as Array).filter(func(w): return is_instance_valid(w) and (w as Suspect).state != Suspect.S.DOWN)
	if crew.is_empty():
		s.jobs = {}
		return
	var nav: BlockNav = dispatch.nav if dispatch else null
	var lorry: Transform3D = s.lorry
	var right := lorry.basis.x
	var side := right * (1.0 if (s.at - lorry.origin).dot(right) > 0.0 else -1.0)
	var dir := lorry.basis.z
	var jobs := {}
	var plan: Array = []    # [job, spot, face]
	if s.stage == "build":
		var pick := lorry * WorksSite.PICK
		plan.append([WorksSite.Job.SLING, lorry.origin + side * 2.0 + dir * 1.0, pick])
		var tgt := Vector3.INF
		if not (s.lift as Dictionary).is_empty():
			tgt = (world.pieces[s.lift.piece].aabb as AABB).get_center()
		elif s.last >= 0:
			tgt = (world.pieces[s.last].aabb as AABB).get_center()
		if tgt == Vector3.INF:
			tgt = s.at
		var to_road := Vector3(lorry.origin.x - tgt.x, 0, lorry.origin.z - tgt.z).normalized()
		var g := Vector3(tgt.x, s.at.y, tgt.z) + to_road * 3.5
		plan.append([WorksSite.Job.BANKSMAN, g, tgt])
		var fit := _fit_spot(s, to_road)
		if fit.is_empty():
			var tp := _trestle(s)
			plan.append([WorksSite.Job.GRIND, tp + dir * 1.6, tp + dir * 1.0 + Vector3(0, 1.0, 0)])
		else:
			plan.append(fit)
	else:
		var rub := _rubble(s)
		rub.sort_custom(func(a, b): return (world.bodies[a] as Node3D).global_position.distance_squared_to(s.at) < (world.bodies[b] as Node3D).global_position.distance_squared_to(s.at))
		for i in 3:
			if i == 2 or rub.is_empty():
				var a := TAU * i / 3.0
				plan.append([WorksSite.Job.SWEEP, s.at + Vector3(cos(a), 0, sin(a)) * 2.5, s.at])
			else:
				var rp: Vector3 = (world.bodies[rub[mini(i * 2, rub.size() - 1)]] as Node3D).global_position
				var off := Vector3(s.at.x - rp.x, 0, s.at.z - rp.z).normalized()
				plan.append([WorksSite.Job.SHOVEL, rp + off * 1.0, rp])
	for i in crew.size():
		var w := crew[i] as Suspect
		var pl: Array = plan[i % plan.size()]
		var spot: Vector3 = pl[1]
		if nav and nav.ready_to_use:
			spot = nav.closest(spot)
		w.work_spot = spot
		w.work_face = pl[2]
		jobs[w.net_id] = [pl[0], pl[2]]
	if str(jobs) != str(s.jobs):
		s.jobs = jobs
		_send_t = 0.0


## The fitter's spot by the last piece set, if it's low enough to reach
## from the ground: drilling it home, or welding a column.
func _fit_spot(s: Dictionary, to_road: Vector3) -> Array:
	if s.last < 0:
		return []
	var p: Dictionary = world.pieces[s.last]
	var box: AABB = p.aabb
	if box.position.y > 2.0:
		return []
	var c := box.get_center()
	var face := Vector3(c.x, s.at.y, c.z) + to_road * (minf(box.size.x, box.size.z) * 0.5 + 0.7)
	var job: int = WorksSite.Job.WELD if String(p.kind).begins_with("column") or String(p.kind).begins_with("slab") else WorksSite.Job.DRILL
	return [job, face, Vector3(c.x, s.at.y + 1.0, c.z)]


func _trestle(s: Dictionary) -> Vector3:
	var lorry: Transform3D = s.lorry
	var right := lorry.basis.x
	var sd := 1.0 if (s.at - lorry.origin).dot(right) > 0.0 else -1.0
	var p := lorry * Vector3(WorksSite.TRESTLE.x * sd, 0, WorksSite.TRESTLE.z)
	return Vector3(p.x, s.at.y, p.z)


## The crew turns up (out of the lorry once it's parked), and if they're
## all down or gone a new lot comes after a while.
func _keep_crew(s: Dictionary, delta: float) -> void:
	var alive: Array = (s.crew as Array).filter(func(w): return is_instance_valid(w) and (w as Suspect).state not in [Suspect.S.DOWN, Suspect.S.BOOKED])
	if not alive.is_empty() or dispatch == null:
		return
	s.crew_t -= delta
	if s.crew_t > 0.0 and not (s.crew as Array).is_empty():
		return
	s.crew_t = NEW_CREW
	_send_crew(s)


func _send_crew(s: Dictionary) -> void:
	for w in s.crew:
		if is_instance_valid(w) and (w as Suspect).state != Suspect.S.DOWN:
			_remove_worker(w)
	s.crew = []
	var nav := dispatch.nav
	var lorry: Transform3D = s.lorry
	var right := lorry.basis.x
	var side := right * (1.0 if (s.at - lorry.origin).dot(right) > 0.0 else -1.0)
	var route: Array = []
	for k in 4:
		var a := TAU * k / 4.0 + _rng.randf_range(-0.3, 0.3)
		var q: Vector3 = s.at + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, 6.0)
		if nav and nav.ready_to_use:
			q = nav.closest(q)
		route.append(q)
	for i in CREW:
		var from: Vector3 = lorry.origin + side * 2.2 + lorry.basis.z * (2.5 - i * 1.2)
		if nav and nav.ready_to_use:
			from = nav.closest(from)
		var w := dispatch.spawn_suspect(from, Suspect.S.WANDER, false)
		w.civilian = true
		w.part = "worker"
		w.look = SuspectLook.WORKER + _rng.randi_range(0, 15)
		SuspectLook.apply(w.rig.model if w.rig else null, w.look)
		w.route = route.duplicate()
		w._route_i = i
		w._pace = 0.6
		s.crew.append(w)
	_assign_jobs(s)


func _remove_worker(w: Suspect) -> void:
	if dispatch:
		dispatch.suspects.erase(w.net_id)
	w.queue_free()


func _close(s: Dictionary) -> void:
	for w in s.crew:
		if is_instance_valid(w) and (w as Suspect).state != Suspect.S.DOWN:
			_remove_worker(w)
	sites.erase(s.id)
	_send_t = 0.0


# --- every machine: the site, vehicles and crew ---------------------------------------------

func _send_sites() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(sites.size())
	for s in sites.values():
		b.put_u16(s.id)
		_put_v(b, s.at)
		b.put_u8(0 if s.paused else 1)
		b.put_u8(1 if s.stage == "build" else 0)
		b.put_float(s.age)
		for k in ["lorry", "crane"]:
			var xf: Transform3D = s[k]
			_put_v(b, xf.origin)
			b.put_float(xf.basis.get_euler().y)
		var jobs: Dictionary = s.jobs
		b.put_u8(jobs.size())
		for nid in jobs:
			b.put_u32(nid)
			b.put_u8(jobs[nid][0])
			_put_v(b, jobs[nid][1])
	if Net.is_online():
		Net.broadcast(MSG_SITES, b.data_array, Net.UNRELIABLE)
	b.seek(0)
	_show_sites(b)


static func _put_v(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _get_v(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_float(), b.get_float(), b.get_float())


func _on_sites(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_show_sites(b)


func _on_lift(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var sid := b.get_u16()
	var piece := b.get_u32()
	var length := b.get_float()
	if _cones.has(sid):
		(_cones[sid] as WorksSite).start_lift(piece, length)


func _show_sites(b: StreamPeerBuffer) -> void:
	var seen := {}
	var people: Dictionary = dispatch.suspects if dispatch else {}
	for i in b.get_u8():
		var id := b.get_u16()
		var at := _get_v(b)
		var working := b.get_u8() == 1
		var build := b.get_u8() == 1
		var age := b.get_float()
		var xfs: Array = []
		for k in 2:
			var o := _get_v(b)
			xfs.append(Transform3D(Basis(Vector3.UP, b.get_float()), o))
		var jobs := {}
		for j in b.get_u8():
			var nid := b.get_u32()
			var job := b.get_u8()
			jobs[nid] = [job, _get_v(b)]
		_cone_at[id] = [at, working]
		seen[id] = true
		if not _cones.has(id):
			_cones[id] = WorksSite.make(id, at, world)
			add_child(_cones[id])
		var site := _cones[id] as WorksSite
		site.working = working
		site.build_stage = build
		site.set_park(xfs[0], xfs[1], age)
		site.set_crew(jobs, people)
	for id in _cones.keys():
		if not seen.has(id):
			# Site closed: whatever blood the crew left goes with them (on
			# every machine, as each one's marks differ a little).
			var at: Vector3 = _cone_at[id][0]
			for d in blood_near(at, SITE_REACH + 6.0):
				(d as Node).queue_free()
			(_cones[id] as WorksSite).leave()
			_cones.erase(id)
			_cone_at.erase(id)


## Every machine: crews at work scrub the blood round their site, a mark at
## a time (quicker with nobody watching).
func _scrub(delta: float) -> void:
	_scrub_t -= delta
	if _scrub_t > 0.0 or _cone_at.is_empty():
		return
	_scrub_t = SCRUB_GAP.x
	for id in _cone_at:
		var at: Vector3 = _cone_at[id][0]
		if not _cone_at[id][1]:
			continue    # crew off the job
		var marks := blood_near(at, SITE_REACH + 6.0)
		if marks.is_empty():
			continue
		if _unseen(at):
			_scrub_t = SCRUB_GAP.y
		marks.sort_custom(func(a, b): return (a as Node3D).global_position.distance_squared_to(at) < (b as Node3D).global_position.distance_squared_to(at))
		(marks[0] as Node).remove_from_group("blood")
		(marks[0] as Node).queue_free()
		scrubbed += 1
