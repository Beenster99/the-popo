class_name FiringRange
extends Node3D
## Wave 3, Phase 3.6: the firing range out the back of the station, once
## it's been bought. Stand on the mark and press F: a 30 second run.
## Targets swing up for a moment at 8 to 25 metres; hit the crooks (red),
## leave the civilians (blue) alone. The score goes out on the radio, with
## the best of the session.
##
## The host runs it and sends the targets' state to everyone.

const MSG_RANGE := 103        # host -> all: targets up, civilians, time, score
const MSG_RANGE_START := 104  # client -> host: start a run
const RUN_TIME := 30.0
const UP_TIME := Vector2(1.4, 2.2)
const LANES := 6
const START_REACH := 1.8

var dispatcher: Dispatcher
var start := Vector3.INF          # the mark to stand on
var targets: Array = []           # RangeTarget
var running := false
var time_left := 0.0
var score := 0
var hits := 0
var civ_hits := 0
var best := 0
var _rng := RandomNumberGenerator.new()
var _pop_t := 0.0
var _send_t := 0.0
var _board: Label3D


func _ready() -> void:
	_rng.randomize()
	Net.register(MSG_RANGE, _on_state)
	Net.register(MSG_RANGE_START, _on_start)


func _exit_tree() -> void:
	Net.unregister(MSG_RANGE)
	Net.unregister(MSG_RANGE_START)


## Builds the range behind the station: a mark, a bench, side walls, a
## sand berm at the far end, and a row of swing-up targets.
func build(st: Dictionary) -> void:
	var u: Vector3 = st.u
	var v: Vector3 = st.v
	var back: Vector3 = (st.origin as Vector3) + v * (float(st.d) * BlockGenerator.M + 2.0)
	var width := 20.0
	var length := 28.0
	var left := back + u * 4.0
	start = left + u * (width * 0.5) + Vector3(0, 0.0, 0)
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color("8a8a84")
	var sand := StandardMaterial3D.new()
	sand.albedo_color = Color("b59b6a")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("6e5238")
	var body := StaticBody3D.new()
	add_child(body)
	# Firing line bench, side walls, the berm.
	_box(body, Vector3(width, 0.9, 0.6), left + u * (width * 0.5) - v * 0.8 + Vector3.UP * 0.45, wood)
	_box(body, Vector3(0.3, 2.4, length), left + v * (length * 0.5) + Vector3.UP * 1.2, concrete)
	_box(body, Vector3(0.3, 2.4, length), left + u * width + v * (length * 0.5) + Vector3.UP * 1.2, concrete)
	_box(body, Vector3(width, 3.0, 2.0), left + u * (width * 0.5) + v * (length + 1.0) + Vector3.UP * 1.5, sand)
	Cel.apply(self)
	var mark := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.8
	disc.bottom_radius = 0.8
	disc.height = 0.02
	mark.mesh = disc
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(0.3, 0.9, 1.0, 0.5)
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mark.material_override = mm
	add_child(mark)
	mark.global_position = start + Vector3(0, 0.03, -0.0) - v * 1.8
	start = mark.global_position
	_board = Label3D.new()
	_board.font_size = 44
	_board.outline_size = 10
	_board.pixel_size = 0.008
	_board.modulate = Color(0.6, 0.95, 1.0)
	add_child(_board)
	_board.global_position = left + u * (width * 0.5) + v * (length + 0.2) + Vector3.UP * 3.6
	_board.rotation.y = atan2(-v.x, -v.z)
	for i in LANES:
		var t := RangeTarget.new()
		t.owner_range = self
		t.index = i
		add_child(t)
		var dist := 8.0 + float(i % 3) * 8.0 + _rng.randf_range(-1.0, 1.0)
		t.global_position = left + u * (2.0 + i * (width - 4.0) / (LANES - 1)) + v * dist
		t.rotation.y = atan2(-v.x, -v.z)
	_show_board()


func near_start(p: Vector3) -> bool:
	return start != Vector3.INF and Vector2(p.x - start.x, p.z - start.z).length() < START_REACH


## Anyone: start a run (the host runs it).
func ask_start() -> void:
	if Net.is_host():
		begin()
	else:
		Net.send(1, MSG_RANGE_START, PackedByteArray())


func begin() -> void:
	if running:
		return
	running = true
	time_left = RUN_TIME
	score = 0
	hits = 0
	civ_hits = 0
	_pop_t = 1.0
	for t in targets_list():
		t.set_up(false, false)
	if dispatcher:
		dispatcher.say("RANGE: run starts. Thirty seconds. Red are crooks, blue are civilians.")


func targets_list() -> Array:
	return get_children().filter(func(c): return c is RangeTarget)


func _physics_process(delta: float) -> void:
	if not Net.is_host() or not running:
		return
	time_left -= delta
	_pop_t -= delta
	for t in targets_list():
		var rt := t as RangeTarget
		if rt.up:
			rt.up_t -= delta
			if rt.up_t <= 0.0:
				rt.set_up(false, false)
	if _pop_t <= 0.0 and time_left > 1.0:
		_pop_t = _rng.randf_range(0.5, 1.1)
		var down := targets_list().filter(func(x): return not x.up)
		if not down.is_empty():
			var rt: RangeTarget = down[_rng.randi_range(0, down.size() - 1)]
			rt.set_up(true, _rng.randf() < 0.25)
			rt.up_t = _rng.randf_range(UP_TIME.x, UP_TIME.y)
	if time_left <= 0.0:
		running = false
		time_left = 0.0
		for t in targets_list():
			t.set_up(false, false)
		var new_best := score > best
		best = maxi(best, score)
		if dispatcher:
			dispatcher.say("RANGE: %d points (%d hits%s). %s" % [score, hits,
				", %d civilian%s shot" % [civ_hits, "" if civ_hits == 1 else "s"] if civ_hits > 0 else "",
				"New best!" if new_best else "Best today: %d." % best])
	_show_board()
	_send_t -= delta
	if Net.is_online() and _send_t <= 0.0:
		_send_t = 0.1
		var b := StreamPeerBuffer.new()
		var up_mask := 0
		var civ_mask := 0
		for t in targets_list():
			var rt := t as RangeTarget
			if rt.up:
				up_mask |= 1 << rt.index
			if rt.civilian:
				civ_mask |= 1 << rt.index
		b.put_u8(up_mask)
		b.put_u8(civ_mask)
		b.put_half(time_left)
		b.put_16(score)
		b.put_16(best)
		Net.broadcast(MSG_RANGE, b.data_array, Net.UNRELIABLE)


## Host: a bullet hit target t.
func hit(t: RangeTarget) -> void:
	if not running or not t.up:
		return
	if t.civilian:
		civ_hits += 1
		score -= 3
		Sfx.play(self, "dry_fire", t.global_position, 0.0, 40.0, 0.0)
	else:
		hits += 1
		score += 2 if t.up_t > 0.8 else 1   # quick shots score double
	t.set_up(false, false)


func _show_board() -> void:
	if _board:
		_board.text = "RANGE  %d   %.0f s\nBEST %d" % [score, ceilf(time_left), best] if running else \
			"RANGE  best %d\nstand on the mark, F to start" % best


func _on_state(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var up_mask := b.get_u8()
	var civ_mask := b.get_u8()
	time_left = b.get_half()
	score = b.get_16()
	best = b.get_16()
	running = time_left > 0.0
	for t in targets_list():
		var rt := t as RangeTarget
		rt.set_up((up_mask & (1 << rt.index)) != 0, (civ_mask & (1 << rt.index)) != 0)
	_show_board()


func _on_start(_from: int, _data: PackedByteArray) -> void:
	if Net.is_host():
		begin()


func _box(body: StaticBody3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	m.material_override = mat
	body.add_child(m)
	m.global_position = at
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	cs.global_position = at
