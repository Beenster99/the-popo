class_name Car
extends RigidBody3D
## Phase 0.4 box car. Raycast suspension on a Jolt rigid body, tuned for
## arcade-sim handling from the isometric camera: grippy at speed, slides
## with the handbrake, and assisted so it is easy to steer from above.
## The body mesh dents where it is hit and the front bumper can come off.

signal dented(local_point: Vector3, local_dir: Vector3, amount: float)
signal bumper_lost
signal part_lost(part_name: String)
signal hit_piece(piece_id: int, impulse: float)

const SIZE := Vector3(1.86, 0.9, 4.3)
const WHEEL_RADIUS := 0.36
const REST := 0.42          # suspension rest length
const SPRING := 42000.0     # N/m
const DAMP := 3800.0        # N s/m
const ENGINE := 9500.0      # N at the wheels at low speed
const TOP_SPEED := 38.0     # m/s, about 85 mph
const BRAKE := 14000.0
const ENGINE_BRAKE := 900.0  # N per driven wheel when off the throttle
const ROLLING := 0.015       # tyre rolling resistance, fraction of wheel load
const GRIP := 9.0           # lateral stiffness per unit load
const MU := 1.25            # tyre friction coefficient
## Wave 4: how much grip the roads give right now (CityWeather: wet roads 0.7).
static var grip_k := 1.0
## v0.8.1: the handbrake was far too strong (rear grip near zero, twice the
## yaw ask and most of the full brake on each rear wheel). Softer now: the
## tail steps out and the car slows, but it no longer spins on the spot.
const HANDBRAKE_REAR_GRIP := 0.5
const YAW_ASSIST := 0.55
const HANDBRAKE_YAW := 1.15
const REAR_GRIP := 0.75         # rear tyres grip less than the fronts: the tail steps out
const HANDBRAKE_LOCK := 0.3     # share of BRAKE the handbrake puts on each rear wheel
## v0.8.1: sideways tyre forces push at this share of the way from the road up to the
## car's centre, as arcade racers do, so hard cornering leans the body
## instead of tipping it over.
const ROLL_CENTRE := 0.7
## Anti-roll: resists body lean (N m per radian, per kg) and lean speed.
const ANTI_ROLL := 14.0
const ANTI_ROLL_DAMP := 2.5
const STEER_MAX := 0.6      # rad at low speed
const STEER_MIN := 0.12     # rad at top speed

@export var color := Color("ecebe6")
## Wave 2 (Phase 2.4): every vehicle type sets its own size and handling
## before it enters the tree (the constants above are the Phase 0.4 car's).
var size := SIZE
var wheel_radius := WHEEL_RADIUS
var rest := REST
var spring := SPRING
var damp := DAMP
var engine := ENGINE
var top_speed := TOP_SPEED
var brake_force := BRAKE
var steer_max := STEER_MAX
var steer_min := STEER_MIN
var yaw_assist := YAW_ASSIST
## Upper body collider (the cabin): [size, centre].
var cabin_box := [Vector3(1.6, 0.6, 2.1), Vector3(0, 0.75, -0.2)]
## Wheel mounts in car space, or empty for the Phase 0.4 four.
var wheel_mounts: Array = []
## Driving input, set by whoever simulates this car.
var throttle := 0.0
var steer := 0.0
var brake := 0.0
var handbrake := false
var horn := false
var _horn_player: AudioStreamPlayer3D

var net_id := 0
## Phase 1.5: burnt out after it went up. No engine, charred black.
var wrecked := false
## Every dent so far [local point, local dir, amount], so a friend joining
## late or a saved game gets the same crumpled car (Phase 1.7).
var dent_log: Array = []
const DENT_LOG_MAX := 200
var bumper_attached := true
var _wheels: Array = []     # [{pos: local mount, front: bool, rear: bool, node: Node3D, compress: float}]
## v0.12.0 skid marks: a friend's copy of the car (frozen, following the
## host) estimates its tyres' slide from how it moved since last tick.
var _skid_prev := Transform3D()
var _skid_prev_v := Vector3.ZERO
var _skid_ok := false
var _steer_smooth := 0.0
var _body_mesh: ArrayMesh
var _body_mi: MeshInstance3D
var _bumper: MeshInstance3D
var _dent_cooldown := 0.0
## Meshes that dent: [{mi, mesh: ArrayMesh, inv: Transform3D (car -> mesh),
## surfaces: [{arrays, verts, rest}]}]
var _deform: Array = []
## Parts that come off: name -> {node: Node3D, box: AABB (car space),
## damage: float, limit: float, mass: float}
var parts := {}


func _init() -> void:
	mass = 1250.0
	collision_layer = 4
	# Not people (layer 2): TrafficSystem knocks down whoever a car hits,
	# instead of the car stopping dead against them like a post.
	collision_mask = 1 | 4 | 16 | 32
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.15, 0.1)
	angular_damp = 1.0
	can_sleep = false


func _ready() -> void:
	_horn_player = AudioStreamPlayer3D.new()
	var horn_wav: AudioStreamWAV = load("res://assets/audio/sfx/car_horn_1.wav")
	horn_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	horn_wav.loop_begin = 0
	horn_wav.loop_end = horn_wav.data.size() / 2  # 16-bit mono frames
	_horn_player.stream = horn_wav
	_horn_player.position = Vector3(0, 0.6, size.z * 0.45)
	_horn_player.unit_size = 8.0
	_horn_player.max_distance = 120.0
	_horn_player.bus = "SFX"
	add_child(_horn_player)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	add_child(cs)
	if not cabin_box.is_empty():
		var cabin := CollisionShape3D.new()
		var cbs := BoxShape3D.new()
		cbs.size = cabin_box[0]
		cabin.shape = cbs
		cabin.position = cabin_box[1]
		add_child(cabin)
	_build_body()
	if wheel_mounts.is_empty():
		for x in [-0.8, 0.8]:
			for z in [1.35, -1.35]:
				wheel_mounts.append(Vector3(x, -0.25, z))
	var front_z := -INF
	for m in wheel_mounts:
		front_z = maxf(front_z, (m as Vector3).z)
	for m in wheel_mounts:
		var holder := Node3D.new()
		holder.add_child(_make_wheel())
		add_child(holder)
		var front: bool = absf((m as Vector3).z - front_z) < 0.3
		_wheels.append({"pos": m, "front": front, "node": holder, "compress": 0.0, "spin": 0.0,
			"ground": Vector3.ZERO, "normal": Vector3.UP, "slide": -1.0})


## The car's look: the Phase 0.4 box car. PoliceCar replaces it.
func _build_body() -> void:
	_build_body_mesh()
	_build_details()


## One wheel's mesh, its axle along x.
func _make_wheel() -> Node3D:
	var wn := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = WHEEL_RADIUS
	cm.bottom_radius = WHEEL_RADIUS
	cm.height = 0.26
	cm.radial_segments = 14
	wn.mesh = cm
	wn.material_override = Cel.material(Color("1c1c20"))
	wn.rotation_degrees.z = 90
	return wn


## Lets a mesh dent. Its surfaces are copied into editable arrays.
func add_deformable(mi: MeshInstance3D) -> void:
	var src := mi.mesh
	var mesh := ArrayMesh.new()
	var entry := {"mi": mi, "mesh": mesh, "surfaces": []}
	for i in src.get_surface_count():
		var arr := src.surface_get_arrays(i)
		var mat := mi.get_surface_override_material(i)
		if mat == null:
			mat = src.surface_get_material(i)
		entry.surfaces.append({"arrays": arr, "verts": (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(),
			"rest": (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate(), "mat": mat})
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(i, mat)
	for i in src.get_surface_count():
		mi.set_surface_override_material(i, null)
	mi.mesh = mesh
	_deform.append(entry)


## A part that can be knocked off: once its damage passes limit it falls
## away as a loose body. box is its bounds in the car's space.
func add_part(part_name: String, node: Node3D, limit: float, part_mass := 12.0) -> void:
	var box := AABB()
	var first := true
	for mi in [node] + node.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D:
			var b: AABB = _local_xf(mi) * (mi as MeshInstance3D).get_aabb()
			box = b if first else box.merge(b)
			first = false
	parts[part_name] = {"node": node, "box": box, "damage": 0.0, "limit": limit, "mass": part_mass}


func _local_xf(n: Node3D) -> Transform3D:
	var xf := n.transform
	var p := n.get_parent()
	while p and p != self and p is Node3D:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func has_part(part_name: String) -> bool:
	return parts.has(part_name)


func _build_details() -> void:
	var glass := MeshInstance3D.new()
	var gb := BoxMesh.new()
	gb.size = Vector3(1.62, 0.55, 2.0)
	glass.mesh = gb
	glass.position = Vector3(0, 0.74, -0.2)
	glass.material_override = Cel.material(Color("27303a"))
	add_child(glass)
	_bumper = MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.9, 0.28, 0.22)
	_bumper.mesh = bb
	_bumper.position = Vector3(0, -0.22, SIZE.z * 0.5 + 0.08)
	_bumper.material_override = Cel.material(Color("2a2a2e"))
	add_child(_bumper)
	add_part("bumper_f", _bumper, 0.19, 18.0)
	for x in [-0.55, 0.55]:
		var lamp := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.4, 0.14, 0.06)
		lamp.mesh = lb
		lamp.position = Vector3(x, 0.12, SIZE.z * 0.5 + 0.01)
		lamp.material_override = Cel.material(Color("fff4c2"), false)
		add_child(lamp)


## Subdivided box so dents have vertices to move.
func _build_body_mesh() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var div := Vector3i(6, 3, 12)
	var h := SIZE * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP, div.z, div.y],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP, div.z, div.y],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK, div.x, div.z],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD, div.x, div.z],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP, div.x, div.y],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, div.x, div.y],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var nu: int = f[3]
		var nv: int = f[4]
		for i in nu:
			for j in nv:
				var quad := []
				for d in [[0, 0], [1, 0], [1, 1], [0, 1]]:
					var a: float = (i + d[0]) / float(nu) * 2.0 - 1.0
					var b: float = (j + d[1]) / float(nv) * 2.0 - 1.0
					quad.append((n + u * a + v * b) * h)
				# Godot treats clockwise triangles as front faces.
				var order := [0, 2, 1, 0, 3, 2] if u.cross(v).dot(n) > 0.0 else [0, 1, 2, 0, 2, 3]
				for k in order:
					st.set_normal(n)
					st.add_vertex(quad[k])
	st.index()
	_body_mesh = st.commit()
	_body_mi = MeshInstance3D.new()
	_body_mi.mesh = _body_mesh
	_body_mi.set_surface_override_material(0, Cel.material(color))
	add_child(_body_mi)
	add_deformable(_body_mi)


## Push body vertices near a local point inward. Deterministic, so every
## machine applies the same dent from the same event. Parts near the dent
## take damage and come off once they have had enough.
func apply_dent(local_point: Vector3, local_dir: Vector3, amount: float) -> void:
	if dent_log.size() < DENT_LOG_MAX:
		dent_log.append([local_point, local_dir, amount])
	var radius := 0.5 + amount * 1.2
	for e in _deform:
		var mi: MeshInstance3D = e.mi
		if not is_instance_valid(mi) or not is_ancestor_of(mi):
			continue   # knocked off
		var to_mesh := _local_xf(mi).affine_inverse()
		var p := to_mesh * local_point
		var d := (to_mesh.basis * local_dir).normalized()
		var mesh: ArrayMesh = e.mesh
		var changed := false
		for si in e.surfaces.size():
			var sf: Dictionary = e.surfaces[si]
			var verts: PackedVector3Array = sf.verts
			var rest: PackedVector3Array = sf.rest
			for i in verts.size():
				var dist := verts[i].distance_to(p)
				if dist < radius:
					var falloff := 1.0 - dist / radius
					verts[i] += d * amount * falloff * falloff
					# Never cave more than 45 cm from the original shape.
					var off := verts[i] - rest[i]
					if off.length() > 0.45:
						verts[i] = rest[i] + off.normalized() * 0.45
					changed = true
			sf.verts = verts
		if changed:
			mesh.clear_surfaces()
			for si in e.surfaces.size():
				var sf: Dictionary = e.surfaces[si]
				var arr: Array = sf.arrays
				arr[Mesh.ARRAY_VERTEX] = sf.verts
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				mesh.surface_set_material(si, sf.mat)
	for n in parts.keys():
		var part: Dictionary = parts[n]
		var gap := _box_distance(part.box, local_point)
		if gap < radius:
			part.damage += amount * (1.0 - gap / radius) * 1.6
			if part.damage >= part.limit:
				detach_part(n, local_dir * -1.0)


static func _box_distance(b: AABB, p: Vector3) -> float:
	var q := p.clamp(b.position, b.end)
	return q.distance_to(p)


## Box car: the front bumper.
func detach_bumper() -> void:
	detach_part("bumper_f", Vector3.FORWARD)


## Knocks a part off: it becomes a loose body that tumbles away.
func detach_part(part_name: String, push := Vector3.ZERO) -> void:
	if not parts.has(part_name):
		return
	var part: Dictionary = parts[part_name]
	parts.erase(part_name)
	var node: Node3D = part.node
	if not is_instance_valid(node):
		return
	if part_name == "bumper_f":
		bumper_attached = false
		bumper_lost.emit()
	part_lost.emit(part_name)
	var box: AABB = part.box
	var rb := RigidBody3D.new()
	rb.mass = part.mass
	rb.collision_layer = 16
	rb.collision_mask = 1 | 4 | 16
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = box.size.max(Vector3(0.04, 0.04, 0.04))
	cs.shape = bs
	rb.add_child(cs)
	var gxf := node.global_transform if node.is_inside_tree() else global_transform * _local_xf(node)
	var centre_g := global_transform * box.get_center() if is_inside_tree() else box.get_center()
	node.get_parent().remove_child(node)
	rb.add_child(node)
	var host := get_parent() if get_parent() else self
	host.add_child(rb)
	rb.global_transform = Transform3D(global_transform.basis.orthonormalized(), centre_g)
	node.global_transform = gxf
	cs.position = Vector3.ZERO
	var out := (box.get_center() * Vector3(1, 0, 1)).normalized()
	if push != Vector3.ZERO:
		out = (out + global_transform.basis * push * 0.5).normalized()
	rb.linear_velocity = linear_velocity * 0.7 + global_transform.basis * out * 1.5 + Vector3.UP * 1.5
	rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))
	rb.add_to_group("car_debris")


## Deepest dent in metres.
func wreck() -> void:
	if wrecked:
		return
	wrecked = true
	throttle = 0.0
	horn = false
	var char_mat := Cel.material(Color("1c1a19"), true, 0.02)
	var stack: Array = [self]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				for i in mi.get_surface_override_material_count():
					mi.set_surface_override_material(i, null)
				mi.material_override = char_mat
			elif c is Light3D:
				(c as Light3D).visible = false
	if get("lights") != null:
		set("lights", false)
		set("siren", 0)


func dent_amount() -> float:
	var deepest := 0.0
	for e in _deform:
		for sf in e.surfaces:
			var verts: PackedVector3Array = sf.verts
			var rest: PackedVector3Array = sf.rest
			for i in verts.size():
				deepest = maxf(deepest, verts[i].distance_to(rest[i]))
	return deepest


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


## v0.19.0: past this (m) from the camera a car's tyres are simplified.
const FAR := 110.0
var _far := false
var _tick_n := 0
var _still_t := 0.0


func _physics_process(delta: float) -> void:
	if horn != _horn_player.playing:
		if horn:
			_horn_player.play()
		else:
			_horn_player.stop()
	_dent_cooldown -= delta
	if freeze:
		_update_wheel_visuals(delta, false)
		_estimate_skids(delta)
		return
	_skid_ok = false
	# v0.19.0: cars well away from the camera do less each tick.
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	_far = cam != null and cam.global_position.distance_squared_to(global_position) > FAR * FAR
	if not _far:
		_lay_skids()
	# v0.8.1: a car nobody is driving may fall asleep (parked cars were
	# simulated every tick forever); any input wakes it.
	# (v0.19.0: a parked car has its handbrake on; that alone is not
	# driving it, or no parked car ever slept.)
	var driven := absf(throttle) > 0.01 or absf(steer) > 0.01 \
		or ((brake > 0.0 or handbrake) and linear_velocity.length_squared() > 0.25)
	can_sleep = not driven
	if driven and sleeping:
		sleeping = false
	# Jolt keeps a body awake while forces are put on it (the suspension
	# does, every tick), so a car standing still is put to sleep here.
	if not driven and not sleeping and linear_velocity.length_squared() < 0.02 and angular_velocity.length_squared() < 0.02:
		_still_t += delta
		if _still_t > 1.0:
			sleeping = true
	else:
		_still_t = 0.0


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if freeze:
		return
	var dt := state.step
	var xf := state.transform
	var fwd := xf.basis.z
	var right := xf.basis.x
	var up := xf.basis.y
	var vel := state.linear_velocity
	var fwd_speed := vel.dot(fwd)
	var speed_t: float = clamp(absf(fwd_speed) / top_speed, 0.0, 1.0)
	_steer_smooth = move_toward(_steer_smooth, steer, dt * 3.5)
	var steer_angle: float = _steer_smooth * lerpf(steer_max, steer_min, speed_t)
	var space := state.get_space_state()
	var grounded := 0
	_tick_n += 1
	var reuse := _far and (_tick_n + get_instance_id()) % 2 == 0
	for w in _wheels:
		var mount: Vector3 = xf * (w.pos as Vector3)
		var hit: Dictionary
		# v0.19.0: a car far from the camera feels the road every other tick
		# (the last hit, carried along with the car, in between).
		if reuse and w.has("hit_d") and float(w.hit_d) >= 0.0:
			hit = {"position": mount - up * (float(w.hit_d) + wheel_radius), "normal": w.hit_n}
		else:
			var q := PhysicsRayQueryParameters3D.create(mount, mount - up * (rest + wheel_radius), 1 | 4 | 16 | 32, [get_rid()])
			hit = space.intersect_ray(q)
			w.hit_d = (hit.position as Vector3).distance_to(mount) - wheel_radius if not hit.is_empty() else -1.0
			if not hit.is_empty():
				w.hit_n = hit.normal
		if hit.is_empty():
			w.compress = 0.0
			w.slide = -1.0
			continue
		grounded += 1
		var dist: float = (hit.position as Vector3).distance_to(mount) - wheel_radius
		var compress := rest - dist
		var comp_speed: float = (compress - w.compress) / dt
		w.compress = compress
		var load: float = max(0.0, spring * compress + damp * comp_speed)
		var contact: Vector3 = hit.position
		var rel := contact - xf.origin
		state.apply_force(up * load, rel)
		# Tyre directions for this wheel.
		var wfwd := fwd
		var wright := right
		if w.front:
			wfwd = fwd.rotated(up, steer_angle)
			wright = right.rotated(up, steer_angle)
		var pv := state.get_velocity_at_local_position(rel)
		var lat_v := pv.dot(wright)
		var lon_v := pv.dot(wfwd)
		var grip := GRIP * grip_k
		if not w.front:
			grip *= REAR_GRIP
			if handbrake:
				grip *= HANDBRAKE_REAR_GRIP
		var lat_f := -lat_v * grip * load / 9.81 * 0.5
		var lon_f := 0.0
		if not w.front:
			var drive := throttle * engine * 0.5 * (1.0 - speed_t * speed_t)
			if throttle < 0.0:
				drive = throttle * engine * 0.35 * (1.0 if fwd_speed > -9.0 else 0.0)
			lon_f += drive
		if brake > 0.0 or (handbrake and not w.front):
			var b := (brake_force * 0.25 * brake) + (brake_force * HANDBRAKE_LOCK if handbrake and not w.front else 0.0)
			lon_f -= sign(lon_v) * min(b, absf(lon_v) * mass * 2.0)
		# Off the throttle the engine drags the driven wheels, and every tyre
		# has a little rolling resistance, so a coasting car comes to rest
		# instead of creeping for half a minute. Clamped so it never pushes
		# the car backwards.
		var drag := load * ROLLING
		if not w.front and absf(throttle) < 0.01:
			drag += ENGINE_BRAKE
		lon_f -= sign(lon_v) * minf(drag, absf(lon_v) * mass * 0.5)
		lon_f -= lon_v * 25.0  # air and bearing drag
		# Friction circle.
		var limit: float = MU * grip_k * load * (0.5 if handbrake and not w.front else 1.0)
		var f := Vector2(lat_f, lon_f)
		w.ground = hit.position
		w.normal = hit.normal
		w.slide = tyre_slide(f.length() / maxf(limit, 1.0), lat_v, lon_v, brake, handbrake and not w.front)
		if f.length() > limit:
			f = f.normalized() * limit
		# Tyre forces act up near the centre height (ROLL_CENTRE) so they
		# lean the car rather than flip it.
		var at := rel - up * rel.dot(up) * ROLL_CENTRE
		state.apply_force(wright * f.x, at)
		state.apply_force(wfwd * f.y, rel)
		w.spin += lon_v * dt / wheel_radius
	if grounded >= 2:
		# Assists: a little downforce and yaw damping so it reads well from above.
		state.apply_central_force(-up * vel.length_squared() * 2.5)
		var yaw_rate := state.angular_velocity.dot(up)
		# It asks for more rotation than the tyres can follow, so the tail
		# steps out (oversteer); the handbrake asks for much more again.
		var wanted_yaw := _steer_smooth * fwd_speed * yaw_assist * (HANDBRAKE_YAW if handbrake else 1.0)
		state.apply_torque(up * (wanted_yaw - yaw_rate) * mass * 0.9)
		# Anti-roll bar: pull the body back level about its long axis.
		var roll := asin(clampf(right.dot(Vector3.UP), -1.0, 1.0))
		var roll_rate := state.angular_velocity.dot(fwd)
		state.apply_torque(-fwd * (roll * ANTI_ROLL + roll_rate * ANTI_ROLL_DAMP) * mass)
	_detect_impacts(state)
	if not _far:
		_update_wheel_visuals(dt, true, steer_angle)


## How hard a tyre is sliding, 0 (gripping) to 1, for the skid marks.
## over: how far the tyre's wanted force is past what the road can give
## (1 = right at the limit); lat_v / lon_v: the tyre's sideways and rolling
## speed (m/s); locked_rear: the handbrake is on this wheel.
static func tyre_slide(over: float, lat_v: float, lon_v: float, brake_in: float, locked_rear: bool) -> float:
	var speed := Vector2(lat_v, lon_v).length()
	if speed < 2.0:
		return 0.0
	var k := clampf((over - 1.15) / 1.0, 0.0, 1.0)
	# Sideways: past a slip angle a road tyre doesn't hold (about 7 degrees).
	k = maxf(k, clampf((absf(lat_v) - maxf(2.0, speed * 0.12)) / 4.0, 0.0, 1.0))
	if brake_in > 0.85 and absf(lon_v) > 4.0:
		k = maxf(k, 0.6)   # a stamp on the brakes: the tyres lock
	if locked_rear and absf(lon_v) > 2.0:
		k = maxf(k, 0.8)
	return k


func _lay_skids() -> void:
	var marks := SkidMarks.for_tree(get_tree()) if is_inside_tree() else null
	if marks == null:
		return
	var base := get_instance_id() * 8
	for i in _wheels.size():
		var w: Dictionary = _wheels[i]
		if w.slide < 0.0:
			marks.lift(base + i)
		else:
			marks.wheel(base + i, w.ground, w.normal, w.slide)


## A friend's copy: no tyre physics here, so judge the slide from the
## motion: each wheel's sideways speed, and hard braking from the slowdown.
func _estimate_skids(delta: float) -> void:
	var xf := global_transform
	if not _skid_ok or delta <= 0.0:
		_skid_prev = xf
		_skid_ok = true
		_skid_prev_v = Vector3.ZERO
		return
	var v := (xf.origin - _skid_prev.origin) / delta
	var turn := (_skid_prev.basis.inverse() * xf.basis).get_rotation_quaternion()
	var w_rate := turn.get_axis() * turn.get_angle() / delta if turn.get_angle() > 0.0001 else Vector3.ZERO
	w_rate = _skid_prev.basis * w_rate
	var decel := (_skid_prev_v.length() - v.length()) / delta
	_skid_prev = xf
	_skid_prev_v = v
	var marks := SkidMarks.for_tree(get_tree()) if is_inside_tree() else null
	if marks == null:
		return
	var up := xf.basis.y
	var space := get_world_3d().direct_space_state
	var base := get_instance_id() * 8
	for i in _wheels.size():
		var w: Dictionary = _wheels[i]
		var mount: Vector3 = xf * (w.pos as Vector3)
		var pv := v + w_rate.cross(mount - xf.origin)
		var slide := tyre_slide(0.0, pv.dot(xf.basis.x), pv.dot(xf.basis.z), 1.0 if decel > 7.0 else 0.0, false)
		if slide < 0.05:
			marks.lift(base + i)
			continue
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(mount, mount - up * (rest + wheel_radius + 0.2), 1 | 16, [get_rid()]))
		if hit.is_empty():
			marks.lift(base + i)
		else:
			marks.wheel(base + i, hit.position, hit.normal, slide)


func _detect_impacts(state: PhysicsDirectBodyState3D) -> void:
	for i in state.get_contact_count():
		var imp := state.get_contact_impulse(i).length()
		var collider := state.get_contact_collider_object(i)
		if collider is Node and (collider as Node).has_meta("piece_id") and imp > 2500.0:
			hit_piece.emit((collider as Node).get_meta("piece_id"), imp)
		if imp < 3500.0 or _dent_cooldown > 0.0:
			continue
		_dent_cooldown = 0.12
		var world_point := state.get_contact_local_position(i)
		var n := state.get_contact_local_normal(i)
		var lp := state.transform.affine_inverse() * world_point
		var ld := state.transform.basis.inverse() * n
		var amount: float = clamp((imp - 3500.0) / 30000.0, 0.03, 0.3)
		dented.emit(lp, ld.normalized(), amount)


func _update_wheel_visuals(dt: float, simulated: bool, steer_angle := 0.0) -> void:
	for w in _wheels:
		var node: Node3D = w.node
		var drop: float = rest - w.compress if simulated else rest * 0.5
		node.position = (w.pos as Vector3) + Vector3(0, -drop, 0)
		node.rotation = Vector3(w.spin, steer_angle if w.front else 0.0, 0)


## Network state ---------------------------------------------------------------

func encode_state(b: StreamPeerBuffer) -> void:
	var xf := global_transform
	for v in [xf.origin, linear_velocity, angular_velocity]:
		b.put_float(v.x)
		b.put_float(v.y)
		b.put_float(v.z)
	var q := xf.basis.get_rotation_quaternion()
	b.put_float(q.x)
	b.put_float(q.y)
	b.put_float(q.z)
	b.put_float(q.w)
	b.put_half(steer)
	b.put_u8(1 if horn else 0)


static func decode_state(b: StreamPeerBuffer) -> Dictionary:
	var o := Vector3(b.get_float(), b.get_float(), b.get_float())
	var lv := Vector3(b.get_float(), b.get_float(), b.get_float())
	var av := Vector3(b.get_float(), b.get_float(), b.get_float())
	var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
	return {"pos": o, "lv": lv, "av": av, "rot": q, "steer": b.get_half(), "horn": b.get_u8() == 1}
