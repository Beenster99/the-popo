class_name FireSystem
extends Node
## Phase 1.5: fire. Started by a blast (barrels, gas bottles, a car going
## up), it burns for a while, sets light to wooden things near it (chairs,
## tables, shelves, crates, doors), hurts anyone standing in it, and spreads
## from what burns. A burst fire extinguisher puts out everything round it.
##
## The host decides; everyone else gets the list of fires a few times a
## second and shows the flames, smoke, light and crackle.

const MSG_FIRES := 92
const SEND_EVERY := 0.25
const TICK := 0.5               # s between spread and burn checks
const PROP_BURN_DPS := 5.0      # hp a second off a burning prop
const PIECE_BURN := 4.0         # damage per tick to wooden walls and doors in it
const PERSON_BURN := 5.0        # per tick to someone standing in it
const SPREAD_REACH := 1.3       # m beyond the flames that can catch
const SPREAD_CHANCE := 0.35     # per tick, per thing in reach
const PUFF_RADIUS := 4.5
const MAX_FIRES := 40

static var current: FireSystem

var world: DestructionWorld
var props: PropWorld
var cars: CarSync
## id -> {id, pos, r, life, prop (id or -1), car (index or -1)}
var fires := {}
var _visuals := {}               # id -> Node3D
var _next := 0
var _tick := 0.0
var _send_t := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	current = self
	_rng.seed = 1234
	Net.register(MSG_FIRES, _on_fires)


func _exit_tree() -> void:
	if current == self:
		current = null
	Net.unregister(MSG_FIRES)


# --- host ----------------------------------------------------------------------------

## Host: a fire on the floor here. Returns its id.
func ignite(pos: Vector3, radius := 1.0, life := 12.0, prop := -1, car := -1) -> int:
	if not Net.is_host() or fires.size() >= MAX_FIRES:
		return -1
	if prop >= 0:
		for f in fires.values():
			if f.prop == prop:
				return f.id
		if props and props.props.has(prop):
			props.props[prop].burning = true
	var id := _next
	_next += 1
	fires[id] = {"id": id, "pos": pos, "r": radius, "life": life, "prop": prop, "car": car}
	_show(id, pos, radius)
	return id


## Host: puts out every fire within radius of pos.
func extinguish(pos: Vector3, radius: float) -> int:
	var n := 0
	for f in fires.values():
		if Vector2(f.pos.x - pos.x, f.pos.z - pos.z).length() < radius + f.r * 0.5 and absf(f.pos.y - pos.y) < 3.0:
			_out(f.id)
			n += 1
	return n


func burning_at(pos: Vector3, extra := 0.0) -> bool:
	for f in fires.values():
		if Vector2(f.pos.x - pos.x, f.pos.z - pos.z).length() < f.r + extra and absf(f.pos.y - pos.y) < 1.8:
			return true
	return false


func _out(id: int) -> void:
	var f: Dictionary = fires.get(id, {})
	if f.is_empty():
		return
	if f.prop >= 0 and props and props.props.has(f.prop):
		props.props[f.prop].burning = false
	fires.erase(id)
	_hide(id)


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	for f in fires.values():
		f.life -= delta
		if f.prop >= 0 and props:
			var rb := props.body(f.prop)
			if rb == null:
				f.prop = -1
				f.life = minf(f.life, 6.0)
			else:
				f.pos = rb.global_position - Vector3(0, PropWorld.height_of(props.props[f.prop].kind) * 0.5, 0)
				props.damage_prop(f.prop, PROP_BURN_DPS * delta, rb.global_position)
		elif f.car >= 0 and cars and f.car < cars.cars.size():
			var c: Car = cars.cars[f.car]
			f.pos = c.global_position + c.global_transform.basis.z * 1.4 + Vector3(0, 0.2, 0)
		if f.life <= 0.0:
			_out(f.id)
		elif _visuals.has(f.id):
			(_visuals[f.id] as Node3D).global_position = f.pos
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_spread_and_burn()
	_send_t -= delta
	if _send_t <= 0.0 and Net.is_online():
		_send_t = SEND_EVERY
		_send()


func _spread_and_burn() -> void:
	var tree := get_tree()
	for f in fires.values().duplicate():
		if not fires.has(f.id):
			continue
		var reach: float = f.r + SPREAD_REACH
		# Wooden things near it catch.
		if props:
			for p in props.intact():
				if p.burning or not PropWorld.KINDS[p.kind].get("flammable", false):
					continue
				var rb: RigidBody3D = p.body
				var d := Vector2(rb.global_position.x - f.pos.x, rb.global_position.z - f.pos.z).length()
				if d < reach and absf(rb.global_position.y - f.pos.y) < 2.0 and _rng.randf() < SPREAD_CHANCE:
					ignite(rb.global_position, 0.6, 30.0, p.id)
			# Explosive things in the flames cook off.
			for p in props.intact():
				if not PropWorld.KINDS[p.kind].get("explosive", false):
					continue
				var rb2: RigidBody3D = p.body
				if Vector2(rb2.global_position.x - f.pos.x, rb2.global_position.z - f.pos.z).length() < f.r + 0.3 and absf(rb2.global_position.y - f.pos.y) < 1.5:
					props.damage_prop(p.id, 4.0, rb2.global_position)
		# Wooden walls and doors char and give way.
		if world:
			for id in world.pieces:
				var pc: Dictionary = world.pieces[id]
				if pc.state != "intact" or DestructionWorld.surface_for(pc.kind) != "wood":
					continue
				if (pc.aabb as AABB).grow(f.r * 0.6).has_point(f.pos + Vector3(0, 0.5, 0)):
					world.damage_piece(id, PIECE_BURN, f.pos, 0.5)
		# Anyone in it.
		for n in tree.get_nodes_in_group("officers"):
			var o := n as Officer
			if _in(f, o.global_position):
				o.take_damage(PERSON_BURN, Vector3.ZERO, "burn")
		for n in tree.get_nodes_in_group("suspects"):
			var s := n as Suspect
			if _in(f, s.global_position) and not s.is_done():
				s.take_damage(PERSON_BURN, Vector3.ZERO)
		# A car in the flames catches too.
		if cars:
			for i in cars.cars.size():
				var c: Car = cars.cars[i]
				if i != f.car and c.global_position.distance_to(f.pos) < f.r + 2.2:
					cars.damage_car(c, 3.0, f.pos)


func _in(f: Dictionary, p: Vector3) -> bool:
	return Vector2(p.x - f.pos.x, p.z - f.pos.z).length() < f.r * 0.9 + 0.2 and p.y - f.pos.y > -0.8 and p.y - f.pos.y < 1.6


func _send() -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(mini(fires.size(), 255))
	var n := 0
	for f in fires.values():
		if n >= 255:
			break
		b.put_u16(f.id)
		b.put_float(f.pos.x)
		b.put_float(f.pos.y)
		b.put_float(f.pos.z)
		b.put_u8(clampi(roundi(f.r * 20.0), 1, 255))
		n += 1
	Net.broadcast(MSG_FIRES, b.data_array, Net.UNRELIABLE)


# --- everyone: what it looks and sounds like --------------------------------------------

func _on_fires(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var n := b.get_u8()
	var seen := {}
	for i in n:
		var id := b.get_u16()
		var pos := Vector3(b.get_float(), b.get_float(), b.get_float())
		var r := b.get_u8() / 20.0
		seen[id] = true
		if not fires.has(id):
			fires[id] = {"id": id, "pos": pos, "r": r, "life": 99.0, "prop": -1, "car": -1}
			_show(id, pos, r)
		fires[id].pos = pos
		if _visuals.has(id):
			(_visuals[id] as Node3D).global_position = pos
	for id in fires.keys():
		if not seen.has(id):
			fires.erase(id)
			_hide(id)


func _show(id: int, pos: Vector3, r: float) -> void:
	var root := Node3D.new()
	root.name = "Fire%d" % id
	add_child(root)
	root.global_position = pos
	_visuals[id] = root
	var parent := get_parent() if get_parent() else self
	var bus := Sfx.BUS_SFX if Sfx.zone_at(get_tree(), pos) == null else Sfx.BUS_INDOOR
	Sfx.ensure_buses()
	var snd := AudioStreamPlayer3D.new()
	snd.stream = Sfx.loop_stream("fire_loop")
	snd.bus = bus
	snd.volume_db = -6.0 + r * 3.0
	snd.unit_size = 4.0
	snd.max_distance = 40.0
	snd.pitch_scale = 0.9 + _rng.randf() * 0.2
	root.add_child(snd)
	snd.play(_rng.randf() * 5.0)
	Sfx.play(parent, "fire_whoomph", pos, -4.0 + r * 2.0, 40.0, 0.1)
	if DisplayServer.get_name() == "headless":
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.2)
	light.light_energy = 2.5
	light.omni_range = 3.0 + r * 3.0
	light.position = Vector3(0, 0.8, 0)
	light.set_meta("fire_light", true)
	root.add_child(light)
	root.add_child(_flames(r))
	root.add_child(_smoke(r))


func _hide(id: int) -> void:
	var v: Node3D = _visuals.get(id)
	_visuals.erase(id)
	if v == null or not is_instance_valid(v):
		return
	# The flames die down, the smoke drifts off.
	for c in v.get_children():
		if c is CPUParticles3D:
			(c as CPUParticles3D).emitting = false
		elif c is AudioStreamPlayer3D:
			var tw := create_tween()
			tw.tween_property(c, "volume_db", -40.0, 1.2)
		elif c is OmniLight3D:
			var tw2 := create_tween()
			tw2.tween_property(c, "light_energy", 0.0, 0.8)
	get_tree().create_timer(4.0).timeout.connect(v.queue_free)


func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id in _visuals:
		var v: Node3D = _visuals[id]
		for c in v.get_children():
			if c is OmniLight3D and c.has_meta("fire_light"):
				(c as OmniLight3D).light_energy = 2.2 + sin(t * 23.0 + id) * 0.4 + sin(t * 9.0 + id * 3.0) * 0.5


static var _soft: Texture2D

## A soft round blob, for flame and smoke sprites.
static func soft_texture() -> Texture2D:
	if _soft == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.45, Color(1, 1, 1, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_soft = t
	return _soft


static func _flames(r: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = int(18 + r * 20)
	p.lifetime = 0.7
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r * 0.7
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.3, 1.0))
	grad.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_texture()
	q.material = m
	p.mesh = q
	p.emitting = true
	return p


static func _smoke(r: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = int(8 + r * 8)
	p.lifetime = 3.5
	p.position = Vector3(0, 1.0, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = r * 0.5
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0.3, 1.2, 0.1)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.0))
	p.scale_amount_curve = curve
	var grad := Gradient.new()
	grad.set_color(0, Color(0.15, 0.14, 0.13, 0.55))
	grad.set_color(1, Color(0.3, 0.3, 0.3, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_texture()
	q.material = m
	p.mesh = q
	p.emitting = true
	return p
