class_name Sfx
extends RefCounted
## Sound for The Popo: buses, layered gunshots, impacts by surface,
## indoor/outdoor reverb by zone and muffling through walls.
##
## Buses (made once by ensure_buses):
##   SFX      dry 3D sound outdoors, feeds Master
##   Outdoor  gunshot tails outdoors: a slapback echo off the street plus a
##            short, wide reverb. Feeds SFX.
##   Indoor   anything fired or hit inside a SoundZone: a tight room reverb.
##            Feeds SFX.
## Occlusion: a ray from the sound to the listener counts the walls between.
## Each wall lowers the cutoff of the player's low-pass filter and the volume.

const BUS_SFX := "SFX"
const BUS_INDOOR := "Indoor"
const BUS_OUTDOOR := "Outdoor"
const SFX_DIR := "res://assets/audio/sfx/"
const OCCLUDE_MASK := 1 | 16  # world and chunks
const MAX_WALLS := 3
const SURFACES := ["wood", "glass", "concrete", "metal"]

## Layers of one handgun shot: [file stem, variants, dB, max distance, pitch spread]
const GUN_LAYERS := [
	["gun_mech", 3, -8.0, 18.0, 0.06],   # slide and hammer, only heard close up
	["gun_crack", 3, 2.0, 120.0, 0.05],  # the sharp supersonic crack
	["gun_body", 3, 0.0, 90.0, 0.08],    # the low thump of the charge
]
const GUN_TAIL := ["gun_tail_outdoor", 2, -4.0, 160.0, 0.04]

static var _cache := {}
static var _rng := RandomNumberGenerator.new()
## The most recent sounds played, newest last, for tests and the debug HUD.
static var history: Array = []


static func ensure_buses() -> void:
	if AudioServer.get_bus_index(BUS_SFX) != -1:
		return
	_add_bus(BUS_SFX, "Master")
	var outdoor := _add_bus(BUS_OUTDOOR, BUS_SFX)
	var slap := AudioEffectDelay.new()
	slap.dry = 1.0
	slap.tap1_active = true
	slap.tap1_delay_ms = 110.0  # the facade across the street, about 19 m away
	slap.tap1_level_db = -9.0
	slap.tap1_pan = -0.3
	slap.tap2_active = true
	slap.tap2_delay_ms = 260.0
	slap.tap2_level_db = -15.0
	slap.tap2_pan = 0.35
	slap.feedback_active = false
	AudioServer.add_bus_effect(outdoor, slap)
	var wide := AudioEffectReverb.new()
	wide.room_size = 0.9
	wide.damping = 0.65
	wide.spread = 1.0
	wide.dry = 1.0
	wide.wet = 0.12
	wide.predelay_msec = 40.0
	AudioServer.add_bus_effect(outdoor, wide)
	var indoor := _add_bus(BUS_INDOOR, BUS_SFX)
	var room := AudioEffectReverb.new()
	room.room_size = 0.45
	room.damping = 0.35  # hard walls: bright reflections
	room.spread = 0.8
	room.dry = 0.85
	room.wet = 0.42
	room.predelay_msec = 8.0
	AudioServer.add_bus_effect(indoor, room)
	var limit := AudioEffectHardLimiter.new()
	AudioServer.add_bus_effect(AudioServer.get_bus_index(BUS_SFX), limit)


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
			return {"cutoff": 1400.0, "db": -7.0}
		2:
			return {"cutoff": 650.0, "db": -13.0}
		_:
			return {"cutoff": 380.0, "db": -19.0}


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
static func play(parent: Node, stem: String, variants: int, pos: Vector3, db := 0.0, max_dist := 60.0, pitch_spread := 0.05, bus := "") -> AudioStreamPlayer3D:
	ensure_buses()
	var tree := parent.get_tree()
	if bus == "":
		bus = BUS_SFX if zone_at(tree, pos) == null else BUS_INDOOR
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(stem, _rng.randi_range(1, variants))
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
	p.attenuation_filter_cutoff_hz = occ.cutoff
	p.attenuation_filter_db = -24.0
	p.volume_db += occ.db
	p.finished.connect(p.queue_free)
	p.play()
	history.append({"stem": stem, "pos": pos, "bus": bus, "walls": walls, "cutoff": occ.cutoff})
	if history.size() > 32:
		history.pop_front()
	return p


## A handgun shot, layered: mechanism, crack, body, and outdoors an echoing tail.
static func gunshot(parent: Node, pos: Vector3) -> void:
	var indoor := zone_at(parent.get_tree(), pos) != null
	for l in GUN_LAYERS:
		play(parent, l[0], l[1], pos, l[2], l[3], l[4], BUS_INDOOR if indoor else BUS_SFX)
	if not indoor:
		var t: Array = GUN_TAIL
		play(parent, t[0], t[1], pos, t[2], t[3], t[4], BUS_OUTDOOR)


## A bullet or debris hit on a surface (wood, glass, concrete, metal).
static func impact(parent: Node, pos: Vector3, surface: String, strength := 1.0) -> void:
	if not surface in SURFACES:
		surface = "concrete"
	var db := linear_to_db(clampf(strength, 0.05, 1.5)) - 2.0
	play(parent, "impact_" + surface, 3, pos, db, 45.0, 0.1)


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
