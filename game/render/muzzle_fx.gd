class_name MuzzleFx
extends RefCounted
## What leaves the barrel when a gun goes off, sized by calibre:
##   flame   a star of fire at the muzzle with tongues of flame thrown
##           forward, white hot in the middle, orange at the edges (hard
##           bands, to sit with the cel look). On screen for a couple of
##           frames, each shot a little different.
##   light   a bright warm flash that lights up the walls, floor and faces
##           round the gun and dies away in a few hundredths of a second. No
##           shadows, and only a few at once, so a firefight costs no fps.
##   blast   a fast cone of burnt powder smoke and embers thrown out in
##           front of the gun.
##   smoke   a grey puff that hangs at the muzzle, curls up and thins out
##           over a couple of seconds (more of it from big guns, and a
##           shotgun leaves a proper cloud).
## Made on every machine from the shot it already hears, so nothing extra
## goes over the network.

## Calibre sizes (1.0 = the service 9mm).
const SIZE_SHOTGUN := 2.2
const MAX_LIGHTS := 4

static var _lights: Array[OmniLight3D] = []
static var _star_mat: StandardMaterial3D
static var _tongue_mat: StandardMaterial3D
static var _ember_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
static var _star_mesh: QuadMesh
static var _tongue_mesh: QuadMesh
## How bright gun smoke is (the weather darkens it at night, so it does
## not glow).
static var smoke_shade := 1.0
## Shots fired (for tests and the capture scene).
static var count := 0


## How big a gun's flash is: an officer's pistol by its weight, a picked-up
## or criminal's gun by its kind.
static func size_for(gun: int, pistol_weight := 1.0) -> float:
	if gun == EnemyGuns.SHOTGUN:
		return SIZE_SHOTGUN
	if gun == EnemyGuns.PISTOL:
		return 1.0
	return clampf(pistol_weight, 0.6, 2.0)


## A shot from `at` along `dir`.
static func fire(parent: Node, at: Vector3, dir: Vector3, size := 1.0) -> void:
	count += 1
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if dir.length() < 0.01:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var tree := parent.get_tree()
	_flame(parent, tree, at, dir, size)
	_light(parent, tree, at + dir * 0.15 * size, size)
	_blast(parent, tree, at, dir, size)
	_smoke(parent, tree, at, dir, size)


# --- flame --------------------------------------------------------------------------------

static func _flame(parent: Node, tree: SceneTree, at: Vector3, dir: Vector3, size: float) -> void:
	_make_meshes()
	var root := Node3D.new()
	parent.add_child(root)
	# Basis with -Z along the barrel, rolled at random.
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var b := Basis.looking_at(dir, up).rotated(dir, randf() * TAU)
	root.global_transform = Transform3D(b, at)
	var s := size * randf_range(0.85, 1.15)
	# The star facing down the barrel: what you see when it points your way.
	var star := _part(root, _star_mesh)
	star.position = Vector3(0, 0, -0.03 * s)
	star.scale = Vector3.ONE * (0.42 * s)
	# Three tongues round the barrel, each a plane through its axis, so the
	# flame reads from the side and from behind too.
	var length := randf_range(0.8, 1.2) * (0.55 if size < SIZE_SHOTGUN else 0.75) * sqrt(s)
	for i in 3:
		var t := _part(root, _tongue_mesh)
		# The tongue's texture runs along its Y; lay Y down the barrel.
		t.basis = Basis(Vector3(0, 0, -1), i * PI / 3.0) * Basis(Vector3(1, 0, 0), -PI * 0.5)
		t.scale = Vector3(0.4 * s, length, 1.0)
		t.position = Vector3(0, 0, -length * 0.5)
	# Counted in drawn frames, not seconds, so it is always seen however
	# slow or fast the game runs: full size, then smaller, then gone.
	var frames := [0]
	var step := func() -> void:
		frames[0] += 1
		if not is_instance_valid(root):
			return
		if frames[0] == 2:
			root.scale = Vector3(0.6, 0.6, 0.75)
		elif frames[0] >= 3:
			root.queue_free()
	tree.process_frame.connect(step)
	root.tree_exiting.connect(func(): tree.process_frame.disconnect(step))


static func _part(root: Node3D, mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return mi


# --- light --------------------------------------------------------------------------------

static func _light(parent: Node, tree: SceneTree, at: Vector3, size: float) -> void:
	_lights = _lights.filter(func(l): return is_instance_valid(l))
	while _lights.size() >= MAX_LIGHTS:
		var old: OmniLight3D = _lights.pop_front()
		old.queue_free()
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.78, 0.45)
	l.light_energy = 1.0 + 0.8 * size
	l.light_indirect_energy = 0.0
	l.light_volumetric_fog_energy = 0.0
	l.light_specular = 0.0
	l.omni_range = 4.0 + 2.5 * size
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	parent.add_child(l)
	l.global_position = at
	_lights.append(l)
	var tw := l.create_tween()
	tw.tween_interval(0.02)
	tw.tween_property(l, "light_energy", 0.0, 0.06 + 0.02 * size).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


# --- smoke --------------------------------------------------------------------------------

## The fast forward blast: a cone of powder smoke with a few hot embers.
static func _blast(parent: Node, tree: SceneTree, at: Vector3, dir: Vector3, size: float) -> void:
	_make_materials()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = int(6 + 5 * size)
	p.lifetime = 0.45
	p.local_coords = false
	p.direction = Vector3(0, 0, -1)
	p.spread = 14.0 if size < SIZE_SHOTGUN else 22.0
	p.initial_velocity_min = 3.0 * size
	p.initial_velocity_max = 6.5 * size
	p.damping_min = 14.0 * size
	p.damping_max = 22.0 * size
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.14 * size
	p.scale_amount_max = 0.22 * size
	p.scale_amount_curve = _grow_curve(2.4)
	var g := Gradient.new()
	g.set_color(0, Color(0.85, 0.8, 0.72, 0.45))
	g.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	p.color_ramp = g
	p.color = Color(smoke_shade, smoke_shade, smoke_shade)
	var q := QuadMesh.new()
	q.material = _smoke_mat
	p.mesh = q
	_place(parent, p, at, dir)
	tree.create_timer(1.0).timeout.connect(p.queue_free)
	# Embers: unburnt powder still glowing, more from big rounds.
	var e := CPUParticles3D.new()
	e.one_shot = true
	e.explosiveness = 1.0
	e.amount = int(3 + 4 * size)
	e.lifetime = 0.16 + 0.05 * size
	e.local_coords = false
	e.direction = Vector3(0, 0, -1)
	e.spread = 10.0 + 6.0 * size
	e.initial_velocity_min = 9.0
	e.initial_velocity_max = 18.0
	e.gravity = Vector3(0, -6, 0)
	e.particle_flag_align_y = true
	e.color = Color(1.0, 0.7, 0.3)
	var em := BoxMesh.new()
	em.size = Vector3(0.012, 0.09, 0.012)
	em.material = _ember_mat
	e.mesh = em
	_place(parent, e, at, dir)
	tree.create_timer(0.8).timeout.connect(e.queue_free)


## The puff that hangs at the muzzle and curls away.
static func _smoke(parent: Node, tree: SceneTree, at: Vector3, dir: Vector3, size: float) -> void:
	_make_materials()
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.randomness = 0.5
	p.amount = int(4 + 3 * size)
	p.lifetime = 1.4 + 0.5 * size
	p.local_coords = false
	p.direction = Vector3(0, 0, -1)
	p.spread = 35.0
	p.initial_velocity_min = 0.8 * size
	p.initial_velocity_max = 2.0 * size
	p.damping_min = 2.5
	p.damping_max = 4.0
	p.gravity = Vector3(0, 0.35, 0)
	p.angular_velocity_min = -40.0
	p.angular_velocity_max = 40.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.04 * size
	p.scale_amount_min = 0.16 * size
	p.scale_amount_max = 0.26 * size
	p.scale_amount_curve = _grow_curve(3.0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.08, 1.0])
	g.colors = PackedColorArray([Color(0.7, 0.69, 0.67, 0.0), Color(0.7, 0.69, 0.67, 0.34), Color(0.74, 0.74, 0.75, 0.0)])
	p.color_ramp = g
	p.color = Color(smoke_shade, smoke_shade, smoke_shade)
	var q := QuadMesh.new()
	q.material = _smoke_mat
	p.mesh = q
	_place(parent, p, at + dir * 0.06 * size, dir)
	tree.create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)


static func _place(parent: Node, p: CPUParticles3D, at: Vector3, dir: Vector3) -> void:
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Not before it is in place: it would puff once at the parent's origin.
	p.emitting = false
	# Hidden for its first frame: until it has run once its particles are
	# all drawn at full size in one place.
	p.visible = false
	parent.add_child(p)
	var up := Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	p.global_transform = Transform3D(Basis.looking_at(dir, up), at)
	p.emitting = true
	parent.get_tree().process_frame.connect(func(): if is_instance_valid(p): p.visible = true, CONNECT_ONE_SHOT)


static func _grow_curve(to: float) -> Curve:
	var c := Curve.new()
	c.max_value = to
	c.add_point(Vector2(0, 1.0))
	c.add_point(Vector2(0.25, to * 0.6))
	c.add_point(Vector2(1, to))
	return c


# --- looks --------------------------------------------------------------------------------

static func _make_meshes() -> void:
	if _star_mesh:
		return
	_make_materials()
	_star_mesh = QuadMesh.new()
	_star_mesh.size = Vector2(1, 1)
	_star_mesh.material = _star_mat
	_tongue_mesh = QuadMesh.new()
	_tongue_mesh.size = Vector2(1, 1)
	_tongue_mesh.material = _tongue_mat


static func _flame_material(tex: Texture2D) -> StandardMaterial3D:
	# Smooth fire colours with soft, feathered edges (no cel bands), a
	# little over full brightness so the glow setting blooms it.
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.disable_receive_shadows = true
	m.albedo_texture = tex
	m.albedo_color = Color(1.25, 1.15, 1.05)
	return m


static func _make_materials() -> void:
	if _smoke_mat:
		return
	_star_mat = _flame_material(_star_texture())
	_tongue_mat = _flame_material(_tongue_texture())
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ember_mat.vertex_color_use_as_albedo = true
	_ember_mat.albedo_color = Color(1.0, 1.0, 1.0)
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.billboard_keep_scale = true
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.albedo_texture = _puff_texture()


## Real fire colour from the white-hot middle (t = 0) out to the dim red
## edge (1), smooth, with the brightness falling away as it goes.
static func _fire(t: float) -> Color:
	t = clampf(t, 0.0, 1.0)
	var hot := Color(1.0, 0.96, 0.86)
	var mid := Color(1.0, 0.72, 0.3)
	var edge := Color(0.85, 0.32, 0.08)
	var c := hot.lerp(mid, smoothstep(0.0, 0.45, t)).lerp(edge, smoothstep(0.4, 1.0, t))
	# Opacity falls away smoothly to nothing at the edge.
	c.a = pow(1.0 - t, 0.7)
	return c


static func _noise(sd: int, freq: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = sd
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = 3
	return n


## The flash seen down the barrel: a hot core with ragged, uneven petals and
## fine streaks, all soft-edged.
static func _star_texture() -> Texture2D:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var points := 5
	var lens := []
	for i in points:
		lens.append(rng.randf_range(0.6, 1.0))
	var streak := _noise(11, 6.0)
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := v.length()
			var ang := fposmod(v.angle(), TAU)
			var a := ang / TAU * points
			var k := int(a) % points
			var f := a - floorf(a)
			var spike := lerpf(float(lens[k]), float(lens[(k + 1) % points]), smoothstep(0.0, 1.0, f))
			var petal := 0.28 + 0.72 * spike * pow(absf(cos(f * PI)), 3.0)
			# Thin streaks of burning powder running out from the middle.
			petal *= 0.8 + 0.4 * streak.get_noise_2d(cos(ang) * 3.0, sin(ang) * 3.0)
			var t := r / maxf(petal, 0.2)
			var c := _fire(t * 0.95)
			# Soft round core on top, so the middle burns out to white.
			var core := exp(-r * r * 22.0)
			c = c.lerp(Color(1.0, 0.97, 0.9, 1.0), core)
			c.a = maxf(c.a, core)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## A tongue of flame from the side: bright and fat at the muzzle, breaking
## up into flickering wisps toward the tip.
static func _tongue_texture() -> Texture2D:
	var w := 64
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var wisp := _noise(23, 0.09)
	for y in h:
		# v: 0 at the muzzle, 1 at the tip (texture V runs top-down, and the
		# quad's top is +Y, pointing away from the muzzle).
		var v := 1.0 - (y + 0.5) / h
		var width := pow(sin(PI * pow(v, 0.5)), 1.2) * (1.0 - 0.4 * v)
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var wob := wisp.get_noise_2d(u * 10.0, v * 40.0)
			var wu := absf(u + wob * 0.25 * v) / maxf(width * (0.85 + 0.3 * wob), 0.001)
			if width <= 0.001:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var t := clampf(maxf(wu, 0.0) * 0.6 + v * 0.45, 0.0, 1.0)
			var c := _fire(t)
			var fade := smoothstep(0.0, 0.6, 1.0 - wu)
			c.a *= fade
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Smoke puff: a soft blob in two flat tones, so it reads as cel smoke.
static func _puff_texture() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var v := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var ang := v.angle()
			var r := v.length() / (0.86 + 0.1 * sin(ang * 5.0) + 0.04 * sin(ang * 11.0))
			var a := 0.0
			if r < 0.62:
				a = 1.0
			elif r < 1.0:
				a = lerpf(0.7, 0.0, smoothstep(0.62, 1.0, r))
			var shade := 1.0 if v.y < 0.15 else 0.93
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return ImageTexture.create_from_image(img)
