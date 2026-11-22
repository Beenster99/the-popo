extends Node
## Phase 1.7 soak test, the part inside the game (see soak.gd).

const PORT := 27995
const MSG_CHECK := 120   # host -> all: write a checkpoint now (index)
const MSG_BYE := 121     # host -> all: done, write your report and quit
var role := ""
var out := ""
var minutes := 20.0
var t := 0.0             # seconds since the block was up (host clock)
var started := false
var report := {"checks": [], "radio": [], "closed": 0, "booked": 0, "rejoins": 0, "events": []}
var _rng := RandomNumberGenerator.new()
var _bot_move := Vector2.ZERO
var _bot_t := 0.0
var _next_check := 60.0
var _check_i := 0
var _acts := {}
var _left_at := -1.0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	out = a[1]
	if a.size() > 2:
		minutes = float(a[2])
	_rng.seed = hash(role)
	Net.register(MSG_CHECK, _on_check)
	Net.register(MSG_BYE, func(_f, _d): _finish())
	if role == "host":
		Net.host(PORT)
		Block.next_seed = 31337
		get_tree().change_scene_to_file("res://prototypes/p08_block/block.tscn")
	else:
		get_tree().create_timer(3.0 if role == "a" else 5.0).timeout.connect(func(): Net.join("127.0.0.1", PORT))


func _scene() -> Node:
	var s := get_tree().current_scene
	return s if s != null and s.get("state") != null and s.get("dispatch") != null else null


func _physics_process(delta: float) -> void:
	var s := _scene()
	if s == null:
		return
	if not s.has_meta("bot"):
		s.set_meta("bot", true)
		(s.sync as PawnSync).input_source = _bot_input.bind(s)
		(s.dispatch as Dispatcher).radio.connect(func(x): report.radio.append([snappedf(t, 0.1), x]))
	if role != "host":
		return
	t += delta
	if not started:
		started = true
	_host_play(s)
	if t >= _next_check:
		_next_check += 60.0
		_check_i += 1
		var b := PackedByteArray([_check_i])
		Net.broadcast(MSG_CHECK, b)
		_on_check(1, b)
	if t >= minutes * 60.0 + 5.0:
		Net.broadcast(MSG_BYE, PackedByteArray())
		get_tree().create_timer(1.0).timeout.connect(_finish)
		set_physics_process(false)


## Wanders about, turning now and then; shoots in short bursts.
func _bot_input(s: Node) -> Dictionary:
	_bot_t -= 1.0 / 60.0
	var o: Officer = (s.sync as PawnSync).my_pawn()
	if _bot_t <= 0.0:
		_bot_t = _rng.randf_range(1.5, 4.0)
		_bot_move = Vector2.from_angle(_rng.randf() * TAU) * (1.0 if _rng.randf() < 0.8 else 0.0)
		if o and o.global_position.distance_to(Vector3(24, 0, 24)) > 26.0:
			var home := Vector2(24 - o.global_position.x, 24 - o.global_position.z)
			_bot_move = home.normalized()
	var buttons := 0
	var yaw := _bot_move.angle() if _bot_move != Vector2.ZERO else 0.0
	if fmod(Time.get_ticks_msec() / 1000.0, 9.0) < 1.2:
		buttons |= PlayerInput.AIM | PlayerInput.FIRE
	if o and o.state == Officer.S.DOWNED and o.state_t > 4.0:
		buttons |= PlayerInput.RELOAD   # respawn
	var aim := (o.global_position + Vector3(cos(yaw), 1.0, sin(yaw)) * 8.0) if o else Vector3.ZERO
	return {"move": _bot_move, "buttons": buttons, "aim_yaw": -yaw + PI * 0.5, "aim_point": aim}


## The host's script: what three players would get up to.
func _host_play(s: Node) -> void:
	var d: Dispatcher = s.dispatch
	var w: DestructionWorld = s.world
	var gen: BlockGenerator = s.gen
	# Calls: once a call has run a while, its suspects are dealt with (booked
	# or put down), so it closes.
	for c in d.active_calls():
		if t - float(_acts.get("call%d" % c.id, t)) > 45.0:
			for id in c.suspects:
				var su: Suspect = d.suspects.get(id)
				if su and not su.is_done():
					if _rng.randf() < 0.5:
						d.book(su)
						report.booked += 1
					else:
						su.set_state(Suspect.S.DOWN)
		elif not _acts.has("call%d" % c.id):
			_acts["call%d" % c.id] = t
	if d.active_calls().is_empty() and t - float(_acts.get("last_call", 0.0)) > 50.0:
		_acts["last_call"] = t
		d.start_call(d._pick_kind())
	# Every few minutes a charge goes off in the same building, until it is down.
	var every := 150.0
	var k := int(t / every)
	if k > int(_acts.get("blast", 0)) and t > 30.0:
		_acts["blast"] = k
		var b: Dictionary = gen.buildings[1 % gen.buildings.size()]
		var bb: AABB = b.bounds
		var at := bb.position + Vector3(_rng.randf() * bb.size.x, _rng.randf_range(0.5, bb.size.y * 0.8), _rng.randf() * bb.size.z)
		w.explode(at, 4.0, 450.0, 7.0)
		report.events.append([snappedf(t, 0.1), "charge", str(at)])
	# Things get broken.
	if int(t / 20.0) > int(_acts.get("props", 0)):
		_acts["props"] = int(t / 20.0)
		var standing := PropWorld.current.intact()
		if not standing.is_empty():
			var p: Dictionary = standing[_rng.randi() % standing.size()]
			PropWorld.current.break_prop(p.id)
	if t > 400.0 and not _acts.has("car"):
		_acts["car"] = true
		var cs: CarSync = s.cars
		cs.damage_car(cs.cars[cs.cars.size() - 1], 500.0)
		report.events.append([snappedf(t, 0.1), "car wrecked"])


func _process(_delta: float) -> void:
	# Friend b drops out at about 10 minutes and comes back 30 s later.
	if role == "b" and _scene() and _left_at < 0.0 and _check_i >= int(minutes / 2.0):
		_left_at = Time.get_ticks_msec() / 1000.0
		report.events.append(["left", _check_i])
		Net.leave()
		get_tree().change_scene_to_file("res://game/ui/main_menu.tscn")
	elif role == "b" and _left_at > 0.0 and Time.get_ticks_msec() / 1000.0 - _left_at > 30.0 and not Net.is_online():
		_left_at = INF
		report.rejoins += 1
		Net.join("127.0.0.1", PORT)


func _on_check(_from: int, data: PackedByteArray) -> void:
	_check_i = data[0]
	var s := _scene()
	if s == null:
		report.checks.append({"i": _check_i, "none": true})
		return
	var w: DestructionWorld = s.world
	var lost := w.pieces.values().filter(func(p): return p.state != "intact").map(func(p): return p.id)
	lost.sort()
	var props := PropWorld.current.props.values().filter(func(p): return p.broken).map(func(p): return p.id)
	props.sort()
	var cs: CarSync = s.cars
	var fires := []
	for i in cs.cars.size():
		fires.append(cs.fire_state.get(i, 0))
	var d: Dispatcher = s.dispatch
	var calls := d.active_calls().map(func(c): return c.id)
	calls.sort()
	var live := d.suspects.values().filter(func(x): return not (x as Suspect).is_done()).size()
	report.checks.append({"i": _check_i, "lost": lost.size(), "lost_hash": hash(lost), "props": props.size(), "props_hash": hash(props),
		"cars": fires, "crime": snappedf(d.crime, 1.0), "calls": calls, "suspects": live, "pawns": (s.sync as PawnSync).pawns.size(),
		"fires": FireSystem.current.fires.size() if FireSystem.current else -1, "fps": Engine.get_frames_per_second()})


func _finish() -> void:
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string(JSON.stringify(report))
	f.close()
	get_tree().quit()
