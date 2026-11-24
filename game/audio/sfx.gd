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
##   v0.13.0: shots pick their bus from the space they are fired in
##            (space_at): Alley (flutter echo), Open (rooftops and open
##            ground, dry), RoomSmall (tight and harsh), Hall (big boom),
##            alongside Outdoor (the street) and Indoor (an ordinary room).
##            The Outdoor/Indoor volume settings cover their families.
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
## v0.13.0: more spaces. Outdoor is the street (and the default outside).
const BUS_ALLEY := "Alley"
const BUS_OPEN := "Open"           # rooftops, parks, open ground
const BUS_ROOM_SMALL := "RoomSmall"
const BUS_HALL := "Hall"
const OUTDOOR_BUSES := [BUS_OUTDOOR, BUS_ALLEY, BUS_OPEN]
const INDOOR_BUSES := [BUS_INDOOR, BUS_ROOM_SMALL, BUS_HALL]
const SFX_DIR := "res://assets/audio/sfx/"
const OCCLUDE_MASK := 1 | 16  # world and chunks
const MAX_WALLS := 3
const SURFACES := ["wood", "glass", "concrete", "metal"]
const MUFFLE_CUTOFF := [1200.0, 500.0]
const NEAR_RANGE := 30.0     # beyond this the distant recording is used
const COUNTS := {"amb_air": 1, "amb_docks": 1, "amb_far_traffic": 1, "amb_industrial": 1, "amb_park": 1,
	"amb_rain": 1, "amb_street": 1, "body_hit": 6, "bone_snap": 4, "break_concrete": 4, "break_metal": 5,
	"break_wood": 7, "bullet_crack": 3, "bullet_whizz": 4, "car_crash": 3, "car_door_close": 1,
	"car_door_open": 1, "car_engine": 1, "car_horn": 1, "car_idle": 1, "car_start": 4, "casing_concrete": 4,
	"casing_metal": 3, "casing_wood": 3, "cloth": 4, "collapse": 4, "cough": 6, "door_close": 4, "door_open": 2,
	"dry_fire": 1, "ear_ring": 1, "explosion": 4, "explosion_body": 2, "fire_loop": 1, "fire_whoomph": 2,
	"flashbang": 4, "frag_crack": 2, "gas_hiss": 1, "gear": 4, "glass_big": 5, "glass_break": 4,
	"glass_settle": 4, "gore_hit": 5, "grapple_fire": 2, "grapple_hit": 3, "gun_9mm_near": 10,
	"gun_9mm_room": 4, "gun_crack_near": 3, "gun_far": 8, "gun_heavy_mid": 4, "gun_heavy_near": 3,
	"gun_heavy_room": 4, "gun_mech": 1, "gun_shotgun_body": 3, "gun_shotgun_near": 4, "gun_shotgun_room": 4,
	"gun_smg": 8, "gun_sub": 3, "gun_tail_city": 3, "gun_thump": 3, "holster": 2, "impact_concrete": 4,
	"impact_glass": 3, "impact_metal": 5, "impact_wood": 4, "lift_ding": 1, "mag_drop_concrete": 2,
	"mag_drop_metal": 2, "mag_drop_wood": 2, "mag_in": 1, "mag_out": 1, "nade_bounce": 5, "nade_pin": 2,
	"ping": 1, "punch": 5, "radio_key": 3, "radio_unkey": 4, "radio_voice": 6, "ricochet": 4, "room_tone": 1,
	"rope_slide": 2, "rubble": 10, "shell_shotgun": 4, "shotgun_pump": 4, "siren_wail": 1, "siren_yelp": 1,
	"slide_rack": 1, "smoke_hiss": 1, "smoke_pop": 2, "step_concrete": 6, "step_dirt": 6, "step_metal": 4,
	"step_wood": 4, "thunder": 3, "tyre_chirp": 4, "tyre_skid": 1, "v8_drive": 1, "v8_idle": 1, "whoosh": 3,
	"works_drill": 2, "works_grind": 2, "works_weld": 2, "works_beep": 1, "works_hyd": 2, "works_chain": 2}
const BUS_AMBIENCE := "Ambience"
const BUS_AMBIENCE_OUT := "AmbienceOut"
const BUS_VEHICLES := "Vehicles"
## Wave 5: the music and the police radio, straight to Master (not ducked
## or muffled with the world).
const BUS_MUSIC := "Music"
const BUS_RADIO := "Radio"
const FAR_RANGE := 90.0      # beyond this a shot is a distant pop through the air
const SPEED_OF_SOUND := 343.0
## Gun kinds (as EnemyGuns: 0 and 1 are handguns, 2 a shotgun).
const SHOTGUN := 2

static var _cache := {}
static var _rng := RandomNumberGenerator.new()
## The most recent sounds played, newest last, for tests and the debug HUD.
static var history: Array = []
## Wave 5: when the last gunshot within earshot was (msec), for the music.
static var last_shot_ms := -100000


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
	# v0.13.0: the space a shot is fired in has its own sound (see space_at).
	# Alleys: hard walls close on both sides, a fast flutter echo and a
	# bright, short ring.
	var alley := _add_bus(BUS_ALLEY, BUS_SFX)
	var flutter := AudioEffectDelay.new()
	flutter.dry = 1.0
	flutter.tap1_active = true
	flutter.tap1_delay_ms = 22.0
	flutter.tap1_level_db = -7.0
	flutter.tap1_pan = -0.4
	flutter.tap2_active = true
	flutter.tap2_delay_ms = 41.0
	flutter.tap2_level_db = -9.0
	flutter.tap2_pan = 0.4
	flutter.feedback_active = true
	flutter.feedback_delay_ms = 44.0
	flutter.feedback_level_db = -9.0
	flutter.feedback_lowpass = 7000.0
	AudioServer.add_bus_effect(alley, flutter)
	var ring_alley := AudioEffectReverb.new()
	ring_alley.room_size = 0.45
	ring_alley.damping = 0.2
	ring_alley.spread = 1.0
	ring_alley.dry = 1.0
	ring_alley.wet = 0.22
	ring_alley.predelay_msec = 12.0
	AudioServer.add_bus_effect(alley, ring_alley)
	# Rooftops and open ground: nothing near to bounce off. Dry and sharp,
	# with only the city answering from far off (the tail layer in shot()).
	var open := _add_bus(BUS_OPEN, BUS_SFX)
	var open_air := AudioEffectReverb.new()
	open_air.room_size = 0.9
	open_air.damping = 0.85
	open_air.spread = 1.0
	open_air.dry = 1.0
	open_air.wet = 0.03
	open_air.predelay_msec = 60.0
	AudioServer.add_bus_effect(open, open_air)
	# Small rooms (bathrooms, corridors, stairwells): tight and harsh.
	var small := _add_bus(BUS_ROOM_SMALL, BUS_SFX)
	var box := AudioEffectReverb.new()
	box.room_size = 0.2
	box.damping = 0.25
	box.spread = 0.6
	box.dry = 0.9
	box.wet = 0.45
	box.predelay_msec = 2.0
	AudioServer.add_bus_effect(small, box)
	# Halls, warehouses, car parks: big and booming.
	var hall := _add_bus(BUS_HALL, BUS_SFX)
	var big := AudioEffectReverb.new()
	big.room_size = 0.8
	big.damping = 0.35
	big.spread = 1.0
	big.dry = 0.9
	big.wet = 0.42
	big.predelay_msec = 25.0
	AudioServer.add_bus_effect(hall, big)
	for base in [BUS_SFX] + OUTDOOR_BUSES + INDOOR_BUSES:
		for level in 2:
			var i := _add_bus(muffled_bus(base, level + 1), base)
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = MUFFLE_CUTOFF[level]
			lp.resonance = 0.5
			AudioServer.add_bus_effect(i, lp)
	# Loud and brutal (beenster): a fast compressor glues the layers of a
	# shot together and lifts its body, the limiter stops it clipping.
	var glue := AudioEffectCompressor.new()
	glue.threshold = -8.0
	glue.ratio = 3.0
	glue.attack_us = 1500.0
	glue.release_ms = 150.0
	glue.gain = 2.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_SFX), glue)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.3
	lim.pre_gain_db = 4.0
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_SFX), lim)
	# Background and engines, which duck under close shots.
	var amb := _add_bus(BUS_AMBIENCE, BUS_SFX)
	AudioServer.add_bus_effect(amb, AudioEffectAmplify.new())
	var amb_out := _add_bus(BUS_AMBIENCE_OUT, BUS_AMBIENCE)
	var lp_out := AudioEffectLowPassFilter.new()
	lp_out.cutoff_hz = 20000.0
	AudioServer.add_bus_effect(amb_out, lp_out)
	var veh := _add_bus(BUS_VEHICLES, BUS_SFX)
	AudioServer.add_bus_effect(veh, AudioEffectAmplify.new())
	_add_bus(BUS_MUSIC, "Master")
	var radio := _add_bus(BUS_RADIO, "Master")
	var hp := AudioEffectHighPassFilter.new()
	hp.cutoff_hz = 300.0
	AudioServer.add_bus_effect(radio, hp)
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


## v0.13.0: the reverb bus for the space at pos (see space_at).
static func space_bus(parent: Node, pos: Vector3) -> String:
	return space_at(parent, pos).bus


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


## A plain handgun shot, one layer (shot() is the full one). Outdoors: the
## close recording with its natural tail, or the distant one when the
## listener is far away. Indoors: the in-room take through that room's reverb.
static func gunshot(parent: Node, pos: Vector3) -> void:
	var sp := space_at(parent, pos)
	if sp.indoor:
		play(parent, "gun_9mm_room", pos, 0.0, 120.0, 0.04, sp.bus)
		return
	var lis: Variant = listener_position(parent)
	var far: bool = lis != null and (lis as Vector3).distance_to(pos) > NEAR_RANGE
	play(parent, "gun_far" if far else "gun_9mm_near", pos, 0.0, 160.0, 0.04, sp.bus)


## v0.13.0: the kind of space a sound is made in, worked out by feeling
## round it with rays (cached per 2 m cell for a few seconds):
##   room_small / room / hall  inside, by how far the walls and ceiling are
##   alley    outside with walls close on two opposite sides
##   street   outside with buildings round about
##   rooftop  outside, high above the street
##   open     outside with nothing much near (parks, docks, wide junctions)
## Returns {kind, bus, indoor}.
const SPACE_RAY := 40.0
const ROOFTOP_Y := 5.5
static var _spaces := {}


## Forgets the spaces felt so far (after the world changes a lot, and in tests).
static func forget_spaces() -> void:
	_spaces.clear()


static func space_at(parent: Node, pos: Vector3) -> Dictionary:
	var key := Vector3i((pos / 2.0).floor())
	var now := Time.get_ticks_msec()
	var c: Dictionary = _spaces.get(key, {})
	if not c.is_empty() and now - int(c.t) < 5000:
		return c
	var tree := parent.get_tree()
	var vp := parent.get_viewport()
	var in_zone := zone_at(tree, pos) != null
	var kind := "room" if in_zone else "street"
	if vp != null and vp.world_3d != null:
		kind = _probe(vp.world_3d.direct_space_state, pos, in_zone)
	var bus: String = {"room_small": BUS_ROOM_SMALL, "room": BUS_INDOOR, "hall": BUS_HALL, "alley": BUS_ALLEY,
		"street": BUS_OUTDOOR, "rooftop": BUS_OPEN, "open": BUS_OPEN}[kind]
	c = {"kind": kind, "bus": bus, "indoor": kind in ["room_small", "room", "hall"], "t": now}
	if _spaces.size() > 512:
		_spaces.clear()
	_spaces[key] = c
	return c


static func _probe(space: PhysicsDirectSpaceState3D, pos: Vector3, in_zone: bool) -> String:
	var from := pos + Vector3(0, 0.1, 0)
	var dist := []
	for k in 8:
		var a := TAU * k / 8.0
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(cos(a), 0, sin(a)) * SPACE_RAY, 1))
		dist.append(from.distance_to(h.position) if h else SPACE_RAY)
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.UP * 30.0, 1))
	var ceiling: float = from.distance_to(up.position) if up else 99.0
	if in_zone and (ceiling < 30.0 or pos.y <= ROOFTOP_Y):
		# Floor area from the two widest-apart pairs of walls, and the height.
		var w := minf(dist[0] + dist[4], dist[1] + dist[5])
		var l := minf(dist[2] + dist[6], dist[3] + dist[7])
		var area := w * l
		if area > 160.0 or ceiling > 5.0:
			return "hall"
		if area < 28.0 or minf(w, l) < 2.2:
			return "room_small"
		return "room"
	if pos.y > ROOFTOP_Y:
		return "rooftop"
	for k in 4:
		var across: float = dist[k] + dist[k + 4]
		var along: float = maxf(dist[(k + 2) % 8], dist[(k + 6) % 8])
		if across < 9.0 and along > 12.0 and ceiling > 30.0:
			return "alley"
	var near := 0
	for d in dist:
		if d < 25.0:
			near += 1
	return "street" if near >= 2 else "open"


## The sound family of a gun: kind 2 is the sawn-off; handguns go by the
## weight of the pistol (Armoury): heavy .45/.357, the machine pistol, else 9 mm.
static func family(kind: int, weight: float) -> String:
	if kind == SHOTGUN:
		return "shotgun"
	if weight >= 1.3:
		return "heavy"
	if weight < 0.83:
		return "smg"
	return "9mm"


## Phase 1.6, reworked v0.13.0 with beenster's Sound Pack 1: a gunshot built
## from layers, as heard from where you are, in the space it was fired in.
##   body       the recording of that gun (9 mm, heavy, machine pistol or
##              shotgun): close with its own tail outdoors; inside, the
##              in-room take (or the shot cut dry) through that room's
##              reverb (small rooms ring hard, halls boom); down a street
##              the heavy guns use their street take; past NEAR_RANGE the
##              distant recordings; past FAR_RANGE a thin pop. Distance
##              dulls it (air soaks up the top end) and, past 35 m, the
##              bang arrives late: you see the flash first.
##   thump      the low-end punch, only up close (bigger for a shotgun).
##   crack      the whip at the front of a close shot.
##   sub        a sub-bass boom you feel in your chest.
##   mechanics  the action cycling, only right next to the gun (and the
##              shotgun's pump racked after each shot).
##   tail       outdoors the shot rolls round the city: short and tight
##              in an alley, long from a rooftop, faint on open ground.
##   slapback   in streets and alleys, echoes off the nearest walls.
## Close shots also duck the background, and a shot (or blast) right by
## your head that is not your own leaves your ears ringing.
## kind: 0/1 handgun, 2 shotgun. own: fired by the player listening.
## weight (Phase 3.5): the officer's pistol: picks the family, and within
## it a heavier gun is pitched a touch lower.
static func shot(parent: Node, pos: Vector3, kind := 0, own := false, weight := 1.0) -> void:
	var lis: Variant = listener_position(parent)
	var d: float = (lis as Vector3).distance_to(pos) if lis != null else 10.0
	if d < 140.0:
		last_shot_ms = Time.get_ticks_msec()
	# Sound travels at 343 m/s: from down the road the bang comes late.
	if d > 35.0 and GameSounds.current:
		var wr: WeakRef = weakref(parent)
		GameSounds.current.later_call(d / SPEED_OF_SOUND, func():
			var pr: Node = wr.get_ref()
			if pr and pr.is_inside_tree():
				_shot_now(pr, pos, kind, own, weight))
		return
	_shot_now(parent, pos, kind, own, weight)


const FAMILY_WEIGHT := {"9mm": 1.0, "heavy": 1.45, "smg": 0.8, "shotgun": 1.0}


static func _shot_now(parent: Node, pos: Vector3, kind: int, own: bool, weight: float) -> void:
	var sp := space_at(parent, pos)
	var indoor: bool = sp.indoor
	var bus: String = sp.bus
	var where: String = sp.kind
	var lis: Variant = listener_position(parent)
	var d: float = (lis as Vector3).distance_to(pos) if lis != null else 10.0
	var fam := family(kind, weight)
	var sg := fam == "shotgun"
	var heavy := fam == "heavy"
	var pitch := 1.0 / pow(weight / FAMILY_WEIGHT[fam], 0.3) if not sg else 1.0
	var boom := maxf(weight - 1.0, 0.0) * 4.0
	var room_db := {"room_small": 9.0, "room": 8.0, "hall": 7.0}
	var p: AudioStreamPlayer3D
	if indoor:
		var body := "gun_smg" if fam == "smg" else "gun_%s_room" % fam
		p = play(parent, body, pos, room_db.get(where, 8.0), 150.0, 0.04, bus)
	elif d > FAR_RANGE:
		p = play(parent, "gun_far", pos, -2.0 + (3.0 if sg or heavy else 0.0), 320.0, 0.06, bus)
		if p and (sg or heavy):
			p.pitch_scale *= 0.85
	elif d > NEAR_RANGE:
		if heavy:
			p = play(parent, "gun_heavy_mid", pos, 4.0, 260.0, 0.04, bus)
		else:
			p = play(parent, "gun_far", pos, 2.0 + (3.0 if sg else 0.0), 240.0, 0.05, bus)
			if p and sg:
				p.pitch_scale *= 0.85
	else:
		var near_db := {"alley": 7.0, "street": 6.0, "rooftop": 5.0, "open": 5.0}
		var body := "gun_smg" if fam == "smg" else "gun_%s_near" % fam
		p = play(parent, body, pos, near_db.get(where, 6.0), 220.0, 0.04, bus)
	if p:
		p.pitch_scale *= pitch
		_air(p, d)
	if d < 28.0:
		var thump_db := (5.0 if indoor else 3.0) + (3.0 if sg else 0.0) + boom - (4.0 if fam == "smg" else 0.0)
		play(parent, "gun_shotgun_body" if sg else "gun_thump", pos, thump_db, 60.0, 0.08, bus)
	if d < 22.0:
		var c := play(parent, "gun_crack_near", pos, (2.0 if indoor else 0.0) - (3.0 if fam == "smg" else 0.0), 45.0, 0.06, bus)
		if c and (sg or heavy):
			c.pitch_scale *= 0.82
	if d < 45.0:
		var sb := play(parent, "gun_sub", pos, 6.0 + (3.0 if sg else 0.0) + (3.0 if indoor else 0.0) + boom - (3.0 if fam == "smg" else 0.0), 90.0, 0.05, BUS_SFX)
		if sb:
			sb.pitch_scale /= pow(weight, 0.3)
	# Outdoors the shot rolls round the streets, and from further off that
	# rolling echo is most of what you hear.
	if not indoor:
		var tail_db := -6.0 + (2.0 if sg or heavy else 0.0)
		var wait := minf(d / SPEED_OF_SOUND, 1.2) * 0.25
		match where:
			"alley":
				tail_db += 1.0
			"rooftop":
				tail_db += 2.0      # the whole city answers, from below
				wait += 0.25
			"open":
				tail_db -= 6.0
				wait += 0.15
		if d > 35.0:
			tail_db += 7.0 - 14.0 * log(d / 60.0) / log(10.0)
		if fam != "smg" or randf() < 0.35:
			later(parent, wait, "gun_tail_city", pos, minf(tail_db, 5.0), 450.0, 0.07, bus, pitch)
	if d < 7.0:
		play(parent, "gun_mech", pos, -14.0, 10.0, 0.08)
	if sg and d < 30.0:
		later(parent, 0.4, "shotgun_pump", pos, -3.0, 25.0, 0.04)
	if not indoor and d < 160.0 and (fam != "smg" or randf() < 0.4):
		shot_echoes(parent, pos, lis, sg or heavy)
	if GameSounds.current:
		GameSounds.current.duck(clampf(1.0 - d / (45.0 if indoor else 30.0), 0.0, 1.0))
		if not own and d < (3.5 if indoor else 2.6):
			GameSounds.current.ear_ring(0.8 if d < 1.6 else 0.5)


## Air soaks up the top end of a far sound: Godot's per-player low-pass,
## which deepens with distance (only on sounds not already muffled by walls).
static func _air(p: AudioStreamPlayer3D, d: float) -> void:
	if p.bus.contains("_Muffled") or d < 15.0:
		return
	p.attenuation_filter_cutoff_hz = 6000.0
	p.attenuation_filter_db = -18.0


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
	var sp := space_at(parent, pos)
	var bus: String = sp.bus
	play(parent, "explosion", pos, 5.0 * size, 320.0, 0.05, bus)
	play(parent, "explosion_body", pos, 6.0 * size, 400.0, 0.05, bus)
	play(parent, "gun_shotgun_body", pos, 4.0, 80.0, 0.1, bus)
	later(parent, 0.35, "rubble", pos, -2.0, 60.0, 0.1)
	var lis: Variant = listener_position(parent)
	if GameSounds.current and lis != null:
		var d := (lis as Vector3).distance_to(pos)
		GameSounds.current.duck(clampf(1.0 - d / 60.0, 0.0, 1.0))
		if d < 12.0:
			GameSounds.current.ear_ring(clampf(1.2 - d / 12.0, 0.3, 1.0))
		if not sp.indoor and d < 200.0:
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
