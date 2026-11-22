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
## Sounds are CC0 recordings imported by tools/audio/import_cc0.py.

const BUS_SFX := "SFX"
const BUS_INDOOR := "Indoor"
const BUS_OUTDOOR := "Outdoor"
const SFX_DIR := "res://assets/audio/sfx/"
const OCCLUDE_MASK := 1 | 16  # world and chunks
const MAX_WALLS := 3
const SURFACES := ["wood", "glass", "concrete", "metal"]
const MUFFLE_CUTOFF := [1200.0, 500.0]
const NEAR_RANGE := 30.0     # beyond this the distant recording is used
const COUNTS := {"gun_near": 5, "gun_dry": 5, "gun_far": 4, "impact_wood": 4, "impact_glass": 3,
	"impact_metal": 5, "impact_concrete": 4, "glass_break": 3}

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
	slap.tap1_delay_ms = 95.0
	slap.tap1_level_db = -16.0
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
	p.stream = stream(stem, _rng.randi_range(1, COUNTS.get(stem, 1)))
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
