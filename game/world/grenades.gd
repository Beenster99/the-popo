class_name Grenades
extends Node3D
## Throwables (beenster, 2026-11-23): police smoke, CS gas and flashbangs,
## and frag grenades that only the enemies have.
##
##   Smoke      pops after a short fuse and pours out a thick grey cloud
##              that hangs about half a minute. Suspects can't see through
##              it, so they can't shoot what they can't see.
##   CS gas     a stinging white-yellow cloud. Anyone in it coughs and
##              can't aim; suspects stumble out of it and most give up. It
##              gets the police too if they walk into it.
##   Flashbang  a blinding white flash and a bang that leaves the ears
##              ringing. Suspects who see it are stunned for a few seconds
##              and often give up; officers who see it get a white-out.
##   Frag       (enemies) bounces, ticks and goes off: a blast that breaks
##              the world and throws people, and shrapnel that hits like
##              bullets (blood on the Gore setting, gibs on Extreme).
##
## The host throws and sets them off. Everyone gets the throw (MSG_THROW)
## and flies the same grenade for themselves, then the host's pop
## (MSG_POP) puts it where it really landed and sets off the effects, so
## the clouds and flashes are made on every machine from the same event.

enum Kind { SMOKE, GAS, FLASH, FRAG }
const NAMES := ["Smoke", "CS gas", "Flashbang", "Frag"]
const SHORT := ["SMOKE", "CS GAS", "FLASH"]
## Seconds from the throw to the pop.
const FUSE := [1.5, 1.5, 1.7, 2.8]
const MSG_THROW := 120    # host -> all: id u16, kind u8, from, velocity
const MSG_POP := 121      # host -> all: id u16, kind u8, where
const SMOKE_TIME := 30.0
const SMOKE_RADIUS := 5.5
const GAS_TIME := 22.0
const GAS_RADIUS := 5.0
const SPREAD_TIME := 4.0       # s for a cloud to reach its full size
const FLASH_RANGE := 12.0
const FRAG_RADIUS := 3.4       # the blast (Blast.go adds a metre for people)
const FRAG_SHRAPNEL := 30      # pieces
const SHRAPNEL_RANGE := 16.0
const SHRAPNEL_DAMAGE := 14.0
## How many of each an officer carries once the station has bought them.
const CARRY := 2
const THROW_SPEED := 14.0
const MAX_THROW := 28.0        # m: further than this lands short

static var current: Grenades

## Live grenades in the air or on the floor: id -> RigidBody3D.
var live := {}
## Clouds hanging about: {kind, pos, age, life, radius, node, hiss}.
var clouds: Array = []
var _next_id := 1
var _gas_t := 0.0
var _cough_t := 0.0
var _overlay: CanvasLayer
var _white: ColorRect
var _sting: ColorRect
var _white_k := 0.0
var _sting_k := 0.0
var _rng := RandomNumberGenerator.new()
static var _mats := {}


# --- officers' pouch: 2 bits a kind (smoke, gas, flash) --------------------------------

static func count(pouch: int, kind: int) -> int:
	return (pouch >> (kind * 2)) & 3


static func with_count(pouch: int, kind: int, n: int) -> int:
	return (pouch & ~(3 << (kind * 2))) | (clampi(n, 0, 3) << (kind * 2))


## A full pouch: two of each kind the station owns.
static func full_pouch() -> int:
	var p := 0
	for k in 3:
		if Armoury.owns(Armoury.NADE_ITEMS[k]):
			p = with_count(p, k, CARRY)
	return p


## The kind actually thrown when kind is picked: it, or the next one there's
## any of (-1 for none at all).
static func pick(pouch: int, kind: int) -> int:
	for i in 3:
		var k := (kind + i) % 3
		if count(pouch, k) > 0:
			return k
	return -1


# --- setting up --------------------------------------------------------------------------

## The scene's grenade system, made the first time it's wanted (next to
## the officers, so it goes when the scene does).
static func ensure(near: Node) -> Grenades:
	if current and is_instance_valid(current) and current.is_inside_tree():
		return current
	var parent := near.get_parent() if near.get_parent() else near
	var g := Grenades.new()
	g.name = "Grenades"
	parent.add_child(g)
	return g


func _enter_tree() -> void:
	current = self


func _ready() -> void:
	_rng.randomize()
	Net.register(MSG_THROW, _on_throw_msg)
	Net.register(MSG_POP, _on_pop_msg)
	if DisplayServer.get_name() != "headless":
		_make_overlay()


func _exit_tree() -> void:
	if current == self:
		current = null
	Net.unregister(MSG_THROW)
	Net.unregister(MSG_POP)


# --- throwing ----------------------------------------------------------------------------

## Host: an officer lets one go toward where they're aiming.
static func officer_throw(o: Node3D, kind: int, aim: Vector3) -> void:
	var fwd := Vector3(sin(o.rotation.y), 0, cos(o.rotation.y))
	var right := Vector3(fwd.z, 0, -fwd.x)
	var from := o.global_position + Vector3(0, 1.75, 0) + fwd * 0.35 - right * 0.15
	var to := aim
	if to == Vector3.ZERO or to.distance_to(from) < 0.5:
		to = from + fwd * 12.0
	var flat := Vector3(to.x - from.x, 0, to.z - from.z)
	if flat.length() > MAX_THROW:
		to = from + flat.normalized() * MAX_THROW + Vector3(0, to.y - from.y, 0)
	throw(o, kind, from, Thrown.launch_velocity(from, to, THROW_SPEED))


## Host: a grenade leaves a hand at from, going at vel.
static func throw(by: Node, kind: int, from: Vector3, vel: Vector3) -> int:
	if not Net.is_host():
		return -1
	var g := ensure(by)
	var id := g._next_id
	g._next_id = (g._next_id % 60000) + 1
	var rb := g._spawn(id, kind, from, vel)
	if by is CollisionObject3D:
		rb.add_collision_exception_with(by)
	if Net.is_online():
		var b := StreamPeerBuffer.new()
		b.put_u16(id)
		b.put_u8(kind)
		_put_v3(b, from)
		_put_v3(b, vel)
		Net.broadcast(MSG_THROW, b.data_array)
	return id


func _on_throw_msg(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var id := b.get_u16()
	var kind := b.get_u8()
	var from := _get_v3(b)
	var vel := _get_v3(b)
	var rb := _spawn(id, kind, from, vel)
	# Clients don't set it off: the host says when and where.
	rb.set_meta("fuse", 999.0)


func _spawn(id: int, kind: int, from: Vector3, vel: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "Grenade%d" % id
	rb.mass = 0.45
	rb.collision_layer = 0
	rb.collision_mask = 1 | 4 | 16
	rb.continuous_cd = true
	rb.angular_damp = 4.0
	rb.linear_damp = 0.4
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.9
	rb.physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.04 if kind == Kind.FRAG else 0.032
	sh.height = 0.1 if kind == Kind.FRAG else 0.14
	cs.shape = sh
	rb.add_child(cs)
	rb.add_child(make_mesh(kind))
	rb.contact_monitor = true
	rb.max_contacts_reported = 2
	rb.set_meta("kind", kind)
	rb.set_meta("fuse", FUSE[kind])
	rb.set_meta("id", id)
	rb.body_entered.connect(_on_bounce.bind(rb))
	add_child(rb)
	rb.global_position = from
	rb.linear_velocity = vel
	rb.angular_velocity = Vector3(_rng.randf_range(-12, 12), _rng.randf_range(-4, 4), _rng.randf_range(-12, 12))
	live[id] = rb
	if not _headless():
		Sfx.play(self, "nade_pin", from, -2.0, 25.0, 0.06)
		Sfx.play(self, "whoosh", from, -8.0, 15.0, 0.1)
		if kind == Kind.FRAG:
			_warning(rb)
	return rb


## What one looks like: a can for the police ones, a pineapple for the frag.
static func make_mesh(kind: int) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var cols := [Color("5d6a73"), Color("8a8c4a"), Color("2b2e33"), Color("3f4a2a")]
	if kind == Kind.FRAG:
		var sm := SphereMesh.new()
		sm.radius = 0.042
		sm.height = 0.1
		body.mesh = sm
	else:
		var cm := CylinderMesh.new()
		cm.top_radius = 0.032
		cm.bottom_radius = 0.032
		cm.height = 0.14
		body.mesh = cm
	body.material_override = _mat(cols[kind])
	root.add_child(body)
	# The fuse head and spoon on top.
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.03, 0.03, 0.05)
	top.mesh = tm
	top.position = Vector3(0, 0.07 if kind != Kind.FRAG else 0.06, 0.008)
	top.material_override = _mat(Color("b0b3b5"))
	root.add_child(top)
	# A coloured band, so you can tell them apart in the hand.
	if kind != Kind.FRAG:
		var band := MeshInstance3D.new()
		var bm := CylinderMesh.new()
		bm.top_radius = 0.0335
		bm.bottom_radius = 0.0335
		bm.height = 0.02
		band.mesh = bm
		band.material_override = _mat([Color("d9d9d9"), Color("e6c629"), Color("d23c2c")][kind])
		root.add_child(band)
	return root


static func _mat(c: Color) -> Material:
	if not _mats.has(c):
		_mats[c] = Cel.material(c, false)
	return _mats[c]


## Frags: a red "GRENADE!" over it so the officers know to move.
func _warning(rb: RigidBody3D) -> void:
	var l := Label3D.new()
	l.text = "GRENADE!"
	l.font_size = 46
	l.outline_size = 10
	l.pixel_size = 0.006
	l.modulate = Color(1.0, 0.2, 0.15)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.top_level = true
	rb.add_child(l)
	rb.set_meta("label", l)


func _on_bounce(_other: Node, rb: RigidBody3D) -> void:
	if not is_instance_valid(rb) or _headless():
		return
	var v := rb.linear_velocity.length()
	if not rb.has_meta("landed"):
		# The first bounce takes most of the throw out of it.
		rb.set_meta("landed", true)
		rb.linear_velocity *= 0.45
	if v > 1.2:
		Sfx.play(self, "nade_bounce", rb.global_position, clampf(-14.0 + v * 1.5, -14.0, 0.0), 30.0, 0.12)


# --- every tick ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	for id in live.keys():
		var rb := live[id] as RigidBody3D
		if rb == null or not is_instance_valid(rb):
			live.erase(id)
			continue
		var l: Label3D = rb.get_meta("label") if rb.has_meta("label") else null
		if l:
			l.global_position = rb.global_position + Vector3(0, 0.7, 0)
			l.visible = fmod(Time.get_ticks_msec() / 1000.0, 0.3) < 0.2
		if rb.global_position.y < -50.0:
			rb.queue_free()
			live.erase(id)
			continue
		var fuse: float = rb.get_meta("fuse") - delta
		rb.set_meta("fuse", fuse)
		if fuse <= 0.0 and Net.is_host():
			_host_pop(id, rb)
	_clouds_step(delta)
	if Net.is_host():
		_gas_t -= delta
		if _gas_t <= 0.0:
			_gas_t = 0.25
			_gas_people(0.25)


func _host_pop(id: int, rb: RigidBody3D) -> void:
	var kind: int = rb.get_meta("kind")
	var at := rb.global_position
	if Net.is_online():
		var b := StreamPeerBuffer.new()
		b.put_u16(id)
		b.put_u8(kind)
		_put_v3(b, at)
		Net.broadcast(MSG_POP, b.data_array)
	_pop(id, kind, at)


func _on_pop_msg(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var id := b.get_u16()
	var kind := b.get_u8()
	_pop(id, kind, _get_v3(b))


## Everyone: it goes off at at.
func _pop(id: int, kind: int, at: Vector3) -> void:
	var rb: RigidBody3D = live.get(id)
	live.erase(id)
	if rb and is_instance_valid(rb):
		if kind in [Kind.SMOKE, Kind.GAS]:
			# The can stays on the floor, pouring it out.
			rb.global_position = at
			rb.set_meta("fuse", 1.0e9)
			rb.get_tree().create_timer(SMOKE_TIME if kind == Kind.SMOKE else GAS_TIME).timeout.connect(rb.queue_free)
		else:
			rb.queue_free()
	match kind:
		Kind.SMOKE, Kind.GAS:
			_start_cloud(kind, at, rb)
		Kind.FLASH:
			_flash(at)
		Kind.FRAG:
			_frag(at)


# --- clouds ---------------------------------------------------------------------------------

func _start_cloud(kind: int, at: Vector3, can: RigidBody3D) -> void:
	var c := {"kind": kind, "pos": at, "age": 0.0, "life": SMOKE_TIME if kind == Kind.SMOKE else GAS_TIME,
		"radius": SMOKE_RADIUS if kind == Kind.SMOKE else GAS_RADIUS, "node": null, "hiss": null, "can": can}
	clouds.append(c)
	if _headless():
		return
	Sfx.play(self, "smoke_pop", at, 2.0, 50.0, 0.08)
	c.node = _cloud_particles(kind, at)
	var h := AudioStreamPlayer3D.new()
	h.stream = Sfx.loop_stream("smoke_hiss")
	h.volume_db = -2.0
	h.max_distance = 40.0
	h.unit_size = 4.0
	h.bus = Sfx.space_bus(self, at)
	add_child(h)
	h.global_position = at
	h.play()
	c.hiss = h


## The cloud (v0.22.0, beenster: "as realistic as possible"): a dense jet
## hissing out of the can along the floor, and the body of the cloud, lots
## of overlapping soft, lumpy puffs that billow out and up, slowly turn,
## drift with the air and thin away. Lit by the sun (dark at night), faded
## where they meet the ground or the camera so there are no hard edges.
func _cloud_particles(kind: int, at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.name = "Cloud"
	add_child(holder)
	holder.global_position = at + Vector3(0, 0.05, 0)
	var smoke := kind == Kind.SMOKE
	var r: float = SMOKE_RADIUS if smoke else GAS_RADIUS
	var tint := Color(0.86, 0.87, 0.88) if smoke else Color(0.93, 0.93, 0.84)
	var dense := 0.8 if smoke else 0.5
	var mat := _smoke_material()
	# The body of the cloud.
	var body := _puffs(mat, 170 if smoke else 120, 13.0, 0.9)
	body.direction = Vector3(0, 0.35, 0)
	body.spread = 85.0
	body.initial_velocity_min = r * 0.18
	body.initial_velocity_max = r * 0.48
	body.damping_min = r * 0.07
	body.damping_max = r * 0.11
	body.gravity = Vector3(0.12, 0.07, 0.08)    # a breath of wind, and warm smoke rises
	body.scale_amount_min = 2.4
	body.scale_amount_max = 4.2
	body.scale_amount_curve = _curve([Vector2(0, 0.3), Vector2(0.25, 0.85), Vector2(1, 1.7)])
	body.color_ramp = _ramp(tint, [0.0, dense, dense * 0.85, 0.0], [0.0, 0.12, 0.6, 1.0])
	body.color_initial_ramp = _shades(tint)
	holder.add_child(body)
	body.position = Vector3(0, 0.6, 0)
	# The jet out of the can: quick, low, thick.
	var jet := _puffs(mat, 36, 2.6, 0.12)
	jet.direction = Vector3(1, 0.25, 0)
	jet.spread = 180.0
	jet.flatness = 0.7
	jet.initial_velocity_min = 2.0
	jet.initial_velocity_max = 4.0
	jet.damping_min = 1.6
	jet.damping_max = 2.4
	jet.gravity = Vector3(0, 0.25, 0)
	jet.scale_amount_min = 0.5
	jet.scale_amount_max = 1.0
	jet.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(1, 2.4)])
	jet.color_ramp = _ramp(tint, [0.0, minf(dense + 0.2, 0.85), dense * 0.6, 0.0], [0.0, 0.08, 0.5, 1.0])
	jet.color_initial_ramp = _shades(tint)
	holder.add_child(jet)
	jet.position = Vector3(0, 0.15, 0)
	return holder


func _puffs(mat: Material, amount: int, life: float, emit_r: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.randomness = 0.6
	p.lifetime_randomness = 0.35
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = emit_r
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -14.0
	p.angular_velocity_max = 14.0
	# Each puff is one of the four lumpy shapes in the atlas.
	p.anim_offset_min = 0.0
	p.anim_offset_max = 1.0
	p.anim_speed_min = 0.0
	p.anim_speed_max = 0.0
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = mat
	p.mesh = q
	p.emitting = true
	return p


static var _smoke_mat: StandardMaterial3D

static func _smoke_material() -> StandardMaterial3D:
	if _smoke_mat == null:
		var m := StandardMaterial3D.new()
		# Unshaded: a lit card facing the camera goes dark whenever the sun is
		# behind it, which smoke doesn't. The day/night level is set on
		# albedo_color instead (see _clouds_step).
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.billboard_keep_scale = true
		m.particles_anim_h_frames = 2
		m.particles_anim_v_frames = 2
		m.particles_anim_loop = false
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = smoke_texture()
		m.albedo_color = Color(1, 1, 1, 1)
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		m.disable_receive_shadows = true
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Soft where a puff cuts into the floor or a wall.
		m.proximity_fade_enabled = true
		m.proximity_fade_distance = 1.4
		# And thin right in front of the camera, so walking through it isn't a
		# wall of flat cards.
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = 0.2
		m.distance_fade_max_distance = 2.2
		_smoke_mat = m
	return _smoke_mat


static var _smoke_tex: ImageTexture

## Four lumpy smoke puffs in a 2x2 atlas: noise (big billows and fine wisps)
## inside a soft round edge, brighter on top so they read as round masses.
static func smoke_texture() -> Texture2D:
	if _smoke_tex:
		return _smoke_tex
	var n := 128
	var img := Image.create(n * 2, n * 2, false, Image.FORMAT_RGBA8)
	for v in 4:
		var big := FastNoiseLite.new()
		big.seed = 101 + v * 17
		big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		big.frequency = 0.035
		big.fractal_type = FastNoiseLite.FRACTAL_FBM
		big.fractal_octaves = 4
		var ox := (v % 2) * n
		var oy := (v / 2) * n
		for y in n:
			for x in n:
				var dx := (x + 0.5) / n * 2.0 - 1.0
				var dy := (y + 0.5) / n * 2.0 - 1.0
				var nz := big.get_noise_2d(x, y) * 0.5 + 0.5
				# The edge wobbles with the noise, so it isn't a circle.
				var d := sqrt(dx * dx + dy * dy) + (nz - 0.5) * 0.55
				var edge := clampf(1.0 - d, 0.0, 1.0)
				edge = edge * edge * (3.0 - 2.0 * edge)
				var a := clampf(edge * (0.55 + 0.9 * nz), 0.0, 1.0)
				var shade := clampf(0.78 + 0.22 * nz - dy * 0.1, 0.0, 1.0)
				img.set_pixel(ox + x, oy + y, Color(shade, shade, shade, a))
	img.generate_mipmaps()
	_smoke_tex = ImageTexture.create_from_image(img)
	return _smoke_tex


static func _curve(pts: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	for pt in pts:
		c.add_point(pt)
	return c


## Colour over a puff's life: tint, with these alphas at these offsets.
static func _ramp(tint: Color, alphas: Array, at: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(at)
	var cols := PackedColorArray()
	for a in alphas:
		cols.append(Color(tint.r, tint.g, tint.b, a))
	g.colors = cols
	return g


## Some puffs a little darker than others, for depth.
static func _shades(tint: Color) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(tint.r * 0.72, tint.g * 0.72, tint.b * 0.74, 1.0), Color(1, 1, 1, 1)])
	return g


## How big a cloud is now (it spreads, then thins at the end).
static func cloud_radius(c: Dictionary) -> float:
	var age: float = c.age
	var k := clampf(age / SPREAD_TIME, 0.15, 1.0)
	var left: float = c.life - age
	if left < 4.0:
		k *= clampf(left / 4.0, 0.0, 1.0)
	return float(c.radius) * k


func _clouds_step(delta: float) -> void:
	for c in clouds.duplicate():
		c.age += delta
		var left: float = c.life - c.age
		var p := c.node as Node3D
		if p and is_instance_valid(p) and left < 8.0:
			for e in p.get_children():
				if e is CPUParticles3D:
					(e as CPUParticles3D).emitting = false
		var h := c.hiss as AudioStreamPlayer3D
		if h and is_instance_valid(h):
			h.volume_db = -2.0 - maxf(0.0, c.age - 6.0) * 2.0
			if c.age > 14.0:
				h.queue_free()
				c.hiss = null
		if left <= -9.0:
			if p and is_instance_valid(p):
				p.queue_free()
			clouds.erase(c)
	if not _headless():
		_local_effects(delta)
		if _smoke_mat and not clouds.is_empty():
			# Bright by day, dim grey at night.
			var night: float = CityWeather.current.night if CityWeather.current and is_instance_valid(CityWeather.current) else 0.0
			var k := lerpf(1.0, 0.3, night)
			_smoke_mat.albedo_color = Color(k, k, k * 1.03, 1.0)


## Anyone: does a smoke cloud stand between a and b? (Suspects can't see,
## so can't shoot, through it.)
static func blocks_sight(a: Vector3, b: Vector3) -> bool:
	if current == null or not is_instance_valid(current):
		return false
	for c in current.clouds:
		if c.kind != Kind.SMOKE:
			continue
		var r := cloud_radius(c) * 0.85
		if r < 0.8:
			continue
		var centre: Vector3 = c.pos + Vector3(0, 1.2, 0)
		var q := Geometry3D.get_closest_point_to_segment(centre, a, b)
		if Vector2(q.x - centre.x, q.z - centre.z).length() < r and absf(q.y - centre.y) < r * 0.6 + 0.8:
			return true
	return false


## Anyone: how thick the gas is at p (0 none, 1 in the middle).
static func gas_at(p: Vector3) -> float:
	if current == null or not is_instance_valid(current):
		return 0.0
	var best := 0.0
	for c in current.clouds:
		if c.kind != Kind.GAS:
			continue
		var r := cloud_radius(c)
		var pos: Vector3 = c.pos
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < r and absf(p.y - pos.y) < 3.5:
			best = maxf(best, 1.0 - d / maxf(r, 0.1) * 0.6)
	return best


## Host: the gas works on suspects (and makes civilians run).
func _gas_people(dt: float) -> void:
	if clouds.is_empty():
		return
	for n in get_tree().get_nodes_in_group("suspects"):
		var s := n as Suspect
		if s == null or not s.is_inside_tree():
			continue
		var g := gas_at(s.global_position)
		if g > 0.0 and s.has_method("gassed"):
			s.gassed(g * dt, _nearest_cloud(s.global_position, Kind.GAS))


func _nearest_cloud(p: Vector3, kind: int) -> Vector3:
	var best := Vector3.INF
	for c in clouds:
		if c.kind == kind and (best == Vector3.INF or p.distance_to(c.pos) < p.distance_to(best)):
			best = c.pos
	return best


# --- flashbang ---------------------------------------------------------------------------------

func _flash(at: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	if Net.is_host():
		get_tree().call_group("alarm_listeners", "on_alarm", at, 40.0)
		for n in get_tree().get_nodes_in_group("suspects"):
			var s := n as Suspect
			if s == null:
				continue
			var k := _seen_from(space, at, s.global_position + Vector3(0, 1.55, 0), s.rotation.y, s)
			if k > 0.0 and s.has_method("flashed"):
				s.flashed(k)
	if _headless():
		return
	Sfx.play(self, "flashbang", at, 9.0, 400.0, 0.04, Sfx.space_bus(self, at))
	Sfx.play(self, "gun_crack_near", at, 6.0, 120.0, 0.05)
	Sfx.play(self, "gun_sub", at, 6.0, 120.0, 0.05)
	Feel.blast_shake(get_tree(), at, 2.5)
	var light := OmniLight3D.new()
	light.light_color = Color(1, 1, 0.97)
	light.light_energy = 40.0
	light.omni_range = 18.0
	light.shadow_enabled = true
	add_child(light)
	light.global_position = at + Vector3(0, 0.4, 0)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.35).set_delay(0.06)
	tw.tween_callback(light.queue_free)
	var sp := CPUParticles3D.new()
	sp.one_shot = true
	sp.explosiveness = 1.0
	sp.amount = 50
	sp.lifetime = 0.5
	sp.spread = 180.0
	sp.initial_velocity_min = 4.0
	sp.initial_velocity_max = 12.0
	sp.gravity = Vector3(0, -9.8, 0)
	var pm := BoxMesh.new()
	pm.size = Vector3.ONE * 0.03
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.albedo_color = Color(1, 0.95, 0.8)
	pm.material = mm
	sp.mesh = pm
	add_child(sp)
	sp.global_position = at
	sp.emitting = true
	get_tree().create_timer(1.5).timeout.connect(sp.queue_free)
	Feel.cloud(self, at, 1.2)
	# Our own officer: a white-out and ringing ears, by how close and how
	# square on they were looking at it.
	var me := _me()
	if me:
		var eye := me.global_position + Vector3(0, 1.6, 0)
		var cam := get_viewport().get_camera_3d()
		var yaw := me.rotation.y
		if cam:
			var f := -cam.global_transform.basis.z
			yaw = atan2(f.x, f.z)
		var k := _seen_from(space, at, eye, yaw, me)
		var d := at.distance_to(eye)
		if k > 0.0:
			_white_k = maxf(_white_k, 0.6 + k * 2.4)
		if GameSounds.current and d < FLASH_RANGE * 1.3:
			GameSounds.current.ear_ring(clampf(1.25 - d / (FLASH_RANGE * 1.3), 0.35, 1.0))
			GameSounds.current.duck(1.0)


## How hard a flash at at hits eyes at eye facing yaw (0 out of sight or
## too far, up to 1 point blank and looking at it).
static func _seen_from(space: PhysicsDirectSpaceState3D, at: Vector3, eye: Vector3, yaw: float, who: Node) -> float:
	var d := at.distance_to(eye)
	if d > FLASH_RANGE:
		return 0.0
	var ex: Array[RID] = []
	if who is CollisionObject3D:
		ex.append((who as CollisionObject3D).get_rid())
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 0.25, 0), eye, 1 | 16, ex)
	if not space.intersect_ray(q).is_empty():
		return 0.0 if d > 3.0 else 0.3   # round a corner, right next to you: still dazzles
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var to := Vector3(at.x - eye.x, 0, at.z - eye.z).normalized()
	var facing := 0.35 + 0.65 * clampf((fwd.dot(to) + 0.3) / 1.3, 0.0, 1.0)
	return clampf((1.0 - d / FLASH_RANGE) * 1.4, 0.0, 1.0) * facing


# --- frag -----------------------------------------------------------------------------------------

func _frag(at: Vector3) -> void:
	var gs := GameSounds.current
	var world: DestructionWorld = gs.world if gs and is_instance_valid(gs) else _find(DestructionWorld)
	var cars: CarSync = gs.cars if gs and is_instance_valid(gs) else _find(CarSync)
	if Net.is_host():
		Blast.go(get_tree(), world, cars, at + Vector3(0, 0.15, 0), FRAG_RADIUS, 160.0, 7.5)
		_shrapnel(at + Vector3(0, 0.3, 0), world)
	if _headless():
		return
	if world == null or not is_instance_valid(world):
		Sfx.explosion(self, at, 1.2)   # the world plays it otherwise
	Sfx.play(self, "frag_crack", at, 8.0, 300.0, 0.05, Sfx.space_bus(self, at))
	Feel.blast_shake(get_tree(), at, 4.0)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.65, 0.3)
	light.light_energy = 18.0
	light.omni_range = 12.0
	add_child(light)
	light.global_position = at + Vector3(0, 0.5, 0)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.3)
	tw.tween_callback(light.queue_free)
	_dark_puff(at)
	_scorch(at)
	# Up close it's messy: the gore follows the slider.
	if Gore.level() > 0:
		for g in ["officers", "suspects"]:
			for n in get_tree().get_nodes_in_group(g):
				var who := n as Node3D
				var d := who.global_position.distance_to(at)
				if d < FRAG_RADIUS * 0.8:
					var chest := who.global_position + Vector3(0, 1.0, 0)
					for i in (1 + Gore.level()):
						Gore.hit(self, at, chest + Vector3(_rng.randf_range(-0.25, 0.25), _rng.randf_range(-0.5, 0.5), _rng.randf_range(-0.25, 0.25)))
					if Gore.level() >= 3 and d < FRAG_RADIUS * 0.5:
						Gore._gibs(self, chest, (chest - at).normalized(), 8)
					Gore.splat(self, Vector3(who.global_position.x, at.y + 0.02, who.global_position.z), Vector3.UP, Gore.POOL_SIZE[Gore.level()] * 0.8)


## Host: the pieces of the casing, like bullets in every direction. They hurt
## who they hit, chip what they hit, and everyone hears and sees them (and
## the blood) through the bullet event.
func _shrapnel(at: Vector3, world: DestructionWorld) -> void:
	var space := get_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(at)
	var sent := 0
	for i in FRAG_SHRAPNEL:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.25, 0.7), rng.randf_range(-1, 1)).normalized()
		var q := PhysicsRayQueryParameters3D.create(at, at + dir * SHRAPNEL_RANGE, 1 | 2 | 4 | 16)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var p: Vector3 = hit.position
		var k := 1.0 - at.distance_to(p) / SHRAPNEL_RANGE
		var what := 0
		var col: Object = hit.collider
		if col is Officer:
			(col as Officer).take_damage(SHRAPNEL_DAMAGE * (0.4 + k), dir, (col as Officer).body_part_at(p))
			what = 1
		elif col is Suspect:
			(col as Suspect).take_damage(SHRAPNEL_DAMAGE * (0.4 + k), dir)
			what = 1
		elif world and is_instance_valid(world) and not (col is Car):
			world.bullet_hit(col, p, hit.normal, dir)
		if (what == 1 or sent < 10) and GameSounds.current and GameSounds.current.sync:
			sent += 1
			GameSounds.current.sync.bullet(at, p, Sfx.surface_of(col), what, 0)


func _dark_puff(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 36
	p.lifetime = 3.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.4
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.damping_min = 3.0
	p.damping_max = 4.0
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 1.4
	p.scale_amount_max = 2.6
	var grad := Gradient.new()
	grad.set_color(0, Color(0.25, 0.22, 0.2, 0.95))
	grad.set_color(1, Color(0.35, 0.34, 0.33, 0.0))
	p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(1.2, 1.2)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = FireSystem.soft_texture()
	q.material = m
	p.mesh = q
	add_child(p)
	p.global_position = at + Vector3(0, 0.3, 0)
	p.emitting = true
	get_tree().create_timer(5.0).timeout.connect(p.queue_free)


## A black scorch mark where it went off.
func _scorch(at: Vector3) -> void:
	var d := Decal.new()
	d.size = Vector3(2.6, 1.0, 2.6)
	d.texture_albedo = FireSystem.soft_texture()
	d.modulate = Color(0.05, 0.04, 0.04, 0.85)
	add_child(d)
	d.global_position = at
	get_tree().create_timer(120.0).timeout.connect(d.queue_free)


# --- what our own officer feels ------------------------------------------------------------------

func _make_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 20
	add_child(_overlay)
	_sting = ColorRect.new()
	_sting.color = Color(0.85, 0.9, 0.55, 0.0)
	_sting.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sting.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_sting)
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0.0)
	_white.set_anchors_preset(Control.PRESET_FULL_RECT)
	_white.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_white)


func _local_effects(delta: float) -> void:
	var me := _me()
	var g := gas_at(me.global_position + Vector3(0, 1.0, 0)) if me else 0.0
	_sting_k = move_toward(_sting_k, g, delta * (1.5 if g > _sting_k else 0.25))
	_white_k = maxf(0.0, _white_k - delta)
	if _white:
		_white.color.a = clampf(_white_k, 0.0, 1.0)
	if _sting:
		_sting.color.a = clampf(_sting_k * 0.5, 0.0, 0.5)
	# Coughing: anyone standing in the gas, now and then.
	_cough_t -= delta
	if _cough_t <= 0.0 and not clouds.is_empty():
		_cough_t = 0.35
		for grp in ["officers", "suspects"]:
			for n in get_tree().get_nodes_in_group(grp):
				var who := n as Node3D
				if who and who.visible and gas_at(who.global_position) > 0.15 and _rng.randf() < 0.3:
					Sfx.play(self, "cough", who.global_position + Vector3(0, 1.5, 0), -3.0, 25.0, 0.12)


func _me() -> Officer:
	if GameSounds.current and is_instance_valid(GameSounds.current) and GameSounds.current.pawn_getter.is_valid():
		var o: Variant = GameSounds.current.pawn_getter.call()
		if o is Officer:
			return o
	for n in get_tree().get_nodes_in_group("officers"):
		var o2 := n as Officer
		if o2 and o2.peer_id == Net.my_id():
			return o2
	return null


func _find(cls: Variant) -> Node:
	var p := get_parent()
	if p == null:
		return null
	for c in p.get_children():
		if is_instance_of(c, cls):
			return c
	return null


static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func _put_v3(b: StreamPeerBuffer, v: Vector3) -> void:
	b.put_float(v.x)
	b.put_float(v.y)
	b.put_float(v.z)


static func _get_v3(b: StreamPeerBuffer) -> Vector3:
	return Vector3(b.get_float(), b.get_float(), b.get_float())
