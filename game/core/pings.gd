extends Node
## Pings: middle mouse (or the controller's touchpad) marks the spot under
## the cursor for every player, with a beam, a ring and the player's name in
## their colour, and a chime. One ping per player at a time; each lasts a few
## seconds. Clients ask the host, and the host shares it with everyone.

const MSG_PING := 60
const LIFE := 6.0
const COLORS := [Color(1.0, 0.85, 0.2), Color(0.3, 0.85, 1.0), Color(1.0, 0.4, 0.8)]

var _markers := {}   # peer id -> Node3D
var history: Array = []   # [peer id, position], for tests


func _ready() -> void:
	Net.register(MSG_PING, _on_msg)


func _unhandled_input(event: InputEvent) -> void:
	# On release, so holding the middle mouse to turn the camera does not ping.
	if event.is_action_released("ping") and IsoCamera.drag_px < IsoCamera.DRAG_START_PX:
		var p = _point_under_cursor()
		if p != null:
			request(p)


## Ping a world position as this player.
func request(pos: Vector3) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u32(Net.my_id())
	b.put_float(pos.x)
	b.put_float(pos.y)
	b.put_float(pos.z)
	if Net.is_host():
		_share(b.data_array)
	else:
		Net.send(1, MSG_PING, b.data_array)


func _share(data: PackedByteArray) -> void:
	Net.broadcast(MSG_PING, data)
	_show(data)


func _on_msg(from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		# Only trust the sender's own id.
		var b := StreamPeerBuffer.new()
		b.data_array = data
		b.seek(0)
		b.put_u32(from)
		_share(b.data_array)
	else:
		_show(data)


func _show(data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var id := b.get_u32()
	var pos := Vector3(b.get_float(), b.get_float(), b.get_float())
	history.append([id, pos])
	var scene := get_tree().current_scene
	if scene == null or not scene is Node3D:
		return
	if _markers.has(id) and is_instance_valid(_markers[id]):
		_markers[id].queue_free()
	var m := _make_marker(id)
	scene.add_child(m)
	m.global_position = pos
	_markers[id] = m
	Sfx.play(scene, "ping", pos, -4.0, 200.0, 0.0)


func _slot(id: int) -> int:
	for i in Net.slots.size():
		if Net.slots[i].id == id:
			return i
	return 0


func _make_marker(id: int) -> Node3D:
	var slot := _slot(id)
	var col: Color = COLORS[slot % COLORS.size()]
	var root := Node3D.new()
	root.name = "Ping_%d" % id
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col, 0.55)
	mat.no_depth_test = true
	mat.render_priority = 9
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.04
	cyl.height = 3.0
	beam.mesh = cyl
	beam.position.y = 1.5
	beam.material_override = mat
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(beam)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	ring.mesh = torus
	ring.material_override = mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(ring)
	var label := Label3D.new()
	label.text = Net.slots[slot].name if slot < Net.slots.size() else "Officer"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.modulate = col
	label.outline_size = 12
	label.font_size = 48
	label.pixel_size = 0.01
	label.position.y = 3.3
	root.add_child(label)
	# Pulse the ring, fade out at the end.
	var tw := root.create_tween().set_loops(int(LIFE / 0.8))
	tw.tween_property(ring, "scale", Vector3.ONE * 1.6, 0.8).from(Vector3.ONE * 0.6)
	var fade := root.create_tween()
	fade.tween_interval(LIFE - 1.0)
	fade.tween_property(mat, "albedo_color:a", 0.0, 1.0)
	fade.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	fade.tween_callback(root.queue_free)
	return root


func _point_under_cursor():
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var n: Node = cam
	while n and not n is IsoCamera:
		n = n.get_parent()
	if n is IsoCamera:
		return (n as IsoCamera).mouse_on_world(0.0).point
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var hit := cam.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(mp) * 500.0))
	return hit.position if hit else null
