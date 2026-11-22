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

const STEP_WALK_DB := -15.0
const STEP_RUN_DB := -8.0
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
	listener = AudioListener3D.new()
	listener.name = "Ears"
	listener.add_to_group(Sfx.LISTENER_GROUP)
	add_child(listener)
	listener.make_current()
	_amb_player("street", "amb_street", Sfx.BUS_AMBIENCE_OUT, -11.0)
	_amb_player("air", "amb_air", Sfx.BUS_AMBIENCE_OUT, -18.0)
	_amb_player("far", "amb_far_traffic", Sfx.BUS_AMBIENCE_OUT, -16.0)
	_amb_player("room", "room_tone", Sfx.BUS_AMBIENCE, -60.0)
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


## Indoors for the ears and the reverb: one zone per building.
func add_building_zones(gen: BlockGenerator) -> void:
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
func _physics_process(delta: float) -> void:
	_clock += delta
	_budget = minf(IMPACT_BUDGET, _budget + IMPACT_BUDGET * delta)
	for n in get_tree().get_nodes_in_group("officers") + get_tree().get_nodes_in_group("suspects"):
		_footsteps(n as Node3D, delta)
	if cars:
		for c in cars.cars:
			_car(c as Car, delta)
	_physics_impacts(delta)


## Plays a sound a little later (echoes, shards settling, reload steps).
## reload_of: an officer's instance id; skipped if they stopped reloading.
func later(t: float, stem: String, pos: Vector3, db := 0.0, dist := 60.0, spread := 0.05, bus := "", pitch := 1.0, reload_of := 0) -> void:
	_pending.append([_clock + t, {"stem": stem, "pos": pos, "db": db, "dist": dist, "spread": spread, "bus": bus,
		"pitch": pitch, "reload_of": reload_of}])


func _play_pending() -> void:
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
	var stride := 0.6 + speed * 0.12
	if w.acc < stride:
		return
	w.acc = 0.0
	w.n += 1
	var surf := surface_under(p)
	var stem := "step_" + (surf if surf in ["wood", "dirt", "concrete"] else "concrete")
	var db := lerpf(STEP_WALK_DB, STEP_RUN_DB, clampf((speed - 1.5) / 3.5, 0.0, 1.0)) - (6.0 if crouched else 0.0)
	var sp := Sfx.play(n.get_parent(), stem, p + Vector3(0, 0.05, 0), db, 28.0, 0.08)
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
		Sfx.shot(parent, muzzle, maxi(gun, 0), own)
		eject_casing(o)
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
		later(Officer.RELOAD_TIME * 0.6, "mag_in", p, -5.0, 14.0, 0.04, "", 1.0, oid)
		if empty:
			later(Officer.RELOAD_TIME * 0.88, "slide_rack", p, -5.0, 14.0, 0.04, "", 1.0, oid)
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
	return s if s in ["wood", "dirt"] else "concrete"


# --- brass ---------------------------------------------------------------------------

## A spent case flies out of the right of the gun and bounces where it lands.
func eject_casing(o: Node3D, at := Vector3.INF, right := Vector3.ZERO) -> void:
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
	mi.material_override = Cel.material(Color("c9a040"), false)
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
		eng.stream = Sfx.loop_stream("car_engine")
		eng.bus = Sfx.BUS_VEHICLES
		eng.unit_size = 5.0
		eng.max_distance = 70.0
		eng.volume_db = -80.0
		c.add_child(eng)
		var skid := AudioStreamPlayer3D.new()
		skid.stream = Sfx.loop_stream("tyre_skid")
		skid.bus = Sfx.BUS_VEHICLES
		skid.unit_size = 6.0
		skid.max_distance = 80.0
		skid.volume_db = -80.0
		c.add_child(skid)
		_car_audio[id] = {"engine": eng, "skid": skid, "last": p, "v": Vector3.ZERO, "on": false, "load": 0.0}
		return
	var v := (p - (a.last as Vector3)) / delta
	var dv := (v - (a.v as Vector3)).length()
	a.last = p
	var prev_v: Vector3 = a.v
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
	elif not driven and a.on and speed < 0.2:
		a.on = false
		eng.stop()
		skid.stop()
	if a.on:
		var accel := (Vector2(v.x, v.z).length() - Vector2(prev_v.x, prev_v.z).length()) / delta
		a.load = lerpf(a.load, clampf(accel / 6.0 + absf(c.throttle), 0.0, 1.0), 1.0 - exp(-6.0 * delta))
		var k := clampf(speed / Car.TOP_SPEED, 0.0, 1.0)
		# Up through three "gears": the pitch climbs and drops back.
		var gear_k := fmod(k * 3.0, 1.0) if k < 0.99 else 1.0
		eng.pitch_scale = 0.75 + k * 0.5 + gear_k * 0.45 + a.load * 0.08
		eng.volume_db = -14.0 + a.load * 6.0 + k * 4.0
		var right := c.global_transform.basis.x
		var slip := absf(v.dot(right))
		var on_ground := p.y < 3.0
		var squeal := clampf((slip - 3.0) / 6.0, 0.0, 1.0) if on_ground and speed > 4.0 else 0.0
		if c.handbrake and speed > 5.0:
			squeal = maxf(squeal, 0.7)
		skid.volume_db = lerpf(-60.0, -6.0, squeal) if squeal > 0.02 else -80.0
		skid.pitch_scale = 0.9 + squeal * 0.2
	# A hard knock: metal crunching, louder the harder.
	if dv > 6.0 and speed + prev_v.length() > 4.0:
		var db := clampf(-10.0 + (dv - 6.0) * 1.2, -10.0, 6.0)
		Sfx.play(c.get_parent(), "car_crash", p + Vector3(0, 0.6, 0), db, 70.0, 0.08)
		duck(clampf(dv / 30.0, 0.0, 0.6))


func _driven(c: Car) -> bool:
	if c is PoliceCar:
		var occ: Dictionary = (c as PoliceCar).occupants()
		return occ.has(0)
	return absf(c.throttle) > 0.01


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
		Sfx.play(parent, "glass_big" if big else "glass_break", at, 3.0 if big else 0.0, 70.0, 0.06)
		later(randf_range(0.35, 0.6), "glass_settle", at - Vector3(0, 0.8, 0), -6.0, 30.0, 0.1)
	elif kind in ["door_closed", "garage_door"] or kind.begins_with("int_wall_door"):
		Sfx.play(parent, "break_wood", at, 2.0, 50.0, 0.08)
	elif kind in ["lamp_post", "bollard"]:
		Sfx.play(parent, "break_metal", at, 0.0, 60.0, 0.08)
	elif kind in ["pavement", "road", "road_line", "road_crossing"]:
		Sfx.play(parent, "break_concrete", at, -2.0, 60.0, 0.08)
	else:
		var size := (p.aabb as AABB).size.length()
		Sfx.play(parent, "break_concrete", at, clampf(-4.0 + size, -4.0, 4.0), 80.0, 0.08)
		later(0.3, "rubble", at, clampf(-8.0 + size, -8.0, 2.0), 70.0, 0.1)


func _on_world_fx(kind: int, at: Vector3, _n: Vector3) -> void:
	if kind == 0:
		Sfx.explosion(world.get_parent(), at)


## Loose chunks and objects landing hard play their material's impact.
func _physics_impacts(delta: float) -> void:
	if world == null or delta <= 0.0:
		return
	var seen := {}
	var list: Array = world.bodies.values()
	for d in world._debris:
		list.append(d[0])
	for n in get_tree().get_nodes_in_group("props"):
		list.append(n)
	for b in list:
		var rb := b as Node3D
		if rb == null or not is_instance_valid(rb) or not rb.is_inside_tree():
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
	if _bodies.size() > seen.size() + 64:
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
