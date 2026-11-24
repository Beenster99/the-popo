class_name RepairCrews
extends Node
## Wave 4, Phase 4.1: the city mends itself. A while after something gets
## knocked down, the council sends a crew: a van parked up at the kerb,
## two or three workers in hi-vis and hard hats, and cones round the site.
## First they cart the rubble away (what's lying in the road goes first),
## then they build what fell back up again, bottom to top, a piece at a
## time. It's slow while you're watching and quicker while nobody is, but
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
## else; the cones go out in MSG_SITES.

const MSG_SITES := 108          # host -> all: the sites, for the cones (every 3 s)
const WAIT := 40.0              # real seconds after damage before a crew is sent
const SITE_REACH := 16.0        # rubble and pieces this close belong to one site
const MAX_SITES := 3
const UNSEEN := 120.0           # nobody within this: work goes quicker
const CLEAN_GAP := Vector2(2.5, 0.5)    # seen, unseen: seconds per load carted away
const BUILD_GAP := Vector2(6.0, 1.0)    # seen, unseen: seconds per piece put back
const CREW := Vector2i(2, 3)
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
var _cones := {}                # site id -> Node3D (every machine)
var _cone_at := {}              # site id -> [position, working] (every machine)
var scrubbed := 0               # blood marks cleaned (this machine)
var _scrub_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Net.register(MSG_SITES, _on_sites)
	if world:
		world.piece_broken.connect(_on_broken)


func _exit_tree() -> void:
	Net.unregister(MSG_SITES)


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
		"van": {}, "t": 1.0, "crew_t": 0.0, "paused": false, "said": false}
	_next_id += 1
	sites[s.id] = s
	_send_t = 0.0
	return s


## Host: one step of work at a site.
func _work(s: Dictionary, delta: float) -> void:
	if s.stage == "done":
		return
	_keep_crew(s, delta)
	# Everyone still on their feet has to be back at work (not running or
	# hiding from something); the ones who went down are out of it.
	var up: Array = (s.crew as Array).filter(func(w): return is_instance_valid(w) and (w as Suspect).state not in [Suspect.S.DOWN, Suspect.S.BOOKED])
	s.paused = up.is_empty() or up.any(func(w): return (w as Suspect).state != Suspect.S.WANDER)
	if s.paused:
		return
	if not s.said and dispatch:
		s.said = true
		dispatch.say("COUNCIL: a crew's on site at %s, clearing up and making good." % CityGenerator.street_at(s.at))
	var unseen := _unseen(s.at)
	s.t -= delta
	if s.t > 0.0:
		return
	if s.stage == "clean":
		s.t = CLEAN_GAP.y if unseen else CLEAN_GAP.x
		var near: Array = world.rubble_near(s.at, SITE_REACH + 6.0)
		for id in s.pieces:
			near.append_array(world.rubble_near((world.pieces[id].aabb as AABB).get_center(), 6.0).filter(func(n): return not near.has(n)))
		if near.is_empty():
			# The crew scrubs the blood (see _scrub) before moving on.
			if not blood_near(s.at, SITE_REACH + 6.0).is_empty():
				return
			s.stage = "build"
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
			if dispatch:
				dispatch.say("COUNCIL: %s is made good. Crew's packing up." % CityGenerator.street_at(s.at))
			return
		# Bottom up; glass and doors after the wall they sit in.
		todo.sort_custom(func(a, b): return _build_key(a) < _build_key(b))
		for id in todo:
			if not _someone_in((world.pieces[id].aabb as AABB).grow(0.3)):
				world.restore_piece(id)
				rebuilt += 1
				return


func _build_key(id: int) -> float:
	var p: Dictionary = world.pieces[id]
	return (p.aabb as AABB).position.y + (0.5 if int(p.held_by) >= 0 else 0.0)


func _unseen(p: Vector3) -> bool:
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


## The crew turns up (a van at the kerb, workers walking the site), and if
## they're all down or gone a new lot comes after a while.
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
	if traffic and (s.van as Dictionary).is_empty():
		s.van = traffic.borrow_car(s.at)
	var nav := dispatch.nav
	var route: Array = []
	for k in 4:
		var a := TAU * k / 4.0 + _rng.randf_range(-0.3, 0.3)
		var q: Vector3 = s.at + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(3.0, 6.0)
		if nav and nav.ready_to_use:
			q = nav.closest(q)
		route.append(q)
	for i in _rng.randi_range(CREW.x, CREW.y):
		var w := dispatch.spawn_suspect(route[i % route.size()], Suspect.S.WANDER, false)
		w.civilian = true
		w.part = "worker"
		w.look = SuspectLook.WORKER + _rng.randi_range(0, 15)
		SuspectLook.apply(w.rig.model if w.rig else null, w.look)
		w.route = route.duplicate()
		w._route_i = i
		w._pace = 0.6
		s.crew.append(w)


func _remove_worker(w: Suspect) -> void:
	if dispatch:
		dispatch.suspects.erase(w.net_id)
	w.queue_free()


func _close(s: Dictionary) -> void:
	for w in s.crew:
		if is_instance_valid(w) and (w as Suspect).state != Suspect.S.DOWN:
			_remove_worker(w)
	if not (s.van as Dictionary).is_empty():
		(s.van as Dictionary).erase("hold")   # the van goes back to the traffic
	sites.erase(s.id)
	_send_t = 0.0


# --- every machine: cones ------------------------------------------------------------

func _send_sites() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(sites.size())
	for s in sites.values():
		b.put_u16(s.id)
		b.put_float(s.at.x)
		b.put_float(s.at.y)
		b.put_float(s.at.z)
		b.put_u8(0 if s.paused else 1)
	if Net.is_online():
		Net.broadcast(MSG_SITES, b.data_array, Net.UNRELIABLE)
	b.seek(0)
	_show_sites(b)


func _on_sites(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_show_sites(b)


func _show_sites(b: StreamPeerBuffer) -> void:
	var seen := {}
	for i in b.get_u8():
		var id := b.get_u16()
		var at := Vector3(b.get_float(), b.get_float(), b.get_float())
		_cone_at[id] = [at, b.get_u8() == 1]
		seen[id] = true
		if not _cones.has(id):
			_cones[id] = _make_cones(at)
			add_child(_cones[id])
	for id in _cones.keys():
		if not seen.has(id):
			# Site closed: whatever blood the crew left goes with them (on
			# every machine, as each one's marks differ a little).
			var at: Vector3 = _cone_at[id][0]
			for d in blood_near(at, SITE_REACH + 6.0):
				(d as Node).queue_free()
			(_cones[id] as Node).queue_free()
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


static var _cone_mesh: Mesh
static var _cone_mat: Material


## A ring of traffic cones and a sign round the site.
func _make_cones(at: Vector3) -> Node3D:
	if _cone_mesh == null:
		var c := CylinderMesh.new()
		c.top_radius = 0.03
		c.bottom_radius = 0.17
		c.height = 0.7
		c.radial_segments = 10
		_cone_mesh = c
		_cone_mat = Cel.material(Color("ff6a13"), true, 0.012)
	var root := Node3D.new()
	root.name = "Site"
	var n := 10
	for k in n:
		var a := TAU * k / n
		var mi := MeshInstance3D.new()
		mi.mesh = _cone_mesh
		mi.material_override = _cone_mat
		mi.position = at + Vector3(cos(a), 0, sin(a)) * 7.5 + Vector3(0, 0.35, 0)
		root.add_child(mi)
	var sign := Label3D.new()
	sign.text = "ROAD WORKS"
	sign.font_size = 48
	sign.outline_size = 10
	sign.pixel_size = 0.01
	sign.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign.modulate = Color("ffcf3a")
	sign.position = at + Vector3(0, 2.4, 0)
	root.add_child(sign)
	return root
