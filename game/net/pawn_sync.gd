class_name PawnSync
extends Node
## Host-authoritative player movement with client prediction and
## interpolation, shared by every Wave 0 prototype that has officers.
##
## Clients send their input commands to the host every physics tick (with the
## last few repeated so a lost packet does not lose input). The host simulates
## every pawn and sends a snapshot 20 times a second. Your own pawn is
## predicted: it moves at once, and when a snapshot arrives it is reset to the
## host's state and the inputs the host has not seen yet are replayed. Other
## players' pawns are drawn 100 ms in the past, interpolated between snapshots.
##
## A pawn is any Node3D with these methods:
##   sim_step(cmd: Dictionary, delta: float)   deterministic movement step
##   encode_state(b: StreamPeerBuffer)         write full state
##   decode_state(b: StreamPeerBuffer) -> Dictionary
##   apply_state(s: Dictionary)                snap to a decoded state
##   blend_state(a: Dictionary, b: Dictionary, t: float) -> Dictionary
##   set_visual_offset(v: Vector3)             cosmetic smoothing of corrections

signal pawn_spawned(peer_id: int, pawn: Node3D)

const MSG_INPUT := 16
const MSG_SNAPSHOT := 17
const SNAPSHOT_EVERY := 3      # physics ticks (60 Hz / 3 = 20 Hz)
const INTERP_DELAY := 0.1      # seconds
const REDUNDANT_INPUTS := 4

## Callable(peer_id: int) -> Node3D: makes a pawn (not yet in the tree).
var pawn_factory: Callable
## Callable() -> Dictionary with move: Vector2 (world x/z), buttons: int, aim_yaw: float
var input_source: Callable
## Parent node for pawns.
var pawn_parent: Node
## Extra snapshot payload hooks (e.g. destruction chunks): host writes, clients read.
var extra_writers: Array[Callable] = []
var extra_readers: Array[Callable] = []

var pawns := {}            # peer id -> pawn
var tick := 0
var prediction_errors := 0
var last_correction := 0.0

var _seq := 0
var _pending: Array = []   # client: unacknowledged commands
var _queues := {}          # host: peer id -> Array of commands
var _last_cmd := {}        # host: peer id -> last command used
var _last_seq := {}        # host: peer id -> last processed seq
var _buffers := {}         # client: peer id -> Array of [server_time, state]
var _render_time := -1.0
var _visual_error := Vector3.ZERO


func _ready() -> void:
	Net.register(MSG_INPUT, _on_input)
	Net.register(MSG_SNAPSHOT, _on_snapshot)
	Net.lobby_changed.connect(_sync_pawns)
	_sync_pawns.call_deferred()


func _exit_tree() -> void:
	Net.unregister(MSG_INPUT)
	Net.unregister(MSG_SNAPSHOT)


func my_pawn() -> Node3D:
	return pawns.get(Net.my_id())


func _sync_pawns() -> void:
	if not is_inside_tree():
		return
	var ids := Net.player_ids()
	for id in ids:
		if not pawns.has(id):
			var p: Node3D = pawn_factory.call(id)
			p.name = "Pawn%d" % id
			pawn_parent.add_child(p)
			pawns[id] = p
			pawn_spawned.emit(id, p)
	for id in pawns.keys():
		if not ids.has(id):
			pawns[id].queue_free()
			pawns.erase(id)
			_queues.erase(id)
			_buffers.erase(id)


func _physics_process(delta: float) -> void:
	tick += 1
	var cmd: Dictionary = input_source.call() if input_source.is_valid() else {}
	cmd["seq"] = _seq
	_seq += 1
	var mine := my_pawn()
	if Net.is_host():
		if mine:
			mine.sim_step(cmd, delta)
		for id in pawns:
			if id == Net.my_id():
				continue
			var q: Array = _queues.get(id, [])
			while q.size() > 6:  # fell behind: drop the oldest to catch up
				q.pop_front()
			var c: Dictionary = q.pop_front() if not q.is_empty() else _last_cmd.get(id, {})
			if not c.is_empty():
				_last_cmd[id] = c
				_last_seq[id] = c.seq
			pawns[id].sim_step(c, delta)
		if tick % SNAPSHOT_EVERY == 0 and Net.is_online():
			_send_snapshot()
	else:
		if mine:
			mine.sim_step(cmd, delta)
		_pending.append(cmd)
		if _pending.size() > 120:
			_pending.pop_front()
		_send_inputs()
		_interpolate(delta)
	if mine:
		_visual_error = _visual_error.lerp(Vector3.ZERO, 1.0 - exp(-15.0 * delta))
		mine.set_visual_offset(_visual_error)


# --- Client to host: input --------------------------------------------------

static func encode_cmd(b: StreamPeerBuffer, c: Dictionary) -> void:
	b.put_u32(c.seq)
	var m: Vector2 = c.get("move", Vector2.ZERO)
	b.put_half(m.x)
	b.put_half(m.y)
	b.put_u16(c.get("buttons", 0))
	b.put_half(c.get("aim_yaw", 0.0))
	var ap: Vector3 = c.get("aim_point", Vector3.ZERO)
	b.put_float(ap.x)
	b.put_float(ap.y)
	b.put_float(ap.z)


static func decode_cmd(b: StreamPeerBuffer) -> Dictionary:
	var c := {}
	c.seq = b.get_u32()
	c.move = Vector2(b.get_half(), b.get_half())
	c.buttons = b.get_u16()
	c.aim_yaw = b.get_half()
	c.aim_point = Vector3(b.get_float(), b.get_float(), b.get_float())
	return c


func _send_inputs() -> void:
	var b := StreamPeerBuffer.new()
	var n: int = min(REDUNDANT_INPUTS, _pending.size())
	b.put_u8(n)
	for i in range(_pending.size() - n, _pending.size()):
		encode_cmd(b, _pending[i])
	Net.send(1, MSG_INPUT, b.data_array, Net.UNRELIABLE, 2)


func _on_input(from: int, data: PackedByteArray) -> void:
	if not Net.is_host() or not pawns.has(from):
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var n := b.get_u8()
	var q: Array = _queues.get(from, [])
	var newest: int = q.back().seq if not q.is_empty() else _last_seq.get(from, -1)
	for i in n:
		var c := decode_cmd(b)
		if c.seq > newest:
			q.append(c)
			newest = c.seq
	_queues[from] = q


# --- Host to clients: snapshots ---------------------------------------------

func _send_snapshot() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u32(tick)
	b.put_u8(pawns.size())
	for id in pawns:
		b.put_u32(id)
		b.put_u32(_last_seq.get(id, 0))
		pawns[id].encode_state(b)
	for w in extra_writers:
		w.call(b)
	Net.broadcast(MSG_SNAPSHOT, b.data_array, Net.ORDERED, 1)
	Net.count("snapshots")


func _on_snapshot(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	Net.count("snapshots")
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var server_tick := b.get_u32()
	var server_time := server_tick / float(Engine.physics_ticks_per_second)
	var n := b.get_u8()
	for i in n:
		var id := b.get_u32()
		var acked := b.get_u32()
		var p: Node3D = pawns.get(id)
		if p == null:
			# Unknown pawn (lobby not synced yet): we still must consume its bytes.
			p = pawn_factory.call(id)
			p.decode_state(b)
			p.free()
			continue
		var s: Dictionary = p.decode_state(b)
		if id == Net.my_id():
			_reconcile(p, s, acked)
		else:
			var buf: Array = _buffers.get(id, [])
			buf.append([server_time, s])
			while buf.size() > 30:
				buf.pop_front()
			_buffers[id] = buf
	for r in extra_readers:
		r.call(b, server_time)
	var target := server_time - INTERP_DELAY
	if _render_time < 0.0 or absf(_render_time - target) > 0.25:
		_render_time = target


func render_time() -> float:
	return _render_time


func _reconcile(p: Node3D, s: Dictionary, acked: int) -> void:
	var before: Vector3 = p.global_position
	p.apply_state(s)
	while not _pending.is_empty() and _pending[0].seq <= acked:
		_pending.pop_front()
	var dt := 1.0 / Engine.physics_ticks_per_second
	for c in _pending:
		p.sim_step(c, dt)
	var err := before - p.global_position
	last_correction = err.length()
	if last_correction > 0.02:
		prediction_errors += 1
	if last_correction > 2.0:
		_visual_error = Vector3.ZERO  # teleport, do not smooth
	else:
		_visual_error += err


func _interpolate(delta: float) -> void:
	if _render_time < 0.0:
		return
	_render_time += delta
	for id in _buffers:
		var p: Node3D = pawns.get(id)
		var buf: Array = _buffers[id]
		if p == null or buf.is_empty():
			continue
		while buf.size() >= 3 and buf[1][0] <= _render_time:
			buf.pop_front()
		if buf.size() >= 2 and buf[0][0] <= _render_time:
			var a: Array = buf[0]
			var c: Array = buf[1]
			var t: float = clamp((_render_time - a[0]) / max(c[0] - a[0], 0.0001), 0.0, 1.0)
			p.apply_state(p.blend_state(a[1], c[1], t))
		else:
			p.apply_state(buf[0][1])
