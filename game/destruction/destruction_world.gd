class_name DestructionWorld
extends Node3D
## Breakable buildings made of kit pieces, simulated with real Jolt physics.
##
## Every kit piece starts as a static body. Each has a pre-fractured twin made
## in Blender (see KitLibrary). The host owns all destruction:
##  - Damage (bullets, charges, falling debris) wears a piece down. At zero it
##    shatters into its chunks, which are real rigid bodies.
##  - After any piece is lost the support graph is re-checked. A piece that
##    has lost its support is released as one rigid body and falls under
##    gravity. When it hits something hard enough it shatters too.
##  - Big chunks (and falling pieces) are synced to clients in snapshots:
##    clients draw them as kinematic proxies interpolated 100 ms behind.
##    When a big chunk falls asleep the host sends its resting transform
##    reliably, so everyone agrees where the rubble ended up.
##  - Small chunks are cosmetic. Each machine simulates its own from the same
##    seed and starting velocities, so they look alike but are not synced.

const MSG_BREAK := 20
const MSG_SETTLE := 21
const MSG_FX := 22

const BIG_CHUNK_VOLUME := 0.12   # m^3; at or above this a chunk is synced
const DENSITY := 1400.0          # kg/m^3, lighter than concrete for game feel
const RELEASED_BIT := 63         # net id suffix for a whole falling piece
const DEBRIS_LIFETIME := 25.0
## Whole falling pieces live on their own layer so fresh rubble can ignore
## them for a moment (see CRUSH_TIME).
const FALLING_LAYER := 32
## Rubble from a shattered piece ignores falling pieces for this long, as if
## crushed, so a floor is not left balanced on the neat stack of cells its
## broken wall made.
const CRUSH_TIME := 0.6
const MAX_LOCAL_DEBRIS := 700

const HP := {"wall": 120.0, "wall_window": 80.0, "wall_door": 90.0, "slab": 220.0, "column": 160.0,
	"wall_half": 80.0, "wall_half_window": 60.0, "wall_shopfront": 70.0, "wall_shopdoor": 70.0, "wall_garage": 70.0,
	"parapet": 60.0, "parapet_half": 40.0, "int_wall": 60.0, "int_wall_door": 45.0, "int_wall_half": 40.0,
	"slab_half": 150.0, "slab_stairwell": 180.0, "stairs": 150.0, "roof": 180.0, "roof_half": 130.0, "column_thin": 90.0,
	"glass_window": 4.0, "glass_half_window": 3.0, "glass_shopfront": 6.0, "glass_shopdoor": 4.0,
	"door_closed": 40.0, "garage_door": 60.0, "pavement": 400.0, "road": 600.0, "road_line": 600.0, "road_crossing": 600.0,
	"low_wall": 90.0, "bollard": 80.0, "lamp_post": 60.0}
## Pieces whose bottom is below this stand on the ground (the pavement is
## 0.15 m high, and buildings stand on it).
const ANCHOR_Y := 0.2
## Floors and roofs: need support on two opposite sides.
const SLABS := ["slab", "slab_half", "slab_stairwell", "roof", "roof_half"]

enum { BREAK_SHATTER, BREAK_RELEASE, BREAK_BODY_SHATTER }

signal piece_broken(id: int)

## Set by the scene so clients can read the interpolation clock.
var sync: PawnSync

var pieces := {}         # piece id -> Dictionary
var bodies := {}         # net id -> RigidBody3D (host: simulated; client: synced proxies)
var _buffers := {}       # client: net id -> Array of [time, pos, quat]
var _debris: Array = []  # local cosmetic chunks [body, spawn time]
var _next_id := 1
var _stability_dirty := false

# Stats
var synced_awake := 0
var bytes_per_snapshot := 0
var chunk_count := 0


func _ready() -> void:
	Net.register(MSG_BREAK, _on_break_msg)
	Net.register(MSG_SETTLE, _on_settle_msg)
	Net.register(MSG_FX, _on_fx_msg)
	if sync:
		sync.extra_writers.append(_write_snapshot)
		sync.extra_readers.append(_read_snapshot)


func _exit_tree() -> void:
	for m in [MSG_BREAK, MSG_SETTLE, MSG_FX]:
		Net.unregister(m)


# --- Building ---------------------------------------------------------------

## Adds one kit piece. bears: whether it carries the load of pieces above it.
## tint recolours exterior wall faces (alpha 0 keeps the kit colour).
## held_by: the piece this one hangs in (glass and doors in their wall); it
## stands while that piece stands.
func add_piece(kind: String, xform: Transform3D, bears := true, tint := Color(0, 0, 0, 0), held_by := -1) -> int:
	var id := _next_id
	_next_id += 1
	var kit := KitLibrary.get_piece(kind)
	var body := StaticBody3D.new()
	body.name = "Piece%d" % id
	body.transform = xform
	body.collision_layer = 1
	body.set_meta("piece_id", id)
	body.set_meta("surface", surface_for(kind))
	var mi := MeshInstance3D.new()
	mi.mesh = kit.mesh
	KitLibrary.tint(mi, kit.surfaces, tint)
	body.add_child(mi)
	for ch in kit.chunks:
		var cs := CollisionShape3D.new()
		cs.shape = ch.shape
		cs.position = ch.offset
		body.add_child(cs)
	add_child(body)
	var world_aabb: AABB = xform * (kit.aabb as AABB)
	pieces[id] = {
		"id": id, "kind": kind, "node": body, "xform": xform, "aabb": world_aabb,
		"hp": HP.get(kind, 100.0), "bears": bears, "state": "intact",
		"anchored": world_aabb.position.y < ANCHOR_Y and held_by < 0, "below": [],
		"tint": tint, "held_by": held_by,
	}
	return id


## What a kit piece sounds like when hit (Sfx surfaces).
static func surface_for(kind: String) -> String:
	if kind.begins_with("glass"):
		return "glass"
	if kind in ["door_closed", "garage_door", "stairs"]:
		return "wood"
	if kind in ["lamp_post", "bollard"]:
		return "metal"
	return "concrete"


## Call once after all pieces are added: works out what rests on what.
func finalize() -> void:
	# Bucket pieces by the height of their top (5 cm steps), so each piece
	# only checks the few that could be right under it.
	var by_top := {}
	for b in pieces.values():
		b.below = []
		var k := int(roundf(b.aabb.end.y * 20.0))
		if not by_top.has(k):
			by_top[k] = []
		by_top[k].append(b)
	for a in pieces.values():
		if a.held_by >= 0:
			continue
		var a_bottom: float = a.aabb.position.y
		var kb := int(roundf(a_bottom * 20.0))
		var ax := Rect2(a.aabb.position.x, a.aabb.position.z, a.aabb.size.x, a.aabb.size.z)
		for k in [kb - 1, kb, kb + 1]:
			for b in by_top.get(k, []):
				# Non-bearing pieces (shopfronts, facades) hold up walls above
				# them but never carry a slab.
				if a == b or (a.kind in SLABS and not b.bears) or b.held_by >= 0:
					continue
				if absf(a_bottom - b.aabb.end.y) > 0.06:
					continue
				var bx := Rect2(b.aabb.position.x, b.aabb.position.z, b.aabb.size.x, b.aabb.size.z)
				if ax.intersection(bx).get_area() > 0.01:
					a.below.append(b.id)


## Stable pieces: anchored to the ground, or held up by stable pieces below.
## Walls and columns need one support. A slab needs support on two opposite
## sides (both ends of its span along X, or both along Z).
func compute_stable() -> Dictionary:
	var stable := {}
	var order: Array = pieces.values().filter(func(p): return p.state == "intact")
	order.sort_custom(func(a, b): return a.aabb.position.y < b.aabb.position.y)
	for p in order:
		if p.anchored:
			stable[p.id] = true
			continue
		if p.held_by >= 0:
			if stable.has(p.held_by):
				stable[p.id] = true
			continue
		var held: Array = p.below.filter(func(i): return stable.has(i))
		if held.is_empty():
			continue
		if p.kind in SLABS:
			var c: Vector3 = p.aabb.get_center()
			var hx: float = p.aabb.size.x * 0.3
			var hz: float = p.aabb.size.z * 0.3
			var minx := false
			var maxx := false
			var minz := false
			var maxz := false
			for i in held:
				# A support counts for a side when its centre lies along that edge.
				var bc: Vector3 = pieces[i].aabb.get_center()
				minx = minx or bc.x < c.x - hx
				maxx = maxx or bc.x > c.x + hx
				minz = minz or bc.z < c.z - hz
				maxz = maxz or bc.z > c.z + hz
			if (minx and maxx) or (minz and maxz):
				stable[p.id] = true
		else:
			stable[p.id] = true
	return stable


# --- Damage (host only) -----------------------------------------------------

func damage_piece(id: int, amount: float, from_point: Vector3, strength: float) -> void:
	if not Net.is_host() or not pieces.has(id) or pieces[id].state != "intact":
		return
	var p: Dictionary = pieces[id]
	p.hp -= amount
	if p.hp <= 0.0:
		_host_break(id, BREAK_SHATTER, from_point, strength)


## A kick or barge: doors burst off their hinges and fly in whole,
## everything else takes the damage as usual.
func strike_piece(id: int, amount: float, point: Vector3, dir: Vector3) -> void:
	if not Net.is_host() or not pieces.has(id) or pieces[id].state != "intact":
		return
	var p: Dictionary = pieces[id]
	if not String(p.kind).begins_with("door"):
		damage_piece(id, amount, point - dir * 0.3, 2.0)
		return
	p.hp -= amount
	if p.hp > 0.0:
		return
	_host_break(id, BREAK_RELEASE, point, 0.0)
	var rb: RigidBody3D = bodies.get(id * 64 + RELEASED_BIT)
	if rb:
		# Off its hinges: free of the frame, pushed high so it topples in.
		var frame: Dictionary = pieces.get(p.held_by, {})
		if frame.get("state", "") == "intact" and is_instance_valid(frame.node):
			rb.add_collision_exception_with(frame.node)
		var high := Vector3(point.x, rb.global_position.y + 1.7, point.z)
		rb.apply_impulse(dir * rb.mass * 3.0, high - rb.global_position)


## Explosion: damages pieces in range and pushes every rigid body nearby.
func explode(at: Vector3, radius: float, damage: float, strength: float) -> void:
	if not Net.is_host():
		return
	_send_fx(0, at)
	for p in pieces.values():
		if p.state != "intact":
			continue
		var d: float = _aabb_distance(p.aabb, at)
		if d < radius:
			damage_piece(p.id, damage * (1.0 - d / radius), at, strength)
	await get_tree().physics_frame
	for b in get_tree().get_nodes_in_group("destruction_body"):
		if b is RigidBody3D and not (b as RigidBody3D).freeze:
			var off: Vector3 = b.global_position - at
			var dist := off.length()
			if dist < radius * 1.5:
				var f := strength * (1.0 - dist / (radius * 1.5))
				(b as RigidBody3D).apply_central_impulse(off.normalized() * f * (b as RigidBody3D).mass * 0.6 + Vector3.UP * f * (b as RigidBody3D).mass * 0.3)


func bullet_hit(collider: Object, point: Vector3, normal: Vector3, dir: Vector3) -> void:
	if not Net.is_host():
		return
	_send_fx(1, point, normal)
	if collider is Node and (collider as Node).has_meta("piece_id"):
		damage_piece((collider as Node).get_meta("piece_id"), 12.0, point - dir * 0.3, 2.0)
	elif PropWorld.current and PropWorld.current.bullet_hit(collider, point, dir):
		pass
	elif collider is RigidBody3D:
		(collider as RigidBody3D).apply_impulse(dir * 40.0, point - (collider as RigidBody3D).global_position)


func _aabb_distance(box: AABB, p: Vector3) -> float:
	var q := p.clamp(box.position, box.end)
	return q.distance_to(p)


func _host_break(id: int, mode: int, origin: Vector3, strength: float) -> void:
	if mode == BREAK_BODY_SHATTER and not bodies.has(id * 64 + RELEASED_BIT):
		return
	var seed := randi()
	var b := StreamPeerBuffer.new()
	b.put_u32(id)
	b.put_u8(mode)
	b.put_u32(seed)
	_put_v3(b, origin)
	b.put_float(strength)
	if mode == BREAK_BODY_SHATTER:
		var body: RigidBody3D = bodies[id * 64 + RELEASED_BIT]
		_put_xform(b, body.global_transform)
		_put_v3(b, body.linear_velocity)
		_put_v3(b, body.angular_velocity)
	Net.broadcast(MSG_BREAK, b.data_array, Net.RELIABLE)
	b.seek(0)
	_apply_break(b)


func _on_break_msg(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_apply_break(b)


## Runs on host and clients from the same message, so both make the same chunks.
func _apply_break(b: StreamPeerBuffer) -> void:
	var id := b.get_u32()
	var mode := b.get_u8()
	var rng := RandomNumberGenerator.new()
	rng.seed = b.get_u32()
	var origin := _get_v3(b)
	var strength := b.get_float()
	var p: Dictionary = pieces[id]
	match mode:
		BREAK_SHATTER:
			if p.state != "intact":
				return
			p.state = "gone"
			p.node.queue_free()
			_spawn_chunks(p, p.xform, Vector3.ZERO, Vector3.ZERO, origin, strength, rng)
			_stability_dirty = true
		BREAK_RELEASE:
			if p.state != "intact":
				return
			p.state = "released"
			p.node.queue_free()
			_spawn_released(p)
			_stability_dirty = true
		BREAK_BODY_SHATTER:
			var xf := _get_xform(b)
			var lv := _get_v3(b)
			var av := _get_v3(b)
			var nid: int = id * 64 + RELEASED_BIT
			if bodies.has(nid):
				bodies[nid].queue_free()
				bodies.erase(nid)
				_buffers.erase(nid)
			p.state = "gone"
			_spawn_chunks(p, xf, lv, av, origin, strength, rng)
	piece_broken.emit(id)


func _physics_process(delta: float) -> void:
	if Net.is_host() and _stability_dirty:
		_stability_dirty = false
		var stable := compute_stable()
		for p in pieces.values():
			if p.state == "intact" and not stable.has(p.id):
				_host_break(p.id, BREAK_RELEASE, p.aabb.get_center(), 0.0)
	if Net.is_host():
		_check_released_impacts(delta)
	else:
		_interpolate()
	# Retire old cosmetic debris.
	var now := Time.get_ticks_msec() / 1000.0
	while not _debris.is_empty() and (now - _debris[0][1] > DEBRIS_LIFETIME or _debris.size() > MAX_LOCAL_DEBRIS):
		var d: Array = _debris.pop_front()
		if is_instance_valid(d[0]):
			d[0].queue_free()
	chunk_count = bodies.size() + _debris.size()


# --- Spawning ---------------------------------------------------------------

func _make_body(mesh: Mesh, shapes: Array, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.mass = max(mass, 1.0)
	rb.collision_layer = 16
	rb.collision_mask = 1 | 2 | 4 | 16 | FALLING_LAYER
	rb.add_to_group("destruction_body")
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	rb.add_child(mi)
	for s in shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s[0]
		cs.position = s[1]
		rb.add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.05
	rb.physics_material_override = pm
	return rb


func _spawn_chunks(p: Dictionary, xf: Transform3D, lin: Vector3, ang: Vector3, origin: Vector3, strength: float, rng: RandomNumberGenerator) -> void:
	var kit := KitLibrary.get_piece(p.kind)
	var now := Time.get_ticks_msec() / 1000.0
	for k in kit.chunks.size():
		var ch: Dictionary = kit.chunks[k]
		var big: bool = ch.volume >= BIG_CHUNK_VOLUME
		var pos: Vector3 = xf * (ch.offset as Vector3)
		var rb := _make_body(ch.mesh, [[ch.shape, Vector3.ZERO]], ch.volume * DENSITY)
		KitLibrary.tint(rb.get_child(0), ch.surfaces, p.tint)
		rb.set_meta("surface", surface_for(p.kind))
		rb.transform = Transform3D(xf.basis, pos)
		# Starting velocity: the parent's motion, plus a push away from the
		# blast that falls off with distance, plus a little seeded noise.
		var v := lin + ang.cross(pos - xf.origin)
		var away := pos - origin
		var push: float = strength / (1.0 + away.length_squared())
		# Crumble: even a gentle break scatters the cells so a broken wall
		# does not stay standing as a neat stack holding up the floor.
		var scatter: float = clampf(strength, 1.0, 4.0)
		v += away.normalized() * push + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.8), rng.randf_range(-1, 1)) * 1.4 * scatter
		var w := ang + Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)) * scatter * 0.6
		if big:
			var nid: int = p.id * 64 + k
			if Net.is_host():
				rb.linear_velocity = v
				rb.angular_velocity = w
				_watch_sleep(rb, nid)
			else:
				_make_proxy(rb)
			bodies[nid] = rb
			rb.set_meta("net_id", nid)
		else:
			rb.linear_velocity = v
			rb.angular_velocity = w
			rb.collision_mask = 1 | 4 | 16  # cosmetic: does not shove players
			_debris.append([rb, now])
		var full_mask := rb.collision_mask | FALLING_LAYER
		rb.collision_mask &= ~FALLING_LAYER
		# By id, not by reference: the chunk may be gone when the timer fires.
		get_tree().create_timer(CRUSH_TIME, true, true).timeout.connect(_restore_mask.bind(rb.get_instance_id(), full_mask))
		add_child(rb)


static func _restore_mask(id: int, mask: int) -> void:
	var rb := instance_from_id(id) as RigidBody3D
	if rb:
		rb.collision_mask = mask


func _spawn_released(p: Dictionary) -> void:
	var kit := KitLibrary.get_piece(p.kind)
	var shapes: Array = []
	var vol := 0.0
	for ch in kit.chunks:
		shapes.append([ch.shape, ch.offset])
		vol += ch.volume
	var rb := _make_body(kit.mesh, shapes, vol * DENSITY)
	KitLibrary.tint(rb.get_child(0), kit.surfaces, p.tint)
	rb.set_meta("surface", surface_for(p.kind))
	rb.collision_layer = FALLING_LAYER
	rb.transform = p.xform
	var nid: int = p.id * 64 + RELEASED_BIT
	rb.set_meta("net_id", nid)
	rb.set_meta("released_piece", p.id)
	bodies[nid] = rb
	# Pieces that stood on this one but are still held up elsewhere would
	# clamp its edge like a vice; let it tear free from under them instead.
	for other in pieces.values():
		if other.state == "intact" and other.below.has(p.id) and is_instance_valid(other.node):
			rb.add_collision_exception_with(other.node)
	# The pieces it was touching when it let go (the next slab along, the
	# wall it hung off). Scraping past them as it tips is not an impact.
	var torn_from: Array = []
	var near: AABB = p.aabb.grow(0.1)
	for other in pieces.values():
		if other.id != p.id and other.state == "intact" and near.intersects(other.aabb):
			torn_from.append(other.id)
	rb.set_meta("torn_from", torn_from)
	if Net.is_host():
		rb.contact_monitor = true
		rb.max_contacts_reported = 6
		rb.body_entered.connect(_on_released_hit.bind(rb, p.id))
		_watch_sleep(rb, nid)
	else:
		_make_proxy(rb)
	add_child(rb)


func _make_proxy(rb: RigidBody3D) -> void:
	rb.freeze = true
	rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC


## Host: a falling piece shatters when it lands hard, and damages what it hits.
func _on_released_hit(other: Node, rb: RigidBody3D, piece_id: int) -> void:
	if not is_instance_valid(rb) or pieces[piece_id].state != "released":
		return
	var speed := rb.linear_velocity.length() + rb.angular_velocity.length() * 0.5
	if other.has_meta("piece_id"):
		var torn_from: Array = rb.get_meta("torn_from", [])
		if speed < TEAR_SCRAPE_SPEED and torn_from.has(other.get_meta("piece_id")):
			return
		damage_piece(other.get_meta("piece_id"), rb.mass * speed * 0.02, rb.global_position, 1.0)


## Host: a falling piece shatters when it is stopped hard (a big change of
## velocity in one physics step), wherever it lands.
const SHATTER_DELTA_V := 2.2
## Physics steps after release before a hard stop can shatter the piece.
const SHATTER_GRACE_STEPS := 6
## Below this speed a falling piece scraping the pieces it tore away from
## does them no damage.
const TEAR_SCRAPE_SPEED := 4.0

func _check_released_impacts(_delta: float) -> void:
	for p in pieces.values():
		if p.state != "released":
			continue
		var rb: RigidBody3D = bodies.get(p.id * 64 + RELEASED_BIT)
		if rb == null or not is_instance_valid(rb):
			continue
		var v := rb.linear_velocity
		var prev: Vector3 = rb.get_meta("prev_v", v)
		rb.set_meta("prev_v", v)
		# Just after letting go it is still pressed against the pieces it tore
		# from, and the solver pushing them apart is not a landing.
		var age: int = rb.get_meta("age", 0) + 1
		rb.set_meta("age", age)
		if age <= SHATTER_GRACE_STEPS:
			continue
		if (v - prev).length() > SHATTER_DELTA_V and rb.get_contact_count() > 0:
			p.state = "shattering"
			_host_break(p.id, BREAK_BODY_SHATTER, rb.global_position - prev.normalized() * 0.5, 1.0)


func _watch_sleep(rb: RigidBody3D, nid: int) -> void:
	rb.can_sleep = true
	rb.sleeping_state_changed.connect(func():
		if rb.sleeping and is_instance_valid(rb):
			var b := StreamPeerBuffer.new()
			b.put_u32(nid)
			_put_xform(b, rb.global_transform)
			Net.broadcast(MSG_SETTLE, b.data_array, Net.RELIABLE))


# --- Sync -------------------------------------------------------------------

## Host: write the awake synced bodies. To keep a big collapse inside a
## bandwidth budget, each snapshot carries at most MAX_BODIES_PER_SNAPSHOT
## bodies, chosen by a priority that grows every snapshot a body is skipped
## (faster bodies grow faster). Positions are quantised to 1/64 m and
## rotations use "smallest three" quaternion packing: 15 bytes a body.
const MAX_BODIES_PER_SNAPSHOT := 110
const POS_SCALE := 64.0
var _priority := {}
var awake_total := 0

func _write_snapshot(b: StreamPeerBuffer) -> void:
	var start := b.get_position()
	var awake: Array = []
	for nid in bodies:
		var rb: RigidBody3D = bodies[nid]
		if is_instance_valid(rb) and not rb.sleeping:
			_priority[nid] = _priority.get(nid, 0.0) + 1.0 + rb.linear_velocity.length() + rb.angular_velocity.length() * 0.3
			awake.append(nid)
	awake_total = awake.size()
	if awake.size() > MAX_BODIES_PER_SNAPSHOT:
		awake.sort_custom(func(x, y): return _priority[x] > _priority[y])
		awake.resize(MAX_BODIES_PER_SNAPSHOT)
	b.put_u16(awake.size())
	for nid in awake:
		var rb: RigidBody3D = bodies[nid]
		_priority[nid] = 0.0
		b.put_u32(nid)
		_put_qpos(b, rb.global_position)
		_put_qquat(b, rb.global_transform.basis.get_rotation_quaternion())
	synced_awake = awake_total
	bytes_per_snapshot = b.get_position() - start


func _read_snapshot(b: StreamPeerBuffer, server_time: float) -> void:
	var n := b.get_u16()
	synced_awake = n
	for i in n:
		var nid := b.get_u32()
		var pos := _get_qpos(b)
		var q := _get_qquat(b)
		if not bodies.has(nid):
			continue
		var buf: Array = _buffers.get(nid, [])
		buf.append([server_time, pos, q])
		while buf.size() > 20:
			buf.pop_front()
		_buffers[nid] = buf


func _interpolate() -> void:
	if sync == null:
		return
	var rt := sync.render_time()
	for nid in _buffers.keys():
		var rb: RigidBody3D = bodies.get(nid)
		var buf: Array = _buffers[nid]
		if rb == null or not is_instance_valid(rb):
			_buffers.erase(nid)
			continue
		while buf.size() >= 3 and buf[1][0] <= rt:
			buf.pop_front()
		if buf.size() >= 2 and buf[0][0] <= rt:
			var t: float = clamp((rt - buf[0][0]) / max(buf[1][0] - buf[0][0], 0.0001), 0.0, 1.0)
			rb.global_transform = Transform3D(Basis((buf[0][2] as Quaternion).slerp(buf[1][2], t)), (buf[0][1] as Vector3).lerp(buf[1][1], t))
		elif buf.size() >= 1:
			rb.global_transform = Transform3D(Basis(buf[0][2]), buf[0][1])


func _on_settle_msg(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var nid := b.get_u32()
	var xf := _get_xform(b)
	_buffers.erase(nid)
	if bodies.has(nid) and is_instance_valid(bodies[nid]):
		bodies[nid].global_transform = xf


# --- Catch-up and saving (Phase 1.7) -------------------------------------------

## The block's damage as it is now: every piece no longer standing, and where
## each big chunk and falling piece is. Sent to a friend who joins late, and
## what the host saves. Small cosmetic chunks are not kept.
func write_state(b: StreamPeerBuffer) -> void:
	var lost: Array = pieces.values().filter(func(p): return p.state != "intact")
	b.put_u32(lost.size())
	for p in lost:
		b.put_u32(p.id)
	var live: Array = bodies.keys().filter(func(n): return is_instance_valid(bodies[n]))
	b.put_u32(live.size())
	for nid in live:
		b.put_u32(nid)
		_put_xform(b, (bodies[nid] as RigidBody3D).global_transform)


## Brings this machine's block to a written state. On the host (loading a
## save) the chunks are real bodies, asleep where they lay; on a client they
## are proxies the host's snapshots move.
func read_state(b: StreamPeerBuffer) -> void:
	for i in b.get_u32():
		var id := b.get_u32()
		var p: Dictionary = pieces.get(id, {})
		if p.is_empty() or p.state != "intact":
			continue
		p.state = "gone"
		if is_instance_valid(p.node):
			p.node.queue_free()
		piece_broken.emit(id)
		_stability_dirty = true
	for i in b.get_u32():
		var nid := b.get_u32()
		var xf := _get_xform(b)
		if bodies.has(nid) and is_instance_valid(bodies[nid]):
			_buffers.erase(nid)
			bodies[nid].global_transform = xf
			continue
		var p: Dictionary = pieces.get(nid / 64, {})
		if p.is_empty():
			continue
		_restore_body(p, nid % 64, xf)


func _restore_body(p: Dictionary, k: int, xf: Transform3D) -> void:
	var kit := KitLibrary.get_piece(p.kind)
	var rb: RigidBody3D
	var nid: int = p.id * 64 + k
	if k == RELEASED_BIT:
		var shapes: Array = []
		var vol := 0.0
		for ch in kit.chunks:
			shapes.append([ch.shape, ch.offset])
			vol += ch.volume
		rb = _make_body(kit.mesh, shapes, vol * DENSITY)
		KitLibrary.tint(rb.get_child(0), kit.surfaces, p.tint)
		rb.collision_layer = FALLING_LAYER
		rb.set_meta("released_piece", p.id)
		p.state = "released"
		if Net.is_host():
			rb.contact_monitor = true
			rb.max_contacts_reported = 6
			rb.body_entered.connect(_on_released_hit.bind(rb, p.id))
			rb.set_meta("age", SHATTER_GRACE_STEPS)
	else:
		if k >= kit.chunks.size():
			return
		var ch: Dictionary = kit.chunks[k]
		rb = _make_body(ch.mesh, [[ch.shape, Vector3.ZERO]], ch.volume * DENSITY)
		KitLibrary.tint(rb.get_child(0), ch.surfaces, p.tint)
	rb.set_meta("surface", surface_for(p.kind))
	rb.set_meta("net_id", nid)
	rb.transform = xf
	bodies[nid] = rb
	if not Net.is_host():
		_make_proxy(rb)
	add_child(rb)
	if Net.is_host():
		rb.sleeping = true
		_watch_sleep(rb, nid)


## Final resting transforms of every synced body, for tests and debugging.
func rest_report() -> Dictionary:
	var out := {}
	for nid in bodies:
		if is_instance_valid(bodies[nid]):
			out[nid] = bodies[nid].global_position
	return out


# --- Effects ------------------------------------------------------------------

func _send_fx(kind: int, at: Vector3, normal := Vector3.UP) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(kind)
	_put_v3(b, at)
	_put_v3(b, normal)
	Net.broadcast(MSG_FX, b.data_array, Net.UNRELIABLE)
	b.seek(0)
	_play_fx(b)


func _on_fx_msg(_from: int, data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_play_fx(b)


signal fx(kind: int, at: Vector3, normal: Vector3)

func _play_fx(b: StreamPeerBuffer) -> void:
	var kind := b.get_u8()
	var at := _get_v3(b)
	var n := _get_v3(b)
	fx.emit(kind, at, n)
	if DisplayServer.get_name() == "headless":
		return
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.35) if kind == 0 else Color(1, 0.9, 0.6)
	flash.light_energy = 8.0 if kind == 0 else 1.5
	flash.omni_range = 8.0 if kind == 0 else 1.5
	flash.position = at + n * 0.2
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.25 if kind == 0 else 0.06)
	tw.tween_callback(flash.queue_free)
	var parts := CPUParticles3D.new()
	parts.one_shot = true
	parts.explosiveness = 1.0
	parts.amount = 60 if kind == 0 else 10
	parts.lifetime = 1.2 if kind == 0 else 0.4
	parts.direction = n
	parts.spread = 80.0 if kind == 0 else 35.0
	parts.initial_velocity_min = 3.0
	parts.initial_velocity_max = 9.0 if kind == 0 else 4.0
	parts.gravity = Vector3(0, -9.8, 0)
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE * (0.12 if kind == 0 else 0.04)
	pm.material = Cel.material(Color(0.55, 0.52, 0.48), false)
	parts.mesh = pm
	parts.position = at
	add_child(parts)
	parts.emitting = true
	get_tree().create_timer(2.0).timeout.connect(parts.queue_free)


# --- Encoding -------------------------------------------------------------------

static func _put_v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _get_v3(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_float(), b.get_float(), b.get_float())


static func _put_quat(b: StreamPeerBuffer, q: Quaternion) -> void:
	q = q.normalized()
	b.put_16(int(q.x * 32767.0))
	b.put_16(int(q.y * 32767.0))
	b.put_16(int(q.z * 32767.0))
	b.put_16(int(q.w * 32767.0))


static func _get_quat(b: StreamPeerBuffer) -> Quaternion:
	return Quaternion(b.get_16() / 32767.0, b.get_16() / 32767.0, b.get_16() / 32767.0, b.get_16() / 32767.0).normalized()


static func _put_qpos(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_16(clampi(roundi(v.x * POS_SCALE), -32768, 32767))
	b.put_16(clampi(roundi(v.y * POS_SCALE), -32768, 32767))
	b.put_16(clampi(roundi(v.z * POS_SCALE), -32768, 32767))


static func _get_qpos(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_16(), b.get_16(), b.get_16()) / POS_SCALE


## Smallest-three: drop the largest component (rebuilt from unit length),
## store its index in 1 byte and the other three in 16 bits each.
static func _put_qquat(b: StreamPeerBuffer, q: Quaternion) -> void:
	q = q.normalized()
	var c := [q.x, q.y, q.z, q.w]
	var big := 0
	for i in 4:
		if absf(c[i]) > absf(c[big]):
			big = i
	var sgn := 1.0 if c[big] >= 0.0 else -1.0
	b.put_u8(big)
	for i in 4:
		if i != big:
			b.put_16(roundi(c[i] * sgn * 32767.0 * 1.41421356))


static func _get_qquat(b: StreamPeerBuffer) -> Quaternion:
	var big := b.get_u8()
	var c := [0.0, 0.0, 0.0, 0.0]
	var sum := 0.0
	for i in 4:
		if i != big:
			c[i] = b.get_16() / (32767.0 * 1.41421356)
			sum += c[i] * c[i]
	c[big] = sqrt(maxf(0.0, 1.0 - sum))
	return Quaternion(c[0], c[1], c[2], c[3]).normalized()


static func _put_xform(b: StreamPeerBuffer, xf: Transform3D) -> void:
	_put_v3(b, xf.origin)
	var q := xf.basis.get_rotation_quaternion()
	b.put_float(q.x)
	b.put_float(q.y)
	b.put_float(q.z)
	b.put_float(q.w)


static func _get_xform(b: StreamPeerBuffer) -> Transform3D:
	var o := _get_v3(b)
	var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
	return Transform3D(Basis(q), o)
