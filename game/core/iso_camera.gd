class_name IsoCamera
extends Node3D
## Isometric camera rig. Follows a target, rotates with Q/E (hold for smooth
## turn, tap to snap to the next 45 degrees) or by holding the middle mouse
## and dragging, and zooms with the mouse wheel.
## Orthographic by default for a true isometric read.

@export var target: Node3D
@export var pitch_deg := -35.264  # true isometric elevation
@export var distance := 40.0
@export var zoom := 16.0          # orthographic size
@export var zoom_min := 6.0
@export var zoom_max := 48.0
@export var rotate_speed_deg := 120.0
@export var follow_sharpness := 8.0

var camera: Camera3D
var _yaw := 45.0
var _yaw_target := 45.0
var _hold_t := 0.0
## Middle mouse held and dragged turns the camera (a click still pings).
const DRAG_DEG_PER_PX := 0.35
const DRAG_START_PX := 6.0
static var drag_px := 0.0      # how far the mouse moved since the middle button went down
var _dragging := false
## Phase 1.5: camera shake, 0..1, eased off over about half a second.
var trauma := 0.0
var _shake_t := 0.0
const SHAKE_MAX := 0.55        # m of sideways jolt at full trauma

## Third-person test view (Tab): the camera sits behind the officer's right
## shoulder, the mouse turns it, and shots go where the centre dot points.
## Static, so it carries over from scene to scene.
static var third_person := false
const TP_FOV := 70.0
const TP_SHOULDER := 0.55      # m to the right of the officer
const TP_PITCH_MIN := -65.0
const TP_PITCH_MAX := 55.0
const TP_MOUSE_DEG_PER_PX := 0.12
const TP_STICK_DEG_PER_S := 160.0
const TP_AIM_RANGE := 80.0
var tp_pitch := -10.0
var tp_distance := 3.2         # mouse wheel: 1.5 to 8 m
var _tp_height := 1.55
var _tp_pull := 3.2            # the distance after walls have pushed the camera in
var _tp_was := false
var _crosshair: CanvasLayer


func _ready() -> void:
	add_to_group(Feel.CAMERA_GROUP)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom
	camera.near = 0.5
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	# Runs while paused too, only to hand the mouse back to the menus.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_crosshair = CanvasLayer.new()
	_crosshair.layer = 5
	var dot := Control.new()
	dot.set_anchors_preset(Control.PRESET_FULL_RECT)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.draw.connect(func():
		var c := dot.size * 0.5
		dot.draw_circle(c, 3.5, Color(0, 0, 0, 0.6))
		dot.draw_circle(c, 2.0, Color(1.0, 0.95, 0.6)))
	dot.resized.connect(dot.queue_redraw)
	_crosshair.add_child(dot)
	_crosshair.visible = false
	add_child(_crosshair)
	_apply()


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func shake(amount: float) -> void:
	trauma = clampf(trauma + amount * float(Settings.values.get("camera_shake", 1.0)), 0.0, 1.0)


func yaw_rad() -> float:
	return deg_to_rad(_yaw)


## Converts WASD input into a world-space direction relative to the view.
func view_relative(input: Vector2) -> Vector3:
	var basis := Basis(Vector3.UP, yaw_rad())
	var v := basis * Vector3(input.x, 0, input.y)
	return v.limit_length(1.0)


## World point under the mouse on a horizontal plane at the given height.
func mouse_on_plane(height := 0.0) -> Vector3:
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var plane := Plane(Vector3.UP, height)
	var hit: Variant = plane.intersects_ray(from, dir)
	return hit if hit != null else global_position


## What the mouse points at: the first wall, prop, car or chunk under the
## cursor, else the point at chest height. Returns {point, normal, hit}.
func mouse_on_world(chest_height: float, exclude: Array[RID] = []) -> Dictionary:
	if third_person:
		return _centre_on_world(exclude)
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var ex := exclude.duplicate()
	var hit := {}
	# Look through ceilings, roofs and walls the cutaway has hidden.
	for i in 12:
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0, 1 | 4 | 16, ex)
		hit = get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or not (hit.collider as Object).get_meta("see_through", false):
			break
		ex.append(hit.rid)
		hit = {}
	if hit:
		return {"point": hit.position, "normal": hit.normal, "hit": true}
	return {"point": mouse_on_plane(chest_height), "normal": Vector3.UP, "hit": false}


## Third person: what the centre dot points at, people included. The ray
## starts level with the officer, so nothing behind them is picked.
func _centre_on_world(exclude: Array[RID]) -> Dictionary:
	var dir := -camera.global_basis.z
	var from := camera.global_position + dir * (_tp_pull + 0.3)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * TP_AIM_RANGE, 1 | 2 | 4 | 16, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		return {"point": hit.position, "normal": hit.normal, "hit": true}
	return {"point": from + dir * TP_AIM_RANGE, "normal": -dir, "hit": false}


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_view") and not PlayerInput.blocked:
		third_person = not third_person
	if third_person:
		var m := event as InputEventMouseMotion
		if m and not PlayerInput.blocked and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var k := TP_MOUSE_DEG_PER_PX * float(Settings.values.get("tp_sensitivity", 1.0))
			_yaw -= m.relative.x * k
			_yaw_target = _yaw
			tp_pitch = clampf(tp_pitch - m.relative.y * k, TP_PITCH_MIN, TP_PITCH_MAX)
		return
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = mb.pressed
		if mb.pressed:
			drag_px = 0.0
		else:
			# Settle on the turned angle rather than snapping back.
			_yaw_target = _yaw
	var mm := event as InputEventMouseMotion
	if mm and _dragging and not PlayerInput.blocked:
		drag_px += absf(mm.relative.x) + absf(mm.relative.y)
		if drag_px >= DRAG_START_PX:
			_yaw -= mm.relative.x * DRAG_DEG_PER_PX
			_yaw_target = _yaw


func _unhandled_input(event: InputEvent) -> void:
	if third_person:
		if event.is_action_pressed("cam_zoom_in"):
			tp_distance = clampf(tp_distance * 0.88, 1.5, 8.0)
		elif event.is_action_pressed("cam_zoom_out"):
			tp_distance = clampf(tp_distance / 0.88, 1.5, 8.0)
		return
	if event.is_action_pressed("cam_zoom_in"):
		zoom = clamp(zoom * 0.88, zoom_min, zoom_max)
	elif event.is_action_pressed("cam_zoom_out"):
		zoom = clamp(zoom / 0.88, zoom_min, zoom_max)
	elif event.is_action_released("cam_rotate_left") and _hold_t < 0.2:
		_yaw_target = snappedf(_yaw + 45.0 + 1.0, 45.0)
	elif event.is_action_released("cam_rotate_right") and _hold_t < 0.2:
		_yaw_target = snappedf(_yaw - 45.0 - 1.0, 45.0)


func _process(delta: float) -> void:
	var want := Input.MOUSE_MODE_CAPTURED if third_person and not PlayerInput.blocked and not get_tree().paused else Input.MOUSE_MODE_VISIBLE
	if Input.mouse_mode != want and (third_person or _tp_was):
		Input.mouse_mode = want
	if get_tree().paused:
		return
	if third_person != _tp_was:
		_tp_was = third_person
		_crosshair.visible = third_person
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE if third_person else Camera3D.PROJECTION_ORTHOGONAL
		camera.fov = TP_FOV
		camera.near = 0.1 if third_person else 0.5
		camera.far = 500.0 if third_person else 200.0
		if target and is_instance_valid(target):
			global_position = target.global_position
			if third_person:
				# Start out looking the way the officer faces.
				_yaw = rad_to_deg(target.rotation.y) + 180.0
				_yaw_target = _yaw
	if third_person:
		_process_third_person(delta)
		return
	var dir := Input.get_axis("cam_rotate_right", "cam_rotate_left")
	if dir != 0.0:
		_hold_t += delta
		if _hold_t >= 0.2:
			_yaw += dir * rotate_speed_deg * delta
			_yaw_target = _yaw
	else:
		_hold_t = 0.0
	_yaw = lerp(_yaw, _yaw_target, 1.0 - exp(-12.0 * delta))
	if target and is_instance_valid(target):
		global_position = global_position.lerp(target.global_position, 1.0 - exp(-follow_sharpness * delta))
	camera.size = lerp(camera.size, zoom, 1.0 - exp(-10.0 * delta))
	trauma = maxf(trauma - delta * 1.8, 0.0)
	_shake_t += delta
	_apply()


func _process_third_person(delta: float) -> void:
	if not PlayerInput.blocked:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", float(Settings.values.get("pad_deadzone", 0.25)))
		_yaw -= stick.x * TP_STICK_DEG_PER_S * delta
		tp_pitch = clampf(tp_pitch - stick.y * TP_STICK_DEG_PER_S * 0.6 * delta, TP_PITCH_MIN, TP_PITCH_MAX)
		_yaw_target = _yaw
	var height := 1.55
	var dist := tp_distance
	var shoulder := TP_SHOULDER
	var exclude: Array[RID] = []
	if target and is_instance_valid(target):
		if target is CollisionObject3D:
			exclude.append((target as CollisionObject3D).get_rid())
		var o := target as Officer
		if o:
			if o.car != null:
				# Driving: further back and centred, over the roof.
				height = 2.1
				dist = tp_distance * 2.0
				shoulder = 0.0
				exclude.append(o.car.get_rid())
			elif o.state == Officer.S.PRONE:
				height = 0.7
			elif o.state in [Officer.S.CROUCH, Officer.S.COVER]:
				height = 1.15
		global_position = global_position.lerp(target.global_position, 1.0 - exp(-25.0 * delta))
	_tp_height = lerpf(_tp_height, height, 1.0 - exp(-10.0 * delta))
	var b := Basis(Vector3.UP, deg_to_rad(_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(tp_pitch))
	var pivot := global_position + Vector3(0, _tp_height, 0)
	# Walls push the camera in: first the step out to the shoulder, then back.
	var space := get_world_3d().direct_space_state
	var side := b.x * shoulder
	if shoulder > 0.0:
		var hs := space.intersect_ray(PhysicsRayQueryParameters3D.create(pivot, pivot + side.normalized() * (shoulder + 0.25), 1 | 4 | 16, exclude))
		if hs:
			side = side.normalized() * maxf(pivot.distance_to(hs.position) - 0.25, 0.0)
	var from := pivot + side
	var back := b.z
	var reach := dist
	var hb := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + back * (dist + 0.3), 1 | 4 | 16, exclude))
	if hb:
		reach = clampf(from.distance_to(hb.position) - 0.3, 0.25, dist)
	# In fast, out slowly, so it does not pump next to railings and posts.
	_tp_pull = reach if reach < _tp_pull else lerpf(_tp_pull, reach, 1.0 - exp(-6.0 * delta))
	trauma = maxf(trauma - delta * 1.8, 0.0)
	_shake_t += delta
	var jolt := Vector3.ZERO
	if trauma > 0.0:
		var k := trauma * trauma * 0.12
		jolt = b * Vector3(sin(_shake_t * 61.0) + sin(_shake_t * 37.0) * 0.5, sin(_shake_t * 53.0 + 1.0) + sin(_shake_t * 29.0) * 0.5, 0) * k
	camera.global_transform = Transform3D(b, from + back * _tp_pull + jolt)


func _apply() -> void:
	if camera == null or third_person:
		return
	var b := Basis(Vector3.UP, deg_to_rad(_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	var jolt := Vector3.ZERO
	if trauma > 0.0:
		var k := trauma * trauma * SHAKE_MAX
		jolt = b * Vector3(sin(_shake_t * 61.0) + sin(_shake_t * 37.0) * 0.5, sin(_shake_t * 53.0 + 1.0) + sin(_shake_t * 29.0) * 0.5, 0) * k * 0.66
	camera.transform = Transform3D(b, b * Vector3(0, 0, distance) + jolt)
