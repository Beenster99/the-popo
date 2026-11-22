class_name Feel
extends RefCounted
## Phase 1.5: how hits feel. Camera shake (your shots, blasts, rounds
## cracking past you, getting hit), a hit marker on the reticle when your
## bullet lands on someone, a short hit-stop when playing on your own, the
## muzzle flash light, and the extinguisher's cloud.

const CAMERA_GROUP := "iso_camera"

## When the local player's last hit on a person landed (ms), for the reticle.
static var last_hit_ms := -100000
static var _stopping := false


static func shake(tree: SceneTree, amount: float) -> void:
	if tree == null:
		return
	for c in tree.get_nodes_in_group(CAMERA_GROUP):
		if c.has_method("shake"):
			c.shake(amount)


## Shake by how close the blast was to the camera's subject.
static func blast_shake(tree: SceneTree, at: Vector3, radius: float) -> void:
	for c in tree.get_nodes_in_group(CAMERA_GROUP):
		var tgt: Node3D = c.get("target")
		var from: Vector3 = tgt.global_position if tgt and is_instance_valid(tgt) else (c as Node3D).global_position
		var d := from.distance_to(at)
		var k := clampf(1.0 - d / (radius * 8.0), 0.0, 1.0)
		if k > 0.0 and c.has_method("shake"):
			c.shake(0.25 + k * 0.75)


## Your bullet or fist landed on someone.
static func hit_marker(tree: SceneTree, hard := false) -> void:
	last_hit_ms = Time.get_ticks_msec()
	shake(tree, 0.12 if not hard else 0.2)
	hit_stop(tree, 0.045 if not hard else 0.07)


## A blink of slow motion on a landed hit, only when nobody else is playing
## (pausing the shared world online would be unfair on the others).
static func hit_stop(tree: SceneTree, seconds: float) -> void:
	if Net.is_online() or _stopping or tree == null or DisplayServer.get_name() == "headless":
		return
	_stopping = true
	Engine.time_scale = 0.08
	tree.create_timer(seconds, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0
		_stopping = false)


## The muzzle lights up the room for a frame or two.
static func muzzle(parent: Node, at: Vector3, big := false) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var flash := OmniLight3D.new()
	flash.light_color = Color("ffd38a")
	flash.light_energy = 5.0 if big else 3.5
	flash.omni_range = 6.0 if big else 4.5
	flash.shadow_enabled = false
	parent.add_child(flash)
	flash.global_position = at
	parent.get_tree().create_timer(0.05).timeout.connect(flash.queue_free)


## A burst extinguisher: a thick white cloud that hangs a few seconds.
static func cloud(parent: Node, at: Vector3, radius: float) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.85
	p.amount = 40
	p.lifetime = 4.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.3
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = radius * 0.6
	p.initial_velocity_max = radius * 1.2
	p.damping_min = radius * 0.6
	p.damping_max = radius * 0.9
	p.gravity = Vector3(0, 0.15, 0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.2
	var grad := Gradient.new()
	grad.set_color(0, Color(0.96, 0.96, 0.96, 0.9))
	grad.set_color(1, Color(0.9, 0.9, 0.92, 0.0))
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
	parent.add_child(p)
	p.global_position = at + Vector3(0, 0.4, 0)
	p.emitting = true
	parent.get_tree().create_timer(6.0).timeout.connect(p.queue_free)


## Where a bullet hit: sparks off metal, splinters off wood, a puff of dust
## off concrete, glints off glass.
static func impact(parent: Node, at: Vector3, from: Vector3, surface: String) -> void:
	if parent == null or not parent.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var back := (from - at).normalized() if from.distance_to(at) > 0.01 else Vector3.UP
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = back
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	var mesh: Mesh
	match surface:
		"metal":
			p.amount = 14
			p.lifetime = 0.35
			p.spread = 50.0
			p.initial_velocity_min = 4.0
			p.initial_velocity_max = 9.0
			p.gravity = Vector3(0, -12, 0)
			p.color = Color(1.0, 0.8, 0.35)
			m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			var bm := BoxMesh.new()
			bm.size = Vector3(0.015, 0.015, 0.09)
			mesh = bm
			p.particle_flag_align_y = true
			var spark := OmniLight3D.new()
			spark.light_color = Color(1.0, 0.75, 0.35)
			spark.light_energy = 2.0
			spark.omni_range = 2.0
			parent.add_child(spark)
			spark.global_position = at + back * 0.1
			parent.get_tree().create_timer(0.04).timeout.connect(spark.queue_free)
		"wood":
			p.amount = 8
			p.lifetime = 0.8
			p.spread = 40.0
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 4.0
			p.gravity = Vector3(0, -9.8, 0)
			p.color = Color("8a5a34")
			var wm := BoxMesh.new()
			wm.size = Vector3(0.02, 0.02, 0.08)
			mesh = wm
		"glass":
			p.amount = 8
			p.lifetime = 0.6
			p.spread = 60.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 3.0
			p.gravity = Vector3(0, -9.8, 0)
			p.color = Color(0.8, 0.92, 1.0)
			var gm := BoxMesh.new()
			gm.size = Vector3(0.03, 0.03, 0.005)
			mesh = gm
		_:
			p.amount = 6
			p.lifetime = 1.2
			p.spread = 35.0
			p.initial_velocity_min = 0.6
			p.initial_velocity_max = 1.6
			p.damping_min = 1.0
			p.damping_max = 2.0
			p.gravity = Vector3(0, -0.4, 0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.2
			var grad := Gradient.new()
			grad.set_color(0, Color(0.62, 0.6, 0.56, 0.55))
			grad.set_color(1, Color(0.62, 0.6, 0.56, 0.0))
			p.color_ramp = grad
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.albedo_texture = FireSystem.soft_texture()
			var q := QuadMesh.new()
			q.size = Vector2(0.35, 0.35)
			mesh = q
	(mesh as PrimitiveMesh).material = m
	p.mesh = mesh
	parent.add_child(p)
	p.global_position = at + back * 0.03
	p.emitting = true
	parent.get_tree().create_timer(p.lifetime + 0.5).timeout.connect(p.queue_free)
