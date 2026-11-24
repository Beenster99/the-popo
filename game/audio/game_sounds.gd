class_name GameSounds
extends Node
## Phase 1.6: the sound of a game scene, added once by each scene that plays.
##
## Every machine hears its own copy of the world: it works out sounds from
## what it sees (officers' synced state, cars and rubble moving), and the
## host tells everyone only what they cannot see for themselves (where a
## bullet went and what it hit; a punch landing), through SfxSync.
##
##  - Ears: on the player's officer (at head height), facing the way the
##    camera looks, so left and right on screen are left and right.
##  - Background: a busy street, air and distant traffic outdoors, a quiet
##    room tone indoors; the street muffles as you walk in. Ducked for a
##    split second under a close shot so the shot dominates.
##  - Footsteps for everyone on their feet, by surface, faster and louder
##    running; kit rattles on officers when they run.
##  - Officers' guns: layered shots (Sfx.shot), dry clicks, the reload
##    (mag out, the empty mag hitting the floor, mag in, slide), holstering,
##    and brass: each case is a little physics body that plays its bounce on
##    whatever it lands on.
##  - Punches and kicks swish; car doors open and shut as officers get in
##    and out.
##  - Cars: engine pitch with speed, tyre squeal when sliding, crunch on a
##    hard knock.
##  - Destruction: pieces breaking by material (glass of every size with
##    shards settling after, wood splintering, concrete crumbling, metal),
##    and every loose chunk and object that lands hard plays its impact,
##    scaled by how hard, with a budget so a collapse stays readable.
##  - Ear ring after a very close shot or blast: a whine and everything
##    muffled for a moment.

static var current: GameSounds

## () -> Node3D: the officer the player controls (or null).
var pawn_getter: Callable
var world: DestructionWorld
var cars: CarSync
var sync: SfxSync
var listener: AudioListener3D

## v0.12.0: boot steps from real recordings, well under the guns and voices
## (beenster found the old ones too loud).
const STEP_WALK_DB := -21.0
const STEP_RUN_DB := -14.0
const IMPACT_BUDGET := 10.0     # physics impact sounds per second, at most
const MAX_CASINGS := 40

var _amb := {}
var _indoor_k := 0.0
var _duck := 0.0
var _ring := 0.0
var _ring_fx := -1
var _walkers := {}        # instance id -> {last, acc, n}
var _officers := {}       # instance id -> {rounds, gun, reload, holster, punch, state, fire}
var _car_audio := {}      # instance id -> {engine, skid, last_pos, last_v, on}
var _bodies := {}         # instance id -> [last pos, last speed]
var _budget := IMPACT_BUDGET
var _recent := []         # [pos, time] of recent impact sounds (merge close ones)
var _casings := []
var _clock := 0.0
var _pending := []        # [time, {stem, pos, db, dist, spread, bus, pitch, reload_of}]
var _calls := []          # [time, Callable]
var _breaks := []         # [pos, time] of recent big breaks (for a collapse)
var _last_collapse := -100.0


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	_set_ring_filter(false, 20000.0)


func _ready() -> void:
	Sfx.ensure_buses()
	_ring_fx = AudioServer.get_bus_effect_count(0) - 1
	sync = SfxSync.new()
	sync.name = "SfxSync"
	add_child(sync)
	var voices := Voices.new()
	voices.name = "Voices"
	add_child(voices)
	listener = AudioListener3D.new()
	listener.name = "Ears"
	listener.add_to_group(Sfx.LISTENER_GROUP)
	add_child(listener)
	listener.make_current()
	_amb_player("street", "amb_street", Sfx.BUS_AMBIENCE_OUT, -11.0)
	_amb_player("air", "amb_air", Sfx.BUS_AMBIENCE_OUT, -18.0)
	_amb_player("far", "amb_far_traffic", Sfx.BUS_AMBIENCE_OUT, -16.0)
	_amb_player("room", "room_tone", Sfx.BUS_AMBIENCE, -60.0)
	# Wave 2: each district has its own sound under the street.
	for k in DISTRICT_BEDS:
		_amb_player(k, DISTRICT_BEDS[k][0], Sfx.BUS_AMBIENCE_OUT, -80.0)
	# Wave 4: rain (CityWeather sets how hard).
	_amb_player("rain", "amb_rain", Sfx.BUS_AMBIENCE_OUT, -80.0)
	if world:
		world.piece_broken.connect(_on_piece_broken)
		world.fx.connect(_on_world_fx)


func _amb_player(key: String, stem: String, bus: String, db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.loop_stream(stem)
	p.bus = bus
	p.volume_db = db
	p.autoplay = false
	add_child(p)
	p.play(randf() * 5.0)
	_amb[key] = p


## Wave 2: the district beds, [stem, loudness at full (dB)], and how loud
## the busy street is in each district (dB).
const DISTRICT_BEDS := {"docks": ["amb_docks", -9.0], "industrial": ["amb_industrial", -12.0], "park": ["amb_park", -10.0]}
const STREET_DB := {"downtown": -9.0, "residential": -14.0, "industrial": -15.0, "docks": -19.0, "park": -17.0, "station": -11.0, "outskirts": -18.0}
var city: CityGenerator
var _bed := {}            # district bed -> 0..1, eased


## Indoors for the ears and the reverb: one zone per building.
func add_building_zones(gen: BlockGenerator) -> void:
	if gen is CityGenerator:
		city = gen
	for b in gen.buildings:
		var box: AABB = b.bounds
		var z := SoundZone.new()
		z.size = box.size - Vector3(0.3, 0, 0.3)
		add_child(z)
		z.global_position = box.get_center()


# --- every frame ---------------------------------------------------------------------

func _process(delta: float) -> void:
	_place_ears()
	_background(delta)
	_mix(delta)
	for n in get_tree().get_nodes_in_group("officers"):
		_officer_foley(n as Officer, delta)
	_play_pending()
	_tidy_casings()


## Movement sounds work from how far things moved each physics step.
const STEPS_HEARD := 45.0
const CARS_HEARD := 130.0


func _physics_process(delta: float) -> void:
	_clock += delta
	_budget = minf(IMPACT_BUDGET, _budget + IMPACT_BUDGET * delta)
	# v0.19.0: only what is within earshot is worked out each tick.
	var ear := _ear()
	for n in get_tree().get_nodes_in_group("officers") + get_tree().get_nodes_in_group("suspects"):
		var nn := n as Node3D
		if nn and nn.global_position.distance_squared_to(ear) < STEPS_HEARD * STEPS_HEARD:
			_footsteps(nn, delta)
	if cars:
		for c in cars.cars:
			var car := c as Car
			if car == null or not is_instance_valid(car):
				continue
			if car.global_position.distance_squared_to(ear) > CARS_HEARD * CARS_HEARD:
				var a: Dictionary = _car_audio.get(car.get_instance_id(), {})
				if not a.is_empty():
					a.last = car.global_position
					a.away = true   # coming back in range is not a "crash"
				continue
			_car(car, delta)
	_physics_impacts(delta)


## Plays a sound a little later (echoes, shards settling, reload steps).
## reload_of: an officer's instance id; skipped if they stopped reloading.
func later(t: float, stem: String, pos: Vector3, db := 0.0, dist := 60.0, spread := 0.05, bus := "", pitch := 1.0, reload_of := 0) -> void:
	_pending.append([_clock + t, {"stem": stem, "pos": pos, "db": db, "dist": dist, "spread": spread, "bus": bus,
		"pitch": pitch, "reload_of": reload_of}])


## v0.13.0: runs f after t seconds (a far shot's bang arriving late).
func later_call(t: float, f: Callable) -> void:
	_calls.append([_clock + t, f])


func _play_pending() -> void:
	var j := 0
	while j < _calls.size():
		if float(_calls[j][0]) > _clock:
			j += 1
			continue
		var f: Callable = _calls[j][1]
		_calls.remove_at(j)
		if f.is_valid():
			f.call()
	var i := 0
	while i < _pending.size():
		var e: Array = _pending[i]
		if float(e[0]) > _clock:
			i += 1
			continue
		_pending.remove_at(i)
		var d: Dictionary = e[1]
		if d.reload_of != 0:
			var o := instance_from_id(d.reload_of) as Officer
			if o == null or o.reload_t <= 0.0:
				continue
			if String(d.stem).begins_with("mag_drop"):
				d.pos = o.global_position + Vector3(0, 0.05, 0)
				d.stem = "mag_drop_" + _drop_surface(surface_under(o.global_position))
			else:
				d.pos = o.global_position + Vector3(0, 1.1, 0)
		var p := Sfx.play(self, d.stem, d.pos, d.db, d.dist, d.spread, d.bus)
		if p:
			p.pitch_scale *= d.pitch


func _pawn() -> Node3D:
	var o: Node3D = pawn_getter.call() if pawn_getter.is_valid() else null
	return o if o and is_instance_valid(o) and o.is_inside_tree() else null


func _place_ears() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var o := _pawn()
	var at: Vector3
	if o:
		at = o.global_position + Vector3(0, 1.6, 0)
	elif cam:
		at = cam.global_position
	else:
		return
	var basis := Basis()
	if cam:
		var f := -cam.global_transform.basis.z
		f.y = 0.0
		if f.length() > 0.01:
			basis = Basis.looking_at(f.normalized(), Vector3.UP)
	listener.global_transform = Transform3D(basis, at)
	var dt := get_process_delta_time()
	if _ear_last != Vector3.INF and dt > 0.0:
		_ear_v = _ear_v.lerp((at - _ear_last) / dt, 0.3)
	_ear_last = at
	if not listener.is_current():
		listener.make_current()


func _background(delta: float) -> void:
	var inside := Sfx.zone_at(get_tree(), listener.global_position) != null
	_indoor_k = move_toward(_indoor_k, 1.0 if inside else 0.0, delta * 1.5)
	var i := AudioServer.get_bus_index(Sfx.BUS_AMBIENCE_OUT)
	if i >= 0:
		var lp := AudioServer.get_bus_effect(i, 0) as AudioEffectLowPassFilter
		if lp:
			lp.cutoff_hz = lerpf(20000.0, 700.0, _indoor_k)
		AudioServer.set_bus_volume_db(i, lerpf(0.0, -9.0, _indoor_k))
	if _amb.has("room"):
		(_amb.room as AudioStreamPlayer).volume_db = lerpf(-60.0, -20.0, _indoor_k)
	if city:
		var here := _district_here()
		for k in DISTRICT_BEDS:
			_bed[k] = move_toward(_bed.get(k, 0.0), 1.0 if here == k else 0.0, delta * 0.25)
			var w: float = _bed[k]
			(_amb[k] as AudioStreamPlayer).volume_db = DISTRICT_BEDS[k][1] + linear_to_db(maxf(w, 0.0001))
		var want: float = STREET_DB.get(here, -11.0)
		var wx := CityWeather.current
		var rn: float = wx.rain if wx else 0.0
		(_amb.rain as AudioStreamPlayer).volume_db = -4.0 + linear_to_db(maxf(rn, 0.0001))
		want -= rn * 5.0   # the rain drowns the street out a bit
		var st := _amb.street as AudioStreamPlayer
		st.volume_db = move_toward(st.volume_db, want, delta * 3.0)


func _district_here() -> String:
	var p := listener.global_position
	var c := CityGenerator.block_at(p)
	if c.x < 0:
		return "docks" if p.z > CityGenerator.extent_z() - 20.0 else "outskirts"
	var b: Dictionary = city.blocks[city.block_index(c.x, c.y)]
	if b.style == "park":
		return "park"
	return b.district


## A close shot: the background and engines drop away for a moment.
func duck(amount: float) -> void:
	_duck = maxf(_duck, clampf(amount, 0.0, 1.0))


## Ears ringing after a very close shot or blast (0..1).
func ear_ring(amount: float) -> void:
	if amount <= _ring * 0.6:
		return
	_ring = clampf(maxf(_ring, amount), 0.0, 1.0)
	var p := AudioStreamPlayer.new()
	p.stream = Sfx.stream("ear_ring", 1)
	p.bus = "Master"
	p.volume_db = lerpf(-22.0, -9.0, amount)
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func _mix(delta: float) -> void:
	_duck = move_toward(_duck, 0.0, delta * 2.5)
	for bus in [Sfx.BUS_AMBIENCE, Sfx.BUS_VEHICLES]:
		var i := AudioServer.get_bus_index(bus)
		if i >= 0:
			var amp := AudioServer.get_bus_effect(i, 0) as AudioEffectAmplify
			if amp:
				amp.volume_db = -14.0 * _duck
	_ring = move_toward(_ring, 0.0, delta * 0.45)
	_set_ring_filter(_ring > 0.01, lerpf(20000.0, 700.0, clampf(_ring * 1.2, 0.0, 1.0)))


func _set_ring_filter(on: bool, cutoff: float) -> void:
	if _ring_fx < 0 or _ring_fx >= AudioServer.get_bus_effect_count(0):
		return
	var lp := AudioServer.get_bus_effect(0, _ring_fx) as AudioEffectLowPassFilter
	if lp == null:
		return
	lp.cutoff_hz = cutoff
	AudioServer.set_bus_effect_enabled(0, _ring_fx, on)


# --- people --------------------------------------------------------------------------

## What is underfoot at p: concrete, wood, metal or dirt.
func surface_under(p: Vector3) -> String:
	var space := get_viewport().world_3d.direct_space_state
	var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3(0, 0.4, 0), p - Vector3(0, 0.8, 0), 1 | 4))
	if h.is_empty():
		return "concrete"
	if h.collider is Car:
		return "metal"
	var s := Sfx.surface_of(h.collider)
	if s == "glass":
		return "concrete"
	# Upstairs floors inside buildings are boards.
	if s == "concrete" and p.y > BlockGenerator.BASE_Y + 1.5 and Sfx.zone_at(get_tree(), p + Vector3(0, 0.5, 0)) != null:
		return "wood"
	return s


func _footsteps(n: Node3D, delta: float) -> void:
	if n == null or not n.visible:
		return
	var id := n.get_instance_id()
	var w: Dictionary = _walkers.get(id, {})
	var p := n.global_position
	if w.is_empty():
		_walkers[id] = {"last": p, "acc": 0.0, "n": 0}
		return
	var step := Vector2(p.x - w.last.x, p.z - w.last.z).length()
	w.last = p
	var walking := true
	var crouched := false
	if n is Officer:
		var o := n as Officer
		walking = o.state in [Officer.S.MOVE, Officer.S.CROUCH, Officer.S.COVER]
		crouched = o.state != Officer.S.MOVE
	elif n is Suspect:
		var s := n as Suspect
		walking = s.state not in [Suspect.S.IN_CAR, Suspect.S.DOWN, Suspect.S.DRIVE, Suspect.S.BOOKED, Suspect.S.SURRENDER]
		crouched = s.state in [Suspect.S.HIDE, Suspect.S.STAGGER]
	if not walking or step > 2.0 or delta <= 0.0:
		w.acc = 0.0
		return
	var speed := step / delta
	if speed < 0.4:
		w.acc = minf(w.acc, 0.3)
		return
	w.acc += step
	# One step per foot plant: about 0.75 m at a walk, 1.1 m at a run and
	# 1.55 m flat out (the old 0.6 + 0.12 v stepped far too often running).
	var stride := 0.45 + speed * 0.22
	if w.acc < stride:
		return
	w.acc = 0.0
	w.n += 1
	var surf := surface_under(p)
	var stem := "step_" + (surf if surf in ["wood", "dirt", "concrete", "metal"] else "concrete")
	var db := lerpf(STEP_WALK_DB, STEP_RUN_DB, clampf((speed - 1.5) / 3.5, 0.0, 1.0)) - (6.0 if crouched else 0.0)
	var sp := Sfx.play(n.get_parent(), stem, p + Vector3(0, 0.05, 0), db, 22.0, 0.06)
	if sp:
		sp.pitch_scale *= 1.0 + (0.06 if w.n % 2 == 0 else -0.03)
	if n is Officer and speed > 3.5 and w.n % 2 == 0:
		Sfx.play(n.get_parent(), "gear", p + Vector3(0, 1.0, 0), -20.0, 16.0, 0.08)


func _officer_foley(o: Officer, _delta: float) -> void:
	if o == null:
		return
	var id := o.get_instance_id()
	# (gun and gun_ammo: a picked-up enemy gun, Phase 1.5; absent before it.)
	var ga: Variant = o.get("gun_ammo")
	var gk: Variant = o.get("gun")
	var rounds: int = o.ammo + (int(ga) if ga != null else 0)
	var gun: int = int(gk) if gk != null else 0
	var fire := (o.buttons & PlayerInput.FIRE) != 0
	var st: Dictionary = _officers.get(id, {})
	if st.is_empty():
		_officers[id] = {"rounds": rounds, "gun": gun, "reload": o.reload_t, "holster": o.holster_t,
			"punch": o.punch_t, "state": o.state, "fire": fire, "hp": o.hp}
		return
	var parent := o.get_parent()
	var own := o == _pawn()
	# Phase 1.5: getting hurt jolts your camera.
	if own and o.hp < float(st.get("hp", o.hp)) - 0.5:
		Feel.shake(get_tree(), clampf((float(st.hp) - o.hp) / 40.0, 0.2, 0.7))
	st.hp = o.hp
	# A shot: fewer rounds in the same gun, and not reloading.
	if gun == st.gun and rounds < st.rounds and o.reload_t <= 0.0:
		var muzzle := o.muzzle_position()
		var kt: Variant = o.get("kit")
		var weight: float = float(Armoury.pistol_of(int(kt)).weight) if gun == 0 and kt != null else 1.0
		Sfx.shot(parent, muzzle, maxi(gun, 0), own, weight)
		eject_casing(o, Vector3.INF, Vector3.ZERO, gun == Sfx.SHOTGUN)
		Feel.muzzle(parent, muzzle, gun == Sfx.SHOTGUN)
		if own:
			Feel.shake(get_tree(), 0.22 if gun == Sfx.SHOTGUN else 0.07)
	# Dry: the trigger pulled on an empty gun.
	if fire and not st.fire and rounds == 0 and o.gun_up() and o.reload_t <= 0.0:
		Sfx.play(parent, "dry_fire", o.muzzle_position(), -8.0, 12.0, 0.05)
	# Reload: mag out, it hits the floor, mag in, slide (only from empty).
	if o.reload_t > 0.0 and st.reload <= 0.0:
		var empty: bool = st.rounds == 0
		var p := o.global_position
		var oid := o.get_instance_id()
		Sfx.play(parent, "mag_out", p + Vector3(0, 1.1, 0), -6.0, 14.0, 0.04)
		later(0.35, "mag_drop", p, -4.0, 16.0, 0.08, "", 1.0, oid)
		later(o.reload_t * 0.6, "mag_in", p, -5.0, 14.0, 0.04, "", 1.0, oid)
		if empty:
			later(o.reload_t * 0.88, "slide_rack", p, -5.0, 14.0, 0.04, "", 1.0, oid)
	if o.holster_t > 0.0 and st.holster <= 0.0:
		Sfx.play(parent, "holster", o.global_position + Vector3(0, 1.0, 0), -12.0, 10.0, 0.06)
	if o.punch_t > 0.3 and st.punch <= 0.0:
		Sfx.play(parent, "whoosh", o.global_position + Vector3(0, 1.3, 0), -8.0, 14.0, 0.1)
	if o.state != st.state:
		if o.state == Officer.S.KICK:
			Sfx.play(parent, "whoosh", o.global_position + Vector3(0, 0.8, 0), -6.0, 14.0, 0.1)
		elif o.state == Officer.S.COVER or st.state == Officer.S.COVER:
			Sfx.play(parent, "cloth", o.global_position + Vector3(0, 1.0, 0), -12.0, 10.0, 0.08)
		elif o.state in [Officer.S.ROLL, Officer.S.SLIDE, Officer.S.PRONE]:
			Sfx.play(parent, "cloth", o.global_position + Vector3(0, 0.5, 0), -9.0, 12.0, 0.08)
		if o.state == Officer.S.VEHICLE or st.state == Officer.S.VEHICLE:
			var p2 := o.global_position + Vector3(0, 1.0, 0)
			Sfx.play(parent, "car_door_open", p2, -6.0, 25.0, 0.05)
			later(0.55, "car_door_close", p2, -3.0, 30.0, 0.05)
		if st.state == Officer.S.AIR and o.state in [Officer.S.MOVE, Officer.S.CROUCH]:
			Sfx.play(parent, "step_" + _step_surface(surface_under(o.global_position)), o.global_position, -6.0, 20.0, 0.06)
	st.rounds = rounds
	st.gun = gun
	st.reload = o.reload_t
	st.holster = o.holster_t
	st.punch = o.punch_t
	st.state = o.state
	st.fire = fire


func _drop_surface(s: String) -> String:
	return s if s in ["wood", "metal"] else "concrete"


func _step_surface(s: String) -> String:
	return s if s in ["wood", "dirt", "metal"] else "concrete"


# --- brass ---------------------------------------------------------------------------

## A spent case flies out of the right of the gun and bounces where it lands.
func eject_casing(o: Node3D, at := Vector3.INF, right := Vector3.ZERO, shell := false) -> void:
	if DisplayServer.get_name() == "headless" and not has_meta("casings_in_headless"):
		return
	var pos := at
	var side := right
	if pos == Vector3.INF and o is Officer:
		pos = (o as Officer).muzzle_position()
		var yaw: float = (o as Officer).aim_yaw
		side = Vector3(cos(yaw), 0, -sin(yaw))
		pos += -Vector3(sin(yaw), 0, cos(yaw)) * 0.12
	if side == Vector3.ZERO:
		side = Vector3.RIGHT
	var rb := RigidBody3D.new()
	rb.mass = 0.012
	rb.collision_layer = 0
	rb.collision_mask = 1 | 4
	rb.continuous_cd = true
	rb.contact_monitor = true
	rb.max_contacts_reported = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.02, 0.02, 0.03)
	cs.shape = box
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0055
	cyl.bottom_radius = 0.0055
	cyl.height = 0.02
	cyl.radial_segments = 6
	cyl.rings = 1
	mi.mesh = cyl
	mi.rotation.x = PI * 0.5
	if shell:   # a red plastic shotgun shell
		cyl.top_radius = 0.0105
		cyl.bottom_radius = 0.0105
		cyl.height = 0.065
	mi.material_override = Cel.material(Color("a32020") if shell else Color("c9a040"), false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rb.add_child(mi)
	var parent := o.get_parent() if o else get_parent()
	parent.add_child(rb)
	rb.global_position = pos
	rb.linear_velocity = side * randf_range(2.2, 3.2) + Vector3.UP * randf_range(1.5, 2.6)
	rb.angular_velocity = Vector3(randf_range(-30, 30), randf_range(-30, 30), randf_range(-30, 30))
	rb.body_entered.connect(func(_b):
		if rb.has_meta("rang"):
			return
		rb.set_meta("rang", true)
		var surf := surface_under(rb.global_position)
		if shell:
			Sfx.play(rb.get_parent(), "shell_shotgun", rb.global_position, -8.0, 14.0, 0.08)
		else:
			Sfx.play(rb.get_parent(), "casing_" + _drop_surface(surf), rb.global_position, -10.0, 12.0, 0.08))
	_casings.append([rb, _clock])


func _tidy_casings() -> void:
	while _casings.size() > MAX_CASINGS or (not _casings.is_empty() and _clock - _casings[0][1] > 20.0):
		var c: Array = _casings.pop_front()
		if is_instance_valid(c[0]):
			(c[0] as Node).queue_free()
	for c in _casings:
		var rb := c[0] as RigidBody3D
		if is_instance_valid(rb) and rb.sleeping and not rb.freeze:
			rb.freeze = true   # resting brass stops costing physics


# --- cars ----------------------------------------------------------------------------

func _car(c: Car, delta: float) -> void:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree() or delta <= 0.0:
		return
	var id := c.get_instance_id()
	var a: Dictionary = _car_audio.get(id, {})
	var p := c.global_position
	if a.is_empty():
		var eng := AudioStreamPlayer3D.new()
		# v0.13.1: police cars have a real V8 (beenster: "beefy V8 sound").
		var v8 := c is PoliceCar
		eng.stream = Sfx.loop_stream("v8_drive" if v8 else "car_engine")
		eng.bus = Sfx.BUS_VEHICLES
		eng.unit_size = 5.0
		eng.max_distance = 110.0 if _engine_tone(c).y > 3.0 else 70.0
		eng.volume_db = -80.0
		c.add_child(eng)
		var skid := AudioStreamPlayer3D.new()
		skid.stream = Sfx.loop_stream("tyre_skid")
		skid.bus = Sfx.BUS_VEHICLES
		skid.unit_size = 6.0
		skid.max_distance = 80.0
		skid.volume_db = -80.0
		c.add_child(skid)
		# v0.13.0: the engine ticking over, under the engine note at a standstill.
		var idle := AudioStreamPlayer3D.new()
		idle.stream = Sfx.loop_stream("v8_idle" if v8 else "car_idle")
		idle.bus = Sfx.BUS_VEHICLES
		idle.unit_size = 4.0
		idle.max_distance = 45.0
		idle.volume_db = -80.0
		c.add_child(idle)
		_car_audio[id] = {"engine": eng, "skid": skid, "idle": idle, "last": p, "v": Vector3.ZERO, "on": false, "load": 0.0, "squeal": 0.0, "v8": v8}
		return
	var v := (p - (a.last as Vector3)) / delta
	var dv := (v - (a.v as Vector3)).length()
	var back: bool = a.get("away", false)
	if back:
		a.away = false
		dv = 0.0
	a.last = p
	var prev_v: Vector3 = v if back else a.v
	a.v = v
	var speed := Vector2(v.x, v.z).length()
	var eng := a.engine as AudioStreamPlayer3D
	var skid := a.skid as AudioStreamPlayer3D
	var driven := _driven(c) or speed > 0.8
	if driven and not a.on:
		a.on = true
		Sfx.play(c.get_parent(), "car_start", p, -6.0, 40.0, 0.03)
		eng.play()
		skid.play()
		(a.idle as AudioStreamPlayer3D).play(randf() * 1.5)
	elif not driven and a.on and speed < 0.2:
		a.on = false
		eng.stop()
		skid.stop()
		(a.idle as AudioStreamPlayer3D).stop()
	if a.on:
		var accel := (Vector2(v.x, v.z).length() - Vector2(prev_v.x, prev_v.z).length()) / delta
		a.load = lerpf(a.load, clampf(accel / 6.0 + absf(c.throttle), 0.0, 1.0), 1.0 - exp(-6.0 * delta))
		var k := clampf(speed / c.top_speed, 0.0, 1.0)
		# Up through three "gears": the pitch climbs and drops back.
		var gear_k := fmod(k * 3.0, 1.0) if k < 0.99 else 1.0
		var tone := _engine_tone(c)
		var dop := _doppler(p, v)
		if a.v8:
			# The V8 loop is held at about 1,250 rpm: from there up to about
			# 3,500 through the gears, and it digs in harder under load.
			eng.pitch_scale = (0.85 + k * 0.75 + gear_k * 0.75 + a.load * 0.15) * dop
		else:
			eng.pitch_scale = (0.75 + k * 0.5 + gear_k * 0.45 + a.load * 0.08) * tone.x * dop
		# At a standstill the engine ticks over; the note takes over as it pulls away.
		var still: float = clampf(1.0 - speed / 4.0, 0.0, 1.0) * (1.0 - float(a.load))
		eng.volume_db = -14.0 + a.load * (9.0 if a.v8 else 6.0) + k * 4.0 + tone.y - still * 7.0 + (3.0 if a.v8 else 0.0)
		var idle := a.idle as AudioStreamPlayer3D
		idle.volume_db = -9.0 + tone.y + linear_to_db(maxf(still, 0.02)) + (2.0 if a.v8 else 0.0)
		idle.pitch_scale = tone.x * (1.0 + a.load * (0.35 if a.v8 else 0.15))
		var right := c.global_transform.basis.x
		var slip := absf(v.dot(right))
		var on_ground := p.y < 3.0
		var squeal := clampf((slip - 3.0) / 6.0, 0.0, 1.0) if on_ground and speed > 4.0 else 0.0
		if c.handbrake and speed > 5.0:
			squeal = maxf(squeal, 0.7)
		# v0.20.0: rear wheelspin screams too.
		squeal = maxf(squeal, clampf(c.spin_k * 1.3, 0.0, 1.0))
		skid.volume_db = lerpf(-60.0, -6.0, squeal) if squeal > 0.02 else -80.0
		# v0.13.0: the tyres bite with a squeal as a skid starts.
		if squeal > 0.45 and float(a.squeal) <= 0.45:
			Sfx.play(c.get_parent(), "tyre_chirp", p, -2.0 + squeal * 4.0, 70.0, 0.06, Sfx.BUS_VEHICLES)
		a.squeal = squeal
		skid.pitch_scale = 0.9 + squeal * 0.2
	# Wave 2: sirens rise as they come at you and fall away as they pass.
	if c is PoliceCar and (c as PoliceCar)._siren_player and (c as PoliceCar)._siren_player.playing:
		(c as PoliceCar)._siren_player.pitch_scale = _doppler(p, v)
	# A hard knock: metal crunching, louder the harder.
	if dv > 6.0 and speed + prev_v.length() > 4.0:
		var db := clampf(-10.0 + (dv - 6.0) * 1.2, -10.0, 6.0)
		Sfx.play(c.get_parent(), "car_crash", p + Vector3(0, 0.6, 0), db, 70.0, 0.08)
		duck(clampf(dv / 30.0, 0.0, 0.6))


func _driven(c: Car) -> bool:
	if c is PoliceCar:
		var occ: Dictionary = (c as PoliceCar).occupants()
		if occ.has(0):
			return true
		# Wave 2: traffic, with someone at the wheel (stopped at the lights too).
		var d := c.get_node_or_null("Driver") as Node3D
		return d != null and d.visible
	return absf(c.throttle) > 0.01


## Engine pitch (x) and loudness (y, dB) by vehicle: lorries low and loud,
## bikes high and buzzy.
static func _engine_tone(c: Car) -> Vector2:
	if c is CivilianVehicle:
		match (c as CivilianVehicle).kind:
			"hgv_tractor", "trash_truck": return Vector2(0.52, 5.0)
			"van_box", "minibus": return Vector2(0.7, 2.0)
			"van_panel": return Vector2(0.85, 1.0)
			"hatchback": return Vector2(1.08, -1.0)
			"motorbike": return Vector2(1.5, 2.0)
	return Vector2(1.0, 0.0)


## The Doppler shift for a sound at p moving at v, heard by our ears
## (exaggerated a touch so a passing siren really drops).
var _ear_last := Vector3.INF
var _ear_v := Vector3.ZERO


func _doppler(p: Vector3, v: Vector3) -> float:
	var ear := listener.global_position
	var u := ear - p
	var d := u.length()
	if d < 0.5:
		return 1.0
	u /= d
	var vs := v.dot(u) * 1.25            # source coming toward us
	var vl := -_ear_v.dot(u) * 1.25      # us going toward it
	return clampf((Sfx.SPEED_OF_SOUND + vl) / maxf(Sfx.SPEED_OF_SOUND - vs, 100.0), 0.7, 1.4)


# --- destruction ----------------------------------------------------------------------

func _on_piece_broken(id: int) -> void:
	if world == null or not world.pieces.has(id):
		return
	var p: Dictionary = world.pieces[id]
	var kind: String = p.kind
	var at: Vector3 = (p.aabb as AABB).get_center()
	var parent := world.get_parent()
	if kind.begins_with("glass"):
		var big := kind in ["glass_shopfront", "glass_shopdoor"]
		Sfx.play(parent, "glass_big" if big else "glass_break", at, 6.0 if big else 3.0, 80.0, 0.06)
		later(randf_range(0.35, 0.6), "glass_settle", at - Vector3(0, 0.8, 0), -6.0, 30.0, 0.1)
	elif kind in ["door_closed", "garage_door"] or kind.begins_with("int_wall_door"):
		Sfx.play(parent, "break_wood", at, 5.0, 70.0, 0.08)
	elif kind in ["lamp_post", "bollard"]:
		Sfx.play(parent, "break_metal", at, 4.0, 80.0, 0.08)
	elif kind in ["pavement", "road", "road_line", "road_crossing"]:
		Sfx.play(parent, "break_concrete", at, 3.0, 80.0, 0.08)
	else:
		var size := (p.aabb as AABB).size.length()
		_collapse_check(parent, at, size)
		Sfx.play(parent, "break_concrete", at, clampf(1.0 + size, 1.0, 8.0), 110.0, 0.08)
		Sfx.play(parent, "gun_thump", at, clampf(-6.0 + size, -6.0, 3.0), 60.0, 0.2)
		later(0.3, "rubble", at, clampf(-8.0 + size, -8.0, 2.0), 70.0, 0.1)


## v0.13.0: when a lot of a building gives way at once (six or more big
## pieces within 12 m in two seconds), the long rumble of it coming down.
func _collapse_check(parent: Node, at: Vector3, size: float) -> void:
	if size < 1.5:
		return
	_breaks.append([at, _clock])
	while not _breaks.is_empty() and _clock - float(_breaks[0][1]) > 2.0:
		_breaks.pop_front()
	var n := 0
	for b in _breaks:
		if (b[0] as Vector3).distance_to(at) < 12.0:
			n += 1
	if n >= 6 and _clock - _last_collapse > 9.0:
		_last_collapse = _clock
		Sfx.play(parent, "collapse", at, 6.0, 260.0, 0.04, Sfx.space_bus(parent, at))
		duck(0.6)


func _on_world_fx(kind: int, at: Vector3, _n: Vector3) -> void:
	if kind == 0:
		Sfx.explosion(world.get_parent(), at)


## Loose chunks and objects landing hard play their material's impact.
const HEAR_IMPACTS := 75.0
var _near: Array = []
var _near_t := 0.0


## Where we listen from: our officer, or the camera.
func _ear() -> Vector3:
	var o: Node3D = pawn_getter.call() if pawn_getter.is_valid() else null
	if o:
		return o.global_position
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam else Vector3.ZERO


func _physics_impacts(delta: float) -> void:
	if world == null or delta <= 0.0:
		return
	var seen := {}
	# Wave 2: a city has thousands of loose things. Twice a second, list the
	# ones within earshot; each frame only those that are awake are checked.
	_near_t -= delta
	if _near_t <= 0.0:
		_near_t = 0.5
		_near.clear()
		var ear := _ear()
		var all: Array = world.bodies.values()
		for d in world._debris:
			all.append(d[0])
		all.append_array(get_tree().get_nodes_in_group("props"))
		for b in all:
			if not is_instance_valid(b):
				continue
			var n := b as Node3D
			if n and n.is_inside_tree() and n.global_position.distance_squared_to(ear) < HEAR_IMPACTS * HEAR_IMPACTS:
				_near.append(n)
	for b in _near:
		if not is_instance_valid(b):
			continue
		var rb := b as Node3D
		if rb == null or not rb.is_inside_tree():
			continue
		if rb is RigidBody3D and (rb as RigidBody3D).sleeping:
			continue
		var id := rb.get_instance_id()
		seen[id] = true
		var p := rb.global_position
		var prev: Array = _bodies.get(id, [])
		if prev.is_empty():
			_bodies[id] = [p, 0.0]
			continue
		var v := (p - (prev[0] as Vector3)) / delta
		var sp := v.length()
		var last_sp: float = prev[1]
		_bodies[id] = [p, sp]
		var drop := last_sp - sp
		if last_sp > 2.5 and drop > 2.0:
			_impact_sound(rb, p, drop)
	if _bodies.size() > seen.size() + 256:
		for id in _bodies.keys():
			if not seen.has(id):
				_bodies.erase(id)


func _impact_sound(rb: Node3D, p: Vector3, hardness: float) -> void:
	if _budget < 1.0:
		return
	for r in _recent:
		if (r[0] as Vector3).distance_to(p) < 1.5 and _clock - float(r[1]) < 0.25:
			return
	_budget -= 1.0
	_recent.append([p, _clock])
	if _recent.size() > 16:
		_recent.pop_front()
	var surf := Sfx.surface_of(rb)
	var mass := (rb as RigidBody3D).mass if rb is RigidBody3D else 20.0
	var heavy := mass > 60.0
	var db := clampf(-16.0 + hardness * 1.4 + (4.0 if heavy else 0.0), -18.0, 4.0)
	if heavy and surf == "concrete":
		Sfx.play(rb.get_parent(), "rubble", p, db - 2.0, 60.0, 0.12)
	else:
		Sfx.impact(rb.get_parent(), p, surf, clampf(hardness / 10.0, 0.1, 1.2))
