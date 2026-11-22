extends Node
## Phase 1.7 drop-in check, the part that runs inside the game (see
## late_join.gd).

const PORT := 27993
var role := ""
var out := ""
var t := 0.0
var step := 0
var report := {"radio": []}


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	out = a[1]
	if role == "host":
		Net.host(PORT)
		Block.next_seed = 4242
		get_tree().change_scene_to_file("res://prototypes/p08_block/block.tscn")


func _scene() -> Node:
	return get_tree().current_scene


func _ready_block() -> bool:
	var s := _scene()
	return s != null and s.get("state") != null and PropWorld.current != null


func _process(delta: float) -> void:
	t += delta
	if t > 90.0:
		report["timeout"] = step
		_write()
		get_tree().quit()
		return
	match role:
		"host": _host()
		"late": _late()
		"other": _other()


func _host() -> void:
	var s := _scene()
	if step == 0 and _ready_block() and t > 3.0:
		(s.dispatch as Dispatcher).enabled = false
		(s.dispatch as Dispatcher).radio.connect(func(x): report.radio.append(x))
		var gen: BlockGenerator = s.gen
		var b: Dictionary = gen.buildings[0]
		var w: DestructionWorld = s.world
		w.explode((b.origin as Vector3) + Vector3(1.0, 1.0, 0.0), 3.5, 400.0, 6.0)
		var pw := PropWorld.current
		var n := 0
		for p in pw.props.values():
			if p.kind in ["chair", "crate", "table"] and n < 6:
				pw.break_prop(p.id)
				n += 1
		var cs: CarSync = s.cars
		cs.cars[0].apply_dent(Vector3(0.9, 0.3, 0.5), Vector3.LEFT, 0.25)
		cs.damage_car(cs.cars[1], 500.0)
		step = 1
		t = 0.0
	elif step == 1 and Net.slots.size() >= 3:
		step = 2
		t = 0.0
	elif step == 2 and t > 3.0:
		_snapshot()
		step = 3
	elif step == 3 and Net.slots.size() == 2:
		step = 4
		t = 0.0
	elif step == 4 and t > 2.0:
		# The late joiner has looked and left.
		report["pawns_after_leave"] = (s.sync as PawnSync).pawns.size()
		_write()
		get_tree().quit()


func _late() -> void:
	if step == 0 and t > 8.0:
		Net.join("127.0.0.1", PORT)
		step = 1
	elif step == 1 and _ready_block() and _scene().state.has_meta("got"):
		step = 2
		t = 0.0
	elif step == 1 and _ready_block() and not _scene().state.caught_up.is_connected(_on_caught_up):
		_scene().state.caught_up.connect(_on_caught_up)
	elif step == 2 and t > 6.0:
		_snapshot()
		_write()
		Net.leave()
		get_tree().quit()


func _on_caught_up() -> void:
	_scene().state.set_meta("got", true)


func _other() -> void:
	if step == 0 and t > 8.0:
		Net.join("127.0.0.1", PORT)
		step = 1
	elif step == 1 and _ready_block():
		step = 2
	elif step == 2 and _scene() and _scene().scene_file_path == "res://game/ui/main_menu.tscn":
		report["menu"] = true
		report["notice_seen"] = true
		_write()
		get_tree().quit()


func _snapshot() -> void:
	var s := _scene()
	var w: DestructionWorld = s.world
	var lost := []
	for p in w.pieces.values():
		if p.state != "intact":
			lost.append(p.id)
	lost.sort()
	report["lost"] = lost
	var bodies := {}
	for nid in w.bodies:
		if is_instance_valid(w.bodies[nid]):
			var v: Vector3 = w.bodies[nid].global_position
			bodies[str(nid)] = [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]
	report["bodies"] = bodies
	var broken := []
	for p in PropWorld.current.props.values():
		if p.broken:
			broken.append(p.id)
	broken.sort()
	report["props_broken"] = broken
	var cs: CarSync = s.cars
	report["car_fire"] = [cs.fire_state.get(0, 0), cs.fire_state.get(1, 0)]
	report["car_dents"] = [cs.cars[0].dent_log.size(), cs.cars[1].dent_log.size()]
	report["car1_wrecked"] = cs.cars[1].wrecked


func _write() -> void:
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report))
	f.close()
