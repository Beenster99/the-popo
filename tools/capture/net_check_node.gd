extends Node
## Phase 1.5 network check, the part that runs inside the game (see
## net_check.gd).

const PORT := 27991
var role := ""
var out := ""
var t := 0.0
var step := 0
var scene: Node
var report := {}


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	out = a[1]
	if role == "host":
		Net.host(PORT)
	else:
		Net.join("127.0.0.1", PORT)


func _props() -> PropWorld:
	return PropWorld.current


func _process(delta: float) -> void:
	t += delta
	if t > 60.0:
		report["timeout"] = true
		_write()
		get_tree().quit()
		return
	if role == "host":
		if step == 0 and Net.slots.size() >= 2:
			Net.load_scene_for_all("res://prototypes/p08_block/block.tscn")
			step = 1
			t = 0.0
		elif step == 1 and t > 6.0 and _props() and FireSystem.current:
			var pw := _props()
			var chair: Dictionary = pw.props.values().filter(func(p): return p.kind == "chair")[0]
			var crate: Dictionary = pw.props.values().filter(func(p): return p.kind == "crate")[0]
			(chair.body as RigidBody3D).sleeping = false
			(chair.body as RigidBody3D).linear_velocity = Vector3(3, 1, 0)
			pw.break_prop(crate.id, (crate.body as Node3D).global_position, Vector3.UP)
			FireSystem.current.ignite(Vector3(30, BlockGenerator.BASE_Y, 30), 1.0, 30.0)
			var cs: CarSync = get_tree().current_scene.get("cars")
			cs.damage_car(cs.cars[0], 200.0)
			report["chair"] = chair.id
			report["crate"] = crate.id
			step = 2
			t = 0.0
		elif step == 2 and t > 4.0:
			_snapshot()
			step = 3
			t = 0.0
		elif step == 3 and t > 6.0:
			_write()
			get_tree().quit()
	else:
		if step == 0 and _props() and FireSystem.current and get_tree().current_scene and get_tree().current_scene.get("cars"):
			step = 1
			t = 0.0
		elif step == 1 and t > 14.0:
			_snapshot()
			_write()
			get_tree().quit()


func _snapshot() -> void:
	var pw := _props()
	var pos := {}
	var broken := []
	for p in pw.props.values():
		if p.broken:
			broken.append(p.id)
		elif p.kind == "chair":
			var v: Vector3 = (p.body as Node3D).global_position
			pos[str(p.id)] = [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
	report["count"] = pw.props.size()
	report["broken"] = broken
	report["chairs"] = pos
	report["fires"] = FireSystem.current.fires.size()
	var cs: CarSync = get_tree().current_scene.get("cars")
	report["car0"] = cs.fire_state.get(0, 0)


func _write() -> void:
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report))
	f.close()
