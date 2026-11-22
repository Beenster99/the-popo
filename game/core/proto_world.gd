class_name ProtoWorld
extends RefCounted
## Builders for the throwaway Wave 0 test scenes: ground, sun, sky, blocks.

static func environment(parent: Node, night := false) -> WorldEnvironment:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("0d1220") if night else Color("8fb3cf")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("26324d") if night else Color("b9c6d6")
	env.ambient_light_energy = 0.6 if night else 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	we.name = "Environment"
	parent.add_child(we)
	return we


static func sun(parent: Node, night := false) -> DirectionalLight3D:
	var s := DirectionalLight3D.new()
	s.name = "Sun"
	s.rotation_degrees = Vector3(-55, -30, 0)
	s.light_color = Color("7f93c9") if night else Color("fff1dc")
	s.light_energy = 0.35 if night else 1.2
	s.shadow_enabled = true
	s.directional_shadow_max_distance = 80.0
	parent.add_child(s)
	return s


static func ground(parent: Node, size := 80.0, color := Color("6d7276")) -> StaticBody3D:
	return block(parent, Vector3(size, 1.0, size), Vector3(0, -0.5, 0), color, "Ground")


static func block(parent: Node, size: Vector3, pos: Vector3, color: Color, node_name := "Block", outline := true) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Cel.material(color, outline)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)
	return body


static func rigid_box(parent: Node, size: Vector3, pos: Vector3, color: Color, mass := 10.0) -> RigidBody3D:
	var body := RigidBody3D.new()
	body.position = pos
	body.mass = mass
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = Cel.material(color)
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	parent.add_child(body)
	return body
