class_name IsoCamera
extends Node3D
## Isometric camera rig. Follows a target, rotates with Q/E (hold for smooth
## turn, tap to snap to the next 45 degrees) and zooms with the mouse wheel.
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


func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = zoom
	camera.near = 0.5
	camera.far = 200.0
	add_child(camera)
	camera.make_current()
	_apply()


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
	var mp := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(mp)
	var dir := camera.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 500.0, 1 | 4 | 16, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		return {"point": hit.position, "normal": hit.normal, "hit": true}
	return {"point": mouse_on_plane(chest_height), "normal": Vector3.UP, "hit": false}


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("cam_zoom_in"):
		zoom = clamp(zoom * 0.88, zoom_min, zoom_max)
	elif event.is_action_pressed("cam_zoom_out"):
		zoom = clamp(zoom / 0.88, zoom_min, zoom_max)
	elif event.is_action_released("cam_rotate_left") and _hold_t < 0.2:
		_yaw_target = snappedf(_yaw + 45.0 + 1.0, 45.0)
	elif event.is_action_released("cam_rotate_right") and _hold_t < 0.2:
		_yaw_target = snappedf(_yaw - 45.0 - 1.0, 45.0)


func _process(delta: float) -> void:
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
	_apply()


func _apply() -> void:
	if camera == null:
		return
	var b := Basis(Vector3.UP, deg_to_rad(_yaw)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	camera.transform = Transform3D(b, b * Vector3(0, 0, distance))
