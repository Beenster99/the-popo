class_name Sfx
extends RefCounted
## Sound for The Popo: buses, layered gunshots, impacts by surface,
## indoor/outdoor reverb by zone and muffling through walls.
##
## Buses (made once by ensure_buses):
##   SFX      dry 3D sound, feeds Master
##   Outdoor  outdoor gunshots: the recordings already carry their natural
##            outdoor tail, so this only adds one faint slapback off the
##            buildings and a little air. Feeds SFX.
##   Indoor   anything fired or hit inside a SoundZone: a tight room reverb.
##            Feeds SFX.
##   <bus>_Muffled1 / _Muffled2: copies of each bus behind a low-pass filter,
##            used when one wall, or two or more, stand between the sound and
##            the listener. Each feeds its own bus, so muffled sounds keep
##            their room.
##   Ambience  the city and room background (Phase 1.6); AmbienceOut, the
##            street, feeds it through a low-pass that closes when you go
##            indoors. Vehicles: engines and tyres. Both duck for a moment
##            under a close gunshot so the shot dominates.
##   Master carries a low-pass that is switched on for the ear ring after a
##            very close shot or blast.
## Sounds are CC0 recordings imported by tools/audio/import_cc0.py and
## import_phase16.py, plus the project's own layers from make_layers.py
## (all listed in assets/audio/manifest.csv).

const BUS_SFX := "SFX"
const BUS_INDOOR := "Indoor"
const BUS_OUTDOOR := "Outdoor"
const SFX_DIR := "res://assets/audio/sfx/"
const OCCLUDE_MASK := 1 | 16  # world and chunks
const MAX_WALLS := 3
const SURFACES := ["wood", "glass", "concrete", "metal"]
const MUFFLE_CUTOFF := [1200.0, 500.0]
const NEAR_RANGE := 30.0     # beyond this the distant recording is used
const COUNTS := {"amb_air": 1, "amb_far_traffic": 1, "amb_street": 1, "body_hit": 6, "bone_snap": 4, "break_concrete": 4,
	"break_metal": 5, "break_wood": 7, "bullet_crack": 3, "bullet_whizz": 3, "car_crash": 3,
	"car_door_close": 1, "car_door_open": 1, "car_engine": 1, "car_horn": 1, "car_start": 1,
	"casing_concrete": 3, "casing_metal": 3, "casing_wood": 3, "cloth": 4, "door_close": 4, "door_open": 2,
	"dry_fire": 1, "ear_ring": 1, "explosion": 1, "explosion_body": 2, "fire_loop": 1, "fire_whoomph": 2, "gas_hiss": 1, "gear": 4, "glass_big": 3, "glass_break": 3,
	"glass_settle": 4, "gore_hit": 5, "gun_dry": 5, "gun_far": 4, "gun_mech": 1, "gun_near": 5, "gun_sub": 3, "gun_crack_near": 3, "gun_tail_city": 3, "amb_docks": 1, "amb_industrial": 1, "amb_park": 1, "amb_rain": 1, "thunder": 3, "gun_shotgun_body": 3,
	"gun_thump": 3, "holster": 2, "impact_concrete": 4, "impact_glass": 3, "impact_metal": 5, "impact_wood": 4,
	"mag_drop_concrete": 2, "mag_drop_metal": 2, "mag_drop_wood": 2, "mag_in": 1, "mag_out": 1, "ping": 1,
	"punch": 5, "ricochet": 4, "room_tone": 1, "rubble": 6, "shotgun_pump": 1, "siren_wail": 1, "siren_yelp": 1,
	"slide_rack": 1, "step_concrete": 6, "step_dirt": 6, "step_wood": 4, "tyre_skid": 1, "whoosh": 3}
const BUS_AMBIENCE := "Ambience"
const BUS_AMBIENCE_OUT := "AmbienceOut"
const BUS_VEHICLES := "Vehicles"
const FAR_RANGE := 90.0      # beyond this a shot is a distant pop through the air
const SPEED_OF_SOUND := 343.0
## Gun kinds (as EnemyGuns: 0 and 1 are handguns, 2 a shotgun).
const SHOTGUN := 2

static var _cache := {}
static var _rng := RandomNumberGenerator.new()
## The most recent sounds played, newest last, for tests and the debug HUD.
static var history: Array = []


static func ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) != -1:
		return
	_add_bus(BUS_SFX, "Master")
	var outdoor := _add_bus(BUS_OUTDOOR, BUS_SFX)
	# Slapback off the buildings is played as real reflections (shot_echoes);
	# this only keeps a faint short echo for open ground.
	var slap := AudioEffectDelay.new()
	slap.dry = 1.0
	slap.tap1_active = true
	slap.tap1_delay_ms = 95.0
	slap.tap1_level_db = -24.0
	slap.tap1_pan = -0.2
	slap.tap2_active = false
	slap.feedback_active = false
	AudioServer.add_bus_effect(outdoor, slap)
	var air := AudioEffectReverb.new()
	air.room_size = 0.7
	air.damping = 0.8
	air.spread = 1.0
	air.dry = 1.0
	air.wet = 0.05
	air.predelay_msec = 30.0
	AudioServer.add_bus_effect(outdoor, air)
	var indoor := _add_bus(BUS_INDOOR, BUS_SFX)
	var room := AudioEffectReverb.new()
	room.room_size = 0.35
	room.damping = 0.4
	room.spread = 0.8
	room.dry = 0.9
	room.wet = 0.35
	room.predelay_msec = 6.0
	AudioServer.add_bus_effect(indoor, room)
	for base in [BUS_SFX, BUS_OUTDOOR, BUS_INDOOR]:
		for level in 2:
			var i := _add_bus(muffled_bus(base, level + 1), base)
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = MUFFLE_CUTOFF[level]
			lp.resonance = 0.5
			AudioServer.add_bus_effect(i, lp)
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_SFX), AudioEffectHardLimiter.new())
	# Background and engines, which duck under close shots.
	var amb := _add_bus(BUS_AMBIENCE, BUS_SFX)
	AudioServer.add_bus_effect(amb, AudioEffectAmplify.new())
	var amb_out := _add_bus(BUS_AMBIENCE_OUT, BUS_AMBIENCE)
	var lp_out := AudioEffectLowPassFilter.new()
	lp_out.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(amb_out, lp_out)
	var veh := _add_bus(BUS_VEHICLES, BUS_SFX)
	AudioServer.add_bus_effect(veh, AudioEffectAmplify.new())
	# The ear ring: a low-pass on everything, off until needed.
	var ring := AudioEffectLowPassFilter.new()
	ring.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(0, ring)
	AudioServer.set_bus_effect_enabled(0, AudioServer.get_bus_effect_count(0) - 1, false)


static func muffled_bus(base: String, walls: int) -> String:
	if walls <= 0:
		return base
	return "%s_Muffled%d" % [base, mini(walls, 2)]


static func _add_bus(bus_name: String, send: String) -> int:
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, send)
	return i


static func stream(stem: String, variant: int) -> AudioStream:
	var path := "%s%s_%d.wav" % [SFX_DIR, stem, variant]
	if not _cache.has(path):
		_cache[path] = load(path)
	return _cache[path]


## A sound that loops forever (ambience, engines, tyres).
static func loop_stream(stem: String) -> AudioStreamWAV:
	var key := "loop:" + stem
	if not _cache.has(key):
		var w := (stream(stem, 1) as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
		_cache[key] = w
	return _cache[key]


static func variants(stem: String) -> int:
	return COUNTS.get(stem, 1)


# --- Zones and occlusion -----------------------------------------------------

## The SoundZone a point is inside, or null outdoors.
static func zone_at(tree: SceneTree, pos: Vector3) -> SoundZone:
	for z in tree.get_nodes_in_group(SoundZone.GROUP):
		if (z as SoundZone).contains(pos):
			return z
	return null


static func bus_at(tree: SceneTree, pos: Vector3) -> String:
	return BUS_INDOOR if zone_at(tree, pos) != null else BUS_OUTDOOR


## Counts the solid things between a sound and the listener, up to MAX_WALLS.
static func walls_between(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID] = []) -> int:
	var ex := exclude.duplicate()
	var walls := 0
	var start := from
	while walls < MAX_WALLS:
		var q := PhysicsRayQueryParameters3D.create(start, to, OCCLUDE_MASK, ex)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		walls += 1
		ex.append(hit.rid)
	return walls


## Low-pass cutoff (Hz) and volume change (dB) for a number of walls.
static func occlusion(walls: int) -> Dictionary:
	match walls:
		0:
			return {"cutoff": 20500.0, "db": 0.0}
		1:
			return {"cutoff": MUFFLE_CUTOFF[0], "db": -6.0}
		2:
			return {"cutoff": MUFFLE_CUTOFF[1], "db": -11.0}
		_:
			return {"cutoff": MUFFLE_CUTOFF[1], "db": -16.0}


static func surface_of(collider: Object) -> String:
	if collider is Node:
		var n := collider as Node
		while n != null:
			if n.has_meta("surface"):
				return n.get_meta("surface")
			n = n.get_parent()
	return "concrete"


# --- Playing -----------------------------------------------------------------

## Plays one positional sound. Returns the player (already playing).
static func play(parent: Node, stem: String, pos: Vector3, db := 0.0, max_dist := 60.0, pitch_spread := 0.05, bus := "") -> AudioStreamPlayer3D:
	ensure_buses()
	var tree := parent.get_tree()
	if bus == "":
		bus = BUS_SFX if zone_at(tree, pos) == null else BUS_INDOOR
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(stem, _rng.randi_range(1, variants(stem)))
	p.bus = bus
	p.volume_db = db
	p.max_distance = max_dist
	p.unit_size = 6.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_spread, pitch_spread)
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	parent.add_child(p)
	p.global_position = pos
	var walls := 0
	var lis: Variant = listener_position(parent)
	if lis != null:
		walls = walls_between(parent.get_viewport().world_3d.direct_space_state, pos, lis)
	var occ := occlusion(walls)
	# Godot's per-player filter scales with distance, so a shot just behind
	# a wall would barely change; route through a muffled bus instead.
	p.attenuation_filter_db = 0.0
	p.bus = muffled_bus(bus, walls)
	p.volume_db += occ.db
	p.finished.connect(p.queue_free)
	p.play()
	history.append({"stem": stem, "pos": pos, "bus": bus, "walls": walls, "cutoff": occ.cutoff, "played_on": p.bus})
	if history.size() > 32:
		history.pop_front()
	return p


## A handgun shot. Outdoors: the near recording with its natural tail, or
## the distant one when the listener is far away. Indoors: the shot with its
## tail cut, through the room reverb.
static func gunshot(parent: Node, pos: Vector3) -> void:
	var indoor := zone_at(parent.get_tree(), pos) != null
	if indoor:
		play(parent, "gun_dry", pos, 0.0, 120.0, 0.04, BUS_INDOOR)
		return
	var lis: Variant = listener_position(parent)
	var far: bool = lis != null and (lis as Vector3).distance_to(pos) > NEAR_RANGE
	play(parent, "gun_far" if far else "gun_near", pos, 0.0, 160.0, 0.04, BUS_OUTDOOR)


## Phase 1.6: a gunshot built from layers, as heard from where you are.
##   crack/body  the recording: close with its tail outdoors, cut dry
##               indoors (through the room reverb, louder: rooms are
##               painfully loud), the distant one past NEAR_RANGE, and past
##               FAR_RANGE a thin pop.
##   thump       the low-end punch, only up close (bigger for a shotgun).
##   mechanics   the slide cycling, only right next to the gun.
##   slapback    outdoors: echoes off the nearest building walls, each from
##               the wall, delayed by the extra distance the sound travels.
## Close shots also duck the background, and a shot (or blast) right by
## your head that is not your own leaves your ears ringing.
## kind: 0/1 handgun, 2 shotgun. own: fired by the player listening.
## weight (Phase 3.5): the officer's pistol: a .357 is deeper and booms more,
## a compact is snappier.
static func shot(parent: Node, pos: Vector3, kind := 0, own := false, weight := 1.0) -> void:
	var tree := parent.get_tree()
	var indoor := zone_at(tree, pos) != null
	var lis: Variant = listener_position(parent)
	var d: float = (lis as Vector3).distance_to(pos) if lis != null else 10.0
	var sg := kind == SHOTGUN
	var pitch := (0.82 if sg else 1.0) / pow(weight, 0.35)
	var boom := (weight - 1.0) * 6.0
	var p: AudioStreamPlayer3D
	if indoor:
		p = play(parent, "gun_dry", pos, 5.0, 140.0, 0.04, BUS_INDOOR)
	elif d > FAR_RANGE:
		p = play(parent, "gun_far", pos, -4.0, 260.0, 0.06, BUS_OUTDOOR)
	elif d > NEAR_RANGE:
		p = play(parent, "gun_far", pos, 0.0, 200.0, 0.05, BUS_OUTDOOR)
	else:
		p = play(parent, "gun_near", pos, 3.0, 180.0, 0.04, BUS_OUTDOOR)
	if p:
		p.pitch_scale *= pitch
	if d < 28.0:
		var thump_db := (6.0 if indoor else 4.0) + (3.0 if sg else 0.0) + boom
		play(parent, "gun_shotgun_body" if sg else "gun_thump", pos, thump_db, 60.0, 0.08, BUS_INDOOR if indoor else BUS_OUTDOOR)
	# Wave 2: the front of a close shot cracks like a whip, and a sub-bass
	# boom underneath you feel in your chest.
	if d < 22.0:
		var c := play(parent, "gun_crack_near", pos, 1.0 + (2.0 if indoor else 0.0), 45.0, 0.06, BUS_INDOOR if indoor else BUS_OUTDOOR)
		if c and sg:
			c.pitch_scale *= 0.8
	if d < 45.0:
		var sb := play(parent, "gun_sub", pos, 7.0 + (3.0 if sg else 0.0) + (2.0 if indoor else 0.0) + boom, 90.0, 0.05, BUS_SFX)
		if sb:
			sb.pitch_scale /= pow(weight, 0.3)
	# Outdoors the shot rolls round the streets, and from further off that
	# rolling echo is most of what you hear.
	if not indoor:
		var tail_db := -7.0 + (2.0 if sg else 0.0)
		if d > 35.0:
			tail_db = 1.0 + (2.0 if sg else 0.0) - 14.0 * log(d / 60.0) / log(10.0)
		later(parent, minf(d / SPEED_OF_SOUND, 1.2) * 0.25, "gun_tail_city", pos, minf(tail_db, 4.0), 450.0, 0.07, BUS_OUTDOOR, pitch)
	if d < 7.0:
		play(parent, "gun_mech", pos, -14.0, 10.0, 0.08)
	if not indoor and d < 160.0:
		shot_echoes(parent, pos, lis, sg)
	if GameSounds.current:
		GameSounds.current.duck(clampf(1.0 - d / (45.0 if indoor else 30.0), 0.0, 1.0))
		if not own and d < (3.5 if indoor else 2.6):
			GameSounds.current.ear_ring(0.8 if d < 1.6 else 0.5)


## Outdoors: the shot slapping back off the buildings round it.
static func shot_echoes(parent: Node, pos: Vector3, lis: Variant, shotgun := false) -> void:
	if lis == null:
		return
	var space := parent.get_viewport().world_3d.direct_space_state
	var l: Vector3 = lis
	var direct := pos.distance_to(l)
	var from := pos + Vector3(0, 1.2, 0)
	var hits := []
	for k in 8:
		var a := TAU * k / 8.0
		var to := from + Vector3(cos(a), 0, sin(a)) * 60.0
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		if h:
			hits.append(h.position)
	hits.sort_custom(func(a, b): return from.distance_to(a) < from.distance_to(b))
	var played := 0
	for w in hits:
		var wp: Vector3 = w
		var path := from.distance_to(wp) + wp.distance_to(l)
		var extra := path - direct
		if extra < 6.0:
			continue   # too close to tell apart from the shot itself
		var delay := extra / SPEED_OF_SOUND
		var db := -9.0 - 20.0 * log(path / 12.0) / log(10.0) + (2.0 if shotgun else 0.0)
		later(parent, delay, "gun_far", wp, db, 200.0, 0.06, BUS_OUTDOOR, 0.93)
		played += 1
		if played >= 3:
			break


## Phase 1.6: what a bullet did, heard from where you are: the hit on the
## surface it struck (or a body), sometimes a ricochet whine off metal or
## concrete, and if it went past your head, the crack (close) or whizz.
## what: 0 world, 1 a person, 2 nothing (it flew off). own: your bullet.
static func bullet(parent: Node, a: Vector3, b: Vector3, surface: String, what := 0, own := false) -> void:
	if what == 1:
		play(parent, "body_hit", b, 3.0, 50.0, 0.08)
		Gore.hit(parent, a, b)
	elif what == 0:
		impact(parent, b, surface, 0.9)
		Feel.impact(parent, b, a, surface)
		var roll := absf(sin(b.x * 12.9898 + b.z * 78.233 + b.y * 3.71))   # same on every machine
		if surface in ["metal", "concrete"] and roll < (0.4 if surface == "metal" else 0.2):
			play(parent, "ricochet", b, -4.0, 60.0, 0.1)
	if own:
		return
	var lis: Variant = listener_position(parent)
	if lis == null:
		return
	var l: Vector3 = lis
	var c := Geometry3D.get_closest_point_to_segment(l, a, b)
	var miss := c.distance_to(l)
	if miss < 2.4 and c.distance_to(a) > 2.0 and c.distance_to(b) > 0.6:
		play(parent, "bullet_crack" if miss < 1.3 else "bullet_whizz", c, 2.0 if miss < 1.3 else -2.0, 12.0, 0.1)
		Feel.shake(parent.get_tree(), 0.2 if miss < 1.3 else 0.08)


## Plays a sound after t seconds (through the scene's GameSounds, which
## owns the queue; without one it plays now).
static func later(parent: Node, t: float, stem: String, pos: Vector3, db := 0.0, dist := 60.0, spread := 0.05, bus := "", pitch := 1.0) -> void:
	if GameSounds.current:
		GameSounds.current.later(t, stem, pos, db, dist, spread, bus, pitch)
	else:
		var p := play(parent, stem, pos, db, dist, spread, bus)
		if p:
			p.pitch_scale *= pitch


## A blast: the bang, a rumble under it, and the ring if you were close.
static func explosion(parent: Node, pos: Vector3, size := 1.0) -> void:
	var tree := parent.get_tree()
	var bus := BUS_INDOOR if zone_at(tree, pos) != null else BUS_OUTDOOR
	play(parent, "explosion", pos, 4.0 * size, 300.0, 0.05, bus)
	play(parent, "explosion_body", pos, 6.0 * size, 400.0, 0.05, bus)
	play(parent, "gun_shotgun_body", pos, 4.0, 80.0, 0.1, bus)
	later(parent, 0.35, "rubble", pos, -2.0, 60.0, 0.1)
	var lis: Variant = listener_position(parent)
	if GameSounds.current and lis != null:
		var d := (lis as Vector3).distance_to(pos)
		GameSounds.current.duck(clampf(1.0 - d / 60.0, 0.0, 1.0))
		if d < 12.0:
			GameSounds.current.ear_ring(clampf(1.2 - d / 12.0, 0.3, 1.0))
		if bus == BUS_OUTDOOR and d < 200.0:
			shot_echoes(parent, pos, lis, true)


## A bullet or debris hit on a surface (wood, glass, concrete, metal).
static func impact(parent: Node, pos: Vector3, surface: String, strength := 1.0) -> void:
	if not surface in SURFACES:
		surface = "concrete"
	var db := linear_to_db(clampf(strength, 0.05, 1.5)) + 3.0
	play(parent, "impact_" + surface, pos, db, 50.0, 0.08)


## A pane of glass breaking.
static func glass_break(parent: Node, pos: Vector3) -> void:
	play(parent, "glass_break", pos, 2.0, 60.0, 0.05)


## Where the ears are: the current AudioListener3D, else the camera.
static func listener_position(node: Node) -> Variant:
	var vp := node.get_viewport()
	if vp == null:
		return null
	for l in node.get_tree().get_nodes_in_group(LISTENER_GROUP):
		if (l as AudioListener3D).is_current():
			return (l as Node3D).global_position
	var cam := vp.get_camera_3d()
	return cam.global_position if cam != null else null


const LISTENER_GROUP := "sfx_listener"


## Puts the ears on a pawn's head, so walls between you and a shot muffle it.
static func attach_listener(pawn: Node3D, height := 1.6) -> AudioListener3D:
	var l := AudioListener3D.new()
	l.name = "Ears"
	l.position = Vector3(0, height, 0)
	l.add_to_group(LISTENER_GROUP)
	pawn.add_child(l)
	l.make_current()
	return l
