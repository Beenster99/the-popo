extends Node
## Two-process collapse test (see run_collapse_test.sh). The host knocks out
## the ground-floor west wall of the first shop. After the rubble settles,
## both sides print every synced body's position; the script compares them.

var role: String
var phase := "connect"
var t := 0.0
var world: DestructionWorld


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	Net.sim_latency_ms = float(a[2])
	Net.sim_loss = float(a[3])
	if role == "host":
		Net.host(int(a[1]))
	else:
		Net.join("127.0.0.1", int(a[1]))


func _physics_process(delta: float) -> void:
	t += delta
	if t > 40.0:
		print("TIMEOUT ", phase)
		get_tree().quit(2)
	match phase:
		"connect":
			if role == "host" and Net.slots.size() == 2:
				Net.load_scene_for_all("res://prototypes/p03_destruction/destruction.tscn")
				phase = "wait_scene"
			elif role == "client" and get_tree().current_scene and get_tree().current_scene.has_method("_on_fired"):
				phase = "wait_scene"
		"wait_scene":
			var s := get_tree().current_scene
			if s and s.get("world") != null:
				world = s.world
				phase = "settle_in"
				t = 0.0
		"settle_in":
			if t > 2.0:
				if role == "host":
					world.damage_piece(1, 9999.0, Vector3(-11, 1.5, -2), 3.0)
				phase = "collapse"
				t = 0.0
		"collapse":
			if t > 15.0:
				var r := world.rest_report()
				var out := []
				for nid in r:
					out.append("%d:%.3f,%.3f,%.3f" % [nid, r[nid].x, r[nid].y, r[nid].z])
				print("BODIES ", " ".join(out))
				phase = "done"
				t = 0.0
		"done":
			if t > 1.0:
				get_tree().quit(0)
