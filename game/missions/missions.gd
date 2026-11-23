class_name Missions
extends Node
## Wave 3, Phase 3.1: dispatcher version 2.
##
## Every job is a template: what it is, who is in it (suspects, a victim, a
## witness), where it happens (a shop, a house, the street, a yard), and how
## likely it is in each district and at each time of day: muggings and drunks
## downtown at night, shoplifting in the afternoon, domestics in the
## evenings out in the houses, deals in the yards and at the docks after dark.
##
## The city has a clock (a game day passes in 48 minutes), shown on the HUD.
##
## Chance encounters: now and then a crime starts just up the street from an
## officer without a call. Nobody is told until an officer gets close
## enough to see it; then it goes out over the radio as theirs. If nobody
## comes by, it is over and gone.
##
## Victims stay where it happened, shaken; reach one and they tell you what
## the suspect looks like and which way they went. Witnesses stand by and
## point. Either way the call's marker jumps to the suspect.

const DAY_MINUTES := 1440.0
const MINUTES_PER_SECOND := 0.5          # 48 real minutes a day
const START_MINUTE := 9 * 60.0
const ENCOUNTER_GAP := Vector2(40.0, 80.0)
const ENCOUNTER_SEEN := 22.0             # m: an officer this close (in sight) has found it
const ENCOUNTER_LIFE := 120.0            # s before an unfound encounter is over
const TALK_REACH := 3.5

## District weights: downtown, residential, industrial, docks.
## Time weights: morning (6-12), afternoon (12-18), evening (18-23), night.
const TEMPLATES := {
	Dispatcher.Kind.ROBBERY: {"d": [3, 2, 1, 0], "h": [1, 2, 2, 1]},
	Dispatcher.Kind.ARMED: {"d": [2, 1, 2, 2], "h": [1, 1, 2, 3]},
	Dispatcher.Kind.TRAFFIC: {"d": [2, 2, 1, 1], "h": [2, 2, 1, 1]},
	Dispatcher.Kind.GANG: {"d": [1, 1, 3, 3], "h": [0.5, 1, 2, 3]},
	Dispatcher.Kind.THEFT: {"d": [2, 3, 2, 1], "h": [1, 1, 2, 3]},
	Dispatcher.Kind.PURSUIT: {"d": [2, 1, 2, 1], "h": [1, 1, 2, 2]},
	Dispatcher.Kind.MUGGING: {"d": [3, 2, 1, 1], "h": [1, 1, 2, 3], "encounter": true},
	Dispatcher.Kind.SHOPLIFT: {"d": [3, 2, 0.3, 0], "h": [2, 3, 2, 0.5], "encounter": true},
	Dispatcher.Kind.FIGHT: {"d": [3, 1, 1, 2], "h": [0.3, 1, 2, 3], "encounter": true},
	Dispatcher.Kind.DOMESTIC: {"d": [0.5, 4, 0.3, 0.3], "h": [1, 1, 3, 2]},
	Dispatcher.Kind.DEAL: {"d": [1, 1, 2, 2], "h": [0.2, 0.5, 2, 3], "encounter": true},
	Dispatcher.Kind.VANDAL: {"d": [2, 2, 2, 1], "h": [0.3, 0.5, 2, 3], "encounter": true},
	Dispatcher.Kind.DRUNK: {"d": [4, 1, 0.5, 1], "h": [0.2, 0.5, 2, 4], "encounter": true},
}
const DISTRICTS := ["downtown", "residential", "industrial", "docks"]

var dispatcher: Dispatcher
var minute := START_MINUTE                # game time of day (synced)
var enabled := true
var _rng := RandomNumberGenerator.new()
var _encounter_t := 30.0
## Host: call id -> {victim, witness, said: {}}
var people := {}


func _ready() -> void:
	_rng.randomize()
	_encounter_t = _rng.randf_range(ENCOUNTER_GAP.x * 0.5, ENCOUNTER_GAP.y * 0.5)


func clock_text() -> String:
	var m := int(minute) % int(DAY_MINUTES)
	return "%02d:%02d" % [m / 60, m % 60]


## 0 morning, 1 afternoon, 2 evening, 3 night.
func time_slot() -> int:
	var h := int(minute / 60.0) % 24
	if h >= 6 and h < 12:
		return 0
	if h >= 12 and h < 18:
		return 1
	if h >= 18 and h < 23:
		return 2
	return 3


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		minute = fposmod(minute + delta * MINUTES_PER_SECOND, DAY_MINUTES)
		return
	minute = fposmod(minute + delta * MINUTES_PER_SECOND, DAY_MINUTES)
	if dispatcher == null or dispatcher.city == null:
		return
	_talk_step()
	_hidden_step(delta)
	if enabled and dispatcher.enabled:
		_encounter_t -= delta
		if _encounter_t <= 0.0:
			_encounter_t = _rng.randf_range(ENCOUNTER_GAP.x, ENCOUNTER_GAP.y)
			if dispatcher._active_count() < Dispatcher.MAX_CALLS + 1:
				start_encounter()


## A job for here and now, weighted by the district the officers are in
## and the time of day (kinds already running are left out).
func pick_kind(exclude: Array = []) -> Dispatcher.Kind:
	var district := _district_near_officers()
	var di := maxi(DISTRICTS.find(district), 1)
	var slot := time_slot()
	var total := 0.0
	var weights := {}
	for k in TEMPLATES:
		if k in exclude:
			continue
		if k == Dispatcher.Kind.TRAFFIC and dispatcher.civ_car == null:
			continue
		if k in [Dispatcher.Kind.THEFT, Dispatcher.Kind.PURSUIT] and dispatcher.traffic == null:
			continue
		var w: float = float(TEMPLATES[k].d[di]) * float(TEMPLATES[k].h[slot])
		if w > 0.0:
			weights[k] = w
			total += w
	if weights.is_empty():
		return Dispatcher.Kind.ROBBERY
	var x := _rng.randf() * total
	for k in weights:
		x -= weights[k]
		if x <= 0.0:
			return k
	return weights.keys()[0]


func _district_near_officers() -> String:
	var city := dispatcher.city
	var officers := get_tree().get_nodes_in_group("officers")
	if officers.is_empty():
		return "downtown"
	return city.district_at((officers[0] as Node3D).global_position)


# --- the new jobs (host) -----------------------------------------------------------------

## Fills in call c (its kind already chosen, its block picked). Returns
## false if there is nowhere for it here.
func setup_call(c: Dictionary, at := Vector3.INF) -> bool:
	var d := dispatcher
	var street := at if at != Vector3.INF else d._street_spot()
	match c.kind:
		Dispatcher.Kind.MUGGING:
			var s := d.spawn_suspect(street, Suspect.S.LOITER, _rng.randf() < 0.2, c.id)
			c.suspects.append(s.net_id)
			var v := _bystander(street + _side(1.1), "victim", c)
			_bystander(street + _side(7.0), "witness", c)
			s._face(v.global_position)
			c.pos = street
			c.text = "Mugging %s. Victim's still there. Suspect may be armed." % d._side_name(street)
		Dispatcher.Kind.SHOPLIFT:
			var b := d._shop()
			if b.is_empty():
				return false
			var inside: Vector3 = b.origin + b.u * (b.w * BlockGenerator.M * 0.5) + b.v * (BlockGenerator.M * 0.9) + Vector3(0, 0.05, 0)
			var s := d.spawn_suspect(inside + b.u * 1.5, Suspect.S.ROB, false, c.id)
			c.suspects.append(s.net_id)
			_bystander(inside - b.u * 1.5, "victim", c)
			c.pos = inside
			c.text = "Shoplifter at the %s on %s. The shopkeeper's holding the door." % [b.type, CityGenerator.street_at(b.door)]
		Dispatcher.Kind.FIGHT:
			var a := d.spawn_suspect(street, Suspect.S.BRAWL, false, c.id)
			var b2 := d.spawn_suspect(street + _side(1.2), Suspect.S.BRAWL, false, c.id)
			a.brawl_with = b2
			b2.brawl_with = a
			c.suspects.append(a.net_id)
			c.suspects.append(b2.net_id)
			_bystander(street + _side(6.0), "witness", c)
			c.pos = street
			c.text = "Fight in the street %s. Two men going at it." % d._side_name(street)
		Dispatcher.Kind.DOMESTIC:
			var h := _house()
			if h.is_empty():
				return false
			var inside: Vector3 = h.origin + h.u * (h.w * BlockGenerator.M * 0.5) + h.v * (BlockGenerator.M * 1.5) + Vector3(0, 0.05, 0)
			var s := d.spawn_suspect(inside, Suspect.S.LOITER, _rng.randf() < 0.25, c.id)
			s.fighter = s.armed
			c.suspects.append(s.net_id)
			_bystander(inside + h.u * 1.6, "victim", c)
			c.pos = inside
			c.text = "Domestic disturbance at a %s on %s. Shouting, things breaking. Go in carefully." % [h.type, CityGenerator.street_at(h.door)]
		Dispatcher.Kind.DEAL:
			var p := at if at != Vector3.INF else d._gang_spot()
			for i in 2:
				var s := d.spawn_suspect(d.nav.closest(p + Vector3(i * 1.4, 0, 0.6)), Suspect.S.LOITER, i == 0, c.id)
				s.fighter = i == 0
				c.suspects.append(s.net_id)
			c.pos = p
			c.text = "Drug deal going down %s. One of them is carrying." % d._side_name(p)
		Dispatcher.Kind.VANDAL:
			var glass := _glass_near(street)
			if glass == Vector3.INF:
				return false
			var s := d.spawn_suspect(d.nav.closest(glass), Suspect.S.BRAWL, false, c.id)
			s.brawl_with = glass
			c.suspects.append(s.net_id)
			c.pos = glass
			c.text = "Someone smashing windows %s." % d._side_name(glass)
		Dispatcher.Kind.DRUNK:
			var s := d.spawn_suspect(street, Suspect.S.LOITER, false, c.id)
			s.drunk = true
			s.hp = Suspect.MAX_HP * 1.4
			c.suspects.append(s.net_id)
			c.pos = street
			c.text = "Drunk and disorderly %s, shouting at traffic. Bring him in." % d._side_name(street)
		_:
			return false
	return true


func _side(dist: float) -> Vector3:
	var a := _rng.randf() * TAU
	return Vector3(cos(a), 0, sin(a)) * dist


## A victim or witness: a civilian who stays put (and doesn't walk off).
func _bystander(p: Vector3, role: String, c: Dictionary) -> Suspect:
	var d := dispatcher
	var q := d.nav.closest(p) if d.nav and d.nav.ready_to_use else p
	var s := d.spawn_suspect(q, Suspect.S.COWER if role == "victim" else Suspect.S.WANDER, false)
	s.civilian = true
	s.part = role
	s._calm_t = 9999.0
	if not people.has(c.id):
		people[c.id] = {"victim": null, "witness": null, "said": {}}
	people[c.id][role] = s
	return s


func _house() -> Dictionary:
	var best: Dictionary = {}
	for b in dispatcher._area_buildings():
		if b.enterable and b.type in ["house", "flats"]:
			best = b
			break
	return best if not best.is_empty() else dispatcher._shop()


## The nearest window glass to p, at street level.
func _glass_near(p: Vector3) -> Vector3:
	var w := dispatcher.world
	var best := Vector3.INF
	var bd := 30.0
	for id in w.pieces_near(p, 30.0):
		var piece: Dictionary = w.pieces[id]
		if piece.state != "intact" or not String(piece.kind).begins_with("glass"):
			continue
		var c: Vector3 = (piece.aabb as AABB).get_center()
		if c.y > 3.0:
			continue
		var dd := c.distance_to(p)
		if dd < bd:
			bd = dd
			best = c
	return best


# --- victims and witnesses ---------------------------------------------------------------

func _talk_step() -> void:
	for id in people.keys():
		var e: Dictionary = people[id]
		var c: Dictionary = dispatcher.calls.get(id, {})
		if c.is_empty() or c.state != Dispatcher.CallState.ACTIVE:
			if c.is_empty() or c.state != Dispatcher.CallState.HIDDEN:
				_release(e)
				people.erase(id)
			continue
		for role in ["victim", "witness"]:
			var s: Suspect = e.get(role)
			if s == null or not is_instance_valid(s) or e.said.has(role) or s.state == Suspect.S.DOWN:
				continue
			for o in get_tree().get_nodes_in_group("officers"):
				if (o as Officer).state != Officer.S.VEHICLE and (o as Node3D).global_position.distance_to(s.global_position) < TALK_REACH:
					e.said[role] = true
					_tell(c, role, s)
					break


## What a victim or witness says: the suspect's clothes and where they went.
func _tell(c: Dictionary, role: String, by: Suspect) -> void:
	var sus: Suspect = null
	for sid in c.suspects:
		var s: Suspect = dispatcher.suspects.get(sid)
		if s and not s.is_done():
			sus = s
			break
	if sus == null:
		dispatcher.say("%s: They're gone, you got them. Thank you." % role.to_upper())
		return
	var look := SuspectLook.colours(sus.look)
	var top := Dispatcher._colour_name(look.shirt)
	var legs := Dispatcher._colour_name(look.trousers)
	var to := sus.global_position - by.global_position
	var where := "right there" if to.length() < 8.0 else "off %s, towards %s" % [_compass(to), CityGenerator.street_at(sus.global_position)]
	var hat := ", beanie" if look.beanie else ""
	if role == "victim":
		dispatcher.say("VICTIM: %s top, %s trousers%s. %s" % [top.capitalize(), legs, hat, "Went " + where + "." if to.length() >= 8.0 else "That's them!"])
	else:
		dispatcher.say("WITNESS: %s top%s, went %s." % [top.capitalize(), hat, where])
	c.marker = sus.global_position
	c.seen_t = 4.0


static func _compass(v: Vector3) -> String:
	var a := atan2(v.x, -v.z)   # 0 north (-z), clockwise
	var names := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
	return names[int(roundf(a / (TAU / 8.0))) % 8 if a >= 0 else int(roundf((a + TAU) / (TAU / 8.0))) % 8]


## The job's over: victims and witnesses get on with their day.
func _release(e: Dictionary) -> void:
	for role in ["victim", "witness"]:
		var s: Suspect = e.get(role)
		if s == null or not is_instance_valid(s) or s.state == Suspect.S.DOWN:
			continue
		s.part = ""
		s.route = PedSystem.route_near(dispatcher.city, s.global_position, _rng)
		s._calm_t = 2.0
		if s.state == Suspect.S.WANDER:
			s._back_to_route()
		if PedSystem.current:
			PedSystem.current.adopt(s)


# --- chance encounters -------------------------------------------------------------------

## Host: a crime just up the street from an officer, unannounced.
func start_encounter() -> int:
	var officers := get_tree().get_nodes_in_group("officers").filter(func(o): return (o as Officer).state != Officer.S.VEHICLE)
	if officers.is_empty():
		return -1
	var o: Officer = officers[_rng.randi_range(0, officers.size() - 1)]
	var spot := _spot_ahead(o)
	if spot == Vector3.INF:
		return -1
	var c2 := CityGenerator.block_at(spot)
	if c2.x < 0:
		return -1
	var kinds: Array = []
	for k in TEMPLATES:
		if TEMPLATES[k].get("encounter", false):
			kinds.append(k)
	var slot := time_slot()
	var di := maxi(DISTRICTS.find(dispatcher.city.district_at(spot)), 1)
	var total := 0.0
	for k in kinds:
		total += float(TEMPLATES[k].d[di]) * float(TEMPLATES[k].h[slot])
	var x := _rng.randf() * total
	var kind: Dispatcher.Kind = kinds[0]
	for k in kinds:
		x -= float(TEMPLATES[k].d[di]) * float(TEMPLATES[k].h[slot])
		if x <= 0.0:
			kind = k
			break
	return dispatcher.start_call(kind, {"block": dispatcher.city.block_index(c2.x, c2.y), "at": spot, "hidden": true})


## A pavement spot 28-50 m from the officer, preferably the way they face.
func _spot_ahead(o: Officer) -> Vector3:
	var nav := dispatcher.nav as CityNav
	var fwd := -o.global_transform.basis.z
	var best := Vector3.INF
	var best_s := -INF
	for i in 14:
		var a := _rng.randf_range(-1.2, 1.2)
		var dir := fwd.rotated(Vector3.UP, a)
		var p := o.global_position + dir * _rng.randf_range(28.0, 50.0)
		var c := CityGenerator.block_at(p)
		if c.x < 0:
			continue
		var k := dispatcher.city.block_index(c.x, c.y)
		if nav and not nav.block_ready(k):
			continue
		var q := dispatcher.city.pavement_near(p)
		q = nav.closest(q) if nav else q
		var d := q.distance_to(o.global_position)
		if d < 25.0 or d > 55.0:
			continue
		var score := -absf(a) * 10.0 + _rng.randf() * 5.0
		if score > best_s:
			best_s = score
			best = q
	return best


## Unfound encounters: found when an officer gets close with a clear view;
## gone if nobody comes.
func _hidden_step(delta: float) -> void:
	for c in dispatcher.calls.values():
		if c.state != Dispatcher.CallState.HIDDEN:
			continue
		c.t += delta
		var found: Officer = null
		for sid in c.suspects:
			var s: Suspect = dispatcher.suspects.get(sid)
			if s == null:
				continue
			for o in get_tree().get_nodes_in_group("officers"):
				var off := o as Officer
				if off.global_position.distance_to(s.global_position) > ENCOUNTER_SEEN:
					continue
				var q := PhysicsRayQueryParameters3D.create(off.global_position + Vector3(0, 1.6, 0), s.global_position + Vector3(0, 1.2, 0), 1)
				if off.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
					found = off
					break
			if found:
				break
		if found:
			c.state = Dispatcher.CallState.ACTIVE
			c.t = 0.0
			dispatcher.say("DISPATCH: you've come across it yourselves: %s" % c.text)
		elif c.t > ENCOUNTER_LIFE:
			c.state = Dispatcher.CallState.CLOSED
			for sid in c.suspects:
				var s: Suspect = dispatcher.suspects.get(sid)
				if s and s.is_free():
					s.set_state(Suspect.S.BOOKED)   # done and gone
