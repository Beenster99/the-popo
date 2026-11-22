class_name Car
extends RigidBody3D
## Phase 0.4 box car. Raycast suspension on a Jolt rigid body, tuned for
## arcade-sim handling from the isometric camera: grippy at speed, slides
## with the handbrake, and assisted so it is easy to steer from above.
## The body mesh dents where it is hit and the front bumper can come off.

signal dented(local_point: Vector3, local_dir: Vector3, amount: float)
signal bumper_lost
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
const HANDBRAKE_REAR_GRIP := 0.25
const STEER_MAX := 0.6      # rad at low speed
const STEER_MIN := 0.12     # rad at top speed

@export var color := Color("ecebe6")
## Driving input, set by whoever simulates this car.
var throttle := 0.0
var steer := 0.0
var brake := 0.0
var handbrake := false

var net_id := 0
var bumper_attached := true
var _wheels: Array = []     # [{pos: local mount, front: bool, rear: bool, node: Node3D, compress: float}]
var _steer_smooth := 0.0
var _body_mesh: ArrayMesh
var _body_mi: MeshInstance3D
var _verts: PackedVector3Array
var _rest_verts: PackedVector3Array
var _normals: PackedVector3Array
var _indices: PackedInt32Array
var _bumper: MeshInstance3D
var _dent_cooldown := 0.0


func _init() -> void:
	mass = 1250.0
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 16 | 32
	contact_monitor = true
	max_contacts_reported = 8
	continuous_cd = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.15, 0.1)
	angular_damp = 1.0
	can_sleep = false


func _ready() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = SIZE
	cs.shape = bs
	add_child(cs)
	var cabin := CollisionShape3D.new()
	var cbs := BoxShape3D.new()
	cbs.size = Vector3(1.6, 0.6, 2.1)
	cabin.shape = cbs
	cabin.position = Vector3(0, 0.75, -0.2)
	add_child(cabin)
	_build_body_mesh()
	_build_details()
	for x in [-0.8, 0.8]:
		for z in [1.35, -1.35]:
			var wn := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = WHEEL_RADIUS
			cm.bottom_radius = WHEEL_RADIUS
			cm.height = 0.26
			cm.radial_segments = 14
			wn.mesh = cm
			wn.material_override = Cel.material(Color("1c1c20"))
			var holder := Node3D.new()
			holder.add_child(wn)
			wn.rotation_degrees.z = 90
			add_child(holder)
			_wheels.append({"pos": Vector3(x, -0.25, z), "front": z > 0, "node": holder, "compress": 0.0, "spin": 0.0})


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
	var arr := _body_mesh.surface_get_arrays(0)
	_verts = arr[Mesh.ARRAY_VERTEX]
	_rest_verts = _verts.duplicate()
	_normals = arr[Mesh.ARRAY_NORMAL]
	_indices = arr[Mesh.ARRAY_INDEX]
	_body_mi = MeshInstance3D.new()
	_body_mi.mesh = _body_mesh
	_body_mi.material_override = Cel.material(color)
	add_child(_body_mi)


## Push body vertices near a local point inward. Deterministic, so every
## machine applies the same dent from the same event.
func apply_dent(local_point: Vector3, local_dir: Vector3, amount: float) -> void:
	var radius := 0.5 + amount * 1.2
	for i in _verts.size():
		var d := _verts[i].distance_to(local_point)
		if d < radius:
			var falloff := 1.0 - d / radius
			_verts[i] += local_dir * amount * falloff * falloff
			# Never cave more than 45 cm from the original shape.
			var off := _verts[i] - _rest_verts[i]
			if off.length() > 0.45:
				_verts[i] = _rest_verts[i] + off.normalized() * 0.45
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = _verts
	arr[Mesh.ARRAY_NORMAL] = _normals
	arr[Mesh.ARRAY_INDEX] = _indices
	_body_mesh.clear_surfaces()
	_body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	if local_point.z > SIZE.z * 0.3 and amount > 0.12 and bumper_attached:
		detach_bumper()


func detach_bumper() -> void:
	if not bumper_attached:
		return
	bumper_attached = false
	bumper_lost.emit()
	var rb := RigidBody3D.new()
	rb.mass = 18.0
	rb.collision_layer = 16
	rb.collision_mask = 1 | 4 | 16
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = (_bumper.mesh as BoxMesh).size
	cs.shape = bs
	rb.add_child(cs)
	var gxf := _bumper.global_transform
	_bumper.get_parent().remove_child(_bumper)
	_bumper.transform = Transform3D.IDENTITY
	rb.add_child(_bumper)
	get_parent().add_child(rb)
	rb.global_transform = gxf
	rb.linear_velocity = linear_velocity * 0.7 + Vector3.UP * 1.5
	rb.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-4, 4), randf_range(-4, 4))


## Deepest dent in metres.
func dent_amount() -> float:
	var deepest := 0.0
	for i in _verts.size():
		deepest = maxf(deepest, _verts[i].distance_to(_rest_verts[i]))
	return deepest


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func _physics_process(delta: float) -> void:
	_dent_cooldown -= delta
	if freeze:
		_update_wheel_visuals(delta, false)
		return


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
	var speed_t: float = clamp(absf(fwd_speed) / TOP_SPEED, 0.0, 1.0)
	_steer_smooth = move_toward(_steer_smooth, steer, dt * 3.5)
	var steer_angle: float = _steer_smooth * lerpf(STEER_MAX, STEER_MIN, speed_t)
	var space := state.get_space_state()
	var grounded := 0
	for w in _wheels:
		var mount: Vector3 = xf * (w.pos as Vector3)
		var q := PhysicsRayQueryParameters3D.create(mount, mount - up * (REST + WHEEL_RADIUS), 1 | 4 | 16 | 32, [get_rid()])
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			w.compress = 0.0
			continue
		grounded += 1
		var dist: float = (hit.position as Vector3).distance_to(mount) - WHEEL_RADIUS
		var compress := REST - dist
		var comp_speed: float = (compress - w.compress) / dt
		w.compress = compress
		var load: float = max(0.0, SPRING * compress + DAMP * comp_speed)
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
		var grip := GRIP
		if not w.front and handbrake:
			grip *= HANDBRAKE_REAR_GRIP
		var lat_f := -lat_v * grip * load / 9.81 * 0.5
		var lon_f := 0.0
		if not w.front:
			var drive := throttle * ENGINE * 0.5 * (1.0 - speed_t * speed_t)
			if throttle < 0.0:
				drive = throttle * ENGINE * 0.35 * (1.0 if fwd_speed > -9.0 else 0.0)
			lon_f += drive
		if brake > 0.0 or (handbrake and not w.front):
			var b := (BRAKE * 0.25 * brake) + (BRAKE * 0.5 if handbrake and not w.front else 0.0)
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
		var limit: float = MU * load * (0.7 if handbrake and not w.front else 1.0)
		var f := Vector2(lat_f, lon_f)
		if f.length() > limit:
			f = f.normalized() * limit
		state.apply_force(wright * f.x + wfwd * f.y, rel)
		w.spin += lon_v * dt / WHEEL_RADIUS
	if grounded >= 2:
		# Assists: a little downforce and yaw damping so it reads well from above.
		state.apply_central_force(-up * vel.length_squared() * 2.5)
		var yaw_rate := state.angular_velocity.dot(up)
		var wanted_yaw := _steer_smooth * fwd_speed * 0.35 * (1.0 if not handbrake else 1.6)
		state.apply_torque(up * (wanted_yaw - yaw_rate) * mass * 0.9 * (0.4 if handbrake else 1.0))
	_detect_impacts(state)
	_update_wheel_visuals(dt, true, steer_angle)


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
		var drop: float = REST - w.compress if simulated else REST * 0.5
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


static func decode_state(b: StreamPeerBuffer) -> Dictionary:
	var o := Vector3(b.get_float(), b.get_float(), b.get_float())
	var lv := Vector3(b.get_float(), b.get_float(), b.get_float())
	var av := Vector3(b.get_float(), b.get_float(), b.get_float())
	var q := Quaternion(b.get_float(), b.get_float(), b.get_float(), b.get_float())
	return {"pos": o, "lv": lv, "av": av, "rot": q, "steer": b.get_half()}
