extends Node
## Transport for every networked prototype.
##
## Friends join the host directly by address and port (ENet). The host is
## authoritative. Up to 3 players in total: the host plus two clients.
##
## All game traffic goes through send()/broadcast() as raw byte messages whose
## first byte is a message type. That lets us add fake latency, jitter and
## packet loss in one place and count every byte for the debug overlay.
## With no connection the game runs offline as the host (peer id 1), using the
## same code paths, so every prototype also works single player.

signal lobby_changed
signal joined
signal join_failed(reason: String)
signal left
signal scene_requested(path: String)
## A client lost the host (it quit, or the connection dropped).
signal host_lost(reason: String)

## Why the last game ended, for the main menu to show once (Phase 1.7).
var last_notice := ""
## ENet gives up on a silent peer after this long (ms), instead of 30 s.
const TIMEOUT_MIN_MS := 4000
const TIMEOUT_MAX_MS := 10000

const MAX_PLAYERS := 3
const DEFAULT_PORT := 27015
const PROTOCOL := 1

## Message types 0-15 are reserved for Net itself; prototypes use 16+.
enum { MSG_HELLO = 1, MSG_LOBBY, MSG_PING, MSG_PONG, MSG_LOAD_SCENE, MSG_KICK }

const RELIABLE := MultiplayerPeer.TRANSFER_MODE_RELIABLE
const UNRELIABLE := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
const ORDERED := MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED

## Fake network conditions, applied to this machine's sends and receives.
## Round-trip latency in ms is split half on the way out, half on the way in,
## so setting it on one machine gives that machine the full round trip.
var sim_latency_ms := 0.0
var sim_jitter_ms := 0.0
var sim_loss := 0.0  # 0..1, unreliable packets only

var player_name := "Officer"
## Lobby slots, index 0 is the host: [{id:int, name:String}]
var slots: Array = []

var _handlers := {}
var _out_queue: Array = []
var _in_queue: Array = []
var _last_reliable_out := 0.0
var _last_reliable_in := 0.0

# Stats for the overlay
var kbps_in := 0.0
var kbps_out := 0.0
var packets_in_per_s := 0
var packets_out_per_s := 0
var ping_ms := {}  # peer id -> smoothed round trip
var _bytes_in := 0
var _bytes_out := 0
var _pk_in := 0
var _pk_out := 0
var _stat_t := 0.0
var _ping_t := 0.0
var _counters := {}  # name -> [count this window, rate last window]


## Opens the game port on the router while hosting (see PortOpener).
var port_opener := PortOpener.new()


func _ready() -> void:
	add_child(port_opener)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach the host."))
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	multiplayer.peer_packet.connect(_on_peer_packet)
	register(MSG_HELLO, _on_hello)
	register(MSG_LOBBY, _on_lobby)
	register(MSG_PING, _on_ping)
	register(MSG_PONG, _on_pong)
	register(MSG_LOAD_SCENE, _on_load_scene)
	register(MSG_KICK, func(_from, data): _fail(data.get_string_from_utf8()))
	_reset_offline_slots()


# --- Session -----------------------------------------------------------------

func host(port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1, 4)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	slots = [{"id": 1, "name": player_name}]
	lobby_changed.emit()
	return OK


func join(address: String, port: int = DEFAULT_PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port, 4)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func leave() -> void:
	var was_online := is_online()
	if multiplayer.multiplayer_peer and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_out_queue.clear()
	_in_queue.clear()
	ping_ms.clear()
	_reset_offline_slots()
	if port_opener and port_opener.state != "idle":
		port_opener.close()
	if was_online:
		left.emit()


func is_online() -> bool:
	return multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer


func is_host() -> bool:
	return multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func player_ids() -> Array:
	return slots.map(func(s): return s.id)


## Host only: tell everyone (including itself) to load a scene.
func load_scene_for_all(path: String) -> void:
	assert(is_host())
	broadcast(MSG_LOAD_SCENE, path.to_utf8_buffer(), RELIABLE)
	_on_load_scene(1, path.to_utf8_buffer())


# --- Messages ----------------------------------------------------------------

func register(msg_type: int, handler: Callable) -> void:
	_handlers[msg_type] = handler


func unregister(msg_type: int) -> void:
	_handlers.erase(msg_type)


## Send to one peer. Sending to yourself is delivered locally at once.
func send(to: int, msg_type: int, data: PackedByteArray, mode := RELIABLE, channel := 0) -> void:
	var bytes := PackedByteArray([msg_type])
	bytes.append_array(data)
	if to == my_id():
		_dispatch(to, bytes)
		return
	if not is_online():
		return
	_queue_out(to, bytes, mode, channel)


## Send to every other peer (not yourself).
func broadcast(msg_type: int, data: PackedByteArray, mode := RELIABLE, channel := 0) -> void:
	if not is_online():
		return
	var bytes := PackedByteArray([msg_type])
	bytes.append_array(data)
	if is_host():
		for id in multiplayer.get_peers():
			_queue_out(id, bytes, mode, channel)
	else:
		_queue_out(1, bytes, mode, channel)


## Count an event for the overlay, e.g. Net.count("snapshots").
func count(counter: String) -> void:
	if not _counters.has(counter):
		_counters[counter] = [0, 0]
	_counters[counter][0] += 1


func rate(counter: String) -> int:
	return _counters[counter][1] if _counters.has(counter) else 0


func rtt_ms() -> float:
	if is_host():
		var worst := 0.0
		for v in ping_ms.values():
			worst = max(worst, v)
		return worst
	return ping_ms.get(1, 0.0)


func _queue_out(to: int, bytes: PackedByteArray, mode: int, channel: int) -> void:
	var now := _now()
	if mode != RELIABLE and sim_loss > 0.0 and randf() < sim_loss:
		return
	var delay := _one_way_delay()
	if delay <= 0.0:
		_raw_send(to, bytes, mode, channel)
		return
	var t := now + delay
	if mode == RELIABLE:
		t = max(t, _last_reliable_out)
		_last_reliable_out = t
	_out_queue.append({"t": t, "to": to, "bytes": bytes, "mode": mode, "ch": channel})


func _raw_send(to: int, bytes: PackedByteArray, mode: int, channel: int) -> void:
	if not is_online():
		return
	if to != 0 and not multiplayer.get_peers().has(to):
		return
	multiplayer.send_bytes(bytes, to, mode, channel)
	_bytes_out += bytes.size() + 28  # rough UDP+IP+ENet header
	_pk_out += 1


func _on_peer_packet(from: int, bytes: PackedByteArray) -> void:
	_bytes_in += bytes.size() + 28
	_pk_in += 1
	var delay := _one_way_delay()
	if delay <= 0.0:
		_dispatch(from, bytes)
		return
	# Loss is only applied on the way out (where we know the transfer mode).
	# Inbound delay keeps arrival order so reliable messages stay in order.
	var t: float = max(_now() + delay, _last_reliable_in)
	_last_reliable_in = t
	_in_queue.append({"t": t, "from": from, "bytes": bytes})


func _dispatch(from: int, bytes: PackedByteArray) -> void:
	if bytes.is_empty():
		return
	var h: Variant = _handlers.get(bytes[0])
	if h is Callable and (h as Callable).is_valid():
		(h as Callable).call(from, bytes.slice(1))


func _one_way_delay() -> float:
	if sim_latency_ms <= 0.0 and sim_jitter_ms <= 0.0:
		return 0.0
	return (sim_latency_ms * 0.5 + randf() * sim_jitter_ms * 0.5) / 1000.0


func _now() -> float:
	return Time.get_ticks_usec() / 1_000_000.0


func _process(delta: float) -> void:
	var now := _now()
	if not _out_queue.is_empty():
		var keep: Array = []
		for p in _out_queue:
			if p.t <= now:
				_raw_send(p.to, p.bytes, p.mode, p.ch)
			else:
				keep.append(p)
		_out_queue = keep
	if not _in_queue.is_empty():
		var keep_in: Array = []
		for p in _in_queue:
			if p.t <= now:
				_dispatch(p.from, p.bytes)
			else:
				keep_in.append(p)
		_in_queue = keep_in

	_stat_t += delta
	if _stat_t >= 1.0:
		kbps_in = _bytes_in * 8.0 / 1000.0 / _stat_t
		kbps_out = _bytes_out * 8.0 / 1000.0 / _stat_t
		packets_in_per_s = _pk_in
		packets_out_per_s = _pk_out
		_bytes_in = 0
		_bytes_out = 0
		_pk_in = 0
		_pk_out = 0
		for k in _counters:
			_counters[k][1] = _counters[k][0]
			_counters[k][0] = 0
		_stat_t = 0.0

	if is_online():
		_ping_t += delta
		if _ping_t >= 0.5:
			_ping_t = 0.0
			var b := StreamPeerBuffer.new()
			b.put_double(now)
			broadcast(MSG_PING, b.data_array, UNRELIABLE, 1)


# --- Lobby -------------------------------------------------------------------

func _reset_offline_slots() -> void:
	slots = [{"id": 1, "name": player_name}]


func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	_set_timeout(id)
	if slots.size() >= MAX_PLAYERS:
		send(id, MSG_KICK, "The game is full (3 players).".to_utf8_buffer())
		get_tree().create_timer(0.5).timeout.connect(func():
			if is_online():
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id))


func _on_peer_disconnected(id: int) -> void:
	ping_ms.erase(id)
	if is_host():
		slots = slots.filter(func(s): return s.id != id)
		_broadcast_lobby()


func _set_timeout(id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet and enet.get_peer(id):
		enet.get_peer(id).set_timeout(0, TIMEOUT_MIN_MS, TIMEOUT_MAX_MS)


func _on_connected_to_server() -> void:
	_set_timeout(1)
	var b := StreamPeerBuffer.new()
	b.put_u16(PROTOCOL)
	b.put_utf8_string(player_name)
	send(1, MSG_HELLO, b.data_array)


func _on_server_disconnected() -> void:
	leave()
	host_lost.emit("Lost the connection to the host.")


func _fail(reason: String) -> void:
	var was_in_game := is_online() and not is_host() and slots.size() > 1
	leave()
	join_failed.emit(reason)
	if was_in_game:
		host_lost.emit(reason)


func _on_hello(from: int, data: PackedByteArray) -> void:
	if not is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var proto := b.get_u16()
	var pname := b.get_utf8_string().strip_edges().left(24)
	if proto != PROTOCOL:
		send(from, MSG_KICK, "Version mismatch: update the game.".to_utf8_buffer())
		return
	if slots.size() >= MAX_PLAYERS:
		return
	if pname.is_empty():
		pname = "Officer %d" % (slots.size() + 1)
	slots.append({"id": from, "name": pname})
	_broadcast_lobby()
	# Late joiner: bring them into whatever prototype the host is running.
	var cur := get_tree().current_scene
	if cur and cur.scene_file_path.begins_with("res://prototypes/p"):
		send(from, MSG_LOAD_SCENE, cur.scene_file_path.to_utf8_buffer(), RELIABLE)


func _broadcast_lobby() -> void:
	broadcast(MSG_LOBBY, var_to_bytes(slots), RELIABLE)
	lobby_changed.emit()


func _on_lobby(_from: int, data: PackedByteArray) -> void:
	if is_host():
		return
	var was_in := slots.any(func(s): return s.id == my_id())
	slots = bytes_to_var(data)
	lobby_changed.emit()
	if not was_in and slots.any(func(s): return s.id == my_id()):
		joined.emit()


func _on_ping(from: int, data: PackedByteArray) -> void:
	send(from, MSG_PONG, data, UNRELIABLE, 1)


func _on_pong(from: int, data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var rtt := (_now() - b.get_double()) * 1000.0
	ping_ms[from] = lerp(ping_ms.get(from, rtt), rtt, 0.3)


func _on_load_scene(from: int, data: PackedByteArray) -> void:
	if from != 1:
		return
	var path := data.get_string_from_utf8()
	if not path.begins_with("res://prototypes/"):
		return
	scene_requested.emit(path)
	get_tree().call_deferred("change_scene_to_file", path)
