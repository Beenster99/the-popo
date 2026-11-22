extends Node
## Driven by net_probe.gd; see there.

var role: String
var port: int
var t := 0.0
var phase := "connect"
var sync: PawnSync
var start_x := 0.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	port = int(a[1])
	# Both processes add fake delay, so each takes half the requested round trip.
	Net.sim_latency_ms = float(a[2]) * 0.5
	Net.sim_loss = float(a[3])
	Net.player_name = role
	if role == "host":
		Net.host(port)
	else:
		Net.join("127.0.0.1", port)


func _find_sync() -> PawnSync:
	if get_tree().current_scene == null:
		return null
	for c in get_tree().current_scene.get_children():
		if c is PawnSync:
			return c
	return null


func _physics_process(_d: float) -> void:
	t += 1.0 / 60.0
	if t > 25.0:
		print("TIMEOUT ", role, " ", phase)
		get_tree().quit(2)
	match phase:
		"connect":
			if role == "host" and Net.slots.size() == 2:
				Net.load_scene_for_all("res://prototypes/p02_netroom/netroom.tscn")
				phase = "play"
			elif role == "client" and _find_sync() != null:
				phase = "play"
		"play":
			sync = _find_sync()
			if sync == null or sync.pawns.size() < 2:
				return
			if role == "client":
				# Walk for the first 2 s of the "wait" phase (t is reset below).
				sync.input_source = func(): return {"move": Vector2(1, 0) if t < 2.0 else Vector2.ZERO, "buttons": 0, "aim_yaw": 0.0}
			var cid: int = Net.my_id() if role == "client" else Net.player_ids().filter(func(i): return i != 1)[0]
			start_x = sync.pawns[cid].global_position.x
			phase = "wait"
			t = 0.0
		"wait":
			if t > 5.0:
				var id: int = Net.my_id() if role == "client" else Net.player_ids().filter(func(i): return i != 1)[0]
				var p: Node3D = sync.pawns[id]
				print("RESULT %.3f %.3f %.3f corrections=%d" % [p.global_position.x, p.global_position.z, p.global_position.x - start_x, sync.prediction_errors])
				phase = "done"
				t = 0.0
		"done":
			if t > 1.0:
				get_tree().quit(0)
